import Foundation
import Glibc

// Host-only adapters are limited to policy/signature/Mach-O metadata. The Coordinator,
// Journal reducer, Durable Journal Store, Staged Store, and Previous Store are production files.
enum HelperPolicy {
    static func isAbsoluteCleanPath(_ s: String) -> Bool { s.hasPrefix("/") && !s.contains("\0") && !s.split(separator: "/").contains("..") }
    static func isValidHash(_ s: String) -> Bool { s.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil }
    static func isValidCDHash(_ s: String) -> Bool { s.range(of: "^[0-9a-fA-F]{40,64}$", options: .regularExpression) != nil }
}
struct HelperInstallerTransactionPlan: Equatable {
    enum Action: String, Codable { case install, upgrade, repin }
    let jbRootPath: String; let action: Action
    var executionEnabled: Bool { false }
}
struct HelperInstallerProvisioningBundle: Codable {
    let jbRootPath: String; let releaseIdentifier: String; let generation: UInt64
    let helperCDHash: String; let teamIdentifier: String?
    func validate() throws { guard HelperPolicy.isAbsoluteCleanPath(jbRootPath), generation > 0, !releaseIdentifier.isEmpty else { throw HostError.invalid } }
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
    func verify(signature: Data, message: Data, publicKey: Data) -> Bool {
        signature == Data(repeating: 0x5a, count: 64) && publicKey.count == 32 && !message.isEmpty
    }
}
struct HelperEd25519SignatureChecker: HelperReleaseSignatureChecking { func verify(signature: Data, message: Data, publicKey: Data) -> Bool { false } }
enum HelperReleaseTrustAnchors { static let keys: [HelperReleaseSigningKey] = [] }
struct HelperProvisioningSignatureVerifier {
    let keys: [HelperReleaseSigningKey]; let checker: HelperReleaseSignatureChecking
    func verify(_ envelope: HelperSignedProvisioningManifest) throws {
        guard envelope.envelopeVersion == 1, envelope.algorithm == "Ed25519",
              let key = keys.first(where: { $0.identifier == envelope.keyIdentifier }), key.status == .active,
              let pub = Data(base64Encoded: key.publicKeyBase64),
              checker.verify(signature: try envelope.signatureBytes(), message: try envelope.signingBytes(), publicKey: pub) else { throw HostError.invalid }
    }
}
struct HelperInstallerArtifactDigest {
    let relativePath: String; let sha256: String
    func validate() -> Bool { HelperPolicy.isValidHash(sha256) && !relativePath.isEmpty }
}
struct HelperRootReleaseSet {
    enum Artifact: String, CaseIterable, Hashable, Codable { case executable, deploymentManifest, launchDaemon }
    struct Verified: Equatable { let releaseIdentifier: String; let generation: UInt64; let hashes: [Artifact:String]; let byteCounts: [Artifact:Int] }
    static let executablePath = "usr/libexec/filterkit-helper"
    static let manifestPath = "Library/FilterKit/Helper/Deployment.json"
    static let launchDaemonPath = "Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"
    func verify(bundle: HelperInstallerProvisioningBundle, artifacts: [String:Data], expectedDigests: [HelperInstallerArtifactDigest]) throws -> Verified {
        let paths = [Self.executablePath, Self.manifestPath, Self.launchDaemonPath]
        guard Set(artifacts.keys) == Set(paths), expectedDigests.count == 3,
              Set(expectedDigests.map(\.relativePath)) == Set(paths), expectedDigests.allSatisfy({ $0.validate() }) else { throw HostError.invalid }
        var hashes:[Artifact:String] = [:], counts:[Artifact:Int] = [:]
        for (a,p) in zip(Artifact.allCases, paths) {
            guard let data = artifacts[p], expectedDigests.first(where:{$0.relativePath == p})?.sha256 == SHA256Digest.hex(data) else { throw HostError.invalid }
            hashes[a] = SHA256Digest.hex(data); counts[a] = data.count
        }
        return Verified(releaseIdentifier: bundle.releaseIdentifier, generation: bundle.generation, hashes: hashes, byteCounts: counts)
    }
}
struct HelperInstallerExecutionGate {
    enum BlockReason { case blocked }
    struct Evidence { let rootInstallerAvailable:Bool; let releaseProvenanceVerified:Bool; let signedArtifactsVerified:Bool; let operatorApproved:Bool }
    func blockReason(plan: HelperInstallerTransactionPlan, evidence: Evidence) -> BlockReason? { nil }
}
enum HelperInstallerProvisioningCommitResult { case committed, rejected, indeterminate }
struct HelperReleaseAcceptanceLock { static func withLock<T>(root:String,_ body:() throws -> T) throws -> T { try body() } }
struct HelperTrustedProvisioningStore {
    enum Failure:Error { case noTrustedBaseline }
    struct Baseline { let envelopeSHA256:String }
    func commit(_ data:Data, action:HelperInstallerTransactionPlan.Action) throws {}
    func recoverPendingTransaction() throws {}
    func loadTrustedBaseline() throws -> Baseline { throw Failure.noTrustedBaseline }
}
struct MachOSliceMetadata { let codeSignatureState:String; let codeSignatureTeamIdentifier:String?; let cdHash:String? }
struct MachOMetadataReader {
    static var expectedCDHash = String(repeating:"a",count:40)
    static var expectedTeam = "TEAM1234"
    func readSlices(data:Data) throws -> [MachOSliceMetadata] {
        guard data.count >= 4 else { throw HostError.invalid }
        return [MachOSliceMetadata(codeSignatureState:"cdhash_extracted",codeSignatureTeamIdentifier:Self.expectedTeam,cdHash:Self.expectedCDHash)]
    }
}
struct HelperInstallerSharedTransactionLock {
    static func withExclusiveLock<T>(jbroot:String,_ body:() throws -> T) throws -> T { try body() }
}
enum HostError:Error { case invalid }

func check(_ condition: @autoclosure () -> Bool, _ label:String, _ failures:inout [String]) {
    if condition() { print("PASS: \(label)") } else { print("FAIL: \(label)"); failures.append(label) }
}
func makeDir(_ path:String,_ mode:mode_t = 0o700) throws {
    try FileManager.default.createDirectory(atPath:path,withIntermediateDirectories:true)
    guard chmod(path,mode) == 0 else { throw HostError.invalid }
}
func write(_ path:String,_ data:Data,_ mode:mode_t) throws {
    try data.write(to:URL(fileURLWithPath:path)); guard chmod(path,mode) == 0 else { throw HostError.invalid }
}
func releaseFiles(root:String, executable:Data, manifest:Data, plist:Data) throws {
    try makeDir(root+"/usr/libexec"); try makeDir(root+"/Library/FilterKit/Helper"); try makeDir(root+"/Library/LaunchDaemons")
    try write(root+"/usr/libexec/filterkit-helper",executable,0o755)
    try write(root+"/Library/FilterKit/Helper/Deployment.json",manifest,0o600)
    try write(root+"/Library/LaunchDaemons/cn.yfen.filterkit.helper.plist",plist,0o644)
}

@main struct Main {
 static func main() throws {
    var failures:[String] = []
    let base = "/root/filterkit-p244-r15-\(UUID().uuidString.lowercased())"
    let jb = base+"/jbroot", journalPath = base+"/journal"
    defer { try? FileManager.default.removeItem(atPath:base) }
    try makeDir(base); try makeDir(jb); try makeDir(journalPath)
    try makeDir(jb+"/"+HelperInstallerStagedReleaseStore.relativeRootPath)
    try makeDir(jb+"/"+HelperInstallerPreviousReleaseStore.relativeRootPath)

    let oldExe = Data([0xcf,0xfa,0xed,0xfe,1,2,3,4,5,6])
    let oldManifest = try JSONSerialization.data(withJSONObject:["schemaVersion":2,"jbRootPath":jb,"executionEnabled":false],options:[.sortedKeys])
    let oldPlist = try PropertyListSerialization.data(fromPropertyList:["Label":"cn.yfen.filterkit.helper","ProgramArguments":[jb+"/usr/libexec/filterkit-helper"],"Disabled":true,"RunAtLoad":false,"KeepAlive":false],format:.xml,options:0)
    try releaseFiles(root:jb,executable:oldExe,manifest:oldManifest,plist:oldPlist)
    let oldBytes:[String:Data] = [HelperRootReleaseSet.executablePath:oldExe,HelperRootReleaseSet.manifestPath:oldManifest,HelperRootReleaseSet.launchDaemonPath:oldPlist]
    let oldHashes = Dictionary(uniqueKeysWithValues:oldBytes.map{($0.key,SHA256Digest.hex($0.value))})
    let oldVerified = HelperRootReleaseSet.Verified(releaseIdentifier:"release-old",generation:1,
        hashes:[.executable:oldHashes[HelperRootReleaseSet.executablePath]!, .deploymentManifest:oldHashes[HelperRootReleaseSet.manifestPath]!, .launchDaemon:oldHashes[HelperRootReleaseSet.launchDaemonPath]!],
        byteCounts:[.executable:oldExe.count,.deploymentManifest:oldManifest.count,.launchDaemon:oldPlist.count])

    let newExe = Data([0xcf,0xfa,0xed,0xfe,9,8,7,6,5,4])
    let newManifest = try JSONSerialization.data(withJSONObject:["schemaVersion":2,"jbRootPath":jb,"executionEnabled":false,"release":"new"],options:[.sortedKeys])
    let newPlist = try PropertyListSerialization.data(fromPropertyList:["Label":"cn.yfen.filterkit.helper","ProgramArguments":[jb+"/usr/libexec/filterkit-helper"],"Disabled":true,"RunAtLoad":false,"KeepAlive":false],format:.xml,options:0)
    let newBytes:[String:Data] = [HelperRootReleaseSet.executablePath:newExe,HelperRootReleaseSet.manifestPath:newManifest,HelperRootReleaseSet.launchDaemonPath:newPlist]
    let digests = newBytes.map{HelperInstallerArtifactDigest(relativePath:$0.key,sha256:SHA256Digest.hex($0.value))}
    let bundle = HelperInstallerProvisioningBundle(jbRootPath:jb,releaseIdentifier:"release-new",generation:2,helperCDHash:MachOMetadataReader.expectedCDHash,teamIdentifier:MachOMetadataReader.expectedTeam)
    let envelope = HelperSignedProvisioningManifest(envelopeVersion:1,keyIdentifier:"host-test",algorithm:"Ed25519",payload:bundle,signatureBase64:Data(repeating:0x5a,count:64).base64EncodedString())
    let envelopeData = try JSONEncoder().encode(envelope)
    let coordinator = HelperTrustedInstallerCoordinator(
        signingKeys:[HelperReleaseSigningKey(identifier:"host-test",publicKeyBase64:Data(repeating:7,count:32).base64EncodedString(),status:.active,minimumGeneration:nil,maximumGeneration:nil)],
        signatureChecker:DeterministicTestSignatureChecker())
    let prepared = try coordinator.prepare(plan:HelperInstallerTransactionPlan(jbRootPath:jb,action:.upgrade),
        provisioningEnvelopeData:envelopeData,artifacts:newBytes,expectedDigests:digests)
    check(prepared.release.releaseIdentifier == "release-new" && prepared.initialJournal.action == .upgrade,"Coordinator.prepare creates signed-test Prepared Upgrade",&failures)

    let journalStore = HelperInstallerDurableJournalStore(directoryPath:journalPath)
    var journal = prepared.initialJournal
    try journal.apply(.intentVerifyArtifacts); try journalStore.save(journal)
    try journal.apply(.verifyArtifacts); try journalStore.save(journal)
    try journal.apply(.intentPreservePreviousRelease); try journalStore.save(journal)
    let previousStore = try HelperInstallerPreviousReleaseStore(jbRootPath:jb)
    let previousReceipt = try previousStore.preserve(prepared:prepared,previousRelease:oldVerified,
        previousHelperCDHash:MachOMetadataReader.expectedCDHash,previousTeamIdentifier:MachOMetadataReader.expectedTeam,
        journal:journal,journalStore:journalStore)
    check(previousReceipt.hashes == oldVerified.hashes,"Previous Store preserves actual Active bytes using trusted old inventory",&failures)
    let afterPreserve = try journalStore.load(transactionID:prepared.initialJournal.transactionID)
    check(afterPreserve.state == .previousReleasePreserved,"Previous Store durably advances Journal",&failures)

    journal = try journalStore.load(transactionID:prepared.initialJournal.transactionID)
    try journal.apply(.intentStageRelease); try journalStore.save(journal)
    let stagedStore = try HelperInstallerStagedReleaseStore(jbRootPath:jb)
    let stagedReceipt = try stagedStore.stage(prepared:prepared,journal:journal,journalStore:journalStore,artifacts:newBytes)
    check(stagedReceipt.hashes == prepared.release.hashes,"Staged Store writes exact verified release bytes",&failures)
    let stagedJournal = try journalStore.load(transactionID:prepared.initialJournal.transactionID)
    check(stagedJournal.state == .staged && stagedJournal.pendingOperation == nil,"Staged Store durably advances Journal to staged",&failures)
    let stagedRead = try stagedStore.loadVerifiedArtifactsForActivation(transactionID:prepared.initialJournal.transactionID,expectedHashes:prepared.release.hashes)
    let previousRead = try previousStore.loadVerifiedArtifactsForActivation(transactionID:prepared.initialJournal.transactionID,expectedHashes:oldVerified.hashes)
    check(stagedRead.count == 3 && stagedRead.allSatisfy{prepared.release.hashes[$0.key] == SHA256Digest.hex($0.value)},"Staged files re-read and hash-verified",&failures)
    check(previousRead.count == 3 && previousRead.allSatisfy{oldVerified.hashes[$0.key] == SHA256Digest.hex($0.value)},"Previous backup re-read and hash-verified",&failures)
    let activeExe = try Data(contentsOf:URL(fileURLWithPath:jb+"/usr/libexec/filterkit-helper"))
    check(activeExe == oldExe,"Preserve leaves Active release unchanged",&failures)
    let stagedInspection = try stagedStore.inspect(prepared:prepared)
    check(stagedInspection.state == .complete,"Staged inspection reports complete after real stage()",&failures)

    // A separate Upgrade transaction injects a Previous backup interruption. The backup
    // remains partial, Active remains unchanged, and the Journal keeps its pending intent.
    let preserveFaultPrepared = try coordinator.prepare(plan:HelperInstallerTransactionPlan(jbRootPath:jb,action:.upgrade),
        provisioningEnvelopeData:envelopeData,artifacts:newBytes,expectedDigests:digests)
    var preserveFaultJournal = preserveFaultPrepared.initialJournal
    try preserveFaultJournal.apply(.intentVerifyArtifacts); try journalStore.save(preserveFaultJournal)
    try preserveFaultJournal.apply(.verifyArtifacts); try journalStore.save(preserveFaultJournal)
    try preserveFaultJournal.apply(.intentPreservePreviousRelease); try journalStore.save(preserveFaultJournal)
    do {
        _ = try previousStore.preserve(prepared:preserveFaultPrepared,previousRelease:oldVerified,
            previousHelperCDHash:MachOMetadataReader.expectedCDHash,previousTeamIdentifier:MachOMetadataReader.expectedTeam,
            journal:preserveFaultJournal,journalStore:journalStore,faultAt:.afterExecutable)
        check(false,"Injected Previous preservation interruption is surfaced",&failures)
    } catch HelperInstallerPreviousReleaseStore.StoreError.injectedCrash {
        check(true,"Injected Previous preservation interruption is surfaced",&failures)
        let partialPrevious = try previousStore.inspect(transactionID:preserveFaultPrepared.initialJournal.transactionID,expected:oldVerified)
        check(partialPrevious.state == .partial,"Interrupted Previous backup remains partial evidence",&failures)
        let pendingPreviousJournal = try journalStore.load(transactionID:preserveFaultPrepared.initialJournal.transactionID)
        check(pendingPreviousJournal.pendingOperation == .preservePreviousRelease,"Interrupted Previous backup retains pending Journal intent",&failures)
    }

    // A second transaction injects a staged-write interruption; partial bytes must remain
    // visible as partial evidence and must not be promoted to a completed journal state.
    let faultPrepared = try coordinator.prepare(plan:HelperInstallerTransactionPlan(jbRootPath:jb,action:.install),
        provisioningEnvelopeData:envelopeData,artifacts:newBytes,expectedDigests:digests)
    var faultJournal = faultPrepared.initialJournal
    try faultJournal.apply(.intentVerifyArtifacts); try journalStore.save(faultJournal)
    try faultJournal.apply(.verifyArtifacts); try journalStore.save(faultJournal)
    try faultJournal.apply(.intentStageRelease); try journalStore.save(faultJournal)
    do {
        _ = try stagedStore.stage(prepared:faultPrepared,journal:faultJournal,journalStore:journalStore,artifacts:newBytes,faultAt:.afterExecutable)
        check(false,"Injected Stage interruption is surfaced",&failures)
    } catch HelperInstallerStagedReleaseStore.StoreError.injectedCrash {
        check(true,"Injected Stage interruption is surfaced",&failures)
        let partial = try stagedStore.inspect(prepared:faultPrepared)
        check(partial.state == .partial,"Interrupted Stage remains partial and is not promoted",&failures)
        let afterFault = try journalStore.load(transactionID:faultPrepared.initialJournal.transactionID)
        check(afterFault.pendingOperation == .stageRelease,"Interrupted Stage retains pending Journal intent",&failures)
    }
    check(geteuid() == 0,"Host process is root for root-owned Store checks",&failures)
    print("RESULT: \(failures.isEmpty ? "PASS" : "FAIL") (\(16-failures.count)/16 assertions)")
    if !failures.isEmpty { exit(1) }
 }
}
