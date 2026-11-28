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
    func validate() throws { guard HelperPolicy.isAbsoluteCleanPath(jbRootPath), generation > 0, !releaseIdentifier.isEmpty else { throw SmokeError.invalid } }
}
struct HelperSignedProvisioningManifest: Codable {
    let envelopeVersion: Int; let keyIdentifier: String; let algorithm: String
    let payload: HelperInstallerProvisioningBundle; let signatureBase64: String
    func signingBytes() throws -> Data { try JSONEncoder().encode(payload) }
    func signatureBytes() throws -> Data { Data(base64Encoded: signatureBase64) ?? Data() }
}
struct HelperReleaseSigningKey {
    enum Status { case active, retired, revoked }
    let identifier: String; let publicKeyBase64: String; let status: Status
    let minimumGeneration: UInt64?; let maximumGeneration: UInt64?
}
protocol HelperReleaseSignatureChecking { func verify(signature: Data, message: Data, publicKey: Data) -> Bool }
struct DeterministicTestSignatureChecker: HelperReleaseSignatureChecking {
    func verify(signature: Data, message: Data, publicKey: Data) -> Bool { signature == Data(repeating: 0x5a, count: 64) && publicKey.count == 32 && !message.isEmpty }
}
struct HelperEd25519SignatureChecker: HelperReleaseSignatureChecking { func verify(signature: Data, message: Data, publicKey: Data) -> Bool { false } }
enum HelperReleaseTrustAnchors { static let keys: [HelperReleaseSigningKey] = [] }
struct HelperProvisioningSignatureVerifier {
    let keys: [HelperReleaseSigningKey]; let checker: HelperReleaseSignatureChecking
    func verify(_ envelope: HelperSignedProvisioningManifest) throws {
        guard let key = keys.first(where: { $0.identifier == envelope.keyIdentifier }), key.status == .active,
              let pub = Data(base64Encoded: key.publicKeyBase64),
              checker.verify(signature: try envelope.signatureBytes(), message: try envelope.signingBytes(), publicKey: pub) else { throw SmokeError.failed }
    }
}
struct HelperTrustedProvisioningStore {
    enum Failure: Error { case noTrustedBaseline }
    func commit(_ data: Data, action: HelperInstallerTransactionJournal.Action) throws {}
    func recoverPendingTransaction() throws {}
    func loadTrustedBaseline() throws -> Baseline { throw Failure.noTrustedBaseline }
    struct Baseline { let envelopeSHA256: String }
}
enum HelperInstallerProvisioningCommitResult { case committed, rejected, indeterminate }
struct HelperReleaseAcceptanceLock { static func withLock<T>(root: String, _ body: () throws -> T) throws -> T { try body() } }
struct HelperInstallerExecutionGate {
    enum BlockReason { case blocked }
    struct Evidence { let rootInstallerAvailable: Bool; let releaseProvenanceVerified: Bool; let signedArtifactsVerified: Bool; let operatorApproved: Bool }
    func blockReason(plan: HelperInstallerTransactionPlan, evidence: Evidence) -> BlockReason? { nil }
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
struct HelperInstallerTransactionPlan: Equatable { enum Action: Equatable { case install, upgrade, repin }; let jbRootPath: String; let action: Action; var executionEnabled: Bool { false } }
struct HelperInstallerTransactionJournal: Equatable {
    enum State { case prepared, artifactsVerified, staged, activated, rollbackRequired, manualIntervention }
    enum PendingOperation { case verifyArtifacts, stageRelease, activateRelease }
    enum Event { case intentVerifyArtifacts, verifyArtifacts, intentStageRelease, stageRelease, intentActivateRelease, activateRelease, requireManualIntervention }
    let transactionID: UUID; let action: Action; let releaseIdentifier: String; let generation: UInt64
    typealias Action = HelperInstallerTransactionPlan.Action
    var state: State = .prepared; var pendingOperation: PendingOperation?
    init(transactionID: UUID = UUID(), action: Action, releaseIdentifier: String, generation: UInt64) {
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
    let jbRootPath: String
    init(jbRootPath: String) { self.jbRootPath = jbRootPath }
    func loadVerifiedArtifactsForActivation(transactionID: UUID, expectedHashes: [HelperRootReleaseSet.Artifact:String]) throws -> [HelperRootReleaseSet.Artifact:Data] {
        let dir = jbRootPath + "/Library/FilterKit/Helper/StagedReleases/" + transactionID.uuidString.lowercased()
        let names: [HelperRootReleaseSet.Artifact:String] = [.executable:"filterkit-helper", .deploymentManifest:"Deployment.json", .launchDaemon:"cn.yfen.filterkit.helper.plist"]
        var result: [HelperRootReleaseSet.Artifact:Data] = [:]
        for (a,n) in names { let d = try Data(contentsOf: URL(fileURLWithPath: dir + "/" + n)); guard SHA256Digest.hex(d) == expectedHashes[a] else { throw SmokeError.failed }; result[a] = d }
        return result
    }
}
struct HelperInstallerPreviousReleaseStore {
    enum State { case missing, complete, partial, mismatched }
    struct Inspection { let state: State; let transactionID: UUID; let observedHashes: [HelperRootReleaseSet.Artifact:String] }
    func loadVerifiedArtifactsForActivation(transactionID: UUID, expectedHashes: [HelperRootReleaseSet.Artifact:String]) throws -> [HelperRootReleaseSet.Artifact:Data] { throw SmokeError.failed }
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
    var checks = 0
    let root = "/tmp/p244-r13-prepared-\(UUID().uuidString.lowercased())"
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: root) }
    for path in ["usr/libexec", "Library/FilterKit/Helper/StagedReleases", "Library/LaunchDaemons", "Library/FilterKit/Helper"] {
        try FileManager.default.createDirectory(atPath: root + "/" + path, withIntermediateDirectories: true)
        _ = chmod(root + "/" + path, 0o700)
    }
    _ = chmod(root, 0o700)
    let executable = Data([0xcf,0xfa,0xed,0xfe,1,2,3,4,5,6,7,8])
    let manifest = Data("deployment-manifest-fixture".utf8)
    let plist = try PropertyListSerialization.data(fromPropertyList:["Label":"cn.yfen.filterkit.helper","Disabled":true,"RunAtLoad":false],format:.xml,options:0)
    let byPath = [HelperRootReleaseSet.executablePath: executable, HelperRootReleaseSet.manifestPath: manifest, HelperRootReleaseSet.launchDaemonPath: plist]
    let digests = byPath.map { HelperInstallerArtifactDigest(relativePath: $0.key, sha256: SHA256Digest.hex($0.value)) }
    let bundle = HelperInstallerProvisioningBundle(jbRootPath: root, releaseIdentifier: "r13-test-release", generation: 130, helperCDHash: String(repeating:"a",count:40), teamIdentifier:"TEAM1234")
    let envelope = HelperSignedProvisioningManifest(envelopeVersion:1, keyIdentifier:"host-test", algorithm:"Ed25519", payload:bundle, signatureBase64:Data(repeating:0x5a,count:64).base64EncodedString())
    let envelopeData = try JSONEncoder().encode(envelope)
    let checker = DeterministicTestSignatureChecker()
    let coordinator = HelperTrustedInstallerCoordinator(signingKeys:[HelperReleaseSigningKey(identifier:"host-test",publicKeyBase64:Data(repeating:7,count:32).base64EncodedString(),status:.active,minimumGeneration:nil,maximumGeneration:nil)], signatureChecker:checker)
    let plan = HelperInstallerTransactionPlan(jbRootPath:root, action:.install)
    var invalidEnvelope = envelope
    invalidEnvelope = HelperSignedProvisioningManifest(envelopeVersion:1, keyIdentifier:"host-test", algorithm:"Ed25519", payload:bundle, signatureBase64:Data(repeating:0,count:64).base64EncodedString())
    do {
        _ = try coordinator.prepare(plan:plan, provisioningEnvelopeData:JSONEncoder().encode(invalidEnvelope), artifacts:byPath, expectedDigests:digests)
        check(false, "invalid deterministic test signature is rejected", &checks)
    } catch { check(true, "invalid deterministic test signature is rejected", &checks) }
    let prepared = try coordinator.prepare(plan:plan, provisioningEnvelopeData:envelopeData, artifacts:byPath, expectedDigests:digests)
    check(prepared.release.releaseIdentifier == bundle.releaseIdentifier && prepared.release.generation == bundle.generation, "Coordinator.prepare verifies deterministic test signature and returns immutable Prepared", &checks)
    check(prepared.provisioningEnvelopeSHA256 == SHA256Digest.hex(envelopeData), "Prepared binds exact provisioning envelope bytes", &checks)
    let id = prepared.initialJournal.transactionID

    let stagedDir = root + "/Library/FilterKit/Helper/StagedReleases/" + id.uuidString.lowercased()
    try FileManager.default.createDirectory(atPath:stagedDir,withIntermediateDirectories:true)
    _ = chmod(stagedDir,0o700)
    try executable.write(to: URL(fileURLWithPath:stagedDir + "/filterkit-helper"))
    try manifest.write(to: URL(fileURLWithPath:stagedDir + "/Deployment.json"))
    try plist.write(to: URL(fileURLWithPath:stagedDir + "/cn.yfen.filterkit.helper.plist"))
    for name in ["filterkit-helper","Deployment.json","cn.yfen.filterkit.helper.plist"] { _ = chmod(stagedDir + "/" + name, 0o600) }

    var journal = prepared.initialJournal
    try journal.apply(.intentVerifyArtifacts); try journal.apply(.verifyArtifacts)
    try journal.apply(.intentStageRelease); try journal.apply(.stageRelease)
    try journal.apply(.intentActivateRelease)
    let store = HelperInstallerDurableJournalStore()
    try store.save(journal)
    let bytes: [HelperRootAtomicActivationExecutor.Artifact:Data] = [.executable:executable,.deploymentManifest:manifest,.launchDaemon:plist]
    let release = HelperRootAtomicActivationExecutor.Release(bundle:bundle,bytes:bytes,expectedDigests:digests,expectedPreviousHashes:[.executable:nil,.deploymentManifest:nil,.launchDaemon:nil])
    let challenge = UUID(), observerHash = String(repeating:"b",count:64), cdhash = String(repeating:"c",count:40)
    let pin = HelperInstallerAuthenticatedServiceObserver.Pin(bundleIdentifier:"com.example.filterkit.observer",teamIdentifier:"TEAM1234",cdHash:cdhash,observerCodeIdentitySHA256:observerHash,auditUID:0)
    let peer = HelperPeerIdentity(pid:42,uid:0,auditTokenDigest:String(repeating:"d",count:64),cdHashHex:cdhash,verifiedCodeIdentifier:pin.bundleIdentifier,verifiedTeamIdentifier:pin.teamIdentifier)
    let report = HelperInstallerAuthenticatedServiceObserver.Report(challenge:challenge,observation:HelperInstallerServiceObservation(launchDaemonLabel:"cn.yfen.filterkit.helper",observerCodeIdentitySHA256:observerHash,state:.stopped))
    let executor = try HelperRootAtomicActivationExecutor(rootDirectory:root)
    let stagedStore = HelperInstallerStagedReleaseStore(jbRootPath:root)
    // A stale observer challenge must be rejected before the first Active destination is created.
    do {
        _ = try executor.activate(release,durableJournal:journal,journalStore:store,prepared:prepared,stagedStore:stagedStore,previousRelease:nil,previousStore:nil,serviceReport:report,expectedChallenge:UUID(),authenticatedPeer:peer,observerPin:pin,expectedObservedHelperSHA256:SHA256Digest.hex(executable))
        check(false, "stale observer challenge is rejected", &checks)
    } catch HelperRootAtomicActivationExecutor.Failure.serviceNotAuthenticatedOrStopped {
        check(!FileManager.default.fileExists(atPath:root + "/usr/libexec/filterkit-helper"), "stale observer challenge is rejected before Active mutation", &checks)
    }
    // Tampering with one staged artifact is detected from disk before activation.
    let manifestPath = stagedDir + "/Deployment.json"
    let originalManifest = try Data(contentsOf:URL(fileURLWithPath:manifestPath))
    try Data("tampered".utf8).write(to:URL(fileURLWithPath:manifestPath))
    do {
        _ = try executor.activate(release,durableJournal:journal,journalStore:store,prepared:prepared,stagedStore:stagedStore,previousRelease:nil,previousStore:nil,serviceReport:report,expectedChallenge:challenge,authenticatedPeer:peer,observerPin:pin,expectedObservedHelperSHA256:SHA256Digest.hex(executable))
        check(false, "tampered staged bytes are rejected", &checks)
    } catch {
        check(!FileManager.default.fileExists(atPath:root + "/usr/libexec/filterkit-helper"), "tampered staged bytes are rejected before Active mutation", &checks)
    }
    try originalManifest.write(to:URL(fileURLWithPath:manifestPath))
    let result = try executor.activate(release,durableJournal:journal,journalStore:store,prepared:prepared,stagedStore:stagedStore,previousRelease:nil,previousStore:nil,serviceReport:report,expectedChallenge:challenge,authenticatedPeer:peer,observerPin:pin,expectedObservedHelperSHA256:SHA256Digest.hex(executable))
    check(result.transactionID == id, "Formal activate(prepared:) executes the same transaction ID", &checks)
    check(try store.load(transactionID:id).state == .activated, "Durable Journal reaches activated", &checks)
    let pointer = try HelperInstallerDescriptorFilesystemObserver(jbRootPath:root).observeActiveReleasePointer()
    check(pointer.transactionID == id && pointer.releaseIdentifier == bundle.releaseIdentifier && pointer.generation == bundle.generation, "Active Pointer binds transaction, release and generation", &checks)
    let activeRecords = try HelperInstallerDescriptorFilesystemObserver(jbRootPath:root).observeArtifactSet(paths:[.executable:HelperRootReleaseSet.executablePath,.deploymentManifest:HelperRootReleaseSet.manifestPath,.launchDaemon:HelperRootReleaseSet.launchDaemonPath])
    let pointerHashes = Dictionary(uniqueKeysWithValues: pointer.artifactHashes.map { ($0.key, $0.value) })
    check(activeRecords.allSatisfy { pointerHashes[$0.key.rawValue] == $0.value.sha256 }, "Pointer hashes match all three independently observed Active files", &checks)
    let activeExe = try Data(contentsOf:URL(fileURLWithPath:root + "/usr/libexec/filterkit-helper"))
    check(activeExe == executable, "Active executable bytes match signed prepared release", &checks)
    print("RESULT: \(checks)/10 passed")
 }
}
