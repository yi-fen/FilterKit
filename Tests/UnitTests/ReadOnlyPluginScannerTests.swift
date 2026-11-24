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
        XCTAssertEqual(result.plugins.first(where: { $0.baseName == "Loose" })?.pairingState, .invalid)
        XCTAssertTrue(result.isReadOnly)
    }

    func testDoesNotScanWhenDirectoryIsAmbiguous() {
        let result = ReadOnlyPluginScanner().scan(assessment: PluginDirectoryAssessment(
            state: .ambiguous, selectedPath: nil, candidates: [], warnings: [], isReadOnly: true))
        XCTAssertNil(result.scannedDirectory)
        XCTAssertTrue(result.plugins.isEmpty)
        XCTAssertEqual(result.directoryState, .ambiguous)
    }

    func testManifestRequiresBothHashesAndExactNames() throws {
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
        XCTAssertEqual(item?.ownership, .filterKit)
        XCTAssertEqual(item?.hardBoundBundleIdentifier, "com.example.app")
        XCTAssertTrue(item?.managementPermission?.canModify == true)
        XCTAssertEqual(item?.filterConfiguration?.bundles, ["com.example.app"])
    }

    func testSHA256KnownVector() {
        XCTAssertEqual(SHA256Digest.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
