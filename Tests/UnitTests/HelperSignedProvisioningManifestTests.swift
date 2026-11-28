import XCTest
@testable import FilterKit

final class HelperSignedProvisioningManifestTests: XCTestCase {
    private struct AcceptAll: HelperReleaseSignatureChecking {
        func verify(signature: Data, message: Data, publicKey: Data) -> Bool { true }
    }

    private func provisioning(generation: UInt64 = 8) -> HelperInstallerProvisioningBundle {
        HelperInstallerProvisioningBundle(schemaVersion: 2, generation: generation,
            releaseIdentifier: "release-\(generation)", bundleIdentifier: "cn.yfen.filterkit",
            jbRootPath: "/var/jb", appCDHash: String(repeating: "a", count: 40),
            helperCDHash: String(repeating: "b", count: 40), allowedClientUID: 501,
            stagingOwnerUID: 501, routeIdentifier: "ellekit-default",
            tweakInjectPath: "/var/jb/usr/lib/TweakInject", stagingRootPath: "/var/jb/Library/FilterKit/Staging",
            socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock", helperVersion: "1.0.0",
            teamIdentifier: "ABCDE12345")
    }

    private func key() -> HelperReleaseSigningKey {
        HelperReleaseSigningKey(identifier: "release-key", publicKeyBase64: Data(repeating: 1, count: 32).base64EncodedString(), status: .active, minimumGeneration: 1)
    }

    func testSignedProvisioningEnvelopeVerifiesCanonicalPayload() throws {
        let envelope = HelperSignedProvisioningManifest(envelopeVersion: 1, keyIdentifier: "release-key",
            algorithm: "Ed25519", payload: provisioning(),
            signatureBase64: Data(repeating: 2, count: 64).base64EncodedString())
        XCTAssertNoThrow(try HelperProvisioningSignatureVerifier(keys: [key()], checker: AcceptAll()).verify(envelope))
        XCTAssertEqual(try envelope.signingBytes(), try JSONEncoder.sorted.encode(provisioning()))
    }

    func testProvisioningSignatureRejectsUnknownOrRevokedKey() {
        let envelope = HelperSignedProvisioningManifest(envelopeVersion: 1, keyIdentifier: "release-key",
            algorithm: "Ed25519", payload: provisioning(), signatureBase64: Data(repeating: 2, count: 64).base64EncodedString())
        let revoked = HelperReleaseSigningKey(identifier: "release-key", publicKeyBase64: key().publicKeyBase64, status: .revoked)
        XCTAssertThrowsError(try HelperProvisioningSignatureVerifier(keys: [revoked], checker: AcceptAll()).verify(envelope))
        XCTAssertThrowsError(try HelperProvisioningSignatureVerifier(keys: [], checker: AcceptAll()).verify(envelope))
    }

    func testGenerationWindowAppliesToProvisioningEnvelope() {
        let envelope = HelperSignedProvisioningManifest(envelopeVersion: 1, keyIdentifier: "release-key",
            algorithm: "Ed25519", payload: provisioning(generation: 2),
            signatureBase64: Data(repeating: 2, count: 64).base64EncodedString())
        let bounded = HelperReleaseSigningKey(identifier: "release-key", publicKeyBase64: key().publicKeyBase64,
            status: .active, minimumGeneration: 3)
        XCTAssertThrowsError(try HelperProvisioningSignatureVerifier(keys: [bounded], checker: AcceptAll()).verify(envelope))
    }

    func testMalformedSignatureAndInvalidPayloadFailClosed() {
        let malformed = HelperSignedProvisioningManifest(envelopeVersion: 1, keyIdentifier: "release-key",
            algorithm: "Ed25519", payload: provisioning(), signatureBase64: "bad")
        XCTAssertThrowsError(try HelperProvisioningSignatureVerifier(keys: [key()], checker: AcceptAll()).verify(malformed))
        let invalid = HelperSignedProvisioningManifest(envelopeVersion: 1, keyIdentifier: "release-key",
            algorithm: "Ed25519", payload: provisioning(generation: 0),
            signatureBase64: Data(repeating: 2, count: 64).base64EncodedString())
        XCTAssertThrowsError(try HelperProvisioningSignatureVerifier(keys: [key()], checker: AcceptAll()).verify(invalid))
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
