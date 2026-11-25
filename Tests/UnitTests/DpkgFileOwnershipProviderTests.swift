import XCTest
@testable import FilterKit

final class DpkgFileOwnershipProviderTests: XCTestCase {
    func testExactDpkgListPathIsPackageManagerOwned() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dpkg = root.appendingPathComponent("var/lib/dpkg", isDirectory: true)
        let info = dpkg.appendingPathComponent("info", isDirectory: true)
        try FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
        let plugin = root.appendingPathComponent("usr/lib/TweakInject/Other.dylib")
        try FileManager.default.createDirectory(at: plugin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: plugin)
        try "Package: com.example.tweak\nStatus: install ok installed\nVersion: 1.2\n\n".write(to: dpkg.appendingPathComponent("status"), atomically: true, encoding: .utf8)
        try "\(plugin.path)\n".write(to: info.appendingPathComponent("com.example.tweak.list"), atomically: true, encoding: .utf8)
        let evidence = try DpkgFileOwnershipProvider(jbroot: root.path).ownershipEvidence(for: plugin)
        XCTAssertTrue(evidence.isOwnedByPackage)
        XCTAssertEqual(evidence.packageIdentifier, "com.example.tweak")
        XCTAssertEqual(evidence.packageVersion, "1.2")
    }

    func testLogicalRootlessListPathMatchesPhysicalJBRootFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dpkg = root.appendingPathComponent("var/lib/dpkg", isDirectory: true)
        let info = dpkg.appendingPathComponent("info", isDirectory: true)
        try FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
        let plugin = root.appendingPathComponent("usr/lib/TweakInject/Rootless.dylib")
        try FileManager.default.createDirectory(at: plugin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: plugin)
        try "Package: org.example.rootless\nStatus: install ok installed\nVersion: 3.4\n\n".write(to: dpkg.appendingPathComponent("status"), atomically: true, encoding: .utf8)
        // dpkg .list stores the logical path, while the file is physically below JBROOT.
        try "/usr/lib/TweakInject/Rootless.dylib\n".write(to: info.appendingPathComponent("org.example.rootless.list"), atomically: true, encoding: .utf8)
        let evidence = try DpkgFileOwnershipProvider(jbroot: root.path).ownershipEvidence(for: plugin)
        XCTAssertTrue(evidence.isOwnedByPackage)
        XCTAssertEqual(evidence.packageIdentifier, "org.example.rootless")
        XCTAssertEqual(evidence.packageVersion, "3.4")
    }

    func testUnownedFileIsNotMisclassifiedAsFilterKit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dpkg = root.appendingPathComponent("var/lib/dpkg", isDirectory: true)
        try FileManager.default.createDirectory(at: dpkg, withIntermediateDirectories: true)
        try "Package: another.package\nStatus: install ok installed\n\n".write(to: dpkg.appendingPathComponent("status"), atomically: true, encoding: .utf8)
        let file = root.appendingPathComponent("Manual.dylib")
        try Data([1]).write(to: file)
        let evidence = try DpkgFileOwnershipProvider(jbroot: root.path).ownershipEvidence(for: file)
        XCTAssertFalse(evidence.isOwnedByPackage)
        XCTAssertEqual(evidence.evidenceSource, "dpkg-status-readable-no-file-owner")
    }
}
