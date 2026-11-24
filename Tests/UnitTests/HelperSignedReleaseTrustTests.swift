import XCTest
@testable import FilterKit

final class HelperSignedReleaseTrustTests: XCTestCase {
    func testSignedEnvelopeRejectsUnsupportedAlgorithmAndMalformedSignature() throws {
        let manifest = HelperReleaseTrustManifest(schemaVersion: 1, releaseIdentifier: "release-42", generation: 42,
            bundleIdentifier: "cn.yfen.filterkit.helper", helperVersion: "1.4.2",
            helperCDHash: String(repeating: "a", count: 40), helperSHA256: String(repeating: "b", count: 64),
            publisherPolicy: .integrityOnly, teamIdentifier: nil, leafCertificateSHA256: nil)
        let wrongAlgorithm = HelperSignedReleaseManifest(envelopeVersion: 1, keyIdentifier: "release-key-1",
            algorithm: "RSA", payload: manifest, signatureBase64: Data(repeating: 1, count: 64).base64EncodedString())
        XCTAssertThrowsError(try wrongAlgorithm.signingBytes())
        let malformed = HelperSignedReleaseManifest(envelopeVersion: 1, keyIdentifier: "release-key-1",
            algorithm: "Ed25519", payload: manifest, signatureBase64: "not-base64")
        XCTAssertThrowsError(try malformed.signatureBytes())
    }

    func testAntiRollbackRejectsOlderGeneration() throws {
        let store = InMemoryHelperReleaseGenerationStore()
        let guarder = HelperReleaseAntiRollbackGuard(store: store)
        func manifest(_ generation: UInt64) -> HelperReleaseTrustManifest {
            HelperReleaseTrustManifest(schemaVersion: 1, releaseIdentifier: "release-\(generation)", generation: generation,
                bundleIdentifier: "cn.yfen.filterkit.helper", helperVersion: "1.4.2",
                helperCDHash: String(repeating: "a", count: 40), helperSHA256: String(repeating: "b", count: 64),
                publisherPolicy: .integrityOnly, teamIdentifier: nil, leafCertificateSHA256: nil)
        }
        try guarder.accept(manifest(42))
        XCTAssertThrowsError(try guarder.check(manifest(41)))
        try guarder.accept(manifest(43))
        XCTAssertNoThrow(try guarder.check(manifest(43)))
    }
    func testKeyRotationGenerationWindowsAndDuplicateKeyIDsFailClosed() throws {
        struct AcceptAll: HelperReleaseSignatureChecking {
            func verify(signature: Data, message: Data, publicKey: Data) -> Bool { true }
        }
        func envelope(_ generation: UInt64, keyID: String = "new-key") -> HelperSignedReleaseManifest {
            let payload = HelperReleaseTrustManifest(schemaVersion: 1, releaseIdentifier: "r-\(generation)",
                generation: generation, bundleIdentifier: "cn.yfen.filterkit.helper", helperVersion: "1.4.3",
                helperCDHash: String(repeating: "a", count: 40), helperSHA256: String(repeating: "b", count: 64),
                publisherPolicy: .integrityOnly, teamIdentifier: nil, leafCertificateSHA256: nil)
            return HelperSignedReleaseManifest(envelopeVersion: 1, keyIdentifier: keyID, algorithm: "Ed25519",
                payload: payload, signatureBase64: Data(repeating: 1, count: 64).base64EncodedString())
        }
        let old = HelperReleaseSigningKey(identifier: "old-key", publicKeyBase64: Data(repeating: 1, count: 32).base64EncodedString(),
            status: .retired, minimumGeneration: 1, maximumGeneration: 50)
        let new = HelperReleaseSigningKey(identifier: "new-key", publicKeyBase64: Data(repeating: 2, count: 32).base64EncodedString(),
            status: .active, minimumGeneration: 51, maximumGeneration: nil)
        let verifier = HelperReleaseSignatureVerifier(keys: [old, new], checker: AcceptAll())
        XCTAssertNoThrow(try verifier.verify(envelope(50, keyID: "old-key")))
        XCTAssertThrowsError(try verifier.verify(envelope(51, keyID: "old-key")))
        XCTAssertNoThrow(try verifier.verify(envelope(51)))
        let duplicate = HelperReleaseSignatureVerifier(keys: [new, new], checker: AcceptAll())
        XCTAssertThrowsError(try duplicate.verify(envelope(51)))
    }

}
