import Foundation
import Glibc


struct ElleKitBinaryVersion { init(currentVersion: String?, compatibilityVersion: String?, installName: String?, uuid: String?, architecture: String?, is64Bit: Bool) {} }
enum ElleKitBinaryMetadataError: Error { case truncated, malformedLoadCommand, noSupportedSlice, notMachO }

enum HelperPolicy {
    static func isAbsoluteCleanPath(_ s: String) -> Bool { s.hasPrefix("/") && !s.contains("\0") && !s.split(separator: "/").contains("..") }
    static func isValidHash(_ s: String) -> Bool { s.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil }
    static func isValidCDHash(_ s: String) -> Bool { s.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil }
}
struct HelperInstallerProvisioningBundle {}
struct HelperInstallerTransactionPlan { enum Action: Equatable { case install, upgrade, repin }; let jbRootPath: String; let action: Action }
struct HelperInstallerTransactionJournal: Equatable {
    enum State { case artifactsVerified, previousReleasePreserved }
    enum PendingOperation { case preservePreviousRelease }
    enum Event { case preservePreviousRelease }
    let transactionID: UUID; let action: HelperInstallerTransactionPlan.Action; let releaseIdentifier: String; let generation: UInt64
    var state: State = .artifactsVerified; var pendingOperation: PendingOperation? = .preservePreviousRelease
    mutating func apply(_ event: Event) throws { state = .previousReleasePreserved; pendingOperation = nil }
}
struct HelperInstallerDurableJournalStore {
    static var values: [UUID: HelperInstallerTransactionJournal] = [:]
    static var failNextSave = false
    func save(_ value: HelperInstallerTransactionJournal) throws { if Self.failNextSave { Self.failNextSave = false; throw SmokeError.failed }; Self.values[value.transactionID] = value }
    func load(transactionID: UUID) throws -> HelperInstallerTransactionJournal { guard let v = Self.values[transactionID] else { throw SmokeError.failed }; return v }
}
struct HelperPreparedRootInstall { let plan: HelperInstallerTransactionPlan; let release: HelperRootReleaseSet.Verified; let initialJournal: HelperInstallerTransactionJournal }
struct HelperRootReleaseSet {
    enum Artifact: String, CaseIterable { case executable, deploymentManifest, launchDaemon }
    struct Verified: Equatable { let releaseIdentifier: String; let generation: UInt64; let hashes: [Artifact:String]; let byteCounts: [Artifact:Int] }
    static let executablePath = "usr/libexec/filterkit-helper"
    static let manifestPath = "Library/FilterKit/Helper/Deployment.json"
    static let launchDaemonPath = "Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"
}
struct HelperInstallerSharedTransactionLock { static func withExclusiveLock<T>(jbroot: String, _ body: () throws -> T) throws -> T { try body() } }
enum SmokeError: Error { case failed }
func pass(_ ok: Bool, _ label: String, _ count: inout Int) { count += 1; if !ok { fputs("FAIL: \(label)\n", stderr); exit(1) }; print("PASS: \(label)") }
func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)] }
func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 255), UInt8((v >> 8) & 255), UInt8((v >> 16) & 255), UInt8(v >> 24)] }
func makeMachO() -> (Data,String) {
    var cd = [UInt8](repeating: 0, count: 112)
    func put(_ o: Int,_ v: UInt32) { cd.replaceSubrange(o..<(o+4), with: be32(v)) }
    put(0,0xFADE0C02); put(4,UInt32(cd.count)); put(8,0x20200); put(20,64); cd[36]=32; cd[37]=2; put(48,88)
    let id = Array("filterkit-helper".utf8)+[0], team = Array("TEAM1234".utf8)+[0]
    cd.replaceSubrange(64..<(64+id.count),with:id); cd.replaceSubrange(88..<(88+team.count),with:team)
    let hash = String(SHA256Digest.hex(Data(cd)).prefix(40))
    let blob = be32(0xFADE0CC0)+be32(UInt32(20+cd.count))+be32(1)+be32(0)+be32(20)+cd
    let cmd = le32(0x1D)+le32(16)+le32(48)+le32(UInt32(blob.count))
    var header=[UInt8](repeating:0,count:32); header.replaceSubrange(0..<4,with:[0xCF,0xFA,0xED,0xFE]); header.replaceSubrange(4..<8,with:le32(0x0100000C)); header.replaceSubrange(12..<16,with:le32(2)); header.replaceSubrange(16..<20,with:le32(1)); header.replaceSubrange(20..<24,with:le32(16))
    return (Data(header+cmd+blob),hash)
}
func mkdir(_ path: String) throws { try FileManager.default.createDirectory(atPath:path,withIntermediateDirectories:true); _ = chmod(path,0o700) }
func writeActive(_ data: Data, path: String, mode: mode_t) throws { try mkdir((path as NSString).deletingLastPathComponent); try data.write(to:URL(fileURLWithPath:path)); _ = chmod(path,mode) }
@main struct Main {
 static func main() throws {
  var checks=0
  let root="/root/p244-r4-\(UUID().uuidString.lowercased())"
  try mkdir(root)
  defer { try? FileManager.default.removeItem(atPath:root) }
  let backupRoot=root+"/"+HelperInstallerPreviousReleaseStore.relativeRootPath; try mkdir(backupRoot)
  let (binary,cdhash)=makeMachO()
  let manifest=Data("{\"schemaVersion\":2,\"jbRootPath\":\"\(root)\",\"executionEnabled\":false}".utf8)
  let launch=try PropertyListSerialization.data(fromPropertyList:["Label":"cn.yfen.filterkit.helper","ProgramArguments":[root+"/usr/libexec/filterkit-helper"],"Disabled":true,"RunAtLoad":false,"KeepAlive":false],format:.xml,options:0)
  let active:[String:Data]=[HelperRootReleaseSet.executablePath:binary,HelperRootReleaseSet.manifestPath:manifest,HelperRootReleaseSet.launchDaemonPath:launch]
  for (p,d) in active { let mode:mode_t = p == HelperRootReleaseSet.executablePath ? 0o755 : (p == HelperRootReleaseSet.manifestPath ? 0o600 : 0o644); try writeActive(d,path:root+"/"+p,mode:mode) }
  var hashes:[HelperRootReleaseSet.Artifact:String]=[:], counts:[HelperRootReleaseSet.Artifact:Int]=[:]
  for (a,p) in zip(HelperRootReleaseSet.Artifact.allCases,[HelperRootReleaseSet.executablePath,HelperRootReleaseSet.manifestPath,HelperRootReleaseSet.launchDaemonPath]) { hashes[a]=SHA256Digest.hex(active[p]!); counts[a]=active[p]!.count }
  let previous=HelperRootReleaseSet.Verified(releaseIdentifier:"previous-1",generation:9,hashes:hashes,byteCounts:counts)
  let id=UUID(); let journal=HelperInstallerTransactionJournal(transactionID:id,action:.upgrade,releaseIdentifier:"target-2",generation:10)
  HelperInstallerDurableJournalStore.values[id]=journal
  let prepared=HelperPreparedRootInstall(plan:HelperInstallerTransactionPlan(jbRootPath:root,action:.upgrade),release:HelperRootReleaseSet.Verified(releaseIdentifier:"target-2",generation:10,hashes:hashes,byteCounts:counts),initialJournal:journal)
  let store=try HelperInstallerPreviousReleaseStore(jbRootPath:root), js=HelperInstallerDurableJournalStore()

  let receipt=try store.preserve(prepared:prepared,previousRelease:previous,previousHelperCDHash:cdhash,previousTeamIdentifier:"TEAM1234",journal:journal,journalStore:js)
  pass(receipt.transactionID==id && receipt.previousReleaseIdentifier=="previous-1","backup receipt binds transaction and previous release",&checks)
  let inspection=try store.inspect(transactionID:id,expected:previous)
  pass(inspection.state == .complete && inspection.observedHashes == hashes,"three-file backup re-read and hashes match",&checks)
  let updated=try js.load(transactionID:id)
  pass(updated.state == .previousReleasePreserved && updated.pendingOperation == nil,"Journal completion recorded after durable backup",&checks)
  do { _=try store.preserve(prepared:prepared,previousRelease:previous,previousHelperCDHash:cdhash,previousTeamIdentifier:"TEAM1234",journal:journal,journalStore:js); pass(false,"existing backup is never overwritten",&checks) }
  catch HelperInstallerPreviousReleaseStore.StoreError.backupAlreadyExists { pass(true,"existing backup is never overwritten",&checks) }
  let tamper=root+"/"+receipt.relativeDirectory+"/Deployment.json"; try Data("tampered".utf8).write(to:URL(fileURLWithPath:tamper)); _=chmod(tamper,0o600)
  let bad=try store.inspect(transactionID:id,expected:previous)
  pass(bad.state == .mismatched && bad.mismatchedArtifacts.contains(.deploymentManifest),"backup tampering detected",&checks)
  // A crash after the first artifact leaves a partial, inspectable backup and does not advance Journal.
  let crashID=UUID(); let crashJournal=HelperInstallerTransactionJournal(transactionID:crashID,action:.upgrade,releaseIdentifier:"target-2",generation:10)
  HelperInstallerDurableJournalStore.values[crashID]=crashJournal
  let crashPrepared=HelperPreparedRootInstall(plan:prepared.plan,release:prepared.release,initialJournal:crashJournal)
  do { _=try store.preserve(prepared:crashPrepared,previousRelease:previous,previousHelperCDHash:cdhash,previousTeamIdentifier:"TEAM1234",journal:crashJournal,journalStore:js,faultAt:.afterExecutable); pass(false,"fault injection interrupts backup after executable",&checks) }
  catch HelperInstallerPreviousReleaseStore.StoreError.injectedCrash(.executable) { pass(true,"fault injection interrupts backup after executable",&checks) }
  let crashInspection=try store.inspect(transactionID:crashID,expected:previous)
  let crashPersisted=try js.load(transactionID:crashID)
  pass(crashInspection.state == .partial && crashPersisted.pendingOperation == .preservePreviousRelease,"partial backup remains visible and Journal intent stays pending",&checks)
  // A failed Journal completion keeps the already durable backup for reconciliation.
  let uncertainID=UUID(); let uncertainJournal=HelperInstallerTransactionJournal(transactionID:uncertainID,action:.upgrade,releaseIdentifier:"target-2",generation:10)
  HelperInstallerDurableJournalStore.values[uncertainID]=uncertainJournal
  let uncertainPrepared=HelperPreparedRootInstall(plan:prepared.plan,release:prepared.release,initialJournal:uncertainJournal)
  HelperInstallerDurableJournalStore.failNextSave=true
  do { _=try store.preserve(prepared:uncertainPrepared,previousRelease:previous,previousHelperCDHash:cdhash,previousTeamIdentifier:"TEAM1234",journal:uncertainJournal,journalStore:js); pass(false,"Journal completion failure is surfaced",&checks) }
  catch HelperInstallerPreviousReleaseStore.StoreError.journalCommitIndeterminate { pass(true,"Journal completion failure is surfaced",&checks) }
  let uncertainInspection=try store.inspect(transactionID:uncertainID,expected:previous)
  let uncertainPersisted=try js.load(transactionID:uncertainID)
  pass(uncertainInspection.state == .complete && uncertainPersisted.pendingOperation == .preservePreviousRelease,"complete backup is retained while Journal remains pending",&checks)
  let badID=UUID(); let badJournal=HelperInstallerTransactionJournal(transactionID:badID,action:.upgrade,releaseIdentifier:"target-2",generation:10); HelperInstallerDurableJournalStore.values[badID]=badJournal
  let badPrepared=HelperPreparedRootInstall(plan:prepared.plan,release:prepared.release,initialJournal:badJournal)
  let activeExe=root+"/"+HelperRootReleaseSet.executablePath; try Data("changed".utf8).write(to:URL(fileURLWithPath:activeExe)); _=chmod(activeExe,0o755)
  do { _=try store.preserve(prepared:badPrepared,previousRelease:previous,previousHelperCDHash:cdhash,previousTeamIdentifier:"TEAM1234",journal:badJournal,journalStore:js); pass(false,"active source mismatch blocks backup",&checks) }
  catch HelperInstallerPreviousReleaseStore.StoreError.activeReleaseMismatch { pass(true,"active source mismatch blocks backup",&checks) }
  print("RESULT: \(checks)/10 passed")
 }
}
