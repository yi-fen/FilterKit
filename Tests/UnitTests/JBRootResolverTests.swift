import XCTest
@testable import FilterKit

final class JBRootResolverTests: XCTestCase {
    private func makeRoot(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("usr/lib"),
                                                withIntermediateDirectories: true)
    }

    func testValidRootIsSelectedOnlyAfterRequiredStructureChecks() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = base.appendingPathComponent("jb")
        try makeRoot(at: root)
        defer { try? FileManager.default.removeItem(at: base) }

        let resolver = JBRootResolver(rootlessCandidates: [(root.path, .rootlessStandard)],
                                      rootHideContainer: base.appendingPathComponent("missing").path)
        let report = resolver.validate()
        XCTAssertEqual(report.validatedRootPath, root.standardizedFileURL.path)
        XCTAssertEqual(report.environmentKind, .rootless)
        XCTAssertTrue(report.candidates.first?.isStructurallyValid == true)
        XCTAssertTrue(report.isReadOnly)
    }

    func testTwoDifferentValidRootsRemainAmbiguous() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = base.appendingPathComponent("one")
        let second = base.appendingPathComponent("two")
        try makeRoot(at: first)
        try makeRoot(at: second)
        defer { try? FileManager.default.removeItem(at: base) }

        let resolver = JBRootResolver(rootlessCandidates: [
            (first.path, .rootlessStandard), (second.path, .rootlessPrivateAlias)
        ], rootHideContainer: base.appendingPathComponent("missing").path)
        let report = resolver.validate()
        XCTAssertNil(report.validatedRootPath)
        XCTAssertEqual(report.environmentKind, .unknown)
        XCTAssertTrue(report.hasAmbiguousRoots)
    }

    func testSymlinkAliasesCollapseToOneCanonicalRoot() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let realRoot = base.appendingPathComponent("real")
        let alias = base.appendingPathComponent("alias")
        try makeRoot(at: realRoot)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: realRoot)
        defer { try? FileManager.default.removeItem(at: base) }

        let resolver = JBRootResolver(rootlessCandidates: [
            (realRoot.path, .rootlessStandard), (alias.path, .rootlessPrivateAlias)
        ], rootHideContainer: base.appendingPathComponent("missing").path)
        let report = resolver.validate()
        XCTAssertEqual(report.candidates.count, 1)
        XCTAssertEqual(report.validatedRootPath, realRoot.standardizedFileURL.path)
        XCTAssertEqual(report.environmentKind, .rootless)
    }

    func testCandidateWithoutRequiredDirectoriesIsRejected() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = base.appendingPathComponent("incomplete")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let resolver = JBRootResolver(rootlessCandidates: [(root.path, .rootlessStandard)],
                                      rootHideContainer: base.appendingPathComponent("missing").path)
        let report = resolver.validate()
        XCTAssertNil(report.validatedRootPath)
        XCTAssertFalse(report.candidates.first?.isStructurallyValid ?? true)
    }

    func testJBRootNameFormatRejectsMalformedAndZeroNames() {
        XCTAssertTrue(JBRootResolver.isJBRootDirectoryName(".jbroot-1234567890ABCDEF"))
        XCTAssertFalse(JBRootResolver.isJBRootDirectoryName(".jbroot-0000000000000000"))
        XCTAssertFalse(JBRootResolver.isJBRootDirectoryName(".jbroot-1234"))
        XCTAssertFalse(JBRootResolver.isJBRootDirectoryName(".jbroot-1234567890ABCDEG"))
        XCTAssertFalse(JBRootResolver.isJBRootDirectoryName("not-jbroot-1234567890ABCDEF"))
    }

    func testDifferentCanonicalRootsAreNotSelectedEvenWhenAPIWouldBePresent() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = base.appendingPathComponent("one")
        let second = base.appendingPathComponent("two")
        try makeRoot(at: first)
        try makeRoot(at: second)
        defer { try? FileManager.default.removeItem(at: base) }
        let resolver = JBRootResolver(rootlessCandidates: [
            (first.path, .rootlessStandard), (second.path, .rootlessPrivateAlias)
        ], rootHideContainer: base.appendingPathComponent("missing").path)
        let report = resolver.validate()
        XCTAssertNil(report.validatedRootPath)
        XCTAssertEqual(report.environmentKind, .unknown)
        XCTAssertTrue(report.warnings.contains("environment.root.ambiguous"))
    }

}
