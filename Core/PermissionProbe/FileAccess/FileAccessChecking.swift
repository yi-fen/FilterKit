//
//  FileAccessChecking.swift
//  FilterKit Core — PermissionProbe 文件访问抽象（Stage 2.4-D2）
//
//  只读文件访问接缝：inspect 做元数据/类型检查，listDirectory 做目录枚举，
//  read 做内容读取；三者结果分开记录，元数据可读 ≠ 内容可读。错误分类保留
//  错误域/码/errno，不把单次 fileExists 失败直接等同于资源不存在。
//  规格：Spec/Stage-2/Stage-2.4-D1-PermissionProbe-Foundation-Spec.md（D2 批次）。
//

import Foundation
import Models

/// 文件/目录访问检查结果（只读事实位；`nil` = 未验证，不填 `false` 冒充结论）。
public struct FileAccessResult: Equatable {
    /// 目标是否存在（依据底层 stat/attributes 结果）。
    public var exists: Bool
    /// 是否为目录；未验证为 `nil`。
    public var isDirectory: Bool?
    /// 是否为符号链接；未验证为 `nil`。
    public var isSymlink: Bool?
    /// 是否可枚举/可读；未验证为 `nil`。
    public var readable: Bool?
    /// 错误域（NSError.domain 映射）；无错误为 `nil`。
    public var errorDomain: String?
    /// 错误码（NSError.code 映射）；无错误为 `nil`。
    public var errorCode: Int?
    /// POSIX errno；无错误为 `nil`。
    public var errno: Int32?

    public init(exists: Bool,
                isDirectory: Bool? = nil,
                isSymlink: Bool? = nil,
                readable: Bool? = nil,
                errorDomain: String? = nil,
                errorCode: Int? = nil,
                errno: Int32? = nil) {
        self.exists = exists
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.readable = readable
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.errno = errno
    }
}

/// 只读文件访问接缝（便于测试层替换桩；生产实现见 `FoundationFileAccessChecker`）。
public protocol FileAccessChecking {
    /// 元数据/类型检查（不枚举内容、不读取文件体）。
    func inspect(_ url: URL) -> FileAccessResult
    /// 枚举目录内容；失败抛错由调用方分类为探针证据。
    func listDirectory(_ url: URL) throws -> [URL]
    /// 读取文件全部内容；失败抛错由调用方分类。不加载/执行 dylib。
    func read(_ url: URL) throws -> Data
}
