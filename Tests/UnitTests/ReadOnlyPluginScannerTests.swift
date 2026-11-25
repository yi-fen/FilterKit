import XCTest
@testable import FilterKit

final class ReadOnlyPluginScannerTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func assessment(_ url: URL) -> PluginDirectoryAssessment {
        PluginDirectoryAssessment(state: .resolved, selectedPath: url.standardizedFileURL.path,
            candidates: [], warnings: [], isReadOnly: true)
    }

    func testScansExactStemPairAndLeavesOrphansVisible() throws {
        let dir = try makeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        try Data([0xcf, 0xfa, 0xed, 0xfe, 1, 2, 3, 4]).write(to: dir.appendingPathComponent("Good.dylib"))
        try PropertyListSerialization.data(fromPropertyList: ["Bundles": ["com.example.app"]], format: .xml, options: 0)
            .write(to: dir.appendingPathComponent("Good.plist"))
        try Data([0xcf, 0xfa, 0xed, 0xfe]).write(to: dir.appendingPathComponent("Orphan.dylib"))
        try Data("<?xml".utf8).write(to: dir.appendingPathComponent("Loose.plist"))
        let result = ReadOnlyPluginScanner().scan(assessment: assessment(dir))
        XCTAssertEqual(result.directoryState, .resolved)
        XCTAssertEqual(result.plugins.first(where: { $0.baseName == "Good" })?.pairingState, .paired)
        XCTAssertEqual(result.plugins.first(where: { $0.baseName == "Orphan" })?.pairingState, .orphanDylib)
        XCTAssertEqual(result.plugins.first(where: { $0.baseName == "Loose" })?.pairingState, .orphanPlist)
        XCTAssertTrue(result.plugins.first(where: { $0.baseName == "Loose" })?.warnings.contains("plugin_scan.plist_invalid_or_unreadable") == true)
        XCTAssertTrue(result.isReadOnly)
    }

    func testAmbiguousPopulatedDirectoriesAreAggregatedForReadOnlyInventory() throws {
        let first = try makeDirectory(); defer { try? FileManager.default.removeItem(at: first) }
        let second = try makeDirectory(); defer { try? FileManager.default.removeItem(at: second) }
        try Data([0xcf, 0xfa, 0xed, 0xfe, 1]).write(to: first.appendingPathComponent("First.dylib"))
        try PropertyListSerialization.data(fromPropertyList: ["Bundles": ["com.example.first"]], format: .xml, options: 0)
            .write(to: first.appendingPathComponent("First.plist"))
        try Data([0xcf, 0xfa, 0xed, 0xfe, 2]).write(to: second.appendingPathComponent("Second.dylib"))
        let candidates = [first, second].map { url in
            PluginDirectoryCandidate(path: url.path, canonicalPath: url.resolvingSymlinksInPath().standardizedFileURL.path,
                kind: .elleKitDynamicLibraries, role: .thirdPartyPluginDirectory,
                exists: true, isDirectory: true, isReadable: true, isEnumerable: true,
                isWritable: false, isSymbolicLink: false, dylibCount: 1, plistCount: 0,
                detailCode: "test")
        }
        let assessment = PluginDirectoryAssessment(state: .ambiguous, selectedPath: nil,
            candidates: candidates, warnings: [], isReadOnly: true)
        let result = ReadOnlyPluginScanner().scan(assessment: assessment)
        XCTAssertEqual(result.directoryState, .resolved)
        XCTAssertEqual(Set(result.plugins.map(\.baseName)), Set(["First", "Second"]))
        XCTAssertEqual(result.plugins.first(where: { $0.baseName == "First" })?.pairingState, .paired)
        XCTAssertEqual(result.plugins.first(where: { $0.baseName == "Second" })?.pairingState, .orphanDylib)
        XCTAssertEqual(result.scannedDirectory?.components(separatedBy: ";").count, 2)
    }

    func testNonMachODylibStillAppearsInFastInventory() throws {
        let dir = try makeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        try Data("not-yet-inspected".utf8).write(to: dir.appendingPathComponent("Visible.dylib"))
        let result = ReadOnlyPluginScanner().scan(assessment: assessment(dir))
        let item = result.plugins.first(where: { $0.baseName == "Visible" })
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.pairingState, .orphanDylib)
        XCTAssertNil(item?.binaryKind, "Binary inspection belongs to the detail path")
        XCTAssertFalse(item?.managementPermission?.canModify ?? false)
    }

    func testAmbiguousWithoutReadableCandidatesRemainsAmbiguous() {
        let result = ReadOnlyPluginScanner().scan(assessment: PluginDirectoryAssessment(
            state: .ambiguous, selectedPath: nil, candidates: [], warnings: [], isReadOnly: true))
        XCTAssertNil(result.scannedDirectory)
        XCTAssertTrue(result.plugins.isEmpty)
        XCTAssertEqual(result.directoryState, .ambiguous)
    }

    func testFastInventoryDefersManifestAndOwnershipVerification() throws {
        let dir = try makeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let dylib = Data([0xcf, 0xfa, 0xed, 0xfe, 1, 2, 3, 4])
        let plist = try PropertyListSerialization.data(fromPropertyList: ["Bundles": ["com.example.app"]], format: .xml, options: 0)
        try dylib.write(to: dir.appendingPathComponent("Owned.dylib")); try plist.write(to: dir.appendingPathComponent("Owned.plist"))
        let manifest: [String: Any] = ["schemaVersion": 1, "pluginID": UUID().uuidString,
            "dylibFileName": "Owned.dylib", "plistFileName": "Owned.plist",
            "dylibSHA256": SHA256Digest.hex(dylib), "plistSHA256": SHA256Digest.hex(plist),
            "hardBoundBundleIdentifier": "com.example.app", "softAssociatedBundleIdentifiers": []]
        let json = try JSONSerialization.data(withJSONObject: manifest)
        try json.write(to: dir.appendingPathComponent("Owned.fk.json"))
        let item = ReadOnlyPluginScanner().scan(assessment: assessment(dir)).plugins.first
        XCTAssertNotNil(item, "Fast inventory must keep the plugin visible")
        XCTAssertEqual(item?.ownership, .unknown, "Ownership verification is deferred from the fast inventory")
        XCTAssertNil(item?.hardBoundBundleIdentifier)
        XCTAssertFalse(item?.managementPermission?.canModify ?? false, "No management permission without detail verification")
        XCTAssertEqual(item?.filterConfiguration?.bundles, ["com.example.app"])
        XCTAssertNil(item?.dylibSHA256, "Fast inventory must not hash dylibs")
        XCTAssertTrue(item?.warnings.contains("plugin_scan.manifest_verification_deferred") == true)
    }

    func testSHA256KnownVector() {
        XCTAssertEqual(SHA256Digest.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
