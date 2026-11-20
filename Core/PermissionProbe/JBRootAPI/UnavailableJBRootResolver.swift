//
//  UnavailableJBRootResolver.swift
//  FilterKit Core — PermissionProbe jbroot() 占位实现（Stage 2.4-D6）
//
//  真实 API 未核实前的保守占位：不声明外部符号、不弱链接、不 dlsym、不调用。
//  真机接口核实后替换本实现；协议快照与探针证据模型保持不变。
//

import Foundation

/// jbroot() 占位解析器。
public struct UnavailableJBRootResolver: JBRootResolving {
    public let reason: String

    public init(reason: String = "jbroot() API signature/linking not verified") {
        self.reason = reason
    }

    public func resolveJBRootViaAPI() -> JBRootAPISnapshot {
        JBRootAPISnapshot(symbolAvailable: false, invoked: false, errorReason: reason)
    }
}
