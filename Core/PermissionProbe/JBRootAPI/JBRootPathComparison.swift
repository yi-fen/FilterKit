//
//  JBRootPathComparison.swift
//  FilterKit Core — PermissionProbe jbroot() 路径一致性分层比较（Stage 2.4-D6 / R2-B）
//
//  替换探针内原始字符串 `==` 比较：路径按四层取证——
//  1. raw：去首尾空白后的原始返回串；
//  2. normalized：词法规范化（`.` / `..`、重复斜杠、尾斜杠，`URL.standardizedFileURL`）；
//  3. symlink：软链解析（`URL.resolvingSymlinksInPath()`；路径不存在时仅作词法解析）；
//  4. accessible：经 `FileAccessChecking` 实测可达；无访问接缝时记 `nil`（unknown），
//     不填 `false` 冒充不可达结论。
//
//  边界：词法规范化不等于真实 inode / dev 文件身份验证；真实身份比对须真机 stat 取证，
//  留待 D2/D6 真机门禁。冻结 Models 与 resolver 协议不改动。
//

import Foundation

/// 路径一致性分层比较结果（只读事实位，Core 内部使用）。
public struct JBRootPathComparison: Equatable {
    /// 探针返回路径（去空白后）。
    public var returnedRaw: String?
    /// 已确认 JBROOT 路径（去空白后）。
    public var confirmedRaw: String?
    /// 规范化后的返回路径。
    public var returnedNormalized: String?
    /// 规范化后的确认路径。
    public var confirmedNormalized: String?
    /// 软链解析后的返回路径。
    public var returnedSymlinkResolved: String?
    /// 软链解析后的确认路径。
    public var confirmedSymlinkResolved: String?
    /// 原始串是否一致；任一路径缺失为 `nil`。
    public var rawMatch: Bool?
    /// 规范化后是否一致；任一路径缺失为 `nil`。
    public var normalizedMatch: Bool?
    /// 软链解析后是否一致；任一路径缺失为 `nil`。
    public var symlinkMatch: Bool?
    /// 两侧是否均实测可达；无访问接缝为 `nil`（unknown）。
    public var accessibleMatch: Bool?

    public init(returnedRaw: String? = nil,
                confirmedRaw: String? = nil,
                returnedNormalized: String? = nil,
                confirmedNormalized: String? = nil,
                returnedSymlinkResolved: String? = nil,
                confirmedSymlinkResolved: String? = nil,
                rawMatch: Bool? = nil,
                normalizedMatch: Bool? = nil,
                symlinkMatch: Bool? = nil,
                accessibleMatch: Bool? = nil) {
        self.returnedRaw = returnedRaw
        self.confirmedRaw = confirmedRaw
        self.returnedNormalized = returnedNormalized
        self.confirmedNormalized = confirmedNormalized
        self.returnedSymlinkResolved = returnedSymlinkResolved
        self.confirmedSymlinkResolved = confirmedSymlinkResolved
        self.rawMatch = rawMatch
        self.normalizedMatch = normalizedMatch
        self.symlinkMatch = symlinkMatch
        self.accessibleMatch = accessibleMatch
    }
}

/// 一致性判定结论。
public enum JBRootConsistencyVerdict: Equatable {
    case passed
    case failed
    case unknown
}

/// 路径规范化与一致性比较器（纯 Core 工具，不碰外部符号、不读写设备）。
public enum JBRootPathComparator {

    /// 去首尾空白；空串归一为 `nil`。
    public static func trimmed(_ path: String?) -> String? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return path
    }

    /// 词法规范化：`.` / `..`、重复斜杠、尾斜杠归一化。
    public static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// 软链解析（路径不存在时仅返回词法解析结果，不保证目标存在）。
    public static func symlinkResolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// 分层比较；`fileAccess` 为可选实测可达接缝，缺省时 accessible 层为 unknown。
    public static func compare(returned: String?,
                               confirmed: String?,
                               fileAccess: FileAccessChecking? = nil) -> JBRootPathComparison {
        let returnedRaw = trimmed(returned)
        let confirmedRaw = trimmed(confirmed)

        var comparison = JBRootPathComparison(
            returnedRaw: returnedRaw,
            confirmedRaw: confirmedRaw,
            returnedNormalized: returnedRaw.map(normalized),
            confirmedNormalized: confirmedRaw.map(normalized),
            returnedSymlinkResolved: returnedRaw.map(symlinkResolved),
            confirmedSymlinkResolved: confirmedRaw.map(symlinkResolved),
            rawMatch: nil,
            normalizedMatch: nil,
            symlinkMatch: nil,
            accessibleMatch: nil
        )

        if let returnedRaw, let confirmedRaw {
            comparison.rawMatch = returnedRaw == confirmedRaw
            comparison.normalizedMatch = normalized(returnedRaw) == normalized(confirmedRaw)
            comparison.symlinkMatch = symlinkResolved(returnedRaw) == symlinkResolved(confirmedRaw)
        }

        if let fileAccess, let returnedRaw, let confirmedRaw {
            let returnedExists = fileAccess.inspect(URL(fileURLWithPath: returnedRaw)).exists
            let confirmedExists = fileAccess.inspect(URL(fileURLWithPath: confirmedRaw)).exists
            comparison.accessibleMatch = returnedExists && confirmedExists
        }

        return comparison
    }

    /// 判定规则：规范化失配 → failed；规范化匹配且软链层失配 → failed；
    /// 规范化匹配且软链层未知或匹配 → passed；路径缺失 → unknown。
    public static func verdict(_ comparison: JBRootPathComparison) -> JBRootConsistencyVerdict {
        guard let normalizedMatch = comparison.normalizedMatch else { return .unknown }
        guard normalizedMatch else { return .failed }
        if let symlinkMatch = comparison.symlinkMatch, !symlinkMatch { return .failed }
        return .passed
    }

    /// 证据摘要（不回显完整私有路径，只记录各层布尔结论）。
    public static func summary(_ comparison: JBRootPathComparison) -> String {
        let raw = comparison.rawMatch.map { $0 ? "raw-match:true" : "raw-match:false" } ?? "raw-match:unknown"
        let normalized = comparison.normalizedMatch.map { $0 ? "normalized-match:true" : "normalized-match:false" } ?? "normalized-match:unknown"
        let symlink = comparison.symlinkMatch.map { $0 ? "symlink-match:true" : "symlink-match:false" } ?? "symlink-match:unknown"
        let accessible = comparison.accessibleMatch.map { $0 ? "accessible:true" : "accessible:false" } ?? "accessible:unknown"
        return "\(raw); \(normalized); \(symlink); \(accessible)"
    }
}
