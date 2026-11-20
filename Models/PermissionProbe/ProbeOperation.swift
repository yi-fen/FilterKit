//
//  ProbeOperation.swift
//  FilterKit Models — PermissionProbe（Stage 2.4-D1）
//
//  探针操作类型：区分路径解析 / 元数据 / 目录枚举 / 内容读取 / 权限检查 /
//  API 调用。元数据可读 ≠ 内容可读 ≠ 格式可识别，不得互相替代。
//  规格：Spec/Stage-2/Stage-2.4-D1-PermissionProbe-Foundation-Spec.md §3.1。
//

import Foundation

/// 探针操作类型。
public enum ProbeOperation: String, Codable, Equatable {
    /// 路径解析（定位/推导）。
    case resolve
    /// 文件/目录元数据读取（stat/attributes）。
    case stat
    /// 目录枚举（list）。
    case list
    /// 文件内容读取（read）。
    case read
    /// 签名 / entitlement / 沙盒等权限检查（inspect）。
    case inspect
    /// 专有 API 调用（invoke，如 jbroot()）。
    case invoke
}
