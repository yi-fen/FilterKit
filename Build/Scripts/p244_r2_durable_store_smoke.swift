import Foundation
import Glibc

enum HelperPolicy {
    static func isValidHash(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }
}
struct HelperInstallerTransactionPlan {
    enum Action: String, Codable { case install, upgrade, repin, start, stop, uninstall }
}
func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    if !condition() { fputs("FAIL: \(label)\n", stderr); exit(1) }
    print("PASS: \(label)")
}
func makeDir(_ name: String, mode: mode_t = 0o700) throws -> String {
    let path = "/root/filterkit-p244-r2-\(name)-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    _ = chmod(path, mode)
    return path
}
func journal() throws -> HelperInstallerTransactionJournal {
    var value = try HelperInstallerTransactionJournal(action: .install, releaseIdentifier: "r2-test", generation: 44)
    try value.apply(.intentVerifyArtifacts)
    return value
}
var checks = 0
func pass(_ condition: @autoclosure () -> Bool, _ label: String) { checks += 1; expect(condition(), label) }

@main
struct SmokeMain {
  static func main() throws {
    let path = try makeDir("roundtrip")
    defer { try? FileManager.default.removeItem(atPath: path) }
    let store = HelperInstallerDurableJournalStore(directoryPath: path)
    let first = try journal()
    try store.save(first)
    let firstLoaded = try store.load(transactionID: first.transactionID)
    pass(firstLoaded == first, "root-owned 0700 store round-trip")
    var updated = first
    try updated.apply(.verifyArtifacts)
    try store.save(updated)
    let updatedLoaded = try store.load(transactionID: first.transactionID)
    pass(updatedLoaded == updated, "atomic replacement of existing journal")
    do { try store.save(first); pass(false, "journal rollback rejected") }
    catch { pass(true, "journal rollback rejected") }
    try store.save(updated)
    let idempotentLoaded = try store.load(transactionID: first.transactionID)
    pass(idempotentLoaded == updated, "idempotent same-head save accepted")

    var fork = try HelperInstallerTransactionJournal(transactionID: first.transactionID, action: .install,
        releaseIdentifier: "different-release", generation: 44)
    try fork.apply(.intentVerifyArtifacts)
    try fork.apply(.verifyArtifacts)
    do { try store.save(fork); pass(false, "journal header fork rejected") }
    catch { pass(true, "journal header fork rejected") }

    let journalPath = path + "/" + first.transactionID.uuidString.lowercased() + ".json"
    let saved = try Data(contentsOf: URL(fileURLWithPath: journalPath))
    var corrupt = saved
    corrupt[corrupt.count / 2] ^= 0x01
    try corrupt.write(to: URL(fileURLWithPath: journalPath))
    try corrupt.write(to: URL(fileURLWithPath: journalPath)); _ = chmod(journalPath, 0o600)
    do { _ = try store.load(transactionID: first.transactionID); pass(false, "tampered journal rejected") }
    catch { pass(true, "tampered journal rejected") }
    do { try store.save(updated); pass(false, "corrupt existing journal is not overwritten") }
    catch { pass(true, "corrupt existing journal is not overwritten") }
    try saved.write(to: URL(fileURLWithPath: journalPath)); _ = chmod(journalPath, 0o600)

    let symlinkPath = path + "/" + first.transactionID.uuidString.lowercased() + ".json"
    try FileManager.default.removeItem(atPath: symlinkPath)
    let target = path + "/target.json"
    try saved.write(to: URL(fileURLWithPath: target)); _ = chmod(target, 0o600)
    pass(symlink(target, symlinkPath) == 0, "symlink fixture created")
    do { _ = try store.load(transactionID: first.transactionID); pass(false, "symlink journal rejected") }
    catch { pass(true, "symlink journal rejected") }

    try FileManager.default.removeItem(atPath: symlinkPath)
    pass(link(target, symlinkPath) == 0, "hardlink fixture created")
    do { _ = try store.load(transactionID: first.transactionID); pass(false, "hardlinked journal rejected") }
    catch { pass(true, "hardlinked journal rejected") }

    let unsafeParent = try makeDir("unsafe-parent", mode: 0o777)
    defer { try? FileManager.default.removeItem(atPath: unsafeParent) }
    let child = unsafeParent + "/store"
    try FileManager.default.createDirectory(atPath: child, withIntermediateDirectories: false)
    _ = chmod(child, 0o700)
    do { try HelperInstallerDurableJournalStore(directoryPath: child).save(try journal()); pass(false, "group/world writable ancestor rejected") }
    catch { pass(true, "group/world writable ancestor rejected") }

    do { try HelperInstallerDurableJournalStore(directoryPath: "/tmp/unsafe-store-\(UUID().uuidString)").save(try journal()); pass(false, "world-writable /tmp ancestor rejected") }
    catch { pass(true, "world-writable /tmp ancestor rejected") }

    do { try HelperInstallerDurableJournalStore(directoryPath: "/root/../tmp/escape").save(try journal()); pass(false, "path traversal rejected") }
    catch { pass(true, "path traversal rejected") }

    let aliasPath = path + "/directory-alias"
    pass(symlink(path, aliasPath) == 0, "symlink parent fixture created")
    do { try HelperInstallerDurableJournalStore(directoryPath: aliasPath).save(try journal()); pass(false, "symlink parent directory rejected") }
    catch { pass(true, "symlink parent directory rejected") }

    let oversizedID = UUID()
    let oversizedName = path + "/" + oversizedID.uuidString.lowercased() + ".json"
    try Data(repeating: 0x41, count: 1_048_577).write(to: URL(fileURLWithPath: oversizedName))
    _ = chmod(oversizedName, 0o600)
    do { _ = try store.load(transactionID: oversizedID); pass(false, "oversized journal rejected") }
    catch { pass(true, "oversized journal rejected") }

    let badMode = try makeDir("bad-mode", mode: 0o755)
    defer { try? FileManager.default.removeItem(atPath: badMode) }
    do { try HelperInstallerDurableJournalStore(directoryPath: badMode).save(try journal()); pass(false, "non-0700 final directory rejected") }
    catch { pass(true, "non-0700 final directory rejected") }

    print("RESULT \(checks)/\(checks)")
  }
}
