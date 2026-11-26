import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Helper-side read-only authorization/preparation for a FilterKit-owned association mutation.
/// It returns exact replacement bytes only inside the Helper process. No filesystem write occurs here.
struct HelperPluginFilterMutationAuthorizer {
    enum AuthorizationError: Error, Equatable {
        case notRoot, invalidRequest, packageOwnershipUnavailable, packageOwned
        case ownershipUnverified, manifestMismatch, stalePlist, staleManifest
        case hardBoundImmutable, associationMetadataMismatch, filterPlanBlocked
        case unsupportedFilterProfile, unsafeDirectory, unsafeFile, readFailed
    }

    struct Configuration {
        let pluginDirectory: String
        let dpkgInfoDirectories: [String]
        init(pluginDirectory: String, dpkgInfoDirectories: [String]) throws {
            guard HelperPolicy.isAbsoluteCleanPath(pluginDirectory), pluginDirectory != "/",
                  !dpkgInfoDirectories.isEmpty, dpkgInfoDirectories.allSatisfy(HelperPolicy.isAbsoluteCleanPath) else {
                throw AuthorizationError.invalidRequest
            }
            self.pluginDirectory = pluginDirectory
            self.dpkgInfoDirectories = Array(Set(dpkgInfoDirectories)).sorted()
        }
    }

    struct PreparedMutation {
        let request: HelperPluginFilterMutationRequest
        let ownershipProof: HelperOwnershipProof
        let previousPlistData: Data
        let replacementPlistData: Data
        let previousManifestData: Data
        let replacementManifestData: Data
        let disposition: HelperPluginFilterMutationDisposition

        var response: HelperPluginFilterMutationResponse {
            HelperPluginFilterMutationResponse(requestID: request.requestID, pluginID: request.pluginID,
                action: request.action, targetBundleIdentifier: request.targetBundleIdentifier,
                disposition: disposition,
                reasonCode: disposition == .preparedForAtomicCommit ? "authorized_read_only_prepare" : "already_in_requested_state",
                previousPlistSHA256: SHA256Digest.hex(previousPlistData),
                proposedPlistSHA256: SHA256Digest.hex(replacementPlistData),
                previousManifestSHA256: SHA256Digest.hex(previousManifestData),
                proposedManifestSHA256: SHA256Digest.hex(replacementManifestData), completedAt: Date())
        }
    }

    private let configuration: Configuration
    private let packageResolver = HelperPackageOwnershipResolver()
    private let ownershipVerifier = HelperOwnershipProofVerifier()
    private let filterStrategy = RootHideElleKitFilterStrategy()

    init(configuration: Configuration) { self.configuration = configuration }

    func prepare(_ request: HelperPluginFilterMutationRequest, now: Date = Date()) throws -> PreparedMutation {
        guard geteuid() == 0 else { throw AuthorizationError.notRoot }
        guard request.validateShape(now: now),
              request.dylibFileName.lowercased().hasSuffix(".dylib"),
              request.plistFileName.lowercased().hasSuffix(".plist") else { throw AuthorizationError.invalidRequest }

        let packageProof: HelperPackageOwnershipProof
        do {
            packageProof = try packageResolver.resolve(pluginDirectory: configuration.pluginDirectory,
                fileNames: [request.dylibFileName, request.plistFileName],
                infoDirectories: configuration.dpkgInfoDirectories)
        } catch HelperPackageOwnershipProof.ProofError.packageOwned {
            throw AuthorizationError.packageOwned
        } catch {
            throw AuthorizationError.packageOwnershipUnavailable
        }
        guard packageProof.validates(directory: configuration.pluginDirectory,
            fileNames: [request.dylibFileName, request.plistFileName], now: now) else {
            throw AuthorizationError.packageOwnershipUnavailable
        }

        let manifestLeaf = String(request.dylibFileName.dropLast(6)) + ".fk.json"
        let proof: HelperOwnershipProof
        do {
            proof = try ownershipVerifier.verify(pluginDirectory: configuration.pluginDirectory,
                dylibFileName: request.dylibFileName, plistFileName: request.plistFileName,
                manifestFileName: manifestLeaf, packageOwnership: .verifiedUnowned)
        } catch {
            throw AuthorizationError.ownershipUnverified
        }
        guard proof.pluginID == request.pluginID else { throw AuthorizationError.manifestMismatch }

        let plistData = try readRootOwnedLeaf(request.plistFileName, maximumBytes: 4 * 1024 * 1024,
                                               allowedModes: [0o644, 0o640, 0o600])
        let manifestData = try readRootOwnedLeaf(manifestLeaf, maximumBytes: 64 * 1024, allowedModes: [0o600])
        let plistHash = SHA256Digest.hex(plistData)
        let manifestHash = SHA256Digest.hex(manifestData)
        guard plistHash.caseInsensitiveCompare(request.expectedPlistSHA256) == .orderedSame,
              plistHash.caseInsensitiveCompare(proof.plistSHA256) == .orderedSame else {
            throw AuthorizationError.stalePlist
        }
        guard manifestHash.caseInsensitiveCompare(request.expectedManifestSHA256) == .orderedSame,
              manifestHash.caseInsensitiveCompare(proof.manifestSHA256) == .orderedSame else {
            throw AuthorizationError.staleManifest
        }
        guard var manifest = try? JSONDecoder().decode(FilterKitPluginManifest.self, from: manifestData),
              manifest.schemaVersion == 3,
              UUID(uuidString: manifest.pluginID) == request.pluginID,
              manifest.dylibFileName == request.dylibFileName,
              manifest.plistFileName == request.plistFileName,
              let hardBound = manifest.hardBoundBundleIdentifier,
              let savedAssociations = manifest.softAssociations,
              manifest.softAssociatedBundleIdentifiers != nil else {
            throw AuthorizationError.manifestMismatch
        }

        if request.action == .disableForApp && request.targetBundleIdentifier == hardBound {
            throw AuthorizationError.hardBoundImmutable
        }
        if request.targetBundleIdentifier == hardBound && request.action == .enableForApp {
            // Hard-bound App is immutable; its presence is established by the signed ownership manifest.
            throw AuthorizationError.hardBoundImmutable
        }
        guard Set(savedAssociations.map(\.bundleIdentifier)) == Set(manifest.softAssociatedBundleIdentifiers ?? []),
              savedAssociations.count == Set(savedAssociations.map(\.bundleIdentifier)).count,
              !savedAssociations.contains(where: { $0.bundleIdentifier == hardBound }) else {
            throw AuthorizationError.associationMetadataMismatch
        }

        let plan = filterStrategy.makePlan(originalData: plistData,
            targetBundleIdentifier: request.targetBundleIdentifier,
            action: request.action == .enableForApp ? .enableForApp : .disableForApp)
        guard plan.isPreviewable, let replacementPlist = plan.previewPropertyList ?? (plan.disposition == .alreadyAssociated || plan.disposition == .alreadyNotAssociated ? plistData : nil) else {
            throw AuthorizationError.filterPlanBlocked
        }

        let requestedEnabledState = request.action == .enableForApp
        let existingAssociation = savedAssociations.first(where: { $0.bundleIdentifier == request.targetBundleIdentifier })
        let alreadyInRequestedState = existingAssociation?.isEnabled == requestedEnabledState &&
            ((request.action == .enableForApp && plan.disposition == .alreadyAssociated) ||
             (request.action == .disableForApp && plan.disposition == .alreadyNotAssociated))

        var associations = savedAssociations
        if let index = associations.firstIndex(where: { $0.bundleIdentifier == request.targetBundleIdentifier }) {
            associations[index] = FilterKitManifestSoftAssociation(bundleIdentifier: request.targetBundleIdentifier,
                isEnabled: requestedEnabledState)
        } else if request.action == .enableForApp {
            associations.append(FilterKitManifestSoftAssociation(bundleIdentifier: request.targetBundleIdentifier, isEnabled: true))
        } else {
            // Disabling an association that is absent from the ownership manifest is not authorized.
            throw AuthorizationError.associationMetadataMismatch
        }
        associations.sort { $0.bundleIdentifier < $1.bundleIdentifier }

        // Ensure the current Bundle list agrees with the manifest's effective desired state before
        // changing it. Unknown/global filter semantics are not silently normalized by this writer.
        let expectedCurrent = Set([hardBound] + savedAssociations.filter(\.isEnabled).map(\.bundleIdentifier))
        guard Set(plan.beforeBundles) == expectedCurrent else { throw AuthorizationError.associationMetadataMismatch }
        let expectedAfter = Set([hardBound] + associations.filter(\.isEnabled).map(\.bundleIdentifier))
        guard Set(plan.afterBundles) == expectedAfter else { throw AuthorizationError.associationMetadataMismatch }

        manifest = FilterKitPluginManifest(schemaVersion: manifest.schemaVersion, pluginID: manifest.pluginID,
            dylibFileName: manifest.dylibFileName, plistFileName: manifest.plistFileName,
            dylibSHA256: manifest.dylibSHA256, plistSHA256: SHA256Digest.hex(replacementPlist),
            hardBoundBundleIdentifier: hardBound,
            softAssociatedBundleIdentifiers: associations.map(\.bundleIdentifier).sorted(),
            machOIdentitySHA256: manifest.machOIdentitySHA256, softAssociations: associations)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let replacementManifest = alreadyInRequestedState ? manifestData : try encoder.encode(manifest)
        let effectiveReplacementPlist = alreadyInRequestedState ? plistData : replacementPlist
        let disposition: HelperPluginFilterMutationDisposition = alreadyInRequestedState
            ? .alreadyInRequestedState : .preparedForAtomicCommit
        return PreparedMutation(request: request, ownershipProof: proof,
            previousPlistData: plistData, replacementPlistData: effectiveReplacementPlist,
            previousManifestData: manifestData, replacementManifestData: replacementManifest,
            disposition: disposition)
    }

    private func readRootOwnedLeaf(_ leaf: String, maximumBytes: Int, allowedModes: Set<mode_t>) throws -> Data {
        guard HelperPolicy.isSafeLeafName(leaf) else { throw AuthorizationError.invalidRequest }
        let directoryFD = try openPluginDirectory()
        defer { _ = close(directoryFD) }
        let fd = leaf.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw AuthorizationError.unsafeFile }
        defer { _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == 0, info.st_gid == 0, allowedModes.contains(info.st_mode & 0o777),
              (info.st_mode & 0o6000) == 0, info.st_size >= 0, info.st_size <= maximumBytes else {
            throw AuthorizationError.unsafeFile
        }
        var data = Data(); data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 32 * 1024)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw AuthorizationError.readFailed }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= maximumBytes else { throw AuthorizationError.unsafeFile }
        }
        return data
    }

    private func openPluginDirectory() throws -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw AuthorizationError.unsafeDirectory }
        for component in configuration.pluginDirectory.split(separator: "/").map(String.init) {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { _ = close(fd); throw AuthorizationError.unsafeDirectory }
            _ = close(fd); fd = next
        }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              info.st_uid == 0, info.st_gid == 0, (info.st_mode & 0o022) == 0 else {
            _ = close(fd); throw AuthorizationError.unsafeDirectory
        }
        return fd
    }
}
