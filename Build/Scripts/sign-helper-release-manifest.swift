#!/usr/bin/env swift
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
fatalError("CryptoKit is required; run this release signing tool on macOS with a supported SDK")
#endif

// Usage: FILTERKIT_RELEASE_ED25519_PRIVATE_KEY_BASE64=<32-byte raw key> \
//        swift sign-helper-release-manifest.swift <payload.json> <key-id> <output.json>
guard CommandLine.arguments.count == 4,
      let privateKeyBase64 = ProcessInfo.processInfo.environment["FILTERKIT_RELEASE_ED25519_PRIVATE_KEY_BASE64"],
      let privateKeyData = Data(base64Encoded: privateKeyBase64), privateKeyData.count == 32 else {
    fputs("Usage: FILTERKIT_RELEASE_ED25519_PRIVATE_KEY_BASE64=<32-byte raw key> swift sign-helper-release-manifest.swift <payload.json> <key-id> <output.json>\n", stderr)
    exit(2)
}
let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])
let keyIdentifier = CommandLine.arguments[2]
let payload = try JSONDecoder().decode(HelperReleaseTrustManifest.self, from: Data(contentsOf: inputURL))
try payload.validate()
let unsigned = HelperSignedReleaseManifest(envelopeVersion: HelperSignedReleaseManifest.currentEnvelopeVersion,
    keyIdentifier: keyIdentifier, algorithm: HelperSignedReleaseManifest.ed25519Algorithm,
    payload: payload, signatureBase64: Data(repeating: 0, count: 64).base64EncodedString())
let signingBytes = try unsigned.signingBytes()
let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
let signature = try privateKey.signature(for: signingBytes)
let signed = HelperSignedReleaseManifest(envelopeVersion: unsigned.envelopeVersion, keyIdentifier: keyIdentifier,
    algorithm: unsigned.algorithm, payload: payload, signatureBase64: signature.base64EncodedString())
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(signed).write(to: outputURL, options: .atomic)
print("Signed release manifest written: \(outputURL.path)")
print("Public key (base64): \(privateKey.publicKey.rawRepresentation.base64EncodedString())")
