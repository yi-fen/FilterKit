import XCTest
@testable import FilterKit

final class ContainerDirectoryAppScannerTests: XCTestCase {
    func testDirectoryFallbackReadsBundleMetadataWithoutChangingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let container = root.appendingPathComponent("A1B2", isDirectory: true)
        let app = container.appendingPathComponent("Demo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.demo",
            "CFBundleDisplayName": "Demo Display",
            "CFBundleShortVersionString": "2.1",
            "CFBundleVersion": "42",
            "CFBundleExecutable": "Demo",
            "CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconName": "NestedAppIcon"]]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Info.plist"))

        let scanner = ContainerDirectoryAppScanner(rootURL: root)
        let apps = try scanner.scan()
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps[0].bundleIdentifier, "com.example.demo")
        XCTAssertEqual(apps[0].displayName, "Demo Display")
        XCTAssertEqual(apps[0].shortVersion, "2.1")
        XCTAssertEqual(apps[0].buildVersion, "42")
        XCTAssertEqual(apps[0].executableName, "Demo")
        XCTAssertEqual(apps[0].discoverySource, .directoryScan)
        XCTAssertEqual(apps[0].iconDescriptor?.assetName, "NestedAppIcon")
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Info.plist").path))
    }

    func testUnreadableOrMissingInventoryIsNotReturnedAsEmptyList() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try ContainerDirectoryAppScanner(rootURL: missing).scan())
    }
}
