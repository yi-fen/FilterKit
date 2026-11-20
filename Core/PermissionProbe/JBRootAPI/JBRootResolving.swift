//
//  JBRootResolving.swift
//  FilterKit Core — PermissionProbe jbroot() API 接缝（Stage 2.4-D6）
//
//  RootHide `jbroot()` 的函数声明、返回类型、所属库/符号导出方式、App 链接或
//  运行时解析方式、头文件/弱链接需求、GUI 进程调用安全性均尚未核实。本接缝
//  只定义快照与协议；未核实前使用占位实现，结果落 unavailable/unknown。
//  禁止在未核实前写入虚构 C 函数声明、弱链接或 dlsym 符号名。
//

import Foundation
import Models

/// jbroot() API 四层证据快照（只读事实位）。
public struct JBRootAPISnapshot: Equatable {
    /// 符号是否可解析/可用。
    public var symbolAvailable: Bool
    /// 是否成功调用。
    public var invoked: Bool
    /// API 返回的路径；未调用或失败为 `nil`。
    public var resolvedPath: String?
    /// 不可用/失败原因；成功为 `nil`。
    public var errorReason: String?

    public init(symbolAvailable: Bool,
                invoked: Bool,
                resolvedPath: String? = nil,
                errorReason: String? = nil) {
        self.symbolAvailable = symbolAvailable
        self.invoked = invoked
        self.resolvedPath = resolvedPath
        self.errorReason = errorReason
    }
}

/// jbroot() 解析接缝（RootHide 专用；独立于 Adapter 七方法协议）。
public protocol JBRootResolving {
    func resolveJBRootViaAPI() -> JBRootAPISnapshot
}
