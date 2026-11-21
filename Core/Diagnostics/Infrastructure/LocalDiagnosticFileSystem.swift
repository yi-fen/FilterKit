//
//  LocalDiagnosticFileSystem.swift
//  FilterKit Stage 2.6 R3-A2 — 生产只读文件系统实现（D-R2-03）
//
//  包装注入的 Foundation `FileManager`；所有抛出错误经
//  `DiagnosticFileSystemError.map` 归类。本类不提供任何写入接口，
//  不做路径规范化、不触发解析、不缓存设备私有数据。
//

import Foundation

final class LocalDiagnosticFileSystem: DiagnosticFileSystem {

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    func isReadableFile(atPath path: String) -> Bool {
        fileManager.isReadableFile(atPath: path)
    }

    func readData(atPath path: String) throws -> Data {
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
        } catch {
            throw DiagnosticFileSystemError.map(error, path: path)
        }
    }

    func attributes(atPath path: String) throws -> [FileAttributeKey: Any] {
        do {
            return try fileManager.attributesOfItem(atPath: path)
        } catch {
            throw DiagnosticFileSystemError.map(error, path: path)
        }
    }

    func listDirectory(atPath path: String) throws -> [String] {
        do {
            return try fileManager.contentsOfDirectory(atPath: path)
        } catch {
            throw DiagnosticFileSystemError.map(error, path: path)
        }
    }
}

extension DiagnosticFileSystem {

    /// 目录类型判定：经 `attributes` 读取 `.type`；属性不可得时按非目录处理，
    /// 与既有 `try? attributesOfItem` 空态口径一致，不抛新异常类型。
    func isDirectory(atPath path: String) -> Bool {
        guard let attrs = try? attributes(atPath: path),
              let type = attrs[.type] as? FileAttributeType else { return false }
        return type == .typeDirectory
    }
}
