import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

struct HelperReleaseSigningKey: Equatable {
    enum Status: Equatable { case active, retired, revoked }
    let identifier: String
    let publicKeyBase64: String
    let status: Status
    /// Generation bounds make retired keys usable only for their explicitly authorized history.
    let minimumGeneration: UInt64?
    let maximumGeneration: UInt64?

    init(identifier: String, publicKeyBase64: String, status: Status,
         minimumGeneration: UInt64? = nil, maximumGeneration: UInt64? = nil) {
        self.identifier = identifier
        self.publicKeyBase64 = publicKeyBase64
        self.status = status
        self.minimumGeneration = minimumGeneration
        self.maximumGeneration = maximumGeneration
    }
}

protocol HelperReleaseSignatureChecking {
    func verify(signature: Data, message: Data, publicKey: Data) -> Bool
}

/// Ed25519 verifier backed by CryptoKit on Apple platforms. No private key is shipped in the app.
struct HelperEd25519SignatureChecker: HelperReleaseSignatureChecking {
    func verify(signature: Data, message: Data, publicKey: Data) -> Bool {
        #if canImport(CryptoKit)
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else { return false }
        return key.isValidSignature(signature, for: message)
        #else
        return false
        #endif
    }
}

struct HelperReleaseSignatureVerifier {
    enum Failure: Error, Equatable { case malformedEnvelope, malformedKeySet, unknownKey, revokedKey, keyGenerationNotAllowed, invalidPublicKey, invalidSignature }
    let keys: [HelperReleaseSigningKey]
    let checker: HelperReleaseSignatureChecking

    func verify(_ envelope: HelperSignedReleaseManifest) throws {
        let bytes: Data
        let signature: Data
        do { bytes = try envelope.signingBytes(); signature = try envelope.signatureBytes() }
        catch { throw Failure.malformedEnvelope }
        guard !keys.isEmpty else { throw Failure.unknownKey }
        let earliestActiveGeneration = keys.filter { $0.status == .active }.compactMap(\.minimumGeneration).min()
        let keySetValid = Set(keys.map(\.identifier)).count == keys.count && keys.allSatisfy({ item in
            let identifierValid = item.identifier.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) != nil
            let rangeOrdered = item.minimumGeneration == nil || item.maximumGeneration == nil || item.minimumGeneration! <= item.maximumGeneration!
            let lifecycleValid = item.status != .retired || item.maximumGeneration != nil
            let activeUnboundedAbove = item.status != .active || item.maximumGeneration == nil
            let retiredBeforeActive = item.status != .retired || earliestActiveGeneration == nil || item.maximumGeneration! < earliestActiveGeneration!
            return identifierValid && rangeOrdered && lifecycleValid && activeUnboundedAbove && retiredBeforeActive
        })
        guard keySetValid else { throw Failure.malformedKeySet }
        guard let key = keys.first(where: { $0.identifier == envelope.keyIdentifier }) else { throw Failure.unknownKey }
        guard key.status != .revoked else { throw Failure.revokedKey }
        guard keys.contains(where: { $0.status == .active }) else { throw Failure.malformedKeySet }
        let generation = envelope.payload.generation
        if let minimum = key.minimumGeneration, generation < minimum { throw Failure.keyGenerationNotAllowed }
        if let maximum = key.maximumGeneration, generation > maximum { throw Failure.keyGenerationNotAllowed }
        guard let publicKey = Data(base64Encoded: key.publicKeyBase64), publicKey.count == 32 else { throw Failure.invalidPublicKey }
        guard checker.verify(signature: signature, message: bytes, publicKey: publicKey) else { throw Failure.invalidSignature }
    }
}
