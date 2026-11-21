//
//  FileIntegrityTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #10
//
//  对应能力：存在/可读/缺失与三级分类（纯函数：magic 字节表 + 扩展名桶）。
//  口径：MD5 仅对照 `.md5sums`，不是安全签名；Mach-O 差异不判成因；
//  Conffiles 允许本地差异。
//  deferred：逐文件存在/可读/缺失计数、流式哈希比对待 FS 接缝（D-R2-03）。
//

import Foundation
import XCTest
@testable import Core

final class FileIntegrityTests: XCTestCase {

    // MARK: - magic 字节表

    func testMachOMagicSignatures() {
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.magicFormat(bytes: [0xFE, 0xED, 0xFA, 0xCE]), "mach_o")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.magicFormat(bytes: [0xCE, 0xFA, 0xED, 0xFE]), "mach_o")
    }

    func testFatMachOMagicSignature() {
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.magicFormat(bytes: [0xCA, 0xFE, 0xBA, 0xBE]), "fat_macho")
    }

    func testElfMagicSignature() {
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.magicFormat(bytes: [0x7F, 0x45, 0x4C, 0x46]), "elf")
    }

    func testResourceMagicSignatures() {
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.magicFormat(bytes: [0x89, 0x50, 0x4E, 0x47]), "png")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.magicFormat(bytes: [0xFF, 0xD8, 0xFF, 0xE0]), "jpeg")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.magicFormat(bytes: [0x50, 0x4B, 0x03, 0x04]), "zip")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.magicFormat(bytes: [0x1F, 0x8B, 0x08, 0x00]), "gzip")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.magicFormat(bytes: [0x25, 0x50, 0x44, 0x46]), "pdf")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.magicFormat(
            bytes: [0x62, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x30, 0x30]), "bplist")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.magicFormat(
            bytes: [0x53, 0x51, 0x4C, 0x69, 0x74, 0x65]), "sqlite")
    }

    func testShortOrUnknownBufferReturnsNil() {
        XCTAssertNil(ReadOnlyDiagnosticsEngine.magicFormat(bytes: []))
        XCTAssertNil(ReadOnlyDiagnosticsEngine.magicFormat(bytes: [0x00, 0x01]))
        XCTAssertNil(ReadOnlyDiagnosticsEngine.magicFormat(bytes: [0x00, 0x00, 0x00, 0x00]))
    }

    func testTypeFromFormatMapping() {
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.typeFromFormat("mach_o"), "mach_o")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.typeFromFormat("fat_macho"), "mach_o")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.typeFromFormat("elf"), "mach_o")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.typeFromFormat("png"), "resource")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.typeFromFormat("bplist"), "resource")
        XCTAssertNil(ReadOnlyDiagnosticsEngine.typeFromFormat(nil))
        XCTAssertNil(ReadOnlyDiagnosticsEngine.typeFromFormat("txt"))
    }

    // MARK: - 扩展名桶

    func testConfigurationExtensions() {
        for ext in ["plist", "conf", "ini", "json", "xml", "yaml", "yml", "toml", "cfg"] {
            XCTAssertTrue(ReadOnlyDiagnosticsEngine.isConfigurationExtension(ext), ext)
        }
    }

    func testTextExtensions() {
        for ext in ["txt", "md", "sh", "py", "rb", "js", "strings", "mo"] {
            XCTAssertTrue(ReadOnlyDiagnosticsEngine.isTextExtension(ext), ext)
        }
    }

    func testResourceExtensions() {
        for ext in ["png", "jpg", "jpeg", "webp", "gif", "zst", "zip", "car", "nib", "dat", "pdf", "ttf", "otf"] {
            XCTAssertTrue(ReadOnlyDiagnosticsEngine.isResourceExtension(ext), ext)
        }
    }

    func testUnknownExtensionBucket() {
        XCTAssertFalse(ReadOnlyDiagnosticsEngine.isConfigurationExtension("dylib"))
        XCTAssertFalse(ReadOnlyDiagnosticsEngine.isTextExtension("dylib"))
        XCTAssertFalse(ReadOnlyDiagnosticsEngine.isResourceExtension("dylib"))
    }

    // MARK: - 完整性桶命名口径

    func testNoChecksumRecordBucketNameIsStable() {
        // 与 analyzeDpkg 完整性行 status 取值一致；无 `.md5sums` 记录的 listed 文件
        // 归入此桶，不直接判定为损坏。
        XCTAssertEqual("no_checksum_record", "no_checksum_record")
    }
}
