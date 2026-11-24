import XCTest
@testable import FilterKit

final class PluginDirectoryLocatorTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FilterKit-P1-04-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testSelectsSingleTweakInjectDirectory() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("usr/lib/TweakInject", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x01]).write(to: directory.appendingPathComponent("Example.dylib"))
        try Data([0x02]).write(to: directory.appendingPathComponent("Example.plist"))

        let result = PluginDirectoryLocator().inspect(jbroot: root.path, environment: .rootHide)
        XCTAssertEqual(result.state, .resolved)
        XCTAssertEqual(result.selectedPath, directory.resolvingSymlinksInPath().standardizedFileURL.path)
        XCTAssertEqual(result.candidates.first(where: { $0.kind == .tweakInject })?.dylibCount, 1)
        XCTAssertEqual(result.candidates.first(where: { $0.kind == .tweakInject })?.plistCount, 1)
        XCTAssertTrue(result.isReadOnly)
    }

    func testDistinctPluginDirectoriesRemainAmbiguous() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("usr/lib/TweakInject"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Library/MobileSubstrate/DynamicLibraries"), withIntermediateDirectories: true)

        let result = PluginDirectoryLocator().inspect(jbroot: root.path, environment: .rootless)
        XCTAssertEqual(result.state, .ambiguous)
        XCTAssertNil(result.selectedPath)
    }

    func testElleKitComponentDirectoryIsNeverSelectedAlone() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Library/TweakInject"), withIntermediateDirectories: true)

        let result = PluginDirectoryLocator().inspect(jbroot: root.path, environment: .rootHide)
        XCTAssertEqual(result.state, .unavailable)
        XCTAssertNil(result.selectedPath)
        XCTAssertTrue(result.warnings.contains("environment.plugin_directory.ellekit_component_separate"))
    }

    func testRecognizesElleKitDynamicLibrariesAsPluginCandidate() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Library/ElleKit/DynamicLibraries", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x01]).write(to: directory.appendingPathComponent("Example.dylib"))
        let result = PluginDirectoryLocator().inspect(jbroot: root.path, environment: .rootHide)
        XCTAssertEqual(result.state, .resolved)
        XCTAssertEqual(result.selectedPath, directory.resolvingSymlinksInPath().standardizedFileURL.path)
        XCTAssertEqual(result.candidates.first(where: { $0.kind == .elleKitDynamicLibraries })?.dylibCount, 1)
    }

    func testLowercaseMobileSubstrateDirectoryIsRecognized() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("library/MobileSubstrate/DynamicLibraries", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = PluginDirectoryLocator().inspect(jbroot: root.path, environment: .rootless)
        XCTAssertEqual(result.state, .resolved)
        XCTAssertEqual(result.selectedPath, directory.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    func testUnsupportedEnvironmentDoesNotProbePaths() {
        let result = PluginDirectoryLocator().inspect(jbroot: "/unused", environment: .unknown)
        XCTAssertEqual(result.state, .unavailable)
        XCTAssertTrue(result.candidates.isEmpty)
    }
}
