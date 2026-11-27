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

    func testAssessmentCarriesDirectoryEntriesForScannerReuse() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("usr/lib/TweakInject", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x01]).write(to: directory.appendingPathComponent("CachedListing.dylib"))

        let result = PluginDirectoryLocator().inspect(jbroot: root.path, environment: .rootHide)
        let candidate = try XCTUnwrap(result.candidates.first(where: { $0.kind == .tweakInject }))
        XCTAssertEqual(candidate.entryNames, ["CachedListing.dylib"])
        XCTAssertEqual(candidate.dylibCount, 1)

        let before = PluginInventoryPerformanceDiagnostics.snapshot()
        let scan = ReadOnlyPluginScanner().scan(assessment: result)
        let after = PluginInventoryPerformanceDiagnostics.snapshot()
        XCTAssertEqual(scan.plugins.map(\.baseName), ["CachedListing"])
        XCTAssertEqual(after.directoryEnumerationCount, before.directoryEnumerationCount,
                       "Scanner must reuse the assessment listing, not enumerate the directory again")
        XCTAssertEqual(after.directoryListingReuseCount, before.directoryListingReuseCount + 1)
    }

    func testMultipleEmptyCompatibilityDirectoriesResolveDeterministically() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("usr/lib/TweakInject"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Library/MobileSubstrate/DynamicLibraries"), withIntermediateDirectories: true)

        let result = PluginDirectoryLocator().inspect(jbroot: root.path, environment: .rootless)
        XCTAssertEqual(result.state, .resolved)
        XCTAssertEqual(result.selectedPath, root.appendingPathComponent("Library/MobileSubstrate/DynamicLibraries").path)
    }

    func testPopulatedDirectoryWinsOverEmptyCompatibilityDirectory() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let populated = root.appendingPathComponent("usr/lib/TweakInject", isDirectory: true)
        try FileManager.default.createDirectory(at: populated, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Library/MobileSubstrate/DynamicLibraries"), withIntermediateDirectories: true)
        try Data([0x01]).write(to: populated.appendingPathComponent("RealPlugin.dylib"))

        let result = PluginDirectoryLocator().inspect(jbroot: root.path, environment: .rootless)
        XCTAssertEqual(result.state, .resolved)
        XCTAssertEqual(result.selectedPath, populated.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    func testTwoPopulatedDirectoriesRemainAmbiguous() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("usr/lib/TweakInject", isDirectory: true)
        let second = root.appendingPathComponent("Library/MobileSubstrate/DynamicLibraries", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try Data([0x01]).write(to: first.appendingPathComponent("A.dylib"))
        try Data([0x01]).write(to: second.appendingPathComponent("B.dylib"))

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

    func testElleKitComponentDirectoryIsNotEnumerated() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let component = root.appendingPathComponent("Library/TweakInject", isDirectory: true)
        try FileManager.default.createDirectory(at: component, withIntermediateDirectories: true)
        try Data([0x01]).write(to: component.appendingPathComponent("ElleKitComponent.dylib"))

        let before = PluginInventoryPerformanceDiagnostics.snapshot()
        let result = PluginDirectoryLocator().inspect(jbroot: root.path, environment: .rootHide)
        let after = PluginInventoryPerformanceDiagnostics.snapshot()
        let candidate = try XCTUnwrap(result.candidates.first(where: { $0.role == .elleKitComponentDirectory }))
        XCTAssertNil(candidate.entryNames)
        XCTAssertEqual(after.directoryEnumerationCount, before.directoryEnumerationCount,
                       "Diagnostic-only ElleKit component directory must not be enumerated")
        XCTAssertEqual(result.state, .unavailable)
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
