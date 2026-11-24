import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

func check24(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw NSError(domain: "P1-24", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
func le32_24(_ value: UInt32) -> [UInt8] {
    [UInt8(value & 255), UInt8((value >> 8) & 255), UInt8((value >> 16) & 255), UInt8((value >> 24) & 255)]
}
let fm = FileManager.default
let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("filterkit-p1-24-\(UUID().uuidString)", isDirectory: true)
let root = base.appendingPathComponent("plugins", isDirectory: true)
let staging = base.appendingPathComponent("staging", isDirectory: true)
let task = staging.appendingPathComponent("task", isDirectory: true)
try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
try fm.createDirectory(at: task, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
defer { try? fm.removeItem(at: base) }

// First-install manifest bootstrap: authenticated peer + exact deployed bytes + verified-unowned evidence.
let uuidBytes: [UInt8] = Array(1...16).map(UInt8.init)
var macho = [UInt8]()
macho += [0xcf, 0xfa, 0xed, 0xfe]
macho += le32_24(0x0100000c) + le32_24(0) + le32_24(6) + le32_24(1) + le32_24(24) + le32_24(0) + le32_24(0)
macho += le32_24(0x1b) + le32_24(24) + uuidBytes
let dylib = Data(macho)
let plist = try PropertyListSerialization.data(fromPropertyList: ["Filter": ["Bundles": ["com.example.app"]]], format: .xml, options: 0)
try dylib.write(to: task.appendingPathComponent("Demo.dylib"))
try plist.write(to: task.appendingPathComponent("Demo.plist"))
try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: task.appendingPathComponent("Demo.dylib").path)
try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: task.appendingPathComponent("Demo.plist").path)
let peer = HelperSocketPeerCredentials(uid: UInt32(getuid()), gid: UInt32(getgid()), pid: getpid())
let identity = HelperPeerIdentity(uid: peer.uid, gid: peer.gid, pid: peer.pid,
    cdHashHex: String(repeating: "a", count: 40), pidVersion: nil, auditSessionID: nil)
let context = HelperAuthenticatedPeerContext(peer: peer, identity: identity,
    sessionNonce: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), authenticatedAt: Date())
let dpkgInfo = base.appendingPathComponent("dpkg-info", isDirectory: true)
try fm.createDirectory(at: dpkgInfo, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
try Data("/usr/lib/example/another-plugin.dylib\n".utf8).write(to: dpkgInfo.appendingPathComponent("other.list"))
try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dpkgInfo.appendingPathComponent("other.list").path)
let ownershipProof = try HelperPackageOwnershipResolver().resolve(pluginDirectory: root.path,
    fileNames: ["Demo.dylib", "Demo.plist"], infoDirectories: [dpkgInfo.path])
try Data((root.path + "/Demo.dylib\n").utf8).write(to: dpkgInfo.appendingPathComponent("owned-package.list"))
try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dpkgInfo.appendingPathComponent("owned-package.list").path)
do {
    _ = try HelperPackageOwnershipResolver().resolve(pluginDirectory: root.path,
        fileNames: ["Demo.dylib", "Demo.plist"], infoDirectories: [dpkgInfo.path])
    throw NSError(domain: "P1-24", code: 3, userInfo: [NSLocalizedDescriptionKey: "dpkg-owned plugin was treated as unowned"])
} catch HelperPackageOwnershipProof.ProofError.packageOwned { }
try fm.removeItem(at: dpkgInfo.appendingPathComponent("owned-package.list"))
let proof = try HelperFirstInstallManifestBootstrap().createManifest(directoryPath: root.path, context: context,
    requestID: UUID(), pluginID: UUID(), dylibFileName: "Demo.dylib", plistFileName: "Demo.plist",
    hardBoundBundleIdentifier: "com.example.app", softAssociations: [], dylibBytes: dylib, plistBytes: plist,
    packageOwnership: ownershipProof)
try check24(proof.manifestSchemaVersion == 3 && proof.isFirstInstallAuthorization, "bootstrap did not produce first-install Schema 3 proof")
let retryProof = try HelperFirstInstallManifestBootstrap().createManifest(directoryPath: root.path, context: context,
    requestID: UUID(), pluginID: proof.pluginID, dylibFileName: "Demo.dylib", plistFileName: "Demo.plist",
    hardBoundBundleIdentifier: "com.example.app", softAssociations: [], dylibBytes: dylib, plistBytes: plist,
    packageOwnership: ownershipProof)
try check24(retryProof.manifestSHA256 == proof.manifestSHA256, "same first-install retry did not return identical proof")

let plans = [
    HelperClosedExecutionPlan(requestID: UUID(), pluginID: proof.pluginID, action: .copyFile,
        sourceRelativePath: "task/Demo.dylib", destinationRelativePath: "Demo.dylib",
        expectedSHA256: proof.dylibSHA256, operation: .installDylib),
    HelperClosedExecutionPlan(requestID: UUID(), pluginID: proof.pluginID, action: .copyFile,
        sourceRelativePath: "task/Demo.plist", destinationRelativePath: "Demo.plist",
        expectedSHA256: proof.plistSHA256, operation: .replaceFilterPlist)
]
let roots = try HelperSafeFileExecutor.Roots(stagingRoot: staging.path, targetDirectory: root.path, expectedStagingUID: UInt32(getuid()))
_ = try HelperSafeFileExecutor(roots: roots).execute(plans, proof: proof)
let verified = try HelperOwnershipProofVerifier().verify(pluginDirectory: root.path, dylibFileName: "Demo.dylib",
    plistFileName: "Demo.plist", manifestFileName: "Demo.fk.json", packageOwnership: .verifiedUnowned)
try check24(verified.pluginID == proof.pluginID, "deployed first-install manifest did not verify")
let conflictRoot = base.appendingPathComponent("conflict", isDirectory: true)
try fm.createDirectory(at: conflictRoot, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
try Data("foreign plist".utf8).write(to: conflictRoot.appendingPathComponent("Demo.plist"))
try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: conflictRoot.appendingPathComponent("Demo.plist").path)
let conflictRoots = try HelperSafeFileExecutor.Roots(stagingRoot: staging.path, targetDirectory: conflictRoot.path, expectedStagingUID: UInt32(getuid()))
do {
    _ = try HelperSafeFileExecutor(roots: conflictRoots).execute(plans, proof: proof)
    throw NSError(domain: "P1-24", code: 4, userInfo: [NSLocalizedDescriptionKey: "first install replaced an existing plist"])
} catch HelperSafeFileExecutor.ExecutorError.targetConflict { }

// Crash recovery: dylib was committed, old plist is in the exact transaction backup, plist temp remains.
let recoveryRoot = base.appendingPathComponent("recovery", isDirectory: true)
try fm.createDirectory(at: recoveryRoot, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
let old = Data("old-plist".utf8), newDylib = Data("new-dylib".utf8), newPlist = Data("new-plist".utf8)
let journal = try HelperTransactionJournal(transactionID: UUID(), pluginID: UUID(), dylibFileName: "Recover.dylib",
    plistFileName: "Recover.plist", dylibSHA256: SHA256Digest.hex(newDylib), plistSHA256: SHA256Digest.hex(newPlist),
    previousPlistSHA256: SHA256Digest.hex(old), phase: .installingDylib)
try newDylib.write(to: recoveryRoot.appendingPathComponent("Recover.dylib"))
try old.write(to: recoveryRoot.appendingPathComponent(journal.previousPlistName))
try newPlist.write(to: recoveryRoot.appendingPathComponent(journal.temporaryPlistName))
for name in ["Recover.dylib", journal.previousPlistName, journal.temporaryPlistName] {
    try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: recoveryRoot.appendingPathComponent(name).path)
}
let store = try HelperTransactionJournalStore(directoryPath: recoveryRoot.path)
try store.save(journal)
try check24(HelperStartupRecoveryCheck().inspect(pluginDirectory: recoveryRoot.path) == .recoveryRequired, "startup check missed pending journal")
let recoveryResult = try HelperTransactionRecoveryExecutor().reconcile(directoryPath: recoveryRoot.path)
try check24(recoveryResult == .recovered, "recovery executor did not complete")
let restoredPlist = try Data(contentsOf: recoveryRoot.appendingPathComponent("Recover.plist"))
try check24(restoredPlist == old, "old plist was not restored")
try check24(!fm.fileExists(atPath: recoveryRoot.appendingPathComponent("Recover.dylib").path), "new dylib was not rolled back")
let clearedJournal = try store.load()
try check24(clearedJournal == nil, "journal was not cleared")
try check24(HelperStartupRecoveryCheck().inspect(pluginDirectory: recoveryRoot.path) == .clean, "startup check did not clear after recovery")

let committedRoot = base.appendingPathComponent("committed", isDirectory: true)
try fm.createDirectory(at: committedRoot, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
let committedJournal = try HelperTransactionJournal(transactionID: UUID(), pluginID: UUID(), dylibFileName: "Done.dylib",
    plistFileName: "Done.plist", dylibSHA256: SHA256Digest.hex(newDylib), plistSHA256: SHA256Digest.hex(newPlist),
    previousPlistSHA256: SHA256Digest.hex(old), phase: .committed)
try newDylib.write(to: committedRoot.appendingPathComponent("Done.dylib"))
try newPlist.write(to: committedRoot.appendingPathComponent("Done.plist"))
try old.write(to: committedRoot.appendingPathComponent(committedJournal.previousPlistName))
for name in ["Done.dylib", "Done.plist", committedJournal.previousPlistName] {
    try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: committedRoot.appendingPathComponent(name).path)
}
let committedStore = try HelperTransactionJournalStore(directoryPath: committedRoot.path)
try committedStore.save(committedJournal)
let committedRecovery = try HelperTransactionRecoveryExecutor().reconcile(directoryPath: committedRoot.path)
try check24(committedRecovery == .recovered, "committed recovery did not clean backup")
try check24(fm.fileExists(atPath: committedRoot.appendingPathComponent("Done.dylib").path), "committed dylib was removed")
try check24(fm.fileExists(atPath: committedRoot.appendingPathComponent("Done.plist").path), "committed plist was removed")
let committedJournalAfter = try committedStore.load()
try check24(committedJournalAfter == nil, "committed journal was not cleared")
let committedSecondPass = try HelperTransactionRecoveryExecutor().reconcile(directoryPath: committedRoot.path)
try check24(committedSecondPass == .clean, "committed recovery was not idempotent")

let foreignRoot = base.appendingPathComponent("foreign", isDirectory: true)
try fm.createDirectory(at: foreignRoot, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
let foreignJournal = try HelperTransactionJournal(transactionID: UUID(), pluginID: UUID(), dylibFileName: "Foreign.dylib",
    plistFileName: "Foreign.plist", dylibSHA256: SHA256Digest.hex(newDylib), plistSHA256: SHA256Digest.hex(newPlist),
    previousPlistSHA256: nil, phase: .installingDylib)
try Data("foreign bytes".utf8).write(to: foreignRoot.appendingPathComponent("Foreign.dylib"))
try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: foreignRoot.appendingPathComponent("Foreign.dylib").path)
let foreignStore = try HelperTransactionJournalStore(directoryPath: foreignRoot.path)
try foreignStore.save(foreignJournal)
let foreignRecovery = try HelperTransactionRecoveryExecutor().reconcile(directoryPath: foreignRoot.path)
try check24(foreignRecovery == .manualIntervention, "foreign bytes were not escalated")
try check24(fm.fileExists(atPath: foreignRoot.appendingPathComponent("Foreign.dylib").path), "foreign bytes were deleted")
print("P1-24 bootstrap/recovery smoke: PASS (first-install bootstrap/deploy, package-owner rejection, startup pending gate, rollback, committed cleanup, manual-intervention preservation, idempotence)")
