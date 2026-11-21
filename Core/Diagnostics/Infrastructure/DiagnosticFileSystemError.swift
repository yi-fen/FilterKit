//
//  DiagnosticFileSystemError.swift
//  FilterKit Stage 2.6 R3-A1 — 文件访问错误分类（D-R2-03）
//
//  访问失败必须保留类别，禁止合并为 notFound：
//  不可访问 ≠ 不存在；类型不符单独记录；系统异常标 unavailable；
//  未归类标 unknown。错误映射结合实际系统调用，不仅凭错误码推断路径状态。
//

import Foundation

enum DiagnosticFileSystemError: Error, Equatable {
    /// 路径不存在（ENOENT / 目录组件缺失）。
    case notFound(path: String)
    /// 存在但无读取/遍历权限（EACCES / EPERM）。不得回落为 notFound。
    case permissionDenied(path: String)
    /// 路径类型与操作不符（文件按目录列、目录按文件读等，ENOTDIR / EISDIR）。
    case typeMismatch(path: String, expected: String)
    /// 文件系统暂时不可用或设备异常（EIO / ENODEV / ESTALE 等）。
    case unavailable(path: String, reason: String?)
    /// 其他未归类系统错误，保留底层描述。
    case unknown(path: String, underlying: String)
}

extension DiagnosticFileSystemError {

    /// 将 Foundation/POSIX 错误映射为本协议类别。非 POSIX 域一律进 unknown，
    /// 不把权限拒绝或 IO 异常误判为 notFound。
    static func map(_ error: Error, path: String) -> DiagnosticFileSystemError {
        let nsError = error as NSError
        #if canImport(Darwin)
        guard nsError.domain == NSPOSIXErrorDomain else {
            return .unknown(path: path, underlying: error.localizedDescription)
        }
        switch nsError.code {
        case Int(ENOENT):
            return .notFound(path: path)
        case Int(EACCES), Int(EPERM):
            return .permissionDenied(path: path)
        case Int(ENOTDIR), Int(EISDIR):
            return .typeMismatch(path: path, expected: "file-or-directory-type-mismatch")
        case Int(EIO), Int(ENODEV), Int(ESTALE):
            return .unavailable(path: path, reason: error.localizedDescription)
        default:
            return .unknown(path: path, underlying: error.localizedDescription)
        }
        #else
        return .unknown(path: path, underlying: error.localizedDescription)
        #endif
    }
}
