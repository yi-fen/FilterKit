import Foundation

/// Reconstructs uninstall authority from Helper-owned files and package-manager evidence.
/// The App contributes only expected identifiers/hashes; no caller-supplied enabled state is trusted.
struct HelperPluginUninstallAuthorizer {
    enum AuthorizationError: Error, Equatable {
        case notRoot, invalidRequest, packageOwnershipUnavailable, packageOwned
        case ownershipUnverified, pluginMismatch, staleDylib, stalePlist, staleManifest
        case associationStateMismatch
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

    struct PreparedUninstall {
        let request: HelperPluginUninstallRequest
        let ownershipProof: HelperOwnershipProof
    }

    private let configuration: Configuration
    private let packageResolver = HelperPackageOwnershipResolver()
    private let ownershipVerifier = HelperOwnershipProofVerifier()

    init(configuration: Configuration) { self.configuration = configuration }

    func prepare(_ request: HelperPluginUninstallRequest, now: Date = Date()) throws -> PreparedUninstall {
        guard geteuid() == 0 else { throw AuthorizationError.notRoot }
        guard request.operatorConfirmed, request.validate(now: now) else { throw AuthorizationError.invalidRequest }
        let manifestName = String(request.dylibFileName.dropLast(6)) + ".fk.json"

        do {
            let packageProof = try packageResolver.resolve(pluginDirectory: configuration.pluginDirectory,
                fileNames: [request.dylibFileName, request.plistFileName, manifestName],
                infoDirectories: configuration.dpkgInfoDirectories)
            guard packageProof.validates(directory: configuration.pluginDirectory,
                fileNames: [request.dylibFileName, request.plistFileName, manifestName], now: now) else {
                throw AuthorizationError.packageOwnershipUnavailable
            }
        } catch HelperPackageOwnershipProof.ProofError.packageOwned {
            throw AuthorizationError.packageOwned
        } catch let error as AuthorizationError {
            throw error
        } catch {
            throw AuthorizationError.packageOwnershipUnavailable
        }

        let proof: HelperOwnershipProof
        do {
            proof = try ownershipVerifier.verify(pluginDirectory: configuration.pluginDirectory,
                dylibFileName: request.dylibFileName, plistFileName: request.plistFileName,
                manifestFileName: manifestName, packageOwnership: .verifiedUnowned)
        } catch {
            throw AuthorizationError.ownershipUnverified
        }
        guard proof.pluginID == request.pluginID else { throw AuthorizationError.pluginMismatch }
        guard proof.dylibSHA256.caseInsensitiveCompare(request.expectedDylibSHA256) == .orderedSame else {
            throw AuthorizationError.staleDylib
        }
        guard proof.plistSHA256.caseInsensitiveCompare(request.expectedPlistSHA256) == .orderedSame else {
            throw AuthorizationError.stalePlist
        }
        guard proof.manifestSHA256.caseInsensitiveCompare(request.expectedManifestSHA256) == .orderedSame else {
            throw AuthorizationError.staleManifest
        }
        guard let filter = proof.filterConfiguration, filter.parseState == .valid else {
            throw AuthorizationError.associationStateMismatch
        }

        if proof.manifestSchemaVersion >= 4 {
            guard let topology = proof.bindingTopology, topology.schemaVersion == 1,
                  HelperBundleIdentifierKey.set(filter.bundles).count == filter.bundles.count,
                  HelperBundleIdentifierKey.set(topology.additionalAssociations.map(\.bundleIdentifier)).count == topology.additionalAssociations.count,
                  HelperBundleIdentifierKey.set(filter.bundles) == HelperBundleIdentifierKey.set(topology.enabledBundleIdentifiers) else {
                throw AuthorizationError.associationStateMismatch
            }
        } else {
            let owner = proof.hardBoundBundleIdentifier
            let associations = proof.softAssociations ?? []
            let associationKeys = HelperBundleIdentifierKey.set(associations.map(\.bundleIdentifier))
            guard associationKeys.count == associations.count,
                  !associations.contains(where: { HelperBundleIdentifierKey.make($0.bundleIdentifier) == HelperBundleIdentifierKey.make(owner ?? "") }),
                  HelperBundleIdentifierKey.set(filter.bundles).count == filter.bundles.count else {
                throw AuthorizationError.associationStateMismatch
            }
            let known = Set(([owner].compactMap { $0 }) + associations.map(\.bundleIdentifier))
            let enabledSoft = Set(associations.filter(\.isEnabled).map(\.bundleIdentifier))
            let actual = HelperBundleIdentifierKey.set(filter.bundles)
            let knownKeys = HelperBundleIdentifierKey.set(known)
            let enabledSoftKeys = HelperBundleIdentifierKey.set(enabledSoft)
            let ownerKeys = HelperBundleIdentifierKey.set([owner].compactMap { $0 })
            guard actual.isSubset(of: knownKeys), enabledSoftKeys.isSubset(of: actual),
                  actual.subtracting(enabledSoftKeys).isSubset(of: ownerKeys) else {
                throw AuthorizationError.associationStateMismatch
            }
        }
        // A verified three-file uninstall removes both the dylib and its complete filter
        // configuration. Existing processes may retain an already mapped image until they
        // restart, but no future App launch can load this plugin after the transaction commits.
        return PreparedUninstall(request: request, ownershipProof: proof)
    }
}
