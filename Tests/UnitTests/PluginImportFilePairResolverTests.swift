import XCTest
@testable import FilterKit

final class PluginImportFilePairResolverTests: XCTestCase {
    func testAutomaticallyMatchesDylibSpecificSiblingPlist() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dylib = directory.appendingPathComponent("Example.dylib")
        let plist = directory.appendingPathComponent("Example.plist")
        try Data([0x01]).write(to: dylib)
        try Data([0x02]).write(to: plist)

        let resolved = try PluginImportFilePairResolver().resolve(dylibURL: dylib)
        XCTAssertEqual(resolved?.lastPathComponent, "Example.plist")
    }

    func testAutomaticallyMatchesConventionalFilterPlist() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dylib = directory.appendingPathComponent("Example.dylib")
        let plist = directory.appendingPathComponent("Filter.plist")
        try Data([0x01]).write(to: dylib)
        try Data([0x02]).write(to: plist)

        let resolved = try PluginImportFilePairResolver().resolve(dylibURL: dylib)
        XCTAssertEqual(resolved?.lastPathComponent, "Filter.plist")
    }

    func testNoMatchingPlistReturnsNilForAutoGenerationPath() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dylib = directory.appendingPathComponent("Example.dylib")
        try Data([0x01]).write(to: dylib)
        XCTAssertNil(try PluginImportFilePairResolver().resolve(dylibURL: dylib))
    }

    func testAmbiguousSiblingPlistsRequireExplicitSelection() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dylib = directory.appendingPathComponent("Example.dylib")
        try Data([0x01]).write(to: dylib)
        try Data([0x02]).write(to: directory.appendingPathComponent("Example.plist"))
        try Data([0x03]).write(to: directory.appendingPathComponent("Filter.plist"))
        XCTAssertThrowsError(try PluginImportFilePairResolver().resolve(dylibURL: dylib))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
