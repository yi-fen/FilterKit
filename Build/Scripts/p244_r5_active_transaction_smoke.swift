import Foundation
import Glibc

// Host-only dependency shims. The real transaction executor and SHA-256 implementation are
// compiled and executed; Darwin launchd/XPC behavior is deliberately not simulated as production.
enum HelperPolicy {
    static func isAbsoluteCleanPath(_ value: String) -> Bool {
        value.hasPrefix("/") && !value.contains("\0") && !value.split(separator: "/").contains("..")
    }
    static func isValidHash(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }
}
struct HelperInstallerProvisioningBundle: Codable {
    let jbRootPath: String; let releaseIdentifier: String; let generation: UInt64
    let helperCDHash: String; let teamIdentifier: String?
}
struct HelperSignedProvisioningManifest: Decodable {
    let payload: HelperInstallerProvisioningBundle
}
struct HelperInstallerArtifactDigest { let relativePath: String; let sha256: String }

struct HelperInstallerDescriptorFilesystemObserver {
    struct ReleasePointer: Codable, Equatable {
        let schemaVersion: Int; let transactionID: UUID; let releaseIdentifier: String
        let generation: UInt64; let artifactHashes: [String:String]
    }
    struct FileRecord { let sha256: String }
    private let jbRootPath: String
    init(jbRootPath: String, expectedOwnerUID: UInt32 = 0) { self.jbRootPath = jbRootPath }
    func observeArtifactSet(paths: [HelperRootReleaseSet.Artifact:String]) throws -> [HelperRootReleaseSet.Artifact:FileRecord] {
        var result: [HelperRootReleaseSet.Artifact:FileRecord] = [:]
        for (artifact, path) in paths {
            let data = try Data(contentsOf: URL(fileURLWithPath: jbRootPath).appendingPathComponent(path))
            result[artifact] = FileRecord(sha256: SHA256Digest.hex(data))
        }
        return result
    }
    func observeActiveReleasePointer() throws -> ReleasePointer {
        let url = URL(fileURLWithPath: jbRootPath).appendingPathComponent("Library/FilterKit/Helper/active-release.json")
        return try JSONDecoder().decode(ReleasePointer.self, from: Data(contentsOf: url))
    }
}
struct HelperRootReleaseSet {
    enum Artifact: String, CaseIterable, Codable, Hashable { case executable, deploymentManifest, launchDaemon }
    struct Verified: Equatable {
        let releaseIdentifier: String; let generation: UInt64
        let hashes: [Artifact:String]; let byteCounts: [Artifact:Int]
    }
    static let executablePath = "usr/libexec/filterkit-helper"
    static let manifestPath = "Library/FilterKit/Helper/Deployment.json"
    static let launchDaemonPath = "Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"
    static let activeReleasePointerPath = "Library/FilterKit/Helper/active-release.json"
    func verify(bundle: HelperInstallerProvisioningBundle, artifacts: [String: Data], expectedDigests: [HelperInstallerArtifactDigest]) throws -> Verified {
        let expected = Dictionary(uniqueKeysWithValues: expectedDigests.map { ($0.relativePath, $0.sha256) })
        guard Set(artifacts.keys) == Set([Self.executablePath, Self.manifestPath, Self.launchDaemonPath]), expected.count == 3 else { throw SmokeError.invalid }
        var hashes: [Artifact:String] = [:], counts: [Artifact:Int] = [:]
        for (artifact, path) in zip(Artifact.allCases, [Self.executablePath,Self.manifestPath,Self.launchDaemonPath]) {
            guard let bytes = artifacts[path], expected[path] == SHA256Digest.hex(bytes) else { throw SmokeError.invalid }
            hashes[artifact] = SHA256Digest.hex(bytes); counts[artifact] = bytes.count
        }
        return Verified(releaseIdentifier:bundle.releaseIdentifier,generation:bundle.generation,hashes:hashes,byteCounts:counts)
    }
}
struct HelperInstallerTransactionJournal: Equatable {
    enum State { case prepared, artifactsVerified, staged, activated, rollbackRequired, manualIntervention }
    enum PendingOperation { case verifyArtifacts, stageRelease, activateRelease }
    enum Event { case intentVerifyArtifacts, verifyArtifacts, intentStageRelease, stageRelease, intentActivateRelease, activateRelease, requireManualIntervention }
    let transactionID: UUID; let action: Action; let releaseIdentifier: String; let generation: UInt64
    enum Action: Equatable { case install, upgrade, repin }
    var state: State = .prepared; var pendingOperation: PendingOperation?
    init(transactionID: UUID, action: Action, releaseIdentifier: String, generation: UInt64) {
        self.transactionID=transactionID; self.action=action; self.releaseIdentifier=releaseIdentifier; self.generation=generation
    }
    func validateChain() throws {}
    mutating func apply(_ event: Event) throws {
        switch event {
        case .intentVerifyArtifacts: pendingOperation = .verifyArtifacts
        case .verifyArtifacts: pendingOperation = nil; state = .artifactsVerified
        case .intentStageRelease: pendingOperation = .stageRelease
        case .stageRelease: pendingOperation = nil; state = .staged
        case .intentActivateRelease: pendingOperation = .activateRelease
        case .activateRelease: pendingOperation = nil; state = .activated
        case .requireManualIntervention: state = .manualIntervention
        }
    }
}
struct HelperInstallerDurableJournalStore {
    static var values: [UUID: HelperInstallerTransactionJournal] = [:]
    static var failNextSave = false
    func save(_ journal: HelperInstallerTransactionJournal) throws {
        if Self.failNextSave { Self.failNextSave = false; throw SmokeError.failed }
        Self.values[journal.transactionID] = journal
    }
    func load(transactionID: UUID) throws -> HelperInstallerTransactionJournal {
        guard let value = Self.values[transactionID] else { throw SmokeError.failed }; return value
    }
}
struct HelperInstallerStagedReleaseStore {
    enum State { case missing, complete, partial, mismatched }
    struct Inspection { let state: State; let transactionID: UUID; let observedHashes: [HelperRootReleaseSet.Artifact:String] }
    func loadVerifiedArtifactsForActivation(transactionID: UUID, expectedHashes: [HelperRootReleaseSet.Artifact:String]) throws -> [HelperRootReleaseSet.Artifact:Data] { throw SmokeError.failed }
}
struct HelperInstallerPreviousReleaseStore {
    enum State { case missing, complete, partial, mismatched }
    struct Inspection { let state: State; let transactionID: UUID; let observedHashes: [HelperRootReleaseSet.Artifact:String] }
    func loadVerifiedArtifactsForActivation(transactionID: UUID, expectedHashes: [HelperRootReleaseSet.Artifact:String]) throws -> [HelperRootReleaseSet.Artifact:Data] { throw SmokeError.failed }
}
struct HelperInstallerTransactionPlan { let jbRootPath: String; let action: HelperInstallerTransactionJournal.Action }
struct HelperPreparedRootInstall {
    let plan: HelperInstallerTransactionPlan
    let release: HelperRootReleaseSet.Verified
    let provisioningEnvelopeSHA256: String
    let provisioningEnvelopeData: Data
    let initialJournal: HelperInstallerTransactionJournal
}
struct HelperPeerIdentity {
    let pid: Int32; let uid: UInt32; let auditTokenDigest: String?
    let cdHashHex: String; let verifiedCodeIdentifier: String?; let verifiedTeamIdentifier: String?
}
struct HelperInstallerServiceObservation: Equatable {
    enum State: Equatable { case running(pid:Int32, executableSHA256:String), stopped, unknown }
    let launchDaemonLabel: String; let observerCodeIdentitySHA256: String; let state: State
}
struct HelperInstallerAuthenticatedServiceObserver {
    struct Pin { let bundleIdentifier:String; let teamIdentifier:String; let cdHash:String; let observerCodeIdentitySHA256:String; let auditUID:UInt32 }
    struct Report { let challenge:UUID; let observation:HelperInstallerServiceObservation }
    static func validate(report:Report, expectedChallenge:UUID, authenticatedPeer:HelperPeerIdentity, pin:Pin, expectedHelperExecutableSHA256:String) throws -> HelperInstallerServiceObservation {
        guard report.challenge == expectedChallenge, authenticatedPeer.pid > 0,
              authenticatedPeer.uid == pin.auditUID, authenticatedPeer.auditTokenDigest != nil,
              authenticatedPeer.verifiedCodeIdentifier == pin.bundleIdentifier,
              authenticatedPeer.verifiedTeamIdentifier == pin.teamIdentifier,
              authenticatedPeer.cdHashHex == pin.cdHash,
              report.observation.launchDaemonLabel == "cn.yfen.filterkit.helper",
              report.observation.observerCodeIdentitySHA256 == pin.observerCodeIdentitySHA256,
              HelperPolicy.isValidHash(expectedHelperExecutableSHA256) else { throw SmokeError.failed }
        return report.observation
    }
}
enum SmokeError: Error { case invalid, failed }

func check(_ ok: Bool, _ label: String, _ count: inout Int) {
    count += 1; if !ok { fputs("FAIL: \(label)\n", stderr); exit(1) }; print("PASS: \(label)")
}
func makeRoot() throws -> String {
    let path = "/tmp/p244-r5-\(UUID().uuidString.lowercased())"
    try FileManager.default.createDirectory(atPath:path,withIntermediateDirectories:true)
    _ = chmod(path,0o700)
    for p in ["usr/libexec","Library/FilterKit/Helper","Library/LaunchDaemons"] {
        try FileManager.default.createDirectory(atPath:path+"/"+p,withIntermediateDirectories:true)
        _ = chmod(path+"/"+p,0o700)
    }
    return path
}
func makeFixture(root:String, id:UUID) throws -> (HelperRootAtomicActivationExecutor.Release, HelperInstallerTransactionJournal, HelperInstallerStagedReleaseStore.Inspection, HelperInstallerAuthenticatedServiceObserver.Report, HelperPeerIdentity, HelperInstallerAuthenticatedServiceObserver.Pin, UUID, String) {
    let executable = Data([0xcf,0xfa,0xed,0xfe,1,2,3,4,5,6,7,8])
    let manifest = Data("deployment-manifest-fixture".utf8)
    let plist = try PropertyListSerialization.data(fromPropertyList:["Label":"cn.yfen.filterkit.helper","Disabled":true,"RunAtLoad":false],format:.xml,options:0)
    let bytes:[HelperRootAtomicActivationExecutor.Artifact:Data] = [.executable:executable,.deploymentManifest:manifest,.launchDaemon:plist]
    let byPath:[String:Data] = [HelperRootReleaseSet.executablePath:executable,HelperRootReleaseSet.manifestPath:manifest,HelperRootReleaseSet.launchDaemonPath:plist]
    let digests = byPath.map { HelperInstallerArtifactDigest(relativePath:$0.key,sha256:SHA256Digest.hex($0.value)) }
    let helperHash = SHA256Digest.hex(executable)
    let bundle = HelperInstallerProvisioningBundle(jbRootPath:root,releaseIdentifier:"release-r5",generation:51,helperCDHash:String(repeating:"a",count:40),teamIdentifier:"TEAM1234")
    let release = HelperRootAtomicActivationExecutor.Release(bundle:bundle,bytes:bytes,expectedDigests:digests,expectedPreviousHashes:[.executable:nil,.deploymentManifest:nil,.launchDaemon:nil])
    var journal = HelperInstallerTransactionJournal(transactionID:id,action:.install,releaseIdentifier:"release-r5",generation:51)
    try journal.apply(.intentVerifyArtifacts); try journal.apply(.verifyArtifacts)
    try journal.apply(.intentStageRelease); try journal.apply(.stageRelease)
    try journal.apply(.intentActivateRelease)
    let hashes:[HelperRootReleaseSet.Artifact:String] = [.executable:SHA256Digest.hex(executable),.deploymentManifest:SHA256Digest.hex(manifest),.launchDaemon:SHA256Digest.hex(plist)]
    let staged = HelperInstallerStagedReleaseStore.Inspection(state:.complete,transactionID:id,observedHashes:hashes)
    let challenge=UUID(), observerHash=String(repeating:"b",count:64), cdhash=String(repeating:"c",count:40)
    let pin=HelperInstallerAuthenticatedServiceObserver.Pin(bundleIdentifier:"com.example.filterkit.observer",teamIdentifier:"TEAM1234",cdHash:cdhash,observerCodeIdentitySHA256:observerHash,auditUID:0)
    let peer=HelperPeerIdentity(pid:42,uid:0,auditTokenDigest:String(repeating:"d",count:64),cdHashHex:cdhash,verifiedCodeIdentifier:pin.bundleIdentifier,verifiedTeamIdentifier:pin.teamIdentifier)
    let report=HelperInstallerAuthenticatedServiceObserver.Report(challenge:challenge,observation:HelperInstallerServiceObservation(launchDaemonLabel:"cn.yfen.filterkit.helper",observerCodeIdentitySHA256:observerHash,state:.stopped))
    return (release,journal,staged,report,peer,pin,challenge,helperHash)
}

@main struct Main {
 static func main() throws {
    var checks=0; let store=HelperInstallerDurableJournalStore()
    // Successful first-install activation writes three real files and advances the durable Journal.
    do {
        let root=try makeRoot(); defer { try? FileManager.default.removeItem(atPath:root) }
        let id=UUID(), f=try makeFixture(root:root,id:id); HelperInstallerDurableJournalStore.values[id]=f.1
        let executor=try HelperRootAtomicActivationExecutor(rootDirectory:root)
        let result=try executor.activate(f.0,durableJournal:f.1,journalStore:store,stagedInspection:f.2,previousInspection:nil,serviceReport:f.3,expectedChallenge:f.6,authenticatedPeer:f.4,observerPin:f.5,expectedObservedHelperSHA256:f.7)
        let committed=try store.load(transactionID:id)
        check(result.transactionID==id && committed.state == .activated && committed.pendingOperation == nil,"three Active files commit and Durable Journal advances",&checks)
        let active=[root+"/usr/libexec/filterkit-helper",root+"/Library/FilterKit/Helper/Deployment.json",root+"/Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"]
        check(active.allSatisfy{FileManager.default.fileExists(atPath:$0)},"all three Active destinations exist",&checks)
        let pointerPath=root+"/Library/FilterKit/Helper/active-release.json"
        let pointerData=try Data(contentsOf:URL(fileURLWithPath:pointerPath))
        let pointer=try JSONDecoder().decode(HelperInstallerDescriptorFilesystemObserver.ReleasePointer.self,from:pointerData)
        check(pointer.schemaVersion==2 && pointer.transactionID==id && pointer.releaseIdentifier=="release-r5" && pointer.generation==51,"Active Pointer binds transaction, release and generation",&checks)
    }
    // Incomplete staged evidence is rejected before an Active transaction record is created.
    do {
        let root=try makeRoot(); defer { try? FileManager.default.removeItem(atPath:root) }
        let id=UUID(), f=try makeFixture(root:root,id:id); HelperInstallerDurableJournalStore.values[id]=f.1
        let bad=HelperInstallerStagedReleaseStore.Inspection(state:.partial,transactionID:id,observedHashes:f.2.observedHashes)
        let executor=try HelperRootAtomicActivationExecutor(rootDirectory:root)
        do { _=try executor.activate(f.0,durableJournal:f.1,journalStore:store,stagedInspection:bad,previousInspection:nil,serviceReport:f.3,expectedChallenge:f.6,authenticatedPeer:f.4,observerPin:f.5,expectedObservedHelperSHA256:f.7); check(false,"partial staged set rejected",&checks) }
        catch HelperRootAtomicActivationExecutor.Failure.stagedSetNotComplete { check(true,"partial staged set rejected",&checks) }
    }
    // A stale observer challenge is rejected before any Active file or transaction record is written.
    do {
        let root=try makeRoot(); defer { try? FileManager.default.removeItem(atPath:root) }
        let id=UUID(), f=try makeFixture(root:root,id:id); HelperInstallerDurableJournalStore.values[id]=f.1
        let stale=HelperInstallerAuthenticatedServiceObserver.Report(challenge:UUID(),observation:f.3.observation)
        let executor=try HelperRootAtomicActivationExecutor(rootDirectory:root)
        do { _=try executor.activate(f.0,durableJournal:f.1,journalStore:store,stagedInspection:f.2,previousInspection:nil,serviceReport:stale,expectedChallenge:f.6,authenticatedPeer:f.4,observerPin:f.5,expectedObservedHelperSHA256:f.7); check(false,"stale observer challenge rejected",&checks) }
        catch HelperRootAtomicActivationExecutor.Failure.serviceNotAuthenticatedOrStopped {
            check(!FileManager.default.fileExists(atPath:root+"/.filterkit-root-activation.json"),"stale observer challenge rejected before Active mutation",&checks)
        }
    }
    // A running Helper cannot be replaced.
    do {
        let root=try makeRoot(); defer { try? FileManager.default.removeItem(atPath:root) }
        let id=UUID(), f=try makeFixture(root:root,id:id); HelperInstallerDurableJournalStore.values[id]=f.1
        let running=HelperInstallerAuthenticatedServiceObserver.Report(challenge:f.6,observation:HelperInstallerServiceObservation(launchDaemonLabel:"cn.yfen.filterkit.helper",observerCodeIdentitySHA256:f.5.observerCodeIdentitySHA256,state:.running(pid:99,executableSHA256:f.7)))
        let executor=try HelperRootAtomicActivationExecutor(rootDirectory:root)
        do { _=try executor.activate(f.0,durableJournal:f.1,journalStore:store,stagedInspection:f.2,previousInspection:nil,serviceReport:running,expectedChallenge:f.6,authenticatedPeer:f.4,observerPin:f.5,expectedObservedHelperSHA256:f.7); check(false,"running Helper blocks Active replacement",&checks) }
        catch HelperRootAtomicActivationExecutor.Failure.serviceNotAuthenticatedOrStopped { check(true,"running Helper blocks Active replacement",&checks) }
    }
    // If Durable Journal completion fails after the Active commit, the internal commit record is
    // retained. Recovery re-verifies Active bytes and completes the Journal before cleanup.
    do {
        let root=try makeRoot(); defer { try? FileManager.default.removeItem(atPath:root) }
        let id=UUID(), f=try makeFixture(root:root,id:id); HelperInstallerDurableJournalStore.values[id]=f.1
        HelperInstallerDurableJournalStore.failNextSave=true
        let executor=try HelperRootAtomicActivationExecutor(rootDirectory:root)
        do { _=try executor.activate(f.0,durableJournal:f.1,journalStore:store,stagedInspection:f.2,previousInspection:nil,serviceReport:f.3,expectedChallenge:f.6,authenticatedPeer:f.4,observerPin:f.5,expectedObservedHelperSHA256:f.7); check(false,"Journal completion failure is indeterminate",&checks) }
        catch HelperRootAtomicActivationExecutor.Failure.journalCommitIndeterminate { check(true,"Journal completion failure is indeterminate",&checks) }
        let recovery=try executor.recover(durableJournal:f.1,journalStore:store,serviceReport:f.3,expectedChallenge:f.6,authenticatedPeer:f.4,observerPin:f.5,expectedObservedHelperSHA256:f.7)
        let reconciled=try store.load(transactionID:id)
        check(recovery == .committed && reconciled.state == .activated && reconciled.pendingOperation == nil,"committed Active state reconciles pending Durable Journal",&checks)
    }
    // A pointer rename failure leaves the committed Active transaction and backups available
    // for a later recovery attempt; it never reports a successful activation.
    do {
        let root=try makeRoot(); defer { try? FileManager.default.removeItem(atPath:root) }
        let id=UUID(), f=try makeFixture(root:root,id:id); HelperInstallerDurableJournalStore.values[id]=f.1
        let executor=try HelperRootAtomicActivationExecutor(rootDirectory:root)
        do { _=try executor.activate(f.0,durableJournal:f.1,journalStore:store,stagedInspection:f.2,previousInspection:nil,serviceReport:f.3,expectedChallenge:f.6,authenticatedPeer:f.4,observerPin:f.5,expectedObservedHelperSHA256:f.7,faultAt:.beforePointerRename); check(false,"pointer rename failure is indeterminate",&checks) }
        catch HelperRootAtomicActivationExecutor.Failure.activePointerCommitIndeterminate {
            check(FileManager.default.fileExists(atPath:root+"/.filterkit-root-activation.json") && !FileManager.default.fileExists(atPath:root+"/Library/FilterKit/Helper/active-release.json"),"pointer rename failure preserves recovery evidence",&checks)
        }
    }
    // Pointer publication failure occurs after Active and Durable Journal commit. Evidence is
    // retained, and recovery safely republishes the pointer without touching Active artifacts.
    do {
        let root=try makeRoot(); defer { try? FileManager.default.removeItem(atPath:root) }
        let id=UUID(), f=try makeFixture(root:root,id:id); HelperInstallerDurableJournalStore.values[id]=f.1
        let executor=try HelperRootAtomicActivationExecutor(rootDirectory:root)
        do { _=try executor.activate(f.0,durableJournal:f.1,journalStore:store,stagedInspection:f.2,previousInspection:nil,serviceReport:f.3,expectedChallenge:f.6,authenticatedPeer:f.4,observerPin:f.5,expectedObservedHelperSHA256:f.7,faultAt:.afterPointerCommit); check(false,"post-pointer crash retains transaction evidence",&checks) }
        catch HelperRootAtomicActivationExecutor.Failure.injectedFault(.afterPointerCommit) { check(FileManager.default.fileExists(atPath:root+"/.filterkit-root-activation.json"),"post-pointer crash retains transaction evidence",&checks) }
        let committed=try store.load(transactionID:id)
        let pointerPath=root+"/Library/FilterKit/Helper/active-release.json"
        let tamperHandle=try FileHandle(forWritingTo:URL(fileURLWithPath:pointerPath))
        try tamperHandle.truncate(atOffset:0); try tamperHandle.write(contentsOf:Data("{\"tampered\":true}".utf8)); try tamperHandle.close()
        let recovery=try executor.recover(durableJournal:committed,journalStore:store,serviceReport:f.3,expectedChallenge:f.6,authenticatedPeer:f.4,observerPin:f.5,expectedObservedHelperSHA256:f.7)
        let pointer=try Data(contentsOf:URL(fileURLWithPath:pointerPath))
        let decoded=try JSONDecoder().decode(HelperInstallerDescriptorFilesystemObserver.ReleasePointer.self,from:pointer)
        check(recovery == .committed && decoded.transactionID == id,"recovery repairs tampered Active Pointer",&checks)
    }
    // A mid-activation crash is rolled back, but the Journal is deliberately moved to manual
    // intervention rather than silently continuing the installer workflow.
    do {
        let root=try makeRoot(); defer { try? FileManager.default.removeItem(atPath:root) }
        let id=UUID(), f=try makeFixture(root:root,id:id); HelperInstallerDurableJournalStore.values[id]=f.1
        let executor=try HelperRootAtomicActivationExecutor(rootDirectory:root)
        do { _=try executor.activate(f.0,durableJournal:f.1,journalStore:store,stagedInspection:f.2,previousInspection:nil,serviceReport:f.3,expectedChallenge:f.6,authenticatedPeer:f.4,observerPin:f.5,expectedObservedHelperSHA256:f.7,faultAt:.afterFirstActivation); check(false,"fault injection interrupts first Active replacement",&checks) }
        catch HelperRootAtomicActivationExecutor.Failure.injectedFault(.afterFirstActivation) { check(true,"fault injection interrupts first Active replacement",&checks) }
        let recovery=try executor.recover(durableJournal:f.1,journalStore:store,serviceReport:f.3,expectedChallenge:f.6,authenticatedPeer:f.4,observerPin:f.5,expectedObservedHelperSHA256:f.7)
        let recovered=try store.load(transactionID:id)
        check(recovery == .rolledBack && recovered.state == .manualIntervention,"partial Active transaction rolls back and requires manual review",&checks)
    }
    print("RESULT: \(checks)/13 passed")
 }
}
