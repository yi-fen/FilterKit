import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw NSError(domain: "P1-23", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
let fm = FileManager.default
let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("filterkit-p1-23-\(UUID().uuidString)", isDirectory: true)
try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
defer { try? fm.removeItem(at: root) }
let journalID = UUID()
let pluginID = UUID()
let oldHash = SHA256Digest.hex(Data("old plist".utf8))
let dylibHash = SHA256Digest.hex(Data("new dylib".utf8))
let plistHash = SHA256Digest.hex(Data("new plist".utf8))
let journal = try HelperTransactionJournal(transactionID: journalID, pluginID: pluginID,
    dylibFileName: "Demo.dylib", plistFileName: "Demo.plist", dylibSHA256: dylibHash,
    plistSHA256: plistHash, previousPlistSHA256: oldHash)
let store = try HelperTransactionJournalStore(directoryPath: root.path)
try store.save(journal)
let loadedInitial = try store.load()
try check(loadedInitial == journal, "journal round trip failed")
var updated = journal
updated.phase = .installingPlist
try store.save(updated)
let loadedUpdated = try store.load()
try check(loadedUpdated?.phase == .installingPlist, "journal phase update failed")

let planner = HelperTransactionRecoveryPlanner()
let afterDylibCommit = HelperTransactionFileObservation(
    temporaryDylibHash: nil, temporaryPlistHash: plistHash,
    deployedDylibHash: dylibHash, deployedPlistHash: nil, previousPlistHash: oldHash)
let actions = try planner.plan(journal: updated, observed: afterDylibCommit)
try check(actions.contains(.removeDeployedDylib("Demo.dylib", expectedSHA256: dylibHash)), "recovery did not remove transaction dylib")
try check(actions.contains(.restorePreviousPlist(backup: journal.previousPlistName, destination: "Demo.plist", expectedSHA256: oldHash)), "recovery did not restore original plist")
try check(actions.contains(.removeTemporaryPlist(journal.temporaryPlistName, expectedSHA256: plistHash)), "recovery did not clean staged plist temp")

var committed = journal
committed.phase = .committed
let committedObservation = HelperTransactionFileObservation(
    temporaryDylibHash: nil, temporaryPlistHash: nil,
    deployedDylibHash: dylibHash, deployedPlistHash: plistHash, previousPlistHash: oldHash)
let committedActions = try planner.plan(journal: committed, observed: committedObservation)
try check(committedActions.contains(.removePreviousPlist(journal.previousPlistName, expectedSHA256: oldHash)), "committed recovery did not clean backup")
try check(committedActions.last == .clearJournal, "committed recovery did not clear journal")

let missingOriginal = HelperTransactionFileObservation(
    temporaryDylibHash: nil, temporaryPlistHash: nil,
    deployedDylibHash: nil, deployedPlistHash: nil, previousPlistHash: nil)
let missingOriginalActions = try planner.plan(journal: updated, observed: missingOriginal)
try check(missingOriginalActions == [.manualIntervention], "missing original plist was not escalated")

let foreign = try HelperTransactionJournal(transactionID: UUID(), pluginID: UUID(),
    dylibFileName: "Other.dylib", plistFileName: "Other.plist", dylibSHA256: dylibHash,
    plistSHA256: plistHash, previousPlistSHA256: nil)
do {
    try store.save(foreign)
    throw NSError(domain: "P1-23", code: 2, userInfo: [NSLocalizedDescriptionKey: "foreign journal replaced active transaction"])
} catch HelperTransactionJournalStore.StoreError.journalAlreadyExists { }
try store.clear()
let loadedAfterClear = try store.load()
try check(loadedAfterClear == nil, "journal clear failed")
print("P1-23 recovery smoke: PASS (root-owned journal round trip, phase update, rollback plan, committed cleanup plan, foreign transaction rejection)")
