//
//  DiagnosticFileSystemTests.swift
//  FilterKit Stage 2.6 R3-A6 — 只读 FS 接缝离线夹具测试（D-R2-03）
//
//  内存替身覆盖六类失败类别；验证权限拒绝 / 类型不符 / 不可用 / 未知错误
//  不被压缩成 notFound 或空列表。生产实现为 LocalDiagnosticFileSystem，
//  本机 Linux 无 Apple 工具链，FileManager 实际行为以 Runner 复测为准。
//

import Foundation
import XCTest
@testable import Core

/// 内存只读文件系统替身：文件 / 目录 / 失败注入三段隔离。
final class InMemoryDiagnosticFileSystem: DiagnosticFileSystem {
    private var files: [String: Data] = [:]
    private var directories: Set<String> = []
    private var failures: [String: DiagnosticFileSystemError] = [:]

    func addFile(path: String, data: Data) {
        files[path] = data
        directories.insert((path as NSString).deletingLastPathComponent)
    }

    func addDirectory(path: String) {
        directories.insert(path)
    }

    func setFailure(_ error: DiagnosticFileSystemError, path: String) {
        failures[path] = error
    }

    func fileExists(atPath path: String) -> Bool {
        failures[path] == nil && (files[path] != nil || directories.contains(path))
    }

    func isReadableFile(atPath path: String) -> Bool {
        failures[path] == nil && files[path] != nil
    }

    func readData(atPath path: String) throws -> Data {
        if let failure = failures[path] { throw failure }
        guard let data = files[path] else { throw DiagnosticFileSystemError.notFound(path: path) }
        return data
    }

    func attributes(atPath path: String) throws -> [FileAttributeKey: Any] {
        if let failure = failures[path] { throw failure }
        guard files[path] != nil || directories.contains(path) else {
            throw DiagnosticFileSystemError.notFound(path: path)
        }
        let type: FileAttributeType = directories.contains(path) ? .typeDirectory : .typeRegular
        return [.type: type, .size: NSNumber(value: files[path]?.count ?? 0)]
    }

    func listDirectory(atPath path: String) throws -> [String] {
        if let failure = failures[path] { throw failure }
        guard directories.contains(path) else {
            throw DiagnosticFileSystemError.typeMismatch(path: path, expected: "directory")
        }
        let prefix = path.hasSuffix("/") ? path : path + "/"
        return Set(files.keys + directories.keys)
            .filter { $0.hasPrefix(prefix) && $0 != path }
            .map { ($0 as NSString).lastPathComponent }
            .sorted()
    }
}

final class DiagnosticFileSystemTests: XCTestCase {

    private func makeFixture() -> InMemoryDiagnosticFileSystem {
        let fs = InMemoryDiagnosticFileSystem()
        fs.addDirectory(path: "/var/jb/Library/ElleKit/DynamicLibraries")
        fs.addFile(path: "/var/jb/Library/ElleKit/DynamicLibraries/filza.dylib",
                   data: Data([0xFE, 0xED, 0xFA, 0xCE]))
        fs.addFile(path: "/var/jb/etc/filter.plist", data: Data("<plist/>".utf8))
        return fs
    }

    func testExistingFileIsReadableAndReturnsData() throws {
        let fs = makeFixture()
        XCTAssertTrue(fs.fileExists(atPath: "/var/jb/etc/filter.plist"))
        XCTAssertTrue(fs.isReadableFile(atPath: "/var/jb/etc/filter.plist"))
        let data = try fs.readData(atPath: "/var/jb/etc/filter.plist")
        XCTAssertEqual(data, Data("<plist/>".utf8))
    }

    func testMissingFileThrowsNotFound() {
        let fs = makeFixture()
        XCTAssertFalse(fs.fileExists(atPath: "/var/jb/var/lib/dpkg/status"))
        XCTAssertThrowsError(try fs.readData(atPath: "/var/jb/var/lib/dpkg/status")) { error in
            guard case .notFound(let path) = error as? DiagnosticFileSystemError else {
                XCTFail("expected notFound, got \(error)")
                return
            }
            XCTAssertEqual(path, "/var/jb/var/lib/dpkg/status")
        }
    }

    func testPermissionDeniedIsNotMappedToNotFound() throws {
        let fs = makeFixture()
        fs.setFailure(.permissionDenied(path: "/var/jb/etc/filter.plist"), path: "/var/jb/etc/filter.plist")
        XCTAssertFalse(fs.isReadableFile(atPath: "/var/jb/etc/filter.plist"))
        XCTAssertThrowsError(try fs.readData(atPath: "/var/jb/etc/filter.plist")) { error in
            guard case .permissionDenied(let path) = error as? DiagnosticFileSystemError else {
                XCTFail("expected permissionDenied, got \(error)")
                return
            }
            XCTAssertEqual(path, "/var/jb/etc/filter.plist")
        }
    }

    func testTypeMismatchWhenListingAFileAsDirectory() {
        let fs = makeFixture()
        XCTAssertThrowsError(try fs.listDirectory(atPath: "/var/jb/etc/filter.plist")) { error in
            guard case .typeMismatch = error as? DiagnosticFileSystemError else {
                XCTFail("expected typeMismatch, got \(error)")
                return
            }
        }
    }

    func testUnavailableErrorPropagates() {
        let fs = makeFixture()
        fs.setFailure(.unavailable(path: "/var/jb", reason: "stale"), path: "/var/jb")
        XCTAssertThrowsError(try fs.listDirectory(atPath: "/var/jb")) { error in
            guard case .unavailable = error as? DiagnosticFileSystemError else {
                XCTFail("expected unavailable, got \(error)")
                return
            }
        }
    }

    func testUnknownErrorPropagates() {
        let fs = makeFixture()
        fs.setFailure(.unknown(path: "/var/jb", underlying: "weird"), path: "/var/jb")
        XCTAssertThrowsError(try fs.attributes(atPath: "/var/jb")) { error in
            guard case .unknown = error as? DiagnosticFileSystemError else {
                XCTFail("expected unknown, got \(error)")
                return
            }
        }
    }

    func testDirectoryListingReturnsSortedChildren() throws {
        let fs = makeFixture()
        let entries = try fs.listDirectory(atPath: "/var/jb/Library/ElleKit/DynamicLibraries")
        XCTAssertEqual(entries, ["filza.dylib"])
    }

    func testDpkgStatusMissingStaysMissingNotEmptyPackageList() {
        // 协议层缺失抛 notFound；纯文本解析空态口径由 DPKGStatusParserTests 覆盖，
        // 此处确认缺失不会被替身伪装成可读空文件。
        let fs = makeFixture()
        XCTAssertFalse(fs.isReadableFile(atPath: "/var/jb/var/lib/dpkg/status"))
        XCTAssertThrowsError(try fs.readData(atPath: "/var/jb/var/lib/dpkg/status"))
    }
}
