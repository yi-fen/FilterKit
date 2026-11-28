import XCTest
@testable import FilterKit

final class PluginDEBArchiveInspectorTests: XCTestCase {
    func testParsesDebianControlFieldsAndContinuationLines() {
        let control = """
        Package: com.example.plugin
        Version: 1.2.3
        Architecture: iphoneos-arm
        Maintainer: Example Author <author@example.com>
        Description: Example plugin
         second description line
        """
        let parsed = PluginDEBArchiveInspector.parseControl(control)
        XCTAssertEqual(parsed["Package"], "com.example.plugin")
        XCTAssertEqual(parsed["Version"], "1.2.3")
        XCTAssertEqual(parsed["Architecture"], "iphoneos-arm")
        XCTAssertEqual(parsed["Maintainer"], "Example Author <author@example.com>")
        XCTAssertEqual(parsed["Description"], "Example plugin\nsecond description line")
    }

    func testParsesDebianArContainerMembers() throws {
        func member(_ name: String, _ body: Data) -> Data {
            let nameField = String((name + "/").prefix(16)).padding(toLength: 16, withPad: " ", startingAt: 0)
            let date = "0".padding(toLength: 12, withPad: " ", startingAt: 0)
            let uid = "0".padding(toLength: 6, withPad: " ", startingAt: 0)
            let gid = "0".padding(toLength: 6, withPad: " ", startingAt: 0)
            let mode = "100644".padding(toLength: 8, withPad: " ", startingAt: 0)
            let size = String(body.count).padding(toLength: 10, withPad: " ", startingAt: 0)
            let header = nameField + date + uid + gid + mode + size + "`\n"
            var result = Data(header.utf8) + body
            if body.count % 2 == 1 { result.append(0x0A) }
            return result
        }
        let bytes = Data("!<arch>\n".utf8)
            + member("debian-binary", Data("2.0\n".utf8))
            + member("control.tar", Data(repeating: 0, count: 512))
        let parsed = try PluginDEBArchiveInspector.parseAr(bytes)
        XCTAssertEqual(parsed.map(\.name), ["debian-binary", "control.tar"])
        XCTAssertEqual(String(data: parsed[0].data, encoding: .ascii), "2.0\n")
    }

    func testRejectsInvalidArMagic() {
        XCTAssertThrowsError(try PluginDEBArchiveInspector.parseAr(Data("not a deb".utf8)))
    }

    func testRejectsUnsafeTarPaths() {
        XCTAssertFalse(PluginDEBArchiveInspector.isSafeRelativePath("/Library/evil.dylib"))
        XCTAssertFalse(PluginDEBArchiveInspector.isSafeRelativePath("../../evil.dylib"))
        XCTAssertFalse(PluginDEBArchiveInspector.isSafeRelativePath("Payload\\evil.dylib"))
        XCTAssertFalse(PluginDEBArchiveInspector.isSafeRelativePath("Payload//evil.dylib"))
        XCTAssertTrue(PluginDEBArchiveInspector.isSafeRelativePath("Library/MobileSubstrate/DynamicLibraries/Example.dylib"))
    }
}
