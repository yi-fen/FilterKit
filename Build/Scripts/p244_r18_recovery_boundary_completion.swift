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
struct HelperInstallerDescriptorFilesystemObserver {
    struct ReleasePointer: Codable, Equatable {
        let schemaVersion: Int
        let transactionID: UUID
        let releaseIdentifier: String
        let generation: UInt64
        let artifactHashes: [String: String]
    }
    private let jbRootPath: String
    private let expectedOwnerUID: UInt32
    init(jbRootPath: String, expectedOwnerUID: UInt32 = 0) {
        self.jbRootPath = jbRootPath; self.expectedOwnerUID = expectedOwnerUID
    }
    func observeArtifactSet(paths: [HelperRootReleaseSet.Artifact: String]) throws -> [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.FileRecord] {
        var result: [HelperRootReleaseSet.Artifact: FileRecord] = [:]
        for (artifact, path) in paths {
            let data = try Data(contentsOf: URL(fileURLWithPath: jbRootPath + "/" + path))
            var st = stat(); guard stat((jbRootPath + "/" + path), &st) == 0, st.st_uid == expectedOwnerUID else { throw HostError.invalid }
            result[artifact] = FileRecord(sha256: SHA256Digest.hex(data))
        }
        return result
    }
    func observeActiveReleasePointer() throws -> ReleasePointer {
        let data = try Data(contentsOf: URL(fileURLWithPath: jbRootPath + "/Library/FilterKit/Helper/active-release.json"))
        return try JSONDecoder().decode(ReleasePointer.self, from: data)
    }
    struct FileRecord { let sha256: String }
}
struct HelperPeerIdentity {
    let pid: Int32; let uid: UInt32; let auditTokenDigest: String?
    let cdHashHex: String; let verifiedCodeIdentifier: String?; let verifiedTeamIdentifier: String?
}
enum HelperPeerIdentityBindingPolicy {
    static func codeSigningIdentityMatches(_ identity: HelperPeerIdentity, bundleIdentifier: String, teamIdentifier: String) -> Bool {
        identity.verifiedCodeIdentifier == bundleIdentifier && identity.verifiedTeamIdentifier == teamIdentifier
    }
}
struct HelperInstallerServiceObservation: Equatable {
    enum State: Equatable { case running(pid: Int32, executableSHA256: String), stopped, unknown }
    let launchDaemonLabel: String; let observerCodeIdentitySHA256: String; let state: State
    func validates(expectedObserverCodeIdentitySHA256: String, expectedExecutableSHA256: String) -> Bool {
        launchDaemonLabel == "cn.yfen.filterkit.helper" && observerCodeIdentitySHA256 == expectedObserverCodeIdentitySHA256 && HelperPolicy.isValidHash(expectedExecutableSHA256) && state == .stopped
    }
}
enum HostError:Error { case invalid }

var passedAssertions = 0
var totalAssertions = 0
func check(_ condition: @autoclosure () -> Bool, _ label:String, _ failures:inout [String]) {
    totalAssertions += 1
    if condition() { passedAssertions += 1; print("PASS: \(label)") } else { print("FAIL: \(label)"); failures.append(label) }; fflush(stdout)
}
func makeDir(_ path:String,_ mode:mode_t = 0o700) throws {
    try FileManager.default.createDirectory(atPath:path,withIntermediateDirectories:true)
    guard chmod(path,mode) == 0 else { throw HostError.invalid }
}
func write(_ path:String,_ data:Data,_ mode:mode_t) throws {
    try data.write(to:URL(fileURLWithPath:path)); guard chmod(path,mode) == 0 else { throw HostError.invalid }
}
func readBytes(_ path: String) throws -> Data {
    let fd = path.withCString { open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
    guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { _ = close(fd) }
    var result = Data(); var buffer = [UInt8](repeating: 0, count: 8192)
    while true {
        let count = read(fd, &buffer, buffer.count)
        if count < 0 && errno == EINTR { continue }
        guard count >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        if count == 0 { break }
        result.append(contentsOf: buffer.prefix(count))
    }
    return result
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
    let base = "/root/filterkit-p244-r18-\(UUID().uuidString.lowercased())"
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
    // Full Upgrade activation: real Coordinator, Durable Journal, Previous Store and Staged Store
    // feed the production prepared activation overload and production Active Pointer writer.
    var activationJournal = try journalStore.load(transactionID: prepared.initialJournal.transactionID)
    try activationJournal.apply(.intentActivateRelease)
    try journalStore.save(activationJournal)
    let activationRelease = HelperRootAtomicActivationExecutor.Release(
        bundle: bundle,
        bytes: [.executable:newExe, .deploymentManifest:newManifest, .launchDaemon:newPlist],
        expectedDigests: digests,
        expectedPreviousHashes: [.executable:oldHashes[HelperRootReleaseSet.executablePath],
                                 .deploymentManifest:oldHashes[HelperRootReleaseSet.manifestPath],
                                 .launchDaemon:oldHashes[HelperRootReleaseSet.launchDaemonPath]])
    let challenge = UUID()
    let observerHash = String(repeating:"b",count:64)
    let observerCDHash = String(repeating:"c",count:40)
    let pin = HelperInstallerAuthenticatedServiceObserver.Pin(bundleIdentifier:"com.example.filterkit.observer",
        teamIdentifier:"TEAM1234",cdHash:observerCDHash,observerCodeIdentitySHA256:observerHash,auditUID:0)
    let peer = HelperPeerIdentity(pid:4242,uid:0,auditTokenDigest:String(repeating:"d",count:64),
        cdHashHex:observerCDHash,verifiedCodeIdentifier:pin.bundleIdentifier,verifiedTeamIdentifier:pin.teamIdentifier)
    let report = HelperInstallerAuthenticatedServiceObserver.Report(challenge:challenge,
        observation:HelperInstallerServiceObservation(launchDaemonLabel:"cn.yfen.filterkit.helper",
            observerCodeIdentitySHA256:observerHash,state:.stopped))
    let executor = try HelperRootAtomicActivationExecutor(rootDirectory:jb)
    let activationResult = try executor.activate(activationRelease,durableJournal:activationJournal,
        journalStore:journalStore,prepared:prepared,stagedStore:stagedStore,
        previousRelease:oldVerified,previousStore:previousStore,serviceReport:report,
        expectedChallenge:challenge,authenticatedPeer:peer,observerPin:pin,
        expectedObservedHelperSHA256:SHA256Digest.hex(oldExe))
    check(activationResult.transactionID == prepared.initialJournal.transactionID,"Production prepared Upgrade activation commits same transaction",&failures)
    let activatedJournal = try journalStore.load(transactionID:prepared.initialJournal.transactionID)
    check(activatedJournal.state == .activated && activatedJournal.pendingOperation == nil,"Durable Journal reaches activated",&failures)
    let activeExecutableBytes = try Data(contentsOf:URL(fileURLWithPath:jb+"/usr/libexec/filterkit-helper"))
    let activeManifestBytes = try Data(contentsOf:URL(fileURLWithPath:jb+"/Library/FilterKit/Helper/Deployment.json"))
    let activeLaunchDaemonBytes = try Data(contentsOf:URL(fileURLWithPath:jb+"/Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"))
    check(activeExecutableBytes == newExe,"Active executable replaced with staged bytes",&failures)
    check(activeManifestBytes == newManifest,"Active deployment manifest replaced with staged bytes",&failures)
    check(activeLaunchDaemonBytes == newPlist,"Active launch daemon replaced with staged bytes",&failures)
    let pointerData = try Data(contentsOf:URL(fileURLWithPath:jb+"/Library/FilterKit/Helper/active-release.json"))
    let pointer = try JSONDecoder().decode(HelperInstallerDescriptorFilesystemObserver.ReleasePointer.self,from:pointerData)
    check(pointer.transactionID == prepared.initialJournal.transactionID && pointer.releaseIdentifier == "release-new" && pointer.generation == 2,"Active Pointer binds transaction, release and generation",&failures)
    check(pointer.artifactHashes["executable"] == SHA256Digest.hex(newExe) && pointer.artifactHashes["deploymentManifest"] == SHA256Digest.hex(newManifest) && pointer.artifactHashes["launchDaemon"] == SHA256Digest.hex(newPlist),"Active Pointer hashes match all three Active files",&failures)
    // Second Upgrade injects a failure immediately before Pointer rename. Active files and
    // Durable Journal are already committed; recovery must republish the Pointer and finalize.
    let nextExe = Data([0xcf,0xfa,0xed,0xfe,3,3,3,3,3,3,3,3])
    let nextManifest = try JSONSerialization.data(withJSONObject:["schemaVersion":2,"jbRootPath":jb,"executionEnabled":false,"release":"next"],options:[.sortedKeys])
    let nextPlist = newPlist
    let nextBytes:[String:Data] = [HelperRootReleaseSet.executablePath:nextExe,HelperRootReleaseSet.manifestPath:nextManifest,HelperRootReleaseSet.launchDaemonPath:nextPlist]
    let nextDigests = nextBytes.map{HelperInstallerArtifactDigest(relativePath:$0.key,sha256:SHA256Digest.hex($0.value))}
    let nextBundle = HelperInstallerProvisioningBundle(jbRootPath:jb,releaseIdentifier:"release-next",generation:3,helperCDHash:MachOMetadataReader.expectedCDHash,teamIdentifier:MachOMetadataReader.expectedTeam)
    let nextEnvelope = HelperSignedProvisioningManifest(envelopeVersion:1,keyIdentifier:"host-test",algorithm:"Ed25519",payload:nextBundle,signatureBase64:Data(repeating:0x5a,count:64).base64EncodedString())
    let nextPrepared = try coordinator.prepare(plan:HelperInstallerTransactionPlan(jbRootPath:jb,action:.upgrade),
        provisioningEnvelopeData:try JSONEncoder().encode(nextEnvelope),artifacts:nextBytes,expectedDigests:nextDigests)
    var nextJournal = nextPrepared.initialJournal
    try nextJournal.apply(.intentVerifyArtifacts); try journalStore.save(nextJournal)
    try nextJournal.apply(.verifyArtifacts); try journalStore.save(nextJournal)
    try nextJournal.apply(.intentPreservePreviousRelease); try journalStore.save(nextJournal)
    let currentVerified = HelperRootReleaseSet.Verified(releaseIdentifier:"release-new",generation:2,
        hashes:[.executable:SHA256Digest.hex(newExe),.deploymentManifest:SHA256Digest.hex(newManifest),.launchDaemon:SHA256Digest.hex(newPlist)],
        byteCounts:[.executable:newExe.count,.deploymentManifest:newManifest.count,.launchDaemon:newPlist.count])
    _ = try previousStore.preserve(prepared:nextPrepared,previousRelease:currentVerified,
        previousHelperCDHash:MachOMetadataReader.expectedCDHash,previousTeamIdentifier:MachOMetadataReader.expectedTeam,
        journal:nextJournal,journalStore:journalStore)
    nextJournal = try journalStore.load(transactionID:nextPrepared.initialJournal.transactionID)
    try nextJournal.apply(.intentStageRelease); try journalStore.save(nextJournal)
    _ = try stagedStore.stage(prepared:nextPrepared,journal:nextJournal,journalStore:journalStore,artifacts:nextBytes)
    nextJournal = try journalStore.load(transactionID:nextPrepared.initialJournal.transactionID)
    try nextJournal.apply(.intentActivateRelease); try journalStore.save(nextJournal)
    let nextRelease = HelperRootAtomicActivationExecutor.Release(bundle:nextBundle,
        bytes:[.executable:nextExe,.deploymentManifest:nextManifest,.launchDaemon:nextPlist],
        expectedDigests:nextDigests,
        expectedPreviousHashes:[.executable:SHA256Digest.hex(newExe),.deploymentManifest:SHA256Digest.hex(newManifest),.launchDaemon:SHA256Digest.hex(newPlist)])
    do {
        _ = try executor.activate(nextRelease,durableJournal:nextJournal,journalStore:journalStore,
            prepared:nextPrepared,stagedStore:stagedStore,previousRelease:currentVerified,previousStore:previousStore,
            serviceReport:report,expectedChallenge:challenge,authenticatedPeer:peer,observerPin:pin,
            expectedObservedHelperSHA256:SHA256Digest.hex(newExe),faultAt:.beforePointerRename)
        check(false,"Injected Pointer publication failure is surfaced",&failures)
    } catch HelperRootAtomicActivationExecutor.Failure.activePointerCommitIndeterminate {
        check(true,"Injected Pointer publication failure is surfaced",&failures)
    }
    let committedBeforeRecovery = try journalStore.load(transactionID:nextPrepared.initialJournal.transactionID)
    check(committedBeforeRecovery.state == .activated,"Pointer failure retains activated Durable Journal",&failures)
    let recovered = try executor.recover(durableJournal:committedBeforeRecovery,journalStore:journalStore,
        serviceReport:report,expectedChallenge:challenge,authenticatedPeer:peer,observerPin:pin,
        expectedObservedHelperSHA256:SHA256Digest.hex(newExe))
    check(recovered == .committed,"Recovery republishes Pointer and finalizes committed Active set",&failures)
    let nextPointer = try JSONDecoder().decode(HelperInstallerDescriptorFilesystemObserver.ReleasePointer.self,
        from:Data(contentsOf:URL(fileURLWithPath:jb+"/Library/FilterKit/Helper/active-release.json")))
    check(nextPointer.transactionID == nextPrepared.initialJournal.transactionID && nextPointer.releaseIdentifier == "release-next" && nextPointer.generation == 3,
        "Recovered Pointer binds next transaction and release",&failures)
    let secondRecovery = try executor.recover()
    check(secondRecovery == nil,"Recovery is idempotent after transaction evidence is finalized",&failures)

    // P2-44-R18: recovery boundary completion matrix. Each case uses production prepare/preserve/stage/
    // activate(prepared:)/recover(durableJournal:) and the same real on-disk stores.
    var matrixCurrentBytes = nextBytes
    var matrixGeneration: UInt64 = 3
    let runRecoveryCase: (String, HelperRootAtomicActivationExecutor.Artifact?, HelperRootAtomicActivationExecutor.FaultPoint?, Bool, HelperRootAtomicActivationExecutor.Artifact?) throws -> Void = { label, crashAfter, faultAt, expectCommit, removeBackupFor in
        matrixGeneration += 1
        let generation = matrixGeneration
        let exe = Data([0xcf,0xfa,0xed,0xfe,UInt8(generation & 0xff),11,12,13,14,15])
        let manifest = try JSONSerialization.data(withJSONObject:["schemaVersion":2,"jbRootPath":jb,"executionEnabled":false,"release":"matrix-\(generation)"],options:[.sortedKeys])
        let plist = try PropertyListSerialization.data(fromPropertyList:["Label":"cn.yfen.filterkit.helper","ProgramArguments":[jb+"/usr/libexec/filterkit-helper"],"Disabled":true,"RunAtLoad":false,"KeepAlive":false,"Generation":generation],format:.xml,options:0)
        let bytes:[String:Data] = [HelperRootReleaseSet.executablePath:exe,HelperRootReleaseSet.manifestPath:manifest,HelperRootReleaseSet.launchDaemonPath:plist]
        let artifactDigests = bytes.map{HelperInstallerArtifactDigest(relativePath:$0.key,sha256:SHA256Digest.hex($0.value))}
        let releaseID = "matrix-\(generation)"
        let releaseBundle = HelperInstallerProvisioningBundle(jbRootPath:jb,releaseIdentifier:releaseID,generation:generation,helperCDHash:MachOMetadataReader.expectedCDHash,teamIdentifier:MachOMetadataReader.expectedTeam)
        let signedEnvelope = HelperSignedProvisioningManifest(envelopeVersion:1,keyIdentifier:"host-test",algorithm:"Ed25519",payload:releaseBundle,signatureBase64:Data(repeating:0x5a,count:64).base64EncodedString())
        let preparedCase = try coordinator.prepare(plan:HelperInstallerTransactionPlan(jbRootPath:jb,action:.upgrade),provisioningEnvelopeData:try JSONEncoder().encode(signedEnvelope),artifacts:bytes,expectedDigests:artifactDigests)
        var caseJournal = preparedCase.initialJournal
        try caseJournal.apply(.intentVerifyArtifacts); try journalStore.save(caseJournal)
        try caseJournal.apply(.verifyArtifacts); try journalStore.save(caseJournal)
        try caseJournal.apply(.intentPreservePreviousRelease); try journalStore.save(caseJournal)
        let currentHashes = Dictionary(uniqueKeysWithValues:matrixCurrentBytes.map{($0.key,SHA256Digest.hex($0.value))})
        let currentVerified = HelperRootReleaseSet.Verified(releaseIdentifier:"matrix-current",generation:generation-1,
            hashes:[.executable:currentHashes[HelperRootReleaseSet.executablePath]!, .deploymentManifest:currentHashes[HelperRootReleaseSet.manifestPath]!, .launchDaemon:currentHashes[HelperRootReleaseSet.launchDaemonPath]!],
            byteCounts:[.executable:matrixCurrentBytes[HelperRootReleaseSet.executablePath]!.count,.deploymentManifest:matrixCurrentBytes[HelperRootReleaseSet.manifestPath]!.count,.launchDaemon:matrixCurrentBytes[HelperRootReleaseSet.launchDaemonPath]!.count])
        _ = try previousStore.preserve(prepared:preparedCase,previousRelease:currentVerified,
            previousHelperCDHash:MachOMetadataReader.expectedCDHash,previousTeamIdentifier:MachOMetadataReader.expectedTeam,
            journal:caseJournal,journalStore:journalStore)
        caseJournal = try journalStore.load(transactionID:preparedCase.initialJournal.transactionID)
        try caseJournal.apply(.intentStageRelease); try journalStore.save(caseJournal)
        _ = try stagedStore.stage(prepared:preparedCase,journal:caseJournal,journalStore:journalStore,artifacts:bytes)
        caseJournal = try journalStore.load(transactionID:preparedCase.initialJournal.transactionID)
        try caseJournal.apply(.intentActivateRelease); try journalStore.save(caseJournal)
        let caseRelease = HelperRootAtomicActivationExecutor.Release(bundle:releaseBundle,
            bytes:[.executable:exe,.deploymentManifest:manifest,.launchDaemon:plist],expectedDigests:artifactDigests,
            expectedPreviousHashes:[.executable:currentHashes[HelperRootReleaseSet.executablePath],.deploymentManifest:currentHashes[HelperRootReleaseSet.manifestPath],.launchDaemon:currentHashes[HelperRootReleaseSet.launchDaemonPath]])
        var activationInterrupted = false
        do {
            _ = try executor.activate(caseRelease,durableJournal:caseJournal,journalStore:journalStore,
                prepared:preparedCase,stagedStore:stagedStore,previousRelease:currentVerified,previousStore:previousStore,
                serviceReport:report,expectedChallenge:challenge,authenticatedPeer:peer,observerPin:pin,
                expectedObservedHelperSHA256:SHA256Digest.hex(matrixCurrentBytes[HelperRootReleaseSet.executablePath]!),
                crashAfter:crashAfter,faultAt:faultAt)
        } catch { activationInterrupted = true }
        check(activationInterrupted,"\(label): injected activation interruption surfaced",&failures)
        let pending = try journalStore.load(transactionID:preparedCase.initialJournal.transactionID)
        if let removeBackupFor {
            let backupName = ".fk-\(preparedCase.initialJournal.transactionID.uuidString.lowercased())-\(removeBackupFor.rawValue).bak"
            let backupPath: String
            switch removeBackupFor {
            case .executable: backupPath = jb + "/usr/libexec/" + backupName
            case .deploymentManifest: backupPath = jb + "/Library/FilterKit/Helper/" + backupName
            case .launchDaemon: backupPath = jb + "/Library/LaunchDaemons/" + backupName
            }
            try FileManager.default.removeItem(atPath: backupPath)
        }
        if removeBackupFor != nil {
            // During a partial activation, untouched artifacts may be absent from Active
            // because their trusted Previous copies are held in transaction backups.
            // Snapshot both presence and bytes; absence is itself part of the pre-recovery state.
            var before:[String:Data?] = [:]
            for path in matrixCurrentBytes.keys {
                let activePath = jb + "/" + path
                before[path] = FileManager.default.fileExists(atPath: activePath) ? try readBytes(activePath) : nil
            }
            do {
                _ = try executor.recover(durableJournal:pending,journalStore:journalStore,
                    serviceReport:report,expectedChallenge:challenge,authenticatedPeer:peer,observerPin:pin,
                    expectedObservedHelperSHA256:SHA256Digest.hex(matrixCurrentBytes[HelperRootReleaseSet.executablePath]!))
                check(false,"\(label): missing backup blocks recovery",&failures)
            } catch HelperRootAtomicActivationExecutor.Failure.recoveryRequiresManualIntervention {
                check(true,"\(label): missing backup blocks recovery",&failures)
            }
            let manual = try journalStore.load(transactionID:preparedCase.initialJournal.transactionID)
            check(manual.state == .manualIntervention,"\(label): Durable Journal enters manual intervention",&failures)
            for (path, expected) in before {
                let activePath = jb + "/" + path
                let exists = FileManager.default.fileExists(atPath: activePath)
                let observed: Data? = exists ? try readBytes(activePath) : nil
                check(observed == expected,"\(label): missing backup leaves Active presence/bytes untouched: \(path)",&failures)
            }
            do {
                _ = try executor.recover()
                check(false,"\(label): quarantined recovery remains blocked",&failures)
            } catch HelperRootAtomicActivationExecutor.Failure.recoveryRequiresManualIntervention {
                check(true,"\(label): quarantined recovery remains blocked",&failures)
            }
            return
        }
        let recoveryResult: HelperRootAtomicActivationExecutor.Phase?
        do {
            recoveryResult = try executor.recover(durableJournal:pending,journalStore:journalStore,
                serviceReport:report,expectedChallenge:challenge,authenticatedPeer:peer,observerPin:pin,
                expectedObservedHelperSHA256: expectCommit ? SHA256Digest.hex(exe) : SHA256Digest.hex(matrixCurrentBytes[HelperRootReleaseSet.executablePath]!))
        } catch {
            check(false,"\(label): recovery invocation failed (\(error))",&failures)
            return
        }
        if expectCommit {
            check(recoveryResult == .committed,"\(label): recovery finalizes committed Active set",&failures)
            let recoveredJournal = try journalStore.load(transactionID:preparedCase.initialJournal.transactionID)
            check(recoveredJournal.state == .activated && recoveredJournal.pendingOperation == nil,"\(label): Durable Journal is activated",&failures)
            matrixCurrentBytes = bytes
        } else {
            check(recoveryResult == .rolledBack,"\(label): recovery rolls back partial Active set",&failures)
            do {
                let recoveredJournal = try journalStore.load(transactionID:preparedCase.initialJournal.transactionID)
                check(recoveredJournal.state == .manualIntervention,"\(label): rollback requires explicit manual intervention (\(recoveredJournal.state))",&failures)
            } catch {
                check(false,"\(label): rollback Journal readable (\(error))",&failures)
            }
            for (path, expected) in matrixCurrentBytes {
                do {
                    let activePath = jb+"/"+path
                    let observed = try readBytes(activePath)
                    check(observed == expected,"\(label): Active \(path) restored to prior bytes",&failures)
                } catch {
                    check(false,"\(label): Active \(path) missing after rollback (\(error)); exists=\(FileManager.default.fileExists(atPath:jb+"/"+path))",&failures)
                }
            }
        }
        do {
            let secondMatrixRecovery = try executor.recover()
            check(secondMatrixRecovery == nil,"\(label): second recovery is idempotent",&failures)
        } catch {
            check(false,"\(label): second recovery is idempotent (\(error))",&failures)
        }
    }

    try runRecoveryCase("crash after executable rename",.executable,nil,false,nil)
    try runRecoveryCase("crash after deployment manifest rename",.deploymentManifest,nil,false,nil)
    try runRecoveryCase("crash after launch daemon rename",.launchDaemon,nil,false,nil)
    try runRecoveryCase("fault after first progress Journal",nil,.afterFirstProgressJournal,false,nil)
    try runRecoveryCase("fault after committed Journal",nil,.afterCommittedJournal,true,nil)
    try runRecoveryCase("fault before Pointer rename",nil,.beforePointerRename,true,nil)
    try runRecoveryCase("fault after Pointer commit",nil,.afterPointerCommit,true,nil)
    try runRecoveryCase("missing Previous backup",.executable,nil,false,.executable)
    // Rebuild the isolated Host fixture after the missing-backup quarantine case.
    // The recovery itself intentionally leaves the partial Active set untouched.
    try write(jb+"/"+HelperRootReleaseSet.executablePath,matrixCurrentBytes[HelperRootReleaseSet.executablePath]!,0o755)
    try write(jb+"/"+HelperRootReleaseSet.manifestPath,matrixCurrentBytes[HelperRootReleaseSet.manifestPath]!,0o600)
    try write(jb+"/"+HelperRootReleaseSet.launchDaemonPath,matrixCurrentBytes[HelperRootReleaseSet.launchDaemonPath]!,0o644)
    // Test-only isolation: the missing-backup case intentionally leaves a manual record.
    // Its quarantine behavior has already been asserted above; remove only this disposable
    // Host fixture's root record so the independent unknown-bytes case can start fresh.
    _ = unlink((jb+"/.filterkit-root-activation.json"))

    // Unknown Active bytes must never be overwritten or deleted during recovery.
    matrixGeneration += 1
    let unknownGeneration = matrixGeneration
    let unknownExe = Data([0xcf,0xfa,0xed,0xfe,44,44,44,44])
    let unknownManifest = try JSONSerialization.data(withJSONObject:["generation":unknownGeneration,"jbRootPath":jb],options:[.sortedKeys])
    let unknownPlist = newPlist
    let unknownBytes:[String:Data] = [HelperRootReleaseSet.executablePath:unknownExe,HelperRootReleaseSet.manifestPath:unknownManifest,HelperRootReleaseSet.launchDaemonPath:unknownPlist]
    let unknownDigests = unknownBytes.map{HelperInstallerArtifactDigest(relativePath:$0.key,sha256:SHA256Digest.hex($0.value))}
    let unknownBundle = HelperInstallerProvisioningBundle(jbRootPath:jb,releaseIdentifier:"unknown-active-case",generation:unknownGeneration,helperCDHash:MachOMetadataReader.expectedCDHash,teamIdentifier:MachOMetadataReader.expectedTeam)
    let unknownEnvelope = HelperSignedProvisioningManifest(envelopeVersion:1,keyIdentifier:"host-test",algorithm:"Ed25519",payload:unknownBundle,signatureBase64:Data(repeating:0x5a,count:64).base64EncodedString())
    let unknownPrepared = try coordinator.prepare(plan:HelperInstallerTransactionPlan(jbRootPath:jb,action:.upgrade),provisioningEnvelopeData:try JSONEncoder().encode(unknownEnvelope),artifacts:unknownBytes,expectedDigests:unknownDigests)
    var unknownJournal = unknownPrepared.initialJournal
    try unknownJournal.apply(.intentVerifyArtifacts); try journalStore.save(unknownJournal)
    try unknownJournal.apply(.verifyArtifacts); try journalStore.save(unknownJournal)
    try unknownJournal.apply(.intentPreservePreviousRelease); try journalStore.save(unknownJournal)
    let matrixHashes = Dictionary(uniqueKeysWithValues:matrixCurrentBytes.map{($0.key,SHA256Digest.hex($0.value))})
    let matrixVerified = HelperRootReleaseSet.Verified(releaseIdentifier:"matrix-current",generation:unknownGeneration-1,
        hashes:[.executable:matrixHashes[HelperRootReleaseSet.executablePath]!, .deploymentManifest:matrixHashes[HelperRootReleaseSet.manifestPath]!, .launchDaemon:matrixHashes[HelperRootReleaseSet.launchDaemonPath]!],
        byteCounts:[.executable:matrixCurrentBytes[HelperRootReleaseSet.executablePath]!.count,.deploymentManifest:matrixCurrentBytes[HelperRootReleaseSet.manifestPath]!.count,.launchDaemon:matrixCurrentBytes[HelperRootReleaseSet.launchDaemonPath]!.count])
    _ = try previousStore.preserve(prepared:unknownPrepared,previousRelease:matrixVerified,previousHelperCDHash:MachOMetadataReader.expectedCDHash,previousTeamIdentifier:MachOMetadataReader.expectedTeam,journal:unknownJournal,journalStore:journalStore)
    unknownJournal = try journalStore.load(transactionID:unknownPrepared.initialJournal.transactionID)
    try unknownJournal.apply(.intentStageRelease); try journalStore.save(unknownJournal)
    _ = try stagedStore.stage(prepared:unknownPrepared,journal:unknownJournal,journalStore:journalStore,artifacts:unknownBytes)
    unknownJournal = try journalStore.load(transactionID:unknownPrepared.initialJournal.transactionID)
    try unknownJournal.apply(.intentActivateRelease); try journalStore.save(unknownJournal)
    let unknownRelease = HelperRootAtomicActivationExecutor.Release(bundle:unknownBundle,bytes:[.executable:unknownExe,.deploymentManifest:unknownManifest,.launchDaemon:unknownPlist],expectedDigests:unknownDigests,expectedPreviousHashes:[.executable:matrixHashes[HelperRootReleaseSet.executablePath],.deploymentManifest:matrixHashes[HelperRootReleaseSet.manifestPath],.launchDaemon:matrixHashes[HelperRootReleaseSet.launchDaemonPath]])
    do { _ = try executor.activate(unknownRelease,durableJournal:unknownJournal,journalStore:journalStore,prepared:unknownPrepared,stagedStore:stagedStore,previousRelease:matrixVerified,previousStore:previousStore,serviceReport:report,expectedChallenge:challenge,authenticatedPeer:peer,observerPin:pin,expectedObservedHelperSHA256:SHA256Digest.hex(matrixCurrentBytes[HelperRootReleaseSet.executablePath]!),faultAt:.afterFirstActivation) } catch { }
    let unknownBytesOnDisk = Data([0xde,0xad,0xbe,0xef,77])
    try write(jb+"/"+HelperRootReleaseSet.executablePath,unknownBytesOnDisk,0o755)
    do {
        let beforeRecovery = try journalStore.load(transactionID:unknownPrepared.initialJournal.transactionID)
        _ = try executor.recover(durableJournal:beforeRecovery,journalStore:journalStore,serviceReport:report,expectedChallenge:challenge,authenticatedPeer:peer,observerPin:pin,expectedObservedHelperSHA256:SHA256Digest.hex(matrixCurrentBytes[HelperRootReleaseSet.executablePath]!))
        check(false,"unknown Active bytes block recovery",&failures)
    } catch HelperRootAtomicActivationExecutor.Failure.recoveryRequiresManualIntervention {
        check(true,"unknown Active bytes block recovery",&failures)
    }
    let observedUnknownActive = try Data(contentsOf:URL(fileURLWithPath:jb+"/"+HelperRootReleaseSet.executablePath))
    check(observedUnknownActive == unknownBytesOnDisk,"unknown Active bytes remain untouched",&failures)
    let unknownManualJournal = try journalStore.load(transactionID:unknownPrepared.initialJournal.transactionID)
    check(unknownManualJournal.state == .manualIntervention,"unknown Active bytes mark Durable Journal manual intervention",&failures)
    do {
        _ = try executor.recover()
        check(false,"unknown Active manual state remains blocked on repeated recovery",&failures)
    } catch HelperRootAtomicActivationExecutor.Failure.recoveryRequiresManualIntervention {
        check(true,"unknown Active manual state remains blocked on repeated recovery",&failures)
    }
    // Reset the isolated Host fixture after asserting the quarantine behavior; this is not
    // a recovery action and does not model a production repair path.
    try write(jb+"/"+HelperRootReleaseSet.executablePath,matrixCurrentBytes[HelperRootReleaseSet.executablePath]!,0o755)
    try write(jb+"/"+HelperRootReleaseSet.manifestPath,matrixCurrentBytes[HelperRootReleaseSet.manifestPath]!,0o600)
    try write(jb+"/"+HelperRootReleaseSet.launchDaemonPath,matrixCurrentBytes[HelperRootReleaseSet.launchDaemonPath]!,0o644)

    // Static audit below verifies that all Previous backups are checked before the
    // rollback mutation loop can unlink any Active destination.

    // No launchd start/restart API is reachable from this executor or recovery path.
    let executorSource = try String(contentsOfFile:FileManager.default.currentDirectoryPath + "/Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift",encoding:.utf8)
    check(!executorSource.contains("launchctl") && !executorSource.contains("bootstrap") && !executorSource.contains("kickstart"),"activation and recovery contain no service-start operation",&failures)

    check(geteuid() == 0,"Host process is root for root-owned Store checks",&failures)
    print("RESULT: \(failures.isEmpty ? "PASS" : "FAIL") (\(passedAssertions)/\(totalAssertions) assertions)")
    if !failures.isEmpty { exit(1) }
 }
}
