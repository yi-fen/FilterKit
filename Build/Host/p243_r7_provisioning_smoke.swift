import Foundation

struct HelperInstallerProvisioningBundle: Codable, Equatable {
    let generation: UInt64
    let bundleIdentifier: String
    func validate() throws {
        guard generation > 0, bundleIdentifier.contains("."), bundleIdentifier.count <= 255 else {
            throw NSError(domain: "invalid-provisioning", code: 1)
        }
    }
}
struct HelperReleaseSigningKey: Equatable {
    enum Status: Equatable { case active, retired, revoked }
    let identifier: String
    let publicKeyBase64: String
    let status: Status
    let minimumGeneration: UInt64?
    let maximumGeneration: UInt64?
}
protocol HelperReleaseSignatureChecking { func verify(signature: Data, message: Data, publicKey: Data) -> Bool }
struct AcceptAllChecker: HelperReleaseSignatureChecking {
    func verify(signature: Data, message: Data, publicKey: Data) -> Bool { signature.count == 64 && publicKey.count == 32 }
}

func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    if !condition() { fputs("FAIL \(label)\n", stderr); exit(1) }
    print("PASS \(label)")
}
let payload = HelperInstallerProvisioningBundle(generation: 8, bundleIdentifier: "cn.yfen.filterkit")
let envelope = HelperSignedProvisioningManifest(envelopeVersion: 1, keyIdentifier: "release-key",
    algorithm: "Ed25519", payload: payload, signatureBase64: Data(repeating: 2, count: 64).base64EncodedString())
let key = HelperReleaseSigningKey(identifier: "release-key", publicKeyBase64: Data(repeating: 1, count: 32).base64EncodedString(), status: .active, minimumGeneration: 1, maximumGeneration: nil)
let verifier = HelperProvisioningSignatureVerifier(keys: [key], checker: AcceptAllChecker())
try verifier.verify(envelope)
let signingBytes = try envelope.signingBytes()
expect(signingBytes.count > 0, "canonical signed provisioning bytes")
let revoked = HelperReleaseSigningKey(identifier: "release-key", publicKeyBase64: key.publicKeyBase64, status: .revoked, minimumGeneration: nil, maximumGeneration: nil)
expect((try? HelperProvisioningSignatureVerifier(keys: [revoked], checker: AcceptAllChecker()).verify(envelope)) == nil, "revoked signing key rejected")
let wrongGeneration = HelperReleaseSigningKey(identifier: "release-key", publicKeyBase64: key.publicKeyBase64, status: .active, minimumGeneration: 9, maximumGeneration: nil)
expect((try? HelperProvisioningSignatureVerifier(keys: [wrongGeneration], checker: AcceptAllChecker()).verify(envelope)) == nil, "key generation window enforced")
let malformed = HelperSignedProvisioningManifest(envelopeVersion: 1, keyIdentifier: "release-key", algorithm: "RSA",
    payload: payload, signatureBase64: envelope.signatureBase64)
expect((try? HelperProvisioningSignatureVerifier(keys: [key], checker: AcceptAllChecker()).verify(malformed)) == nil, "non-Ed25519 envelope rejected")
print("4/4 R7 provisioning smoke assertions passed")
