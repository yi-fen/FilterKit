//
//  FoundationFileAccessChecker.swift
//  FilterKit Core — PermissionProbe Foundation 文件访问实现（Stage 2.4-D2）
//
//  只读实现：stat 元数据、目录枚举、文件内容读取；不加载/执行 dylib，不做
//  路径猜测与软链改写。错误保留 NSError 域/码与 POSIX errno。
//

import Foundation

/// 基于 Foundation `FileManager` / `Data` 的只读访问实现。
public final class FoundationFileAccessChecker: FileAccessChecking {

    public init() {}

    public func inspect(_ url: URL) -> FileAccessResult {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let type = attrs[.type] as? FileAttributeType
            let isDirectory = type.map { $0 == .typeDirectory }
            let symlink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?
                .isSymbolicLink ?? nil
            return FileAccessResult(exists: true,
                                    isDirectory: isDirectory,
                                    isSymlink: symlink,
                                    readable: nil)
        } catch {
            let ns = error as NSError
            return FileAccessResult(
                exists: false,
                errorDomain: ns.domain,
                errorCode: ns.code,
                errno: Self.posixErrno(ns)
            )
        }
    }

    public func listDirectory(_ url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        )
    }

    public func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func posixErrno(_ ns: NSError) -> Int32? {
        guard ns.domain == NSPOSIXErrorDomain else { return nil }
        return Int32(ns.code)
    }
}
