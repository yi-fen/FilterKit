import XCTest
@testable import FilterKit

final class PluginZIPArchiveInspectorTests: XCTestCase {
    func testRejectsAbsolutePaths() {
        XCTAssertFalse(PluginZIPArchiveInspector.isSafeRelativePath("/tmp/evil.dylib"))
    }

    func testRejectsParentTraversal() {
        XCTAssertFalse(PluginZIPArchiveInspector.isSafeRelativePath("Payload/../../evil.dylib"))
        XCTAssertFalse(PluginZIPArchiveInspector.isSafeRelativePath("../evil.dylib"))
    }

    func testRejectsBackslashAndEmptyComponents() {
        XCTAssertFalse(PluginZIPArchiveInspector.isSafeRelativePath("Payload\\evil.dylib"))
        XCTAssertFalse(PluginZIPArchiveInspector.isSafeRelativePath("Payload//evil.dylib"))
    }

    func testAcceptsNestedRelativePath() {
        XCTAssertTrue(PluginZIPArchiveInspector.isSafeRelativePath("Payload/Plugins/Example.dylib"))
    }
}
