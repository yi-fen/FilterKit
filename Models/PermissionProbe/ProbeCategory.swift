//
//  ProbeCategory.swift
//  FilterKit Models — PermissionProbe（Stage 2.4-D1）
//
//  探针分类；路线专属规则不在此枚举内表达。
//  规格：Spec/Stage-2/Stage-2.4-D1-PermissionProbe-Foundation-Spec.md §3.2。
//

import Foundation

/// 探针分类。
public enum ProbeCategory: String, Codable, Equatable {
    /// 环境探针（D2）。
    case environment
    /// JBROOT 探针（D2）。
    case jbroot
    /// ElleKit / TweakInject 目录探针（D3）。
    case ellekit
    /// 插件文件探针（D4）。
    case pluginFiles = "plugin_files"
    /// 包管理数据库读取探针（D4）。
    case packageDatabase = "package_database"
    /// 签名 / entitlement 探针（D5）。
    case entitlement
    /// 沙盒探针（D5）。
    case sandbox
    /// jbroot() API 探针（D6）。
    case jbrootAPI = "jbroot_api"
}
