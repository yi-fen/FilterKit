import Foundation
import Glibc

// Minimal model shims keep this Host smoke focused on the real descriptor-relative store and
// real Mach-O parser. The production target supplies these models from the application sources.
enum HelperPolicy {
    static func isAbsoluteCleanPath(_ value: String) -> Bool {
        value.hasPrefix("/") && !value.contains("\0") && !value.split(separator: "/").contains("..")
    }
    static func isValidHash(_ value: String) -> Bool { value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil }
}
struct HelperInstallerProvisioningBundle: Codable, Equatable {
    let jbRootPath: String
    let releaseIdentifier: String
    let generation: UInt64
    let helperCDHash: String
    let teamIdentifier: String?
}
struct HelperSignedProvisioningManifest: Codable { let payload: HelperInstallerProvisioningBundle }
struct HelperInstallerArtifactDigest { let relativePath: String; let sha256: String }
struct HelperInstallerTransactionPlan {
    enum Action { case install, upgrade, repin }
    let jbRootPath: String
    let action: Action
}
struct HelperInstallerTransactionJournal: Equatable {
    enum State { case prepared, artifactsVerified, previousReleasePreserved, staged }
    enum PendingOperation { case stageRelease }
    let transactionID: UUID
    let action: HelperInstallerTransactionPlan.Action
    let releaseIdentifier: String
    let generation: UInt64
    var state: State = .prepared
    var pendingOperation: PendingOperation? = nil
    mutating func apply(_ event: Event) throws {
        switch event {
        case .intentVerifyArtifacts: state = .prepared
        case .verifyArtifacts: state = .artifactsVerified
        case .intentStageRelease: pendingOperation = .stageRelease
        case .stageRelease: pendingOperation = nil; state = .staged
        }
    }
    enum Event { case intentVerifyArtifacts, verifyArtifacts, intentStageRelease, stageRelease }
}
struct HelperInstallerDurableJournalStore {
    private static var values: [UUID: HelperInstallerTransactionJournal] = [:]
    static var failNextSave = false
    func save(_ journal: HelperInstallerTransactionJournal) throws {
        if Self.failNextSave { Self.failNextSave = false; throw SmokeError.invalid }
        Self.values[journal.transactionID] = journal
    }
    func load(transactionID: UUID) throws -> HelperInstallerTransactionJournal {
        guard let value = Self.values[transactionID] else { throw SmokeError.invalid }
        return value
    }
}
struct HelperPreparedRootInstall {
    let plan: HelperInstallerTransactionPlan
    let release: HelperRootReleaseSet.Verified
    let provisioningEnvelopeSHA256: String
    let provisioningEnvelopeData: Data
    let initialJournal: HelperInstallerTransactionJournal
}
struct HelperRootReleaseSet {
    enum Artifact: String, CaseIterable { case executable, deploymentManifest, launchDaemon }
    struct Verified: Equatable {
        let releaseIdentifier: String
        let generation: UInt64
        let hashes: [Artifact: String]
        let byteCounts: [Artifact: Int]
    }
    static let executablePath = "usr/libexec/filterkit-helper"
    static let manifestPath = "Library/FilterKit/Helper/Deployment.json"
    static let launchDaemonPath = "Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"
    func verify(bundle: HelperInstallerProvisioningBundle, artifacts: [String: Data],
                expectedDigests: [HelperInstallerArtifactDigest]) throws -> Verified {
        let paths = [Self.executablePath, Self.manifestPath, Self.launchDaemonPath]
        guard Set(artifacts.keys) == Set(paths), expectedDigests.count == 3 else { throw SmokeError.invalid }
        let expected = Dictionary(uniqueKeysWithValues: expectedDigests.map { ($0.relativePath, $0.sha256) })
        var hashes: [Artifact: String] = [:], counts: [Artifact: Int] = [:]
        for (artifact, path) in zip(Artifact.allCases, paths) {
            guard let data = artifacts[path] else { throw SmokeError.invalid }
            let hash = SHA256Digest.hex(data)
            guard expected[path] == hash else { throw SmokeError.invalid }
            hashes[artifact] = hash; counts[artifact] = data.count
        }
        return Verified(releaseIdentifier: bundle.releaseIdentifier, generation: bundle.generation,
                        hashes: hashes, byteCounts: counts)
    }
}
enum SmokeError: Error { case invalid }
struct ElleKitBinaryVersion {
    init(currentVersion: String?, compatibilityVersion: String?, installName: String?,
         uuid: String?, architecture: String?, is64Bit: Bool) {}
}
enum ElleKitBinaryMetadataError: Error { case truncated, malformedLoadCommand, noSupportedSlice, notMachO }

func pass(_ condition: @autoclosure () -> Bool, _ label: String, _ count: inout Int) {
    count += 1
    if !condition() { fputs("FAIL: \(label)\n", stderr); exit(1) }
    print("PASS: \(label)")
}
func be32(_ value: UInt32) -> [UInt8] { [UInt8(value >> 24), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)] }
func le32(_ value: UInt32) -> [UInt8] { [UInt8(value & 255), UInt8((value >> 8) & 255), UInt8((value >> 16) & 255), UInt8(value >> 24)] }
func makeSignedMachO() -> (Data, String) {
    var cd = [UInt8](repeating: 0, count: 112)
    func put(_ offset: Int, _ value: UInt32) { cd.replaceSubrange(offset..<(offset + 4), with: be32(value)) }
    put(0, 0xFADE0C02); put(4, UInt32(cd.count)); put(8, 0x20200)
    put(20, 64); cd[36] = 32; cd[37] = 2; cd[38] = 0; put(48, 88)
    let identifier = Array("filterkit-helper".utf8) + [0]
    let team = Array("TEAM1234".utf8) + [0]
    cd.replaceSubrange(64..<(64 + identifier.count), with: identifier)
    cd.replaceSubrange(88..<(88 + team.count), with: team)
    let cdHash = String(SHA256Digest.hex(Data(cd)).prefix(40))
    var superBlob = be32(0xFADE0CC0) + be32(UInt32(20 + cd.count)) + be32(1)
    superBlob += be32(0) + be32(20) + cd
    let command = le32(0x1D) + le32(16) + le32(48) + le32(UInt32(superBlob.count))
    var header = [UInt8](repeating: 0, count: 32)
    header.replaceSubrange(0..<4, with: [0xCF, 0xFA, 0xED, 0xFE])
    header.replaceSubrange(4..<8, with: le32(0x0100000C))
    header.replaceSubrange(8..<12, with: le32(0))
    header.replaceSubrange(12..<16, with: le32(2))
    header.replaceSubrange(16..<20, with: le32(1))
    header.replaceSubrange(20..<24, with: le32(16))
    return (Data(header + command + superBlob), cdHash)
}
func createDirectory(_ path: String, mode: mode_t = 0o700) throws {
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    _ = chmod(path, mode)
}
func makePrepared(root: String, id: UUID, executable: Data, cdHash: String) throws -> (HelperPreparedRootInstall, [String: Data]) {
    let bundle = HelperInstallerProvisioningBundle(jbRootPath: root, releaseIdentifier: "r3-host-test",
        generation: 44, helperCDHash: cdHash, teamIdentifier: "TEAM1234")
    let manifest = Data("deployment-manifest-fixture".utf8)
    let launch = try PropertyListSerialization.data(fromPropertyList: ["Label": "cn.yfen.filterkit.helper"], format: .xml, options: 0)
    let artifacts = [HelperRootReleaseSet.executablePath: executable,
                     HelperRootReleaseSet.manifestPath: manifest,
                     HelperRootReleaseSet.launchDaemonPath: launch]
    let digests = artifacts.map { HelperInstallerArtifactDigest(relativePath: $0.key, sha256: SHA256Digest.hex($0.value)) }
    let verified = try HelperRootReleaseSet().verify(bundle: bundle, artifacts: artifacts, expectedDigests: digests)
    let envelope = try JSONEncoder().encode(HelperSignedProvisioningManifest(payload: bundle))
    let prepared = HelperPreparedRootInstall(plan: HelperInstallerTransactionPlan(jbRootPath: root, action: .install), release: verified,
        provisioningEnvelopeSHA256: SHA256Digest.hex(envelope), provisioningEnvelopeData: envelope,
        initialJournal: HelperInstallerTransactionJournal(transactionID: id, action: .install,
            releaseIdentifier: bundle.releaseIdentifier, generation: bundle.generation))
    return (prepared, artifacts)
}

func journalReadyForStage(_ prepared: HelperPreparedRootInstall,
                          store: HelperInstallerDurableJournalStore) throws -> HelperInstallerTransactionJournal {
    var journal = prepared.initialJournal
    try journal.apply(.intentVerifyArtifacts)
    try journal.apply(.verifyArtifacts)
    try journal.apply(.intentStageRelease)
    try store.save(journal)
    return journal
}

@main struct SmokeMain {
    static func main() throws {
        var checks = 0
        let root = "/root/filterkit-p244-r3-\(UUID().uuidString.lowercased())"
        let stageRoot = root + "/" + HelperInstallerStagedReleaseStore.relativeRootPath
        try createDirectory(stageRoot)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = try HelperInstallerStagedReleaseStore(jbRootPath: root)
        let (binary, cdHash) = makeSignedMachO()
        let (prepared, artifacts) = try makePrepared(root: root, id: UUID(), executable: binary, cdHash: cdHash)

        let missing = try store.inspect(prepared: prepared)
        pass(missing.state == .missing, "absent transaction classified as missing", &checks)
        let durableJournalStore = HelperInstallerDurableJournalStore()
        let readyJournal = try journalReadyForStage(prepared, store: durableJournalStore)
        let loadedJournal = try durableJournalStore.load(transactionID: readyJournal.transactionID)
        pass(loadedJournal == readyJournal, "Journal intent is durably reloaded before staging", &checks)
        let receipt: HelperInstallerStagedReleaseStore.Receipt
        do { receipt = try store.stage(prepared: prepared, journal: readyJournal,
                                      journalStore: durableJournalStore, artifacts: artifacts) }
        catch { fputs("STAGE ERROR: \(error)\n", stderr); throw error }
        pass(receipt.hashes == prepared.release.hashes && receipt.byteCounts == prepared.release.byteCounts,
             "verified three-artifact release staged with exact receipt", &checks)
        let committedJournal = try durableJournalStore.load(transactionID: readyJournal.transactionID)
        pass(committedJournal.state == .staged && committedJournal.pendingOperation == nil,
             "Durable Journal completion follows staged file and directory fsync", &checks)
        let complete = try store.inspect(prepared: prepared)
        pass(complete.state == .complete && complete.observedHashes == prepared.release.hashes,
             "staged release re-read and hash verified", &checks)
        do { _ = try store.stage(prepared: prepared, journal: readyJournal,
            journalStore: durableJournalStore, artifacts: artifacts); pass(false, "existing transaction is never overwritten", &checks) }
        catch HelperInstallerStagedReleaseStore.StoreError.transactionAlreadyExists { pass(true, "existing transaction is never overwritten", &checks) }

        let executablePath = stageRoot + "/" + prepared.initialJournal.transactionID.uuidString.lowercased() + "/filterkit-helper"
        var changed = try Data(contentsOf: URL(fileURLWithPath: executablePath)); changed.append(0x41)
        try changed.write(to: URL(fileURLWithPath: executablePath)); _ = chmod(executablePath, 0o755)
        let mismatch = try store.inspect(prepared: prepared)
        pass(mismatch.state == .mismatched && mismatch.mismatchedArtifacts.contains(.executable),
             "tampered staged artifact classified as mismatched", &checks)

        let (crashPrepared, crashArtifacts) = try makePrepared(root: root, id: UUID(), executable: binary, cdHash: cdHash)
        let crashJournalStore = HelperInstallerDurableJournalStore()
        let crashJournal = try journalReadyForStage(crashPrepared, store: crashJournalStore)
        do {
            _ = try store.stage(prepared: crashPrepared, journal: crashJournal,
                journalStore: crashJournalStore, artifacts: crashArtifacts, faultAt: .afterManifest)
            pass(false, "fault injection stops after manifest", &checks)
        } catch HelperInstallerStagedReleaseStore.StoreError.injectedCrash(.deploymentManifest) {
            pass(true, "fault injection stops after manifest", &checks)
        }
        let partial = try store.inspect(prepared: crashPrepared)
        pass(partial.state == .partial && partial.missingArtifacts == [.launchDaemon],
             "interrupted stage remains partial and is not auto-promoted", &checks)

        let (postWriteCrashPrepared, postWriteCrashArtifacts) = try makePrepared(root: root, id: UUID(), executable: binary, cdHash: cdHash)
        let postWriteCrashStore = HelperInstallerDurableJournalStore()
        let postWriteCrashJournal = try journalReadyForStage(postWriteCrashPrepared, store: postWriteCrashStore)
        do { _ = try store.stage(prepared: postWriteCrashPrepared, journal: postWriteCrashJournal,
            journalStore: postWriteCrashStore, artifacts: postWriteCrashArtifacts, faultAt: .afterLaunchDaemon)
            pass(false, "post-write crash injection reached", &checks) }
        catch HelperInstallerStagedReleaseStore.StoreError.injectedCrash(.launchDaemon) {
            pass(true, "post-write crash injection reached", &checks)
        }
        let postWriteInspection = try store.inspect(prepared: postWriteCrashPrepared)
        let stillPending = try postWriteCrashStore.load(transactionID: postWriteCrashJournal.transactionID)
        pass(postWriteInspection.state == .complete && stillPending.pendingOperation == .stageRelease && stillPending.state == .artifactsVerified,
             "complete files with pending Journal remain ambiguous and unpromoted", &checks)

        let extraPath = stageRoot + "/" + postWriteCrashPrepared.initialJournal.transactionID.uuidString.lowercased() + "/unexpected.tmp"
        try Data("unexpected".utf8).write(to: URL(fileURLWithPath: extraPath)); _ = chmod(extraPath, 0o600)
        let extraInspection = try store.inspect(prepared: postWriteCrashPrepared)
        pass(extraInspection.state == .mismatched && extraInspection.unexpectedEntries == ["unexpected.tmp"],
             "unexpected staged directory entries are rejected", &checks)

        let (journalFailurePrepared, journalFailureArtifacts) = try makePrepared(root: root, id: UUID(), executable: binary, cdHash: cdHash)
        let journalFailureStore = HelperInstallerDurableJournalStore()
        let journalFailureIntent = try journalReadyForStage(journalFailurePrepared, store: journalFailureStore)
        HelperInstallerDurableJournalStore.failNextSave = true
        do { _ = try store.stage(prepared: journalFailurePrepared, journal: journalFailureIntent,
            journalStore: journalFailureStore, artifacts: journalFailureArtifacts)
            pass(false, "Journal completion I/O failure is surfaced", &checks) }
        catch HelperInstallerStagedReleaseStore.StoreError.journalCommitIndeterminate {
            pass(true, "Journal completion I/O failure is surfaced", &checks)
        }
        let journalFailureInspection = try store.inspect(prepared: journalFailurePrepared)
        let journalFailureStillPending = try journalFailureStore.load(transactionID: journalFailureIntent.transactionID)
        pass(journalFailureInspection.state == .complete && journalFailureStillPending.pendingOperation == .stageRelease,
             "durable staged bytes are preserved when Journal completion is indeterminate", &checks)

        let (noIntentPrepared, noIntentArtifacts) = try makePrepared(root: root, id: UUID(), executable: binary, cdHash: cdHash)
        do { _ = try store.stage(prepared: noIntentPrepared, journal: noIntentPrepared.initialJournal,
            journalStore: HelperInstallerDurableJournalStore(), artifacts: noIntentArtifacts)
            pass(false, "staging without durable Journal intent rejected", &checks) }
        catch HelperInstallerStagedReleaseStore.StoreError.journalIntentRequired {
            pass(true, "staging without durable Journal intent rejected", &checks)
        }
        let noIntentInspection = try store.inspect(prepared: noIntentPrepared)
        pass(noIntentInspection.state == .missing,
             "missing Journal intent causes no filesystem side effect", &checks)

        let (badPrepared, badArtifacts) = try makePrepared(root: root, id: UUID(), executable: Data("not-macho".utf8), cdHash: cdHash)
        let badJournalStore = HelperInstallerDurableJournalStore()
        let badJournal = try journalReadyForStage(badPrepared, store: badJournalStore)
        do { _ = try store.stage(prepared: badPrepared, journal: badJournal,
            journalStore: badJournalStore, artifacts: badArtifacts); pass(false, "non-Mach-O helper rejected", &checks) }
        catch HelperInstallerStagedReleaseStore.StoreError.machOIdentityMismatch { pass(true, "non-Mach-O helper rejected", &checks) }
        let badInspection = try store.inspect(prepared: badPrepared)
        pass(badInspection.state == .missing, "failed identity validation creates no staged transaction", &checks)

        let symlinkRoot = "/root/filterkit-p244-r3-link-\(UUID().uuidString.lowercased())"
        pass(symlink(root, symlinkRoot) == 0, "symlink fixture created", &checks)
        defer { _ = unlink(symlinkRoot) }
        do { _ = try HelperInstallerStagedReleaseStore(jbRootPath: symlinkRoot).inspect(prepared: prepared); pass(false, "JBROOT symlink traversal rejected", &checks) }
        catch { pass(true, "JBROOT symlink traversal rejected", &checks) }

        print("RESULT \(checks)/\(checks)")
    }
}
