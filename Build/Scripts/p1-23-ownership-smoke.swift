import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

func assertP1(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw NSError(domain: "P1-23", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
func le32(_ value: UInt32) -> [UInt8] {
    [UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff)]
}
let fm = FileManager.default
let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("filterkit-p1-23-owner-\(UUID().uuidString)", isDirectory: true)
try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
defer { try? fm.removeItem(at: directory) }
let pluginID = UUID()
let uuidBytes: [UInt8] = Array(0..<16).map { UInt8($0 + 1) }
var macho = [UInt8]()
macho += [0xcf, 0xfa, 0xed, 0xfe] // MH_MAGIC_64, little endian
macho += le32(0x0100000c) // arm64
macho += le32(0) // subtype
macho += le32(6) // MH_DYLIB
macho += le32(1) // ncmds
macho += le32(24) // sizeofcmds
macho += le32(0) // flags
macho += le32(0) // reserved
macho += le32(0x1b) // LC_UUID
macho += le32(24)
macho += uuidBytes
let dylibData = Data(macho)
let plistData = try PropertyListSerialization.data(fromPropertyList: ["Filter": ["Bundles": ["com.example.app"]]], format: .xml, options: 0)
let slices = try MachOMetadataReader().readSlices(data: dylibData)
let identity = PluginIdentityFingerprint.make(slices: slices)!
let dylibHash = SHA256Digest.hex(dylibData)
let plistHash = SHA256Digest.hex(plistData)
let manifest: [String: Any] = [
    "schemaVersion": 3, "pluginID": pluginID.uuidString,
    "dylibFileName": "Demo.dylib", "plistFileName": "Demo.plist",
    "dylibSHA256": dylibHash, "plistSHA256": plistHash,
    "hardBoundBundleIdentifier": "com.example.app",
    "softAssociatedBundleIdentifiers": [], "machOIdentitySHA256": identity,
    "softAssociations": []
]
let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
try dylibData.write(to: directory.appendingPathComponent("Demo.dylib"))
try plistData.write(to: directory.appendingPathComponent("Demo.plist"))
try manifestData.write(to: directory.appendingPathComponent("Demo.fk.json"))
try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: directory.appendingPathComponent("Demo.dylib").path)
try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: directory.appendingPathComponent("Demo.plist").path)
try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: directory.appendingPathComponent("Demo.fk.json").path)
let verifier = HelperOwnershipProofVerifier()
let proof = try verifier.verify(pluginDirectory: directory.path, dylibFileName: "Demo.dylib",
    plistFileName: "Demo.plist", manifestFileName: "Demo.fk.json", packageOwnership: .verifiedUnowned)
try assertP1(proof.pluginID == pluginID, "verified plugin UUID mismatch")
try assertP1(proof.dylibSHA256 == dylibHash && proof.plistSHA256 == plistHash, "verified payload hashes mismatch")
try assertP1(proof.binaryIdentityVerified, "binary identity was not verified")
do {
    _ = try verifier.verify(pluginDirectory: directory.path, dylibFileName: "Demo.dylib",
        plistFileName: "Demo.plist", manifestFileName: "Demo.fk.json", packageOwnership: .unavailable)
    throw NSError(domain: "P1-23", code: 4, userInfo: [NSLocalizedDescriptionKey: "unavailable package evidence was accepted"])
} catch HelperOwnershipProofVerifier.VerificationError.ownershipEvidenceUnavailable { }
do {
    _ = try verifier.verify(pluginDirectory: directory.path, dylibFileName: "Demo.dylib",
        plistFileName: "Demo.plist", manifestFileName: "Demo.fk.json", packageOwnership: .packageOwned)
    throw NSError(domain: "P1-23", code: 2, userInfo: [NSLocalizedDescriptionKey: "package-owned plugin was accepted"])
} catch HelperOwnershipProofVerifier.VerificationError.packageOwnershipConflict { }
try Data([0, 1, 2]).write(to: directory.appendingPathComponent("Demo.dylib"))
do {
    _ = try verifier.verify(pluginDirectory: directory.path, dylibFileName: "Demo.dylib",
        plistFileName: "Demo.plist", manifestFileName: "Demo.fk.json", packageOwnership: .verifiedUnowned)
    throw NSError(domain: "P1-23", code: 3, userInfo: [NSLocalizedDescriptionKey: "tampered dylib was accepted"])
} catch HelperOwnershipProofVerifier.VerificationError.payloadHashMismatch { }
print("P1-23 ownership smoke: PASS (root-owned manifest, payload hashes, Mach-O identity, package conflict denial, tamper rejection)")
