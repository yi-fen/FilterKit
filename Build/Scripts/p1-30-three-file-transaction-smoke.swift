import Foundation
import Glibc

enum HelperPolicy {
    static func isAbsoluteCleanPath(_ value: String) -> Bool { value.hasPrefix("/") && !value.contains("..") && URL(fileURLWithPath: value).standardizedFileURL.path == value }
    static func isSafeLeafName(_ value: String) -> Bool { !value.isEmpty && value != "." && value != ".." && !value.hasPrefix(".") && !value.contains("/") && !value.contains("\\") && !value.contains("..") }
    static func isValidHash(_ value: String) -> Bool { value.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil }
}

func check130(_ condition: Bool, _ message: String) throws {
    guard condition else { throw NSError(domain: "P1-30", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

func manifest130(pluginID: UUID, dylibName: String, plistName: String, dylib: Data, plist: Data, version: String) throws -> Data {
    let object: [String: Any] = ["schemaVersion": 3, "pluginID": pluginID.uuidString,
        "dylibFileName": dylibName, "plistFileName": plistName,
        "dylibSHA256": SHA256Digest.hex(dylib), "plistSHA256": SHA256Digest.hex(plist),
        "hardBoundBundleIdentifier": "com.example.source", "softAssociatedBundleIdentifiers": [String](),
        "machOIdentitySHA256": String(repeating: "a", count: 64), "version": version]
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

@main struct P130ThreeFileTransactionSmoke {
    static func main() throws {
        guard geteuid() == 0 else { print("P1-30 smoke skipped: root required"); return }
        let fm = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("filterkit-p1-30-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        defer { try? fm.removeItem(at: base) }
        let dylibName = "Demo.dylib", plistName = "Demo.plist", manifestName = "Demo.fk.json"
        let executor = try HelperThreeFileTransactionExecutor(directoryPath: base.path)
        let pluginID = UUID()
        let firstD = Data("first-dylib".utf8), firstP = try PropertyListSerialization.data(fromPropertyList: ["Filter": ["Bundles": ["com.first"]]], format: .xml, options: 0)
        let firstM = try manifest130(pluginID: pluginID, dylibName: dylibName, plistName: plistName, dylib: firstD, plist: firstP, version: "first")
        let first = try executor.execute(pluginID: pluginID, dylibName: dylibName, plistName: plistName,
            dylib: firstD, plist: firstP, manifest: firstM, route: .firstInstall)
        try check130(first.route == "firstInstall", "first-install receipt route mismatch")
        try check130(try Data(contentsOf: base.appendingPathComponent(dylibName)) == firstD, "first dylib bytes mismatch")
        try check130(try Data(contentsOf: base.appendingPathComponent(plistName)) == firstP, "first plist bytes mismatch")
        try check130(try Data(contentsOf: base.appendingPathComponent(manifestName)) == firstM, "first manifest bytes mismatch")

        let wrongD = Data("wrong-update".utf8)
        let wrongM = try manifest130(pluginID: pluginID, dylibName: dylibName, plistName: plistName, dylib: wrongD, plist: firstP, version: "wrong")
        do {
            _ = try executor.execute(pluginID: pluginID, dylibName: dylibName, plistName: plistName,
                dylib: wrongD, plist: firstP, manifest: wrongM, route: .update,
                expectedPrevious: (String(repeating: "0", count: 64), SHA256Digest.hex(firstP), SHA256Digest.hex(firstM)))
            throw NSError(domain: "P1-30", code: 5, userInfo: [NSLocalizedDescriptionKey: "stale previous hash was accepted"])
        } catch HelperThreeFileTransactionExecutor.TransactionError.conflict { }
        try check130(try Data(contentsOf: base.appendingPathComponent(dylibName)) == firstD, "stale-hash rejection mutated existing dylib")

        let nextD = Data("updated-dylib".utf8), nextP = try PropertyListSerialization.data(fromPropertyList: ["Filter": ["Bundles": ["com.updated"]]], format: .xml, options: 0)
        let nextM = try manifest130(pluginID: pluginID, dylibName: dylibName, plistName: plistName, dylib: nextD, plist: nextP, version: "updated")
        let previous = (SHA256Digest.hex(firstD), SHA256Digest.hex(firstP), SHA256Digest.hex(firstM))
        let update = try executor.execute(pluginID: first.pluginID, dylibName: dylibName, plistName: plistName,
            dylib: nextD, plist: nextP, manifest: nextM, route: .update,
            expectedPrevious: (previous.0, previous.1, previous.2))
        try check130(update.route == "update", "update receipt route mismatch")
        try check130(try Data(contentsOf: base.appendingPathComponent(dylibName)) == nextD, "updated dylib bytes mismatch")

        let crashD = Data("crash-dylib".utf8), crashP = try PropertyListSerialization.data(fromPropertyList: ["Filter": ["Bundles": ["com.crash"]]], format: .xml, options: 0)
        let crashM = try manifest130(pluginID: pluginID, dylibName: dylibName, plistName: plistName, dylib: crashD, plist: crashP, version: "crash")
        let preCommitPhases: [HelperThreeFileTransactionExecutor.Phase] = [.prepared, .backingUp, .installingDylib, .installingPlist, .installingManifest]
        for (index, phase) in preCommitPhases.enumerated() {
            let attemptedD = Data("crash-\(index)-dylib".utf8)
            let attemptedP = try PropertyListSerialization.data(fromPropertyList: ["Filter": ["Bundles": ["com.crash.\(index)"]]], format: .xml, options: 0)
            let attemptedM = try manifest130(pluginID: pluginID, dylibName: dylibName, plistName: plistName, dylib: attemptedD, plist: attemptedP, version: "crash-\(index)")
            do {
                _ = try executor.execute(pluginID: pluginID, dylibName: dylibName, plistName: plistName,
                    dylib: attemptedD, plist: attemptedP, manifest: attemptedM, route: .update,
                    expectedPrevious: (SHA256Digest.hex(nextD), SHA256Digest.hex(nextP), SHA256Digest.hex(nextM)),
                    simulateCrashAfter: phase)
                throw NSError(domain: "P1-30", code: 2, userInfo: [NSLocalizedDescriptionKey: "crash injection did not fire at \(phase)"])
            } catch HelperThreeFileTransactionExecutor.TransactionError.injectedCrash(phase) { }
            try check130(try executor.inspectPendingJournal(), "startup probe missed pending journal at \(phase)")
            try check130(try executor.reconcile(), "crash recovery did not report recovered at \(phase)")
            try check130(try Data(contentsOf: base.appendingPathComponent(dylibName)) == nextD, "rollback failed to restore dylib at \(phase)")
            try check130(try Data(contentsOf: base.appendingPathComponent(plistName)) == nextP, "rollback failed to restore plist at \(phase)")
            try check130(try Data(contentsOf: base.appendingPathComponent(manifestName)) == nextM, "rollback failed to restore manifest at \(phase)")
            try check130(try !executor.reconcile(), "recovery is not idempotent at \(phase)")
        }

        do {
            _ = try executor.execute(pluginID: first.pluginID, dylibName: dylibName, plistName: plistName,
                dylib: crashD, plist: crashP, manifest: crashM, route: .update,
                expectedPrevious: (SHA256Digest.hex(nextD), SHA256Digest.hex(nextP), SHA256Digest.hex(nextM)),
                simulateCrashAfter: .installingManifest)
            throw NSError(domain: "P1-30", code: 2, userInfo: [NSLocalizedDescriptionKey: "crash injection did not fire"])
        } catch HelperThreeFileTransactionExecutor.TransactionError.injectedCrash(.installingManifest) { }
        try check130(try executor.reconcile(), "crash recovery did not report recovered")
        try check130(try Data(contentsOf: base.appendingPathComponent(dylibName)) == nextD, "rollback failed to restore dylib")
        try check130(try Data(contentsOf: base.appendingPathComponent(plistName)) == nextP, "rollback failed to restore plist")
        try check130(try Data(contentsOf: base.appendingPathComponent(manifestName)) == nextM, "rollback failed to restore manifest")
        try check130(try !executor.reconcile(), "recovery is not idempotent")

        do {
            _ = try executor.execute(pluginID: first.pluginID, dylibName: dylibName, plistName: plistName,
                dylib: crashD, plist: crashP, manifest: crashM, route: .update,
                expectedPrevious: (SHA256Digest.hex(nextD), SHA256Digest.hex(nextP), SHA256Digest.hex(nextM)),
                simulateCrashAfter: .committed)
            throw NSError(domain: "P1-30", code: 3, userInfo: [NSLocalizedDescriptionKey: "committed crash injection did not fire"])
        } catch HelperThreeFileTransactionExecutor.TransactionError.injectedCrash(.committed) { }
        try check130(try executor.reconcile(), "committed recovery did not finalize")
        try check130(try Data(contentsOf: base.appendingPathComponent(dylibName)) == crashD, "committed recovery lost dylib")
        try check130(try Data(contentsOf: base.appendingPathComponent(plistName)) == crashP, "committed recovery lost plist")
        try check130(try Data(contentsOf: base.appendingPathComponent(manifestName)) == crashM, "committed recovery lost manifest")
        try check130(try !executor.reconcile(), "committed recovery is not idempotent")

        let firstCrashDirectory = base.appendingPathComponent("FirstInstallCrash", isDirectory: true)
        try fm.createDirectory(at: firstCrashDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let firstCrashExecutor = try HelperThreeFileTransactionExecutor(directoryPath: firstCrashDirectory.path)
        do {
            _ = try firstCrashExecutor.execute(pluginID: pluginID, dylibName: dylibName, plistName: plistName,
                dylib: crashD, plist: crashP, manifest: crashM, route: .firstInstall,
                simulateCrashAfter: .installingManifest)
            throw NSError(domain: "P1-30", code: 4, userInfo: [NSLocalizedDescriptionKey: "first-install crash injection did not fire"])
        } catch HelperThreeFileTransactionExecutor.TransactionError.injectedCrash(.installingManifest) { }
        try check130(try firstCrashExecutor.inspectPendingJournal(), "first-install pending journal not detected")
        try check130(try firstCrashExecutor.reconcile(), "first-install rollback did not run")
        try check130(!fm.fileExists(atPath: firstCrashDirectory.appendingPathComponent(dylibName).path) &&
            !fm.fileExists(atPath: firstCrashDirectory.appendingPathComponent(plistName).path) &&
            !fm.fileExists(atPath: firstCrashDirectory.appendingPathComponent(manifestName).path), "first-install rollback left partial files")

        // P1-31: startup inspection remains read-only; explicit recovery is a separate root-only action.
        let coordinatorDirectory = base.appendingPathComponent("AuthorizedRecovery", isDirectory: true)
        try fm.createDirectory(at: coordinatorDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let coordinatorExecutor = try HelperThreeFileTransactionExecutor(directoryPath: coordinatorDirectory.path)
        do {
            _ = try coordinatorExecutor.execute(pluginID: pluginID, dylibName: dylibName, plistName: plistName,
                dylib: crashD, plist: crashP, manifest: crashM, route: .firstInstall,
                simulateCrashAfter: .installingDylib)
            throw NSError(domain: "P1-31", code: 10, userInfo: [NSLocalizedDescriptionKey: "recovery crash injection did not fire"])
        } catch HelperThreeFileTransactionExecutor.TransactionError.injectedCrash(.installingDylib) { }
        let startup = HelperStartupRecoveryCheck()
        try check130(startup.inspectDetailed(pluginDirectory: coordinatorDirectory.path) == .threeFileRecoveryRequired,
                     "startup detail did not classify three-file journal")
        try check130(startup.inspect(pluginDirectory: coordinatorDirectory.path) == .recoveryRequired,
                     "startup compatibility result did not block pending journal")
        try check130(try HelperAuthorizedRecoveryCoordinator().reconcileThreeFileTransaction(pluginDirectory: coordinatorDirectory.path),
                     "explicit recovery coordinator did not recover pending journal")
        try check130(startup.inspectDetailed(pluginDirectory: coordinatorDirectory.path) == .clean,
                     "startup inspection did not return clean after explicit recovery")

        // A symlink substituted for a transaction-owned destination must never be followed or removed.
        let hostileDirectory = base.appendingPathComponent("SymlinkRecovery", isDirectory: true)
        try fm.createDirectory(at: hostileDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let hostileExecutor = try HelperThreeFileTransactionExecutor(directoryPath: hostileDirectory.path)
        let outside = base.appendingPathComponent("outside-payload")
        try Data("outside sentinel".utf8).write(to: outside)
        do {
            _ = try hostileExecutor.execute(pluginID: pluginID, dylibName: dylibName, plistName: plistName,
                dylib: crashD, plist: crashP, manifest: crashM, route: .firstInstall,
                simulateCrashAfter: .installingPlist)
            throw NSError(domain: "P1-31", code: 11, userInfo: [NSLocalizedDescriptionKey: "symlink crash injection did not fire"])
        } catch HelperThreeFileTransactionExecutor.TransactionError.injectedCrash(.installingPlist) { }
        try fm.removeItem(at: hostileDirectory.appendingPathComponent(dylibName))
        try fm.createSymbolicLink(at: hostileDirectory.appendingPathComponent(dylibName), withDestinationURL: outside)
        do {
            _ = try hostileExecutor.reconcile()
            throw NSError(domain: "P1-31", code: 12, userInfo: [NSLocalizedDescriptionKey: "recovery followed a substituted symlink"])
        } catch HelperThreeFileTransactionExecutor.TransactionError.unsafeFile { }
        try check130(try Data(contentsOf: outside) == Data("outside sentinel".utf8), "symlink target was modified")
        try check130(try hostileExecutor.inspectPendingJournal(), "unsafe recovery discarded its journal")

        // A group/world-writable transaction file is not eligible for recovery.
        let modeDirectory = base.appendingPathComponent("UnsafeModeRecovery", isDirectory: true)
        try fm.createDirectory(at: modeDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let modeExecutor = try HelperThreeFileTransactionExecutor(directoryPath: modeDirectory.path)
        do {
            _ = try modeExecutor.execute(pluginID: pluginID, dylibName: dylibName, plistName: plistName,
                dylib: crashD, plist: crashP, manifest: crashM, route: .firstInstall,
                simulateCrashAfter: .installingPlist)
            throw NSError(domain: "P1-31", code: 13, userInfo: [NSLocalizedDescriptionKey: "mode crash injection did not fire"])
        } catch HelperThreeFileTransactionExecutor.TransactionError.injectedCrash(.installingPlist) { }
        try fm.setAttributes([.posixPermissions: 0o666], ofItemAtPath: modeDirectory.appendingPathComponent(dylibName).path)
        do {
            _ = try modeExecutor.reconcile()
            throw NSError(domain: "P1-31", code: 14, userInfo: [NSLocalizedDescriptionKey: "recovery accepted group/world-writable file"])
        } catch HelperThreeFileTransactionExecutor.TransactionError.unsafeFile { }
        try check130(try modeExecutor.inspectPendingJournal(), "unsafe-mode recovery discarded its journal")

        print("P1-31 recovery hardening smoke: PASS (read-only startup classification, explicit authorized recovery, symlink substitution refusal, writable-mode refusal, journal preservation)")
    }
}
