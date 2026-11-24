import Foundation

/// Signed envelope. The signature covers the canonical JSON encoding of `payload` only.
struct HelperSignedReleaseManifest: Codable, Equatable {
    let envelopeVersion: Int
    let keyIdentifier: String
    let algorithm: String
    let payload: HelperReleaseTrustManifest
    let signatureBase64: String

    static let currentEnvelopeVersion = 1
    static let ed25519Algorithm = "Ed25519"

    enum ValidationError: Error, Equatable { case unsupportedEnvelope, invalidKeyIdentifier, unsupportedAlgorithm, invalidSignatureEncoding }

    func signingBytes() throws -> Data {
        guard envelopeVersion == Self.currentEnvelopeVersion else { throw ValidationError.unsupportedEnvelope }
        guard keyIdentifier.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) != nil else { throw ValidationError.invalidKeyIdentifier }
        guard algorithm == Self.ed25519Algorithm else { throw ValidationError.unsupportedAlgorithm }
        try payload.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    func signatureBytes() throws -> Data {
        guard let data = Data(base64Encoded: signatureBase64), data.count == 64 else { throw ValidationError.invalidSignatureEncoding }
        return data
    }
}
