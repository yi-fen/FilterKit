import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum HelperRootReleaseSet {
    enum Artifact: String, CaseIterable, Hashable { case executable, deploymentManifest, launchDaemon }
    struct Verified { let releaseIdentifier: String; let generation: UInt64; let hashes: [Artifact: String]; let byteCounts: [Artifact: Int] }
}
enum HelperPolicy { static func isValidHash(_ value: String) -> Bool { value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil } }
struct HelperInstallerTransactionJournal {
    enum State { case prepared, artifactsVerified, previousReleasePreserved, staged, activated, serviceVerified, committed, rollbackRequired, rolledBack, manualIntervention }
    enum PendingOperation { case verifyArtifacts, preservePreviousRelease, stageRelease, activateRelease, verifyService, commitProvisioning }
    enum Action { case install, upgrade, repin }
    let state: State; let pendingOperation: PendingOperation?; let action: Action; let generation: UInt64; let releaseIdentifier: String
    func validateChain() throws {}
}
struct HelperInstallerRecoveryAssessment {
    enum Recommendation { case noActionRequired, beginNextOperation(HelperInstallerTransactionJournal.PendingOperation), reconcilePendingOperation(HelperInstallerTransactionJournal.PendingOperation), manualIntervention, confirmRollback }
    struct Result { let recommendation: Recommendation }
    static func assess(_ journal: HelperInstallerTransactionJournal) throws -> Result {
        if let pending = journal.pendingOperation { return Result(recommendation: .reconcilePendingOperation(pending)) }
        return Result(recommendation: .beginNextOperation(.stageRelease))
    }
}
struct HelperInstallerDescriptorFilesystemObserver {
    struct FileRecord { let sha256: String }
    enum ArtifactState { case missing, present(FileRecord) }
    struct ReleasePointer: Codable, Equatable { let schemaVersion: Int; let transactionID: UUID; let releaseIdentifier: String; let generation: UInt64; let artifactHashes: [String: String] }
}
struct HelperInstallerArtifactReconciliationBackend {
    struct Result {
        let activeArtifacts: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState]
        let stagedArtifacts: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState]
        let previousArtifacts: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState]
        let activeReleasePointer: HelperInstallerDescriptorFilesystemObserver.ReleasePointer?
        let activePointerMatchesObservedArtifacts: Bool
        let ownershipVerified: Bool
    }
}
func check(_ condition: @autoclosure () -> Bool, _ label: String) { if !condition() { fatalError("FAIL: \(label)") }; print("PASS: \(label)") }
let digest = String(repeating: "a", count: 64)
let hashes: [HelperRootReleaseSet.Artifact: String] = [.executable: digest, .deploymentManifest: String(repeating: "b", count: 64), .launchDaemon: String(repeating: "c", count: 64)]
let release = HelperRootReleaseSet.Verified(releaseIdentifier: "r13", generation: 13, hashes: hashes, byteCounts: [:])
func set(_ hashes: [HelperRootReleaseSet.Artifact: String]?, partial: Bool = false) -> [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState] {
    guard let hashes else { return Dictionary(uniqueKeysWithValues: HelperRootReleaseSet.Artifact.allCases.map { ($0, .missing) }) }
    var result: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState] = [:]
    for artifact in HelperRootReleaseSet.Artifact.allCases {
        if partial && artifact == .launchDaemon { result[artifact] = .missing }
        else { result[artifact] = .present(.init(sha256: hashes[artifact]!)) }
    }
    return result
}
let coordinator = HelperInstallerRecoveryCoordinator()
func journal(_ state: HelperInstallerTransactionJournal.State = .staged, pending: HelperInstallerTransactionJournal.PendingOperation? = nil, action: HelperInstallerTransactionJournal.Action = .install) -> HelperInstallerTransactionJournal {
    .init(state: state, pendingOperation: pending, action: action, generation: 13, releaseIdentifier: "r13")
}
func result(active: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState], staged: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState], previous: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState] = [:], pointer: Bool = false, ownership: Bool = true) -> HelperInstallerArtifactReconciliationBackend.Result {
    let pointerValue = pointer ? HelperInstallerDescriptorFilesystemObserver.ReleasePointer(schemaVersion: 2, transactionID: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!, releaseIdentifier: "r13", generation: 13, artifactHashes: ["executable": hashes[.executable]!, "deploymentManifest": hashes[.deploymentManifest]!, "launchDaemon": hashes[.launchDaemon]!]) : nil
    return .init(activeArtifacts: active, stagedArtifacts: staged, previousArtifacts: previous, activeReleasePointer: pointerValue, activePointerMatchesObservedArtifacts: pointer, ownershipVerified: ownership)
}
let activeComplete = set(hashes)
let stagedComplete = set(hashes)
let absent = set(nil)
let oldHashes: [HelperRootReleaseSet.Artifact: String] = [.executable: String(repeating: "d", count: 64), .deploymentManifest: String(repeating: "e", count: 64), .launchDaemon: String(repeating: "f", count: 64)]
let previousComplete = set(oldHashes)
let scenarios: [(String, HelperInstallerArtifactReconciliationBackend.Result, HelperInstallerTransactionJournal, [HelperRootReleaseSet.Artifact: String]?, Bool)] = [
    ("active three artifacts complete", result(active: activeComplete, staged: absent, pointer: true), journal(.activated), nil, false),
    ("active partial missing", result(active: set(hashes, partial: true), staged: absent), journal(.activated), nil, true),
    ("active pointer hash mismatch", result(active: activeComplete, staged: absent, pointer: false), journal(.activated), nil, true),
    ("staged complete", result(active: absent, staged: stagedComplete), journal(.staged), nil, false),
    ("staged partial", result(active: absent, staged: set(hashes, partial: true)), journal(.staged), nil, true),
    ("previous backup complete", result(active: activeComplete, staged: absent, previous: previousComplete, pointer: true), journal(.activated, action: .upgrade), oldHashes, false),
    ("upgrade staged with previous active", result(active: previousComplete, staged: stagedComplete, previous: previousComplete), journal(.staged, action: .upgrade), oldHashes, false),
    ("previous backup corrupt", result(active: activeComplete, staged: absent, previous: set([.executable: digest, .deploymentManifest: digest, .launchDaemon: digest]), pointer: true), journal(.activated, action: .upgrade), oldHashes, true),
    ("active and previous both incomplete", result(active: set(hashes, partial: true), staged: absent, previous: set(hashes, partial: true)), journal(.activated, action: .upgrade), oldHashes, true),
    ("journal and disk disagree", result(active: absent, staged: absent), journal(.committed), nil, true)
]
for (label, observation, record, previous, mustStop) in scenarios {
    let assessment = coordinator.assess(journal: record, verifiedRelease: release, observation: observation, previousExpectedHashes: previous)
    if mustStop { if case .keepServiceStopped = assessment.decision { check(true, label + " -> service remains stopped") } else { fatalError("FAIL: \(label) did not stop") } }
    else { if case .evidenceConsistentButExecutionNotAuthorized = assessment.decision { check(true, label + " -> no automatic execution") } else { fatalError("FAIL: \(label) unexpectedly stopped") } }
}

// Exercise the actual atomic pointer writer against an isolated root-owned host fixture.
let root = "/tmp/filterkit-r13-\(UUID().uuidString.lowercased())"
try FileManager.default.createDirectory(atPath: root + "/Library/FilterKit/Helper", withIntermediateDirectories: true)
guard chmod(root, 0o700) == 0, chmod(root + "/Library", 0o700) == 0,
      chmod(root + "/Library/FilterKit", 0o700) == 0, chmod(root + "/Library/FilterKit/Helper", 0o700) == 0 else { fatalError("fixture chmod failed") }
let writer = HelperInstallerActiveReleasePointerWriter(jbRootPath: root)
let pointerTransactionID = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
try writer.write(transactionID: pointerTransactionID, release: release, observedActiveHashes: hashes)
let pointerPath = root + "/Library/FilterKit/Helper/active-release.json"
var pointerStat = stat(); guard lstat(pointerPath, &pointerStat) == 0 else { fatalError("pointer absent") }
check((pointerStat.st_mode & 0o777) == 0o600 && pointerStat.st_uid == 0 && pointerStat.st_nlink == 1, "pointer is root-owned private regular file")
let pointerData = try Data(contentsOf: URL(fileURLWithPath: pointerPath))
let pointer = try JSONDecoder().decode(HelperInstallerDescriptorFilesystemObserver.ReleasePointer.self, from: pointerData)
check(pointer.transactionID == pointerTransactionID && pointer.releaseIdentifier == "r13" && pointer.generation == 13, "atomic pointer binds transaction and verified release identity")
do { try writer.write(transactionID: pointerTransactionID, release: release, observedActiveHashes: [.executable: digest]); fatalError("mismatch accepted") }
catch HelperInstallerActiveReleasePointerWriter.WriterError.invalidRelease { check(true, "pointer writer rejects mismatched active hashes") }
try FileManager.default.removeItem(atPath: root)
print("R13 recovery smoke: 13/13 assertions passed")
