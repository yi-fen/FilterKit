import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Concrete root-side authorization and deployment backend. It performs real filesystem,
/// staging, package ownership, plist and Mach-O checks. P1-30 connects its prepared payloads to
/// the three-file transaction, but the independent release gate remains closed.
final class HelperProductionDeploymentBackend: HelperDeploymentPipelineBackend {
    enum BackendError: Error, Equatable {
        case notRoot, invalidConfiguration, unauthenticatedPeer, manifestStateUnsafe
        case packageOwnershipUnavailable, packageOwned, manifestMismatch, pluginMismatch
        case stagingPayloadMismatch, invalidPlist, invalidMachO, missingFirstInstallMetadata
        case targetConflict, executionNotReleased
    }

    struct Configuration {
        let pluginDirectory: String
        let stagingRoot: String
        let stagingOwnerUID: UInt32
        let dpkgInfoDirectories: [String]

        init(pluginDirectory: String, stagingRoot: String, stagingOwnerUID: UInt32,
             dpkgInfoDirectories: [String]) throws {
            guard HelperPolicy.isAbsoluteCleanPath(pluginDirectory), pluginDirectory != "/",
                  HelperPolicy.isAbsoluteCleanPath(stagingRoot), stagingRoot != "/",
                  !dpkgInfoDirectories.isEmpty,
                  dpkgInfoDirectories.allSatisfy(HelperPolicy.isAbsoluteCleanPath) else {
                throw BackendError.invalidConfiguration
            }
            self.pluginDirectory = pluginDirectory
            self.stagingRoot = stagingRoot
            self.stagingOwnerUID = stagingOwnerUID
            self.dpkgInfoDirectories = Array(Set(dpkgInfoDirectories)).sorted()
        }
    }

    /// Kept false independently of the on-disk Helper manifest and Dispatcher release flag.
    static let executionReleased = false

    private let configuration: Configuration
    private let packageResolver = HelperPackageOwnershipResolver()
    private let ownershipVerifier = HelperOwnershipProofVerifier()
    private let payloadReader: HelperStagingPayloadReader

    init(configuration: Configuration) throws {
        self.configuration = configuration
        self.payloadReader = try HelperStagingPayloadReader(rootPath: configuration.stagingRoot,
            expectedOwner: configuration.stagingOwnerUID)
    }

    func inspectRoute(batch: HelperDeploymentBatchRequest,
                      context: HelperAuthenticatedPeerContext) throws -> HelperDeploymentRouteEvidence {
        try requireAuthenticated(context)
        let pair = try HelperDeploymentBatchValidator().validate(batch.operations)
        let manifestName = Self.manifestName(for: pair.dylib.targetFileName)
        let exists = try manifestExistsSafely(manifestName)
        let packageEvidence: HelperDeploymentRouteResolver.OwnershipEvidence
        do {
            _ = try packageResolver.resolve(pluginDirectory: configuration.pluginDirectory,
                fileNames: [pair.dylib.targetFileName, pair.plist.targetFileName],
                infoDirectories: configuration.dpkgInfoDirectories)
            packageEvidence = .verifiedUnowned
        } catch HelperPackageOwnershipProof.ProofError.packageOwned {
            packageEvidence = .packageManagerOwned
        } catch {
            packageEvidence = .unknown
        }

        guard exists else {
            return HelperDeploymentRouteEvidence(manifestExists: false, ownership: packageEvidence)
        }
        guard packageEvidence == .verifiedUnowned else {
            return HelperDeploymentRouteEvidence(manifestExists: true, ownership: packageEvidence)
        }
        do {
            let proof = try ownershipVerifier.verify(pluginDirectory: configuration.pluginDirectory,
                dylibFileName: pair.dylib.targetFileName, plistFileName: pair.plist.targetFileName,
                manifestFileName: manifestName, packageOwnership: .verifiedUnowned)
            return HelperDeploymentRouteEvidence(manifestExists: true,
                ownership: proof.pluginID == batch.pluginID ? .filterKitOwned : .unknown)
        } catch {
            return HelperDeploymentRouteEvidence(manifestExists: true, ownership: .unknown)
        }
    }

    func authorizeFirstInstall(batch: HelperDeploymentBatchRequest,
                               context: HelperAuthenticatedPeerContext) throws -> HelperAuthorizedDeployment {
        try requireAuthenticated(context)
        guard let metadata = batch.deploymentMetadata, metadata.validate() else {
            throw BackendError.missingFirstInstallMetadata
        }
        let pair = try HelperDeploymentBatchValidator().validate(batch.operations)
        let packageProof: HelperPackageOwnershipProof
        do {
            packageProof = try packageResolver.resolve(pluginDirectory: configuration.pluginDirectory,
                fileNames: [pair.dylib.targetFileName, pair.plist.targetFileName],
                infoDirectories: configuration.dpkgInfoDirectories)
        } catch HelperPackageOwnershipProof.ProofError.packageOwned { throw BackendError.packageOwned }
        catch { throw BackendError.packageOwnershipUnavailable }
        guard try !manifestExistsSafely(Self.manifestName(for: pair.dylib.targetFileName)) else {
            throw BackendError.manifestStateUnsafe
        }
        try requireTargetAbsent(pair.dylib.targetFileName)
        try requireTargetAbsent(pair.plist.targetFileName)

        let payloads = try readAndValidatePayloads(pair: pair)
        do {
            if try packageResolver.containsPackageManagedDylibSHA256(pluginDirectory: configuration.pluginDirectory,
                expectedSHA256: SHA256Digest.hex(payloads.dylib), infoDirectories: configuration.dpkgInfoDirectories) {
                throw BackendError.packageOwned
            }
        } catch let error as BackendError { throw error }
        catch { throw BackendError.packageOwnershipUnavailable }
        guard packageProof.validates(directory: configuration.pluginDirectory,
            fileNames: [pair.dylib.targetFileName, pair.plist.targetFileName]) else {
            throw BackendError.packageOwnershipUnavailable
        }
        let manifest: FilterKitPluginManifest
        do {
            manifest = try PluginFirstInstallBindingPolicy.makeManifest(
                pluginID: batch.pluginID,
                dylibFileName: pair.dylib.targetFileName,
                plistFileName: pair.plist.targetFileName,
                dylibSHA256: SHA256Digest.hex(payloads.dylib),
                plistSHA256: SHA256Digest.hex(payloads.plist),
                machOIdentitySHA256: payloads.identity,
                fixedOwnerBundleIdentifier: metadata.hardBoundBundleIdentifier,
                additionalAssociations: metadata.softAssociations,
                filterPlistData: payloads.plist)
        } catch {
            throw BackendError.invalidPlist
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifestBytes = try encoder.encode(manifest)
        let proof = try HelperOwnershipProof(pluginID: batch.pluginID,
            dylibFileName: pair.dylib.targetFileName, plistFileName: pair.plist.targetFileName,
            dylibSHA256: SHA256Digest.hex(payloads.dylib), plistSHA256: SHA256Digest.hex(payloads.plist),
            manifestSchemaVersion: 4, manifestSHA256: SHA256Digest.hex(manifestBytes),
            binaryIdentityVerified: true, isFirstInstallAuthorization: true)
        return HelperAuthorizedDeployment(proof: proof, plans: makePlans(pair),
            dylibData: payloads.dylib, plistData: payloads.plist, manifestData: manifestBytes)
    }

    func authorizeUpdate(batch: HelperDeploymentBatchRequest,
                         context: HelperAuthenticatedPeerContext) throws -> HelperAuthorizedDeployment {
        try requireAuthenticated(context)
        let pair = try HelperDeploymentBatchValidator().validate(batch.operations)
        let packageProof: HelperPackageOwnershipProof
        do {
            packageProof = try packageResolver.resolve(pluginDirectory: configuration.pluginDirectory,
                fileNames: [pair.dylib.targetFileName, pair.plist.targetFileName],
                infoDirectories: configuration.dpkgInfoDirectories)
        } catch HelperPackageOwnershipProof.ProofError.packageOwned { throw BackendError.packageOwned }
        catch { throw BackendError.packageOwnershipUnavailable }
        let oldProof: HelperOwnershipProof
        do {
            oldProof = try ownershipVerifier.verify(pluginDirectory: configuration.pluginDirectory,
                dylibFileName: pair.dylib.targetFileName, plistFileName: pair.plist.targetFileName,
                manifestFileName: Self.manifestName(for: pair.dylib.targetFileName), packageOwnership: .verifiedUnowned)
        } catch { throw BackendError.manifestMismatch }
        guard oldProof.pluginID == batch.pluginID else { throw BackendError.pluginMismatch }
        guard packageProof.validates(directory: configuration.pluginDirectory,
            fileNames: [pair.dylib.targetFileName, pair.plist.targetFileName]) else {
            throw BackendError.packageOwnershipUnavailable
        }
        let payloads = try readAndValidatePayloads(pair: pair)
        let oldManifestData = try readRootManifest(Self.manifestName(for: pair.dylib.targetFileName))
        let oldManifestHash = SHA256Digest.hex(oldManifestData)
        guard oldProof.manifestSHA256.caseInsensitiveCompare(oldManifestHash) == .orderedSame,
              let oldManifest = try? JSONDecoder().decode(FilterKitPluginManifest.self, from: oldManifestData),
              (oldManifest.schemaVersion == 3 || oldManifest.schemaVersion == 4),
              UUID(uuidString: oldManifest.pluginID) == batch.pluginID,
              oldManifest.dylibFileName == pair.dylib.targetFileName,
              oldManifest.plistFileName == pair.plist.targetFileName,
              let hardBound = oldManifest.hardBoundBundleIdentifier else { throw BackendError.manifestMismatch }
        let existingAssociations = oldManifest.softAssociations ?? []
        let updatedManifest: FilterKitPluginManifest
        if oldManifest.schemaVersion == 4 {
            guard let oldTopology = oldManifest.bindingTopology,
                  oldTopology.schemaVersion == 1,
                  HelperBundleIdentifierKey.make(oldTopology.fixedOwnerBundleIdentifier ?? "") == HelperBundleIdentifierKey.make(hardBound),
                  oldTopology.additionalAssociations.count == existingAssociations.count,
                  oldTopology.additionalAssociations.allSatisfy({ topologyAssociation in
                      existingAssociations.contains {
                          HelperBundleIdentifierKey.make($0.bundleIdentifier) == HelperBundleIdentifierKey.make(topologyAssociation.bundleIdentifier) &&
                          $0.isEnabled == topologyAssociation.isEnabled
                      }
                  }) else { throw BackendError.manifestMismatch }
            let normalized = oldTopology.additionalAssociations.sorted {
                HelperBundleIdentifierKey.make($0.bundleIdentifier) < HelperBundleIdentifierKey.make($1.bundleIdentifier)
            }
            updatedManifest = FilterKitPluginManifest(schemaVersion: 4, pluginID: batch.pluginID.uuidString,
                dylibFileName: pair.dylib.targetFileName, plistFileName: pair.plist.targetFileName,
                dylibSHA256: SHA256Digest.hex(payloads.dylib), plistSHA256: SHA256Digest.hex(payloads.plist),
                hardBoundBundleIdentifier: hardBound,
                softAssociatedBundleIdentifiers: normalized.map(\.bundleIdentifier),
                machOIdentitySHA256: payloads.identity,
                softAssociations: normalized,
                bindingTopology: FilterKitManifestBindingTopology(schemaVersion: 1,
                    fixedOwnerBundleIdentifier: hardBound,
                    fixedOwnerIsEnabled: oldTopology.fixedOwnerIsEnabled,
                    additionalAssociations: normalized))
        } else {
            updatedManifest = FilterKitPluginManifest(schemaVersion: 3, pluginID: batch.pluginID.uuidString,
                dylibFileName: pair.dylib.targetFileName, plistFileName: pair.plist.targetFileName,
                dylibSHA256: SHA256Digest.hex(payloads.dylib), plistSHA256: SHA256Digest.hex(payloads.plist),
                hardBoundBundleIdentifier: hardBound,
                softAssociatedBundleIdentifiers: oldManifest.softAssociatedBundleIdentifiers ?? [],
                machOIdentitySHA256: payloads.identity,
                softAssociations: existingAssociations)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifestBytes = try encoder.encode(updatedManifest)
        let proof = try HelperOwnershipProof(pluginID: batch.pluginID,
            dylibFileName: pair.dylib.targetFileName, plistFileName: pair.plist.targetFileName,
            dylibSHA256: SHA256Digest.hex(payloads.dylib), plistSHA256: SHA256Digest.hex(payloads.plist),
            manifestSchemaVersion: updatedManifest.schemaVersion, manifestSHA256: SHA256Digest.hex(manifestBytes),
            binaryIdentityVerified: true, isFirstInstallAuthorization: false)
        return HelperAuthorizedDeployment(proof: proof, plans: makePlans(pair),
            dylibData: payloads.dylib, plistData: payloads.plist, manifestData: manifestBytes,
            expectedPrevious: HelperExpectedPreviousDeployment(dylibSHA256: oldProof.dylibSHA256,
                plistSHA256: oldProof.plistSHA256, manifestSHA256: oldManifestHash))
    }

    func execute(_ prepared: HelperAuthorizedDeployment) throws -> HelperSafeFileExecutor.TransactionReceipt {
        guard Self.executionReleased else { throw BackendError.executionNotReleased }
        guard let dylib = prepared.dylibData, let plist = prepared.plistData,
              let manifest = prepared.manifestData,
              SHA256Digest.hex(manifest).caseInsensitiveCompare(prepared.proof.manifestSHA256) == .orderedSame,
              let dylibPlan = prepared.plans.first(where: { $0.operation == .installDylib }),
              let plistPlan = prepared.plans.first(where: { $0.operation == .replaceFilterPlist }) else {
            throw BackendError.stagingPayloadMismatch
        }
        let packageProof: HelperPackageOwnershipProof
        do {
            packageProof = try packageResolver.resolve(pluginDirectory: configuration.pluginDirectory,
                fileNames: [prepared.proof.dylibFileName, prepared.proof.plistFileName],
                infoDirectories: configuration.dpkgInfoDirectories)
        } catch HelperPackageOwnershipProof.ProofError.packageOwned {
            // Package ownership is re-read at the last privileged boundary. Never collapse this
            // into a generic I/O failure: it is an explicit external-owner denial.
            throw BackendError.packageOwned
        } catch { throw BackendError.packageOwnershipUnavailable }
        guard packageProof.validates(directory: configuration.pluginDirectory,
            fileNames: [prepared.proof.dylibFileName, prepared.proof.plistFileName]) else {
            throw BackendError.packageOwnershipUnavailable
        }
        do {
            if try packageResolver.containsPackageManagedDylibSHA256(pluginDirectory: configuration.pluginDirectory,
                expectedSHA256: prepared.proof.dylibSHA256, infoDirectories: configuration.dpkgInfoDirectories) {
                throw BackendError.packageOwned
            }
        } catch let error as BackendError { throw error }
        catch { throw BackendError.packageOwnershipUnavailable }
        let route: HelperThreeFileTransactionExecutor.Route = prepared.proof.isFirstInstallAuthorization ? .firstInstall : .update
        if route == .firstInstall {
            // Re-check all destination leaves immediately before transaction creation. The
            // transaction independently enforces absent dylib/plist/manifest under its lock.
            guard try !manifestExistsSafely(Self.manifestName(for: prepared.proof.dylibFileName)) else {
                throw BackendError.manifestStateUnsafe
            }
            try requireTargetAbsent(prepared.proof.dylibFileName)
            try requireTargetAbsent(prepared.proof.plistFileName)
        }
        let expectedPrevious: (dylib: String, plist: String, manifest: String)?
        if route == .update {
            guard let expected = prepared.expectedPrevious else { throw BackendError.manifestMismatch }
            let old = try ownershipVerifier.verify(pluginDirectory: configuration.pluginDirectory,
                dylibFileName: prepared.proof.dylibFileName, plistFileName: prepared.proof.plistFileName,
                manifestFileName: Self.manifestName(for: prepared.proof.dylibFileName), packageOwnership: .verifiedUnowned)
            let currentManifest = try currentManifestHash(Self.manifestName(for: prepared.proof.dylibFileName))
            guard old.dylibSHA256 == expected.dylibSHA256,
                  old.plistSHA256 == expected.plistSHA256,
                  currentManifest == expected.manifestSHA256 else { throw BackendError.manifestMismatch }
            expectedPrevious = (expected.dylibSHA256, expected.plistSHA256, expected.manifestSHA256)
        } else {
            guard prepared.expectedPrevious == nil else { throw BackendError.manifestMismatch }
            expectedPrevious = nil
        }
        guard let binding = prepared.transactionBinding, binding.validate() else { throw BackendError.stagingPayloadMismatch }
        let executor = try HelperThreeFileTransactionExecutor(directoryPath: configuration.pluginDirectory)
        let receipt = try executor.execute(pluginID: prepared.proof.pluginID,
            dylibName: dylibPlan.destinationRelativePath, plistName: plistPlan.destinationRelativePath,
            dylib: dylib, plist: plist, manifest: manifest, route: route, expectedPrevious: expectedPrevious,
            transactionID: binding.transactionID, deploymentBinding: binding)
        return HelperSafeFileExecutor.TransactionReceipt(requestIDs: prepared.plans.map(\.requestID),
            pluginID: receipt.pluginID, changedPaths: prepared.plans.map(\.destinationRelativePath).sorted(),
            dylibSHA256: receipt.dylibSHA256, plistSHA256: receipt.plistSHA256,
            completedAt: receipt.completedAt, manifestSHA256: receipt.manifestSHA256,
            transactionID: receipt.transactionID)
    }

    private func readAndValidatePayloads(pair: (pluginID: UUID, dylib: HelperOperationRequest, plist: HelperOperationRequest)) throws -> (dylib: Data, plist: Data, identity: String) {
        guard let dylibPath = pair.dylib.stagingRelativePath,
              let plistPath = pair.plist.stagingRelativePath else { throw BackendError.stagingPayloadMismatch }
        let dylib = try payloadReader.read(relativePath: dylibPath)
        let plist = try payloadReader.read(relativePath: plistPath)
        guard SHA256Digest.hex(dylib).caseInsensitiveCompare(pair.dylib.expectedSHA256 ?? "") == .orderedSame,
              SHA256Digest.hex(plist).caseInsensitiveCompare(pair.plist.expectedSHA256 ?? "") == .orderedSame else {
            throw BackendError.stagingPayloadMismatch
        }
        guard (try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil)) != nil else {
            throw BackendError.invalidPlist
        }
        let slices: [MachOSliceMetadata]
        do { slices = try MachOMetadataReader().readSlices(data: dylib) }
        catch { throw BackendError.invalidMachO }
        guard let identity = PluginIdentityFingerprint.make(slices: slices), HelperPolicy.isValidHash(identity) else {
            throw BackendError.invalidMachO
        }
        return (dylib, plist, identity)
    }

    private func makePlans(_ pair: (pluginID: UUID, dylib: HelperOperationRequest, plist: HelperOperationRequest)) -> [HelperClosedExecutionPlan] {
        [
            HelperClosedExecutionPlan(requestID: pair.dylib.requestID, pluginID: pair.pluginID, action: .copyFile,
                sourceRelativePath: pair.dylib.stagingRelativePath, destinationRelativePath: pair.dylib.targetFileName,
                expectedSHA256: pair.dylib.expectedSHA256?.lowercased(), operation: .installDylib),
            HelperClosedExecutionPlan(requestID: pair.plist.requestID, pluginID: pair.pluginID, action: .copyFile,
                sourceRelativePath: pair.plist.stagingRelativePath, destinationRelativePath: pair.plist.targetFileName,
                expectedSHA256: pair.plist.expectedSHA256?.lowercased(), operation: .replaceFilterPlist)
        ]
    }

    private func readRootManifest(_ leaf: String) throws -> Data {
        let dir = try openTargetDirectory(); defer { _ = close(dir) }
        let file = leaf.withCString { openat(dir, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard file >= 0 else { throw BackendError.manifestStateUnsafe }; defer { _ = close(file) }
        var st = stat()
        guard fstat(file, &st) == 0, (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              st.st_uid == 0, st.st_gid == 0, (st.st_mode & 0o777) == 0o600,
              st.st_size >= 0, st.st_size <= 256 * 1024 else { throw BackendError.manifestStateUnsafe }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while true { let n = read(file, &buffer, buffer.count); if n < 0 && errno == EINTR { continue }; guard n >= 0 else { throw BackendError.manifestStateUnsafe }; if n == 0 { break }; data.append(contentsOf: buffer.prefix(n)); guard data.count <= 256 * 1024 else { throw BackendError.manifestStateUnsafe } }
        return data
    }

    private func currentManifestHash(_ leaf: String) throws -> String { SHA256Digest.hex(try readRootManifest(leaf)) }

    private func requireAuthenticated(_ context: HelperAuthenticatedPeerContext) throws {
        guard geteuid() == 0 else { throw BackendError.notRoot }
        guard context.peer.uid == context.identity.uid, context.peer.gid == context.identity.gid,
              context.peer.pid == context.identity.pid, context.identity.pid > 0,
              HelperPolicy.isValidCDHash(context.identity.cdHashHex),
              context.sessionNonce.range(of: "^[0-9a-fA-F]{32,128}$", options: .regularExpression) != nil,
              abs(Date().timeIntervalSince(context.authenticatedAt)) <= 120 else {
            throw BackendError.unauthenticatedPeer
        }
    }

    private func manifestExistsSafely(_ leaf: String) throws -> Bool {
        let fd = try openTargetDirectory()
        defer { _ = close(fd) }
        var info = stat()
        let result = leaf.withCString { fstatat(fd, $0, &info, AT_SYMLINK_NOFOLLOW) }
        if result != 0 { if errno == ENOENT { return false }; throw BackendError.manifestStateUnsafe }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_uid == 0, info.st_gid == 0,
              (info.st_mode & 0o777) == 0o600, (info.st_mode & 0o6000) == 0 else {
            throw BackendError.manifestStateUnsafe
        }
        return true
    }

    private func requireTargetAbsent(_ leaf: String) throws {
        let fd = try openTargetDirectory()
        defer { _ = close(fd) }
        var info = stat()
        let result = leaf.withCString { fstatat(fd, $0, &info, AT_SYMLINK_NOFOLLOW) }
        if result == 0 { throw BackendError.targetConflict }
        guard errno == ENOENT else { throw BackendError.manifestStateUnsafe }
    }

    private func openTargetDirectory() throws -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw BackendError.manifestStateUnsafe }
        for component in configuration.pluginDirectory.split(separator: "/").map(String.init) {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { _ = close(fd); throw BackendError.manifestStateUnsafe }
            _ = close(fd); fd = next
        }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              info.st_uid == 0, info.st_gid == 0, (info.st_mode & 0o022) == 0 else {
            _ = close(fd); throw BackendError.manifestStateUnsafe
        }
        return fd
    }

    private static func manifestName(for dylib: String) -> String {
        String(dylib.dropLast(6)) + ".fk.json"
    }
}
