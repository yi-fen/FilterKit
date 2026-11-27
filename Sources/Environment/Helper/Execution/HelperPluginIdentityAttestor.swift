import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Root-side read-only identity attestation. Package ownership, root-owned manifest,
/// exact payload hashes, and Mach-O identity are re-read by Helper for every request.
struct HelperPluginIdentityAttestor {
    struct Configuration {
        let pluginDirectory: String
        let dpkgInfoDirectories: [String]
        init(pluginDirectory: String, dpkgInfoDirectories: [String]) throws {
            guard HelperPolicy.isAbsoluteCleanPath(pluginDirectory), pluginDirectory != "/",
                  !dpkgInfoDirectories.isEmpty, dpkgInfoDirectories.allSatisfy(HelperPolicy.isAbsoluteCleanPath) else {
                throw HelperOwnershipProofVerifier.VerificationError.invalidPath
            }
            self.pluginDirectory = pluginDirectory
            self.dpkgInfoDirectories = Array(Set(dpkgInfoDirectories)).sorted()
        }
    }

    private let configuration: Configuration
    init(configuration: Configuration) { self.configuration = configuration }

    func attest(_ request: HelperPluginIdentityAttestationRequest, now: Date = Date()) -> HelperPluginIdentityAttestation {
        func response(_ status: HelperPluginIdentityAttestationStatus, _ reason: String,
                      _ proof: HelperOwnershipProof? = nil) -> HelperPluginIdentityAttestation {
            HelperPluginIdentityAttestation(requestID: request.requestID, status: status, reasonCode: reason,
                pluginID: proof?.pluginID, dylibFileName: proof?.dylibFileName,
                plistFileName: proof?.plistFileName, dylibSHA256: proof?.dylibSHA256,
                plistSHA256: proof?.plistSHA256, manifestSHA256: proof?.manifestSHA256,
                machOIdentitySHA256: proof?.machOIdentitySHA256,
                hardBoundBundleIdentifier: proof?.hardBoundBundleIdentifier,
                softAssociations: proof?.softAssociations,
                filterConfiguration: proof?.filterConfiguration, completedAt: now)
        }
        guard geteuid() == 0 else { return response(.unavailable, "helper_not_root") }
        guard request.validate(now: now) else { return response(.rejected, "invalid_request") }
        do {
            let packageProof = try HelperPackageOwnershipResolver().resolve(pluginDirectory: configuration.pluginDirectory,
                fileNames: [request.dylibFileName, request.plistFileName],
                infoDirectories: configuration.dpkgInfoDirectories)
            guard packageProof.validates(directory: configuration.pluginDirectory,
                fileNames: [request.dylibFileName, request.plistFileName], now: now) else {
                return response(.unavailable, "package_ownership_proof_stale")
            }
        } catch HelperPackageOwnershipProof.ProofError.packageOwned {
            return response(.rejected, "package_manager_owned")
        } catch {
            return response(.unavailable, "package_ownership_unavailable")
        }
        let manifestName = String(request.dylibFileName.dropLast(6)) + ".fk.json"
        do {
            let proof = try HelperOwnershipProofVerifier().verify(pluginDirectory: configuration.pluginDirectory,
                dylibFileName: request.dylibFileName, plistFileName: request.plistFileName,
                manifestFileName: manifestName, packageOwnership: .verifiedUnowned)
            guard proof.pluginID == request.pluginID else { return response(.rejected, "plugin_id_mismatch") }
            guard proof.filterConfiguration?.parseState == .valid,
                  proof.hardBoundBundleIdentifier != nil,
                  proof.machOIdentitySHA256 != nil else { return response(.unavailable, "identity_evidence_incomplete") }
            let verified = response(.verified, "helper_verified_root_owned_manifest_and_payloads", proof)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            guard let encoded = try? encoder.encode(verified), encoded.count <= 64 * 1024 else {
                return response(.unavailable, "identity_projection_exceeds_ipc_limit")
            }
            return verified
        } catch {
            return response(.unavailable, "helper_identity_verification_failed")
        }
    }
}
