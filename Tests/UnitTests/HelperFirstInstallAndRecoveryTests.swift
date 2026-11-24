import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import FilterKit

final class HelperFirstInstallAndRecoveryTests: XCTestCase {
    func testFirstInstallBootstrapRejectsUnauthenticatedPeerBeforeWriting() throws {
        guard geteuid() == 0 else { throw XCTSkip("Helper bootstrap is root-only") }
        let context = HelperAuthenticatedPeerContext(
            peer: HelperSocketPeerCredentials(uid: 501, gid: 501, pid: 42),
            identity: HelperPeerIdentity(uid: 501, gid: 501, pid: 42, cdHashHex: String(repeating: "a", count: 40), pidVersion: nil, auditSessionID: nil),
            sessionNonce: "nonce", authenticatedAt: Date())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let info = root.appendingPathComponent("info", isDirectory: true)
        try FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
        try Data("/some/other/file\n".utf8).write(to: info.appendingPathComponent("other.list"))
        defer { try? FileManager.default.removeItem(at: root) }
        let ownership = try HelperPackageOwnershipResolver().resolve(pluginDirectory: root.path,
            fileNames: ["Demo.dylib", "Demo.plist"], infoDirectories: [info.path])
        XCTAssertThrowsError(try HelperFirstInstallManifestBootstrap().createManifest(
            directoryPath: root.path, context: context, requestID: UUID(), pluginID: UUID(),
            dylibFileName: "Demo.dylib", plistFileName: "Demo.plist", hardBoundBundleIdentifier: "com.example.app",
            softAssociations: [], dylibBytes: Data([1]), plistBytes: Data("{}".utf8), packageOwnership: ownership))
    }

    func testRecoveryPlannerRequiresManualInterventionForForeignBytes() throws {
        let journal = try HelperTransactionJournal(transactionID: UUID(), pluginID: UUID(),
            dylibFileName: "Demo.dylib", plistFileName: "Demo.plist",
            dylibSHA256: String(repeating: "a", count: 64), plistSHA256: String(repeating: "b", count: 64),
            previousPlistSHA256: nil, phase: .installingDylib)
        let observed = HelperTransactionFileObservation(temporaryDylibHash: nil, temporaryPlistHash: nil,
            deployedDylibHash: String(repeating: "c", count: 64), deployedPlistHash: nil, previousPlistHash: nil)
        XCTAssertEqual(try HelperTransactionRecoveryPlanner().plan(journal: journal, observed: observed), [.manualIntervention])
    }

    func testStartupCheckTreatsMissingJournalAsClean() throws {
        guard geteuid() == 0 else { throw XCTSkip("Startup journal inspection requires Helper privileges") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(HelperStartupRecoveryCheck().inspect(pluginDirectory: root.path), .clean)
    }
}
