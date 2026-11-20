//
//  ProbeStatusClassifier.swift
//  FilterKit Core — PermissionProbe 状态分类（Stage 2.4-D2）
//
//  底层文件错误 → 探针状态分类：不存在 = unavailable；明确拒绝 = permissionDenied；
//  其他 I/O 错误 = failed；无法得出可靠结论 = unknown。unavailable 与
//  permissionDenied 不合并；fileExists 为 false 不单独作为 unavailable 依据，
//  须结合错误域/码判断。
//

import Foundation
import Models

/// 探针状态纯函数分类接缝（测试可直接复用）。
public enum ProbeStatusClassifier {

    /// 依据 inspect 结果与错误信息分类。
    public static func classify(exists: Bool,
                                errorDomain: String?,
                                errorCode: Int?) -> ProbeStatus {
        guard let domain = errorDomain, let code = errorCode else {
            return exists ? .unknown : .unavailable
        }

        if domain == NSPOSIXErrorDomain,
           let posix = POSIXErrorCode(rawValue: Int32(code)) {
            switch posix {
            case .ENOENT, .ENOTDIR:
                return .unavailable
            case .EACCES, .EPERM:
                return .permissionDenied
            default:
                return .failed
            }
        }

        if domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: code) {
            case .fileNoSuchFile, .fileReadNoSuchFile:
                return .unavailable
            case .fileReadNoPermission:
                return .permissionDenied
            default:
                return .failed
            }
        }

        return exists ? .unknown : .unavailable
    }
}
