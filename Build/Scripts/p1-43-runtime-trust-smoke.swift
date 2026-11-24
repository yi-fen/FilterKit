import Foundation

enum HelperPolicy {
    static func isValidCDHash(_ value: String) -> Bool { value.range(of: "^[0-9a-fA-F]{40}$", options: .regularExpression) != nil }
    static func isValidHash(_ value: String) -> Bool { value.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil }
}
struct HelperInstallerProvisioningBundle {
    let releaseIdentifier: String; let generation: UInt64; let bundleIdentifier: String
    let helperVersion: String; let helperCDHash: String
    func validate() throws {}
}
struct AcceptExpectedMessage: HelperReleaseSignatureChecking {
    let expected: Data
    func verify(signature: Data, message: Data, publicKey: Data) -> Bool {
        return message == expected && signature == Data(repeating: 7, count: 64) && publicKey == Data(repeating: 1, count: 32)
    }
}
@main struct P142Smoke {
    static func main() throws {
        let cd = String(repeating: "a", count: 40), sha = String(repeating: "b", count: 64)
        func release(_ generation: UInt64) -> HelperReleaseTrustManifest {
            HelperReleaseTrustManifest(schemaVersion: 1, releaseIdentifier: "release-\(generation)", generation: generation,
                bundleIdentifier: "cn.yfen.filterkit.helper", helperVersion: "1.4.2", helperCDHash: cd,
                helperSHA256: sha, publisherPolicy: .integrityOnly, teamIdentifier: nil, leafCertificateSHA256: nil)
        }
        let payload = release(42)
        let unsigned = HelperSignedReleaseManifest(envelopeVersion: 1, keyIdentifier: "release-key-1", algorithm: "Ed25519",
            payload: payload, signatureBase64: Data(repeating: 7, count: 64).base64EncodedString())
        let signingBytes = try unsigned.signingBytes()
        let key = HelperReleaseSigningKey(identifier: "release-key-1", publicKeyBase64: Data(repeating: 1, count: 32).base64EncodedString(), status: .active)
        let verifier = HelperReleaseSignatureVerifier(keys: [key], checker: AcceptExpectedMessage(expected: signingBytes))
        try verifier.verify(unsigned)
        do {
            let changed = HelperSignedReleaseManifest(envelopeVersion: 1, keyIdentifier: "release-key-1", algorithm: "Ed25519", payload: release(43), signatureBase64: unsigned.signatureBase64)
            try verifier.verify(changed); fatalError("tampered payload accepted")
        } catch HelperReleaseSignatureVerifier.Failure.invalidSignature {}
        do {
            let revoked = HelperReleaseSignatureVerifier(keys: [HelperReleaseSigningKey(identifier: "release-key-1", publicKeyBase64: key.publicKeyBase64, status: .revoked)], checker: AcceptExpectedMessage(expected: signingBytes))
            try revoked.verify(unsigned); fatalError("revoked key accepted")
        } catch HelperReleaseSignatureVerifier.Failure.revokedKey {}
        do {
            let unknown = HelperReleaseSignatureVerifier(keys: [], checker: AcceptExpectedMessage(expected: signingBytes))
            try unknown.verify(unsigned); fatalError("unknown key accepted")
        } catch HelperReleaseSignatureVerifier.Failure.unknownKey {}
        let store = InMemoryHelperReleaseGenerationStore()
        let guarder = HelperReleaseAntiRollbackGuard(store: store)
        try guarder.accept(payload)
        try guarder.check(payload) // same generation is idempotently accepted
        do { try guarder.check(release(41)); fatalError("rollback accepted") }
        catch HelperReleaseAntiRollbackGuard.Failure.rollbackDetected {}
        try guarder.accept(release(43))
        do { try guarder.accept(release(42)); fatalError("older generation accepted") }
        catch HelperReleaseAntiRollbackGuard.Failure.rollbackDetected {}
        let oldKey = HelperReleaseSigningKey(identifier: "old", publicKeyBase64: key.publicKeyBase64,
            status: .retired, minimumGeneration: 1, maximumGeneration: 42)
        let newKey = HelperReleaseSigningKey(identifier: "new", publicKeyBase64: key.publicKeyBase64,
            status: .active, minimumGeneration: 43, maximumGeneration: nil)
        let rotationVerifier = HelperReleaseSignatureVerifier(keys: [oldKey, newKey], checker: AcceptExpectedMessage(expected: try unsigned.signingBytes()))
        let oldEnvelope = HelperSignedReleaseManifest(envelopeVersion: 1, keyIdentifier: "old", algorithm: "Ed25519",
            payload: release(42), signatureBase64: Data(repeating: 7, count: 64).base64EncodedString())
        try rotationVerifier.verify(oldEnvelope)
        let outOfWindow = HelperSignedReleaseManifest(envelopeVersion: 1, keyIdentifier: "old", algorithm: "Ed25519",
            payload: release(43), signatureBase64: Data(repeating: 7, count: 64).base64EncodedString())
        do { try rotationVerifier.verify(outOfWindow); fatalError("retired key accepted beyond its generation window") }
        catch HelperReleaseSignatureVerifier.Failure.keyGenerationNotAllowed {}
        let duplicateVerifier = HelperReleaseSignatureVerifier(keys: [newKey, newKey], checker: AcceptExpectedMessage(expected: signingBytes))
        do { try duplicateVerifier.verify(unsigned); fatalError("duplicate key IDs accepted") }
        catch HelperReleaseSignatureVerifier.Failure.malformedKeySet {}
        print("PASS: signed release envelope canonical payload validation")
        print("PASS: payload tampering, unknown key and revoked key rejected")
        print("PASS: anti-rollback generation monotonicity and idempotent same-generation check")
        print("PASS: retired-key generation window and active-key rotation boundary")
        print("PASS: duplicate key identifiers rejected")
        print("NOTE: signature checker is deterministic test double; Ed25519 CryptoKit runtime is not exercised on Linux")
    }
}
