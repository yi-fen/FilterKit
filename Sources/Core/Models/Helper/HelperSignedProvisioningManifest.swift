import Foundation

/// Signed, canonical installer provenance for the App/Helper identity pair.
/// The provisioning payload is never trusted merely because it was decoded from disk.
struct HelperSignedProvisioningManifest: Codable, Equatable {
    let envelopeVersion: Int
    let keyIdentifier: String
    let algorithm: String
    let payload: HelperInstallerProvisioningBundle
    let signatureBase64: String

    static let currentEnvelopeVersion = 1
    static let ed25519Algorithm = "Ed25519"

    enum ValidationError: Error, Equatable {
        case unsupportedEnvelope, invalidKeyIdentifier, unsupportedAlgorithm
        case invalidSignatureEncoding
    }

    func signingBytes() throws -> Data {
        guard envelopeVersion == Self.currentEnvelopeVersion else { throw ValidationError.unsupportedEnvelope }
        guard keyIdentifier.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) != nil else {
            throw ValidationError.invalidKeyIdentifier
        }
        guard algorithm == Self.ed25519Algorithm else { throw ValidationError.unsupportedAlgorithm }
        try payload.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    func signatureBytes() throws -> Data {
        guard let data = Data(base64Encoded: signatureBase64), data.count == 64 else {
            throw ValidationError.invalidSignatureEncoding
        }
        return data
    }
}

struct HelperProvisioningSignatureVerifier {
    enum Failure: Error, Equatable { case malformedEnvelope, unknownKey, revokedKey, keyGenerationNotAllowed, invalidSignature }
    let keys: [HelperReleaseSigningKey]
    let checker: HelperReleaseSignatureChecking

    func verify(_ envelope: HelperSignedProvisioningManifest) throws {
        let message: Data
        let signature: Data
        do { message = try envelope.signingBytes(); signature = try envelope.signatureBytes() }
        catch { throw Failure.malformedEnvelope }
        let earliestActiveGeneration = keys.filter { $0.status == .active }.compactMap(\.minimumGeneration).min()
        let keySetValid = !keys.isEmpty && Set(keys.map(\.identifier)).count == keys.count && keys.allSatisfy { item in
            let identifierValid = item.identifier.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) != nil
            let rangeOrdered = item.minimumGeneration == nil || item.maximumGeneration == nil || item.minimumGeneration! <= item.maximumGeneration!
            let lifecycleValid = item.status != .retired || item.maximumGeneration != nil
            let activeUnboundedAbove = item.status != .active || item.maximumGeneration == nil
            let retiredBeforeActive: Bool
            if item.status == .retired, let maximum = item.maximumGeneration,
               let earliestActive = earliestActiveGeneration {
                retiredBeforeActive = maximum < earliestActive
            } else {
                retiredBeforeActive = item.status != .retired || item.maximumGeneration != nil
            }
            return identifierValid && rangeOrdered && lifecycleValid && activeUnboundedAbove && retiredBeforeActive
        }
        guard keySetValid, let key = keys.first(where: { $0.identifier == envelope.keyIdentifier }) else { throw Failure.unknownKey }
        guard key.status != .revoked else { throw Failure.revokedKey }
        guard keys.contains(where: { $0.status == .active }) else { throw Failure.unknownKey }
        if let minimum = key.minimumGeneration, envelope.payload.generation < minimum { throw Failure.keyGenerationNotAllowed }
        if let maximum = key.maximumGeneration, envelope.payload.generation > maximum { throw Failure.keyGenerationNotAllowed }
        guard let publicKey = Data(base64Encoded: key.publicKeyBase64), publicKey.count == 32,
              checker.verify(signature: signature, message: message, publicKey: publicKey) else {
            throw Failure.invalidSignature
        }
    }
}
