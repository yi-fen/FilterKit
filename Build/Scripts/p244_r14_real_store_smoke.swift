import Foundation
import Glibc

// Narrow Host shims for policy/model types only. The three Store implementations,
// TransactionJournal reducer, SHA-256 implementation, and descriptor-relative reads
// are compiled from production sources below.
enum HelperPolicy {
    static func isAbsoluteCleanPath(_ s: String) -> Bool { s.hasPrefix("/") && !s.contains("\0") && !s.split(separator: "/").contains("..") }
    static func isValidHash(_ s: String) -> Bool { s.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil }
    static func isValidCDHash(_ s: String) -> Bool { s.range(of: "^[0-9a-fA-F]{40,64}$", options: .regularExpression) != nil }
}
struct HelperInstallerTransactionPlan {
    enum Action: String, Codable { case install, upgrade, repin }
    let jbRootPath: String; let action: Action
}
struct HelperSignedProvisioningManifest: Codable {
    struct Payload: Codable { let jbRootPath: String; let releaseIdentifier: String; let generation: UInt64; let helperCDHash: String; let teamIdentifier: String? }
    let payload: Payload
}
struct HelperInstallerArtifactDigest { let relativePath: String; let sha256: String }
struct HelperRootReleaseSet {
    enum Artifact: String, CaseIterable, Codable, Hashable { case executable, deploymentManifest, launchDaemon }
    struct Verified: Equatable { let releaseIdentifier: String; let generation: UInt64; let hashes: [Artifact:String]; let byteCounts: [Artifact:Int] }
    static let executablePath = "usr/libexec/filterkit-helper"
    static let manifestPath = "Library/FilterKit/Helper/Deployment.json"
    static let launchDaemonPath = "Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"
    func verify(bundle: HelperSignedProvisioningManifest.Payload, artifacts: [String:Data], expectedDigests: [HelperInstallerArtifactDigest]) throws -> Verified {
        var hashes:[Artifact:String] = [:], counts:[Artifact:Int] = [:]
        let pairs:[(Artifact,String)] = [(.executable,Self.executablePath),(.deploymentManifest,Self.manifestPath),(.launchDaemon,Self.launchDaemonPath)]
        for (a,p) in pairs { guard let d=artifacts[p], expectedDigests.first(where:{$0.relativePath == p})?.sha256 == SHA256Digest.hex(d) else { throw SmokeFailure.failed }; hashes[a]=SHA256Digest.hex(d); counts[a]=d.count }
        return Verified(releaseIdentifier:bundle.releaseIdentifier,generation:bundle.generation,hashes:hashes,byteCounts:counts)
    }
}
struct HelperPreparedRootInstall {
    let plan: HelperInstallerTransactionPlan
    let initialJournal: HelperInstallerTransactionJournal
    let release: HelperRootReleaseSet.Verified
    let provisioningEnvelopeData: Data
    let provisioningEnvelopeSHA256: String
}
struct HelperInstallerSharedTransactionLock {
    static func withExclusiveLock<T>(jbroot: String, _ body: () throws -> T) throws -> T { try body() }
}
struct MachOSliceMetadata { let codeSignatureState: String; let codeSignatureTeamIdentifier: String?; let cdHash: String? }
struct MachOMetadataReader { func readSlices(data: Data) throws -> [MachOSliceMetadata] { [] } }
enum SmokeFailure: Error { case failed }

@inline(__always) func check(_ condition: @autoclosure () -> Bool, _ label: String, _ failures: inout [String]) {
    if condition() { print("PASS: \(label)") } else { print("FAIL: \(label)"); failures.append(label) }
}
func makeDir(_ path: String, _ mode: mode_t = 0o700) throws { try FileManager.default.createDirectory(atPath:path,withIntermediateDirectories:true); guard chmod(path,mode)==0 else { throw SmokeFailure.failed } }
func writeFile(_ path:String,_ data:Data,_ mode:mode_t) throws { try data.write(to:URL(fileURLWithPath:path)); guard chmod(path,mode)==0 else { throw SmokeFailure.failed } }

let root = "/root/filterkit-p244-r14-\(UUID().uuidString.lowercased())"
let jb = root + "/jbroot"
let txn = UUID()
var failures:[String] = []
do {
    try makeDir(root); try makeDir(jb)
    let stagedRoot = jb + "/" + HelperInstallerStagedReleaseStore.relativeRootPath
    let previousRoot = jb + "/" + HelperInstallerPreviousReleaseStore.relativeRootPath
    let journalRoot = root + "/journal"
    try makeDir(stagedRoot); try makeDir(previousRoot); try makeDir(journalRoot)
    let stagedDir = stagedRoot + "/" + txn.uuidString.lowercased()
    let previousDir = previousRoot + "/" + txn.uuidString.lowercased()
    try makeDir(stagedDir); try makeDir(previousDir)

    let names:[HelperRootReleaseSet.Artifact:String] = [.executable:"filterkit-helper",.deploymentManifest:"Deployment.json",.launchDaemon:"cn.yfen.filterkit.helper.plist"]
    let modes:[HelperRootReleaseSet.Artifact:mode_t] = [.executable:0o755,.deploymentManifest:0o600,.launchDaemon:0o644]
    let stagedBytes:[HelperRootReleaseSet.Artifact:Data] = [.executable:Data("new-helper".utf8),.deploymentManifest:Data("new-manifest".utf8),.launchDaemon:Data("new-launchd".utf8)]
    let previousBytes:[HelperRootReleaseSet.Artifact:Data] = [.executable:Data("old-helper".utf8),.deploymentManifest:Data("old-manifest".utf8),.launchDaemon:Data("old-launchd".utf8)]
    var stagedHashes:[HelperRootReleaseSet.Artifact:String]=[:], previousHashes:[HelperRootReleaseSet.Artifact:String]=[:]
    for a in HelperRootReleaseSet.Artifact.allCases {
        let name=names[a]!, mode=modes[a]!
        try writeFile(stagedDir+"/"+name,stagedBytes[a]!,mode); try writeFile(previousDir+"/"+name,previousBytes[a]!,mode)
        stagedHashes[a]=SHA256Digest.hex(stagedBytes[a]!); previousHashes[a]=SHA256Digest.hex(previousBytes[a]!)
    }

    let stagedStore = try HelperInstallerStagedReleaseStore(jbRootPath: jb)
    let previousStore = try HelperInstallerPreviousReleaseStore(jbRootPath: jb)
    let stagedRead = try stagedStore.loadVerifiedArtifactsForActivation(transactionID:txn,expectedHashes:stagedHashes)
    let previousRead = try previousStore.loadVerifiedArtifactsForActivation(transactionID:txn,expectedHashes:previousHashes)
    check(stagedRead.count == 3 && stagedRead.allSatisfy({ stagedHashes[$0.key] == SHA256Digest.hex($0.value) }),"real Staged Store reads three verified artifacts",&failures)
    check(previousRead.count == 3 && previousRead.allSatisfy({ previousHashes[$0.key] == SHA256Digest.hex($0.value) }),"real Previous Store reads three verified artifacts",&failures)

    var journal = try HelperInstallerTransactionJournal(transactionID:txn,action:.upgrade,releaseIdentifier:"release-new",generation:2)
    try journal.apply(.intentVerifyArtifacts); try journal.apply(.verifyArtifacts)
    try journal.apply(.intentPreservePreviousRelease); try journal.apply(.preservePreviousRelease)
    try journal.apply(.intentStageRelease); try journal.apply(.stageRelease)
    try journal.apply(.intentActivateRelease)
    let journalStore = HelperInstallerDurableJournalStore(directoryPath:journalRoot)
    try journalStore.save(journal)
    let loaded = try journalStore.load(transactionID:txn)
    check(loaded == journal && loaded.state == .staged && loaded.pendingOperation == .activateRelease,"real Durable Journal persists and reloads hash-chained Upgrade intent",&failures)

    // Content tampering must be rejected by the production Staged reader.
    try writeFile(stagedDir+"/Deployment.json",Data("tampered".utf8),0o600)
    do { _ = try stagedStore.loadVerifiedArtifactsForActivation(transactionID:txn,expectedHashes:stagedHashes); check(false,"Staged tamper rejected",&failures) }
    catch { check(true,"Staged tamper rejected",&failures) }
    try writeFile(stagedDir+"/Deployment.json",stagedBytes[.deploymentManifest]!,0o600)
    var wrongHashes = stagedHashes; wrongHashes[.launchDaemon] = String(repeating:"0",count:64)
    do { _ = try stagedStore.loadVerifiedArtifactsForActivation(transactionID:txn,expectedHashes:wrongHashes); check(false,"Staged expected-hash mismatch rejected",&failures) }
    catch { check(true,"Staged expected-hash mismatch rejected",&failures) }
    let extraPath = stagedDir+"/unexpected.bin"; try writeFile(extraPath,Data("extra".utf8),0o600)
    do { _ = try stagedStore.loadVerifiedArtifactsForActivation(transactionID:txn,expectedHashes:stagedHashes); check(false,"Staged unexpected entry rejected",&failures) }
    catch { check(true,"Staged unexpected entry rejected",&failures) }
    try FileManager.default.removeItem(atPath:extraPath)

    // Previous symlink substitution must be rejected by descriptor-relative O_NOFOLLOW.
    let previousManifest = previousDir+"/Deployment.json"
    try FileManager.default.removeItem(atPath:previousManifest)
    try FileManager.default.createSymbolicLink(atPath:previousManifest,withDestinationPath:previousDir+"/filterkit-helper")
    do { _ = try previousStore.loadVerifiedArtifactsForActivation(transactionID:txn,expectedHashes:previousHashes); check(false,"Previous symlink rejected",&failures) }
    catch { check(true,"Previous symlink rejected",&failures) }
    try FileManager.default.removeItem(atPath:previousManifest)
    try writeFile(previousManifest,previousBytes[.deploymentManifest]!,0o644)
    do { _ = try previousStore.loadVerifiedArtifactsForActivation(transactionID:txn,expectedHashes:previousHashes); check(false,"Previous unsafe mode rejected",&failures) }
    catch { check(true,"Previous unsafe mode rejected",&failures) }

    // Journal corruption is rejected after modifying the persisted bytes.
    let journalPath = journalRoot+"/"+txn.uuidString.lowercased()+".json"
    var jdata=try Data(contentsOf:URL(fileURLWithPath:journalPath)); jdata[jdata.count/2] ^= 0x01
    try writeFile(journalPath,jdata,0o600)
    do { _ = try journalStore.load(transactionID:txn); check(false,"corrupt Durable Journal rejected",&failures) }
    catch { check(true,"corrupt Durable Journal rejected",&failures) }

    check(geteuid()==0,"Host fixture executes as root for root-owned Store checks",&failures)
} catch { print("FATAL: \(error)"); failures.append("unexpected error") }
try? FileManager.default.removeItem(atPath:root)
print("RESULT: \(failures.isEmpty ? "PASS" : "FAIL") (\(10-failures.count)/10 assertions)")
if !failures.isEmpty { exit(1) }
