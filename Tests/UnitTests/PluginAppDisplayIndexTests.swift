import XCTest
@testable import FilterKit

final class PluginAppDisplayIndexTests: XCTestCase {
    func testBundleIdentifierLookupIsCaseInsensitiveAndFallsBackToIdentity() {
        let index = PluginAppDisplayIndex(apps: [
            InstalledApp(bundleIdentifier: "com.example.Reader", displayName: "Reader App",
                         systemClassification: .user, executableName: "Reader")
        ])
        XCTAssertEqual(index.appName(forBundleIdentifier: "COM.EXAMPLE.READER"), "Reader App")
        XCTAssertEqual(index.appName(forBundleIdentifier: "com.example.missing"), "com.example.missing")
    }

    func testExecutableLookupIsNormalizedAndEmptyDisplayNameFallsBackToBundleID() {
        let index = PluginAppDisplayIndex(apps: [
            InstalledApp(bundleIdentifier: "com.example.reader", displayName: " ",
                         systemClassification: .user, executableName: "Reader")
        ])
        XCTAssertEqual(index.namesByExecutable["reader"], "com.example.reader")
    }

    func testDisplayNamesAreDeduplicatedAndSortedDeterministically() {
        let index = PluginAppDisplayIndex(apps: [])
        XCTAssertEqual(index.sortedUniqueNames(["Zebra", "Alpha", "Alpha"]), ["Alpha", "Zebra"])
    }
}
