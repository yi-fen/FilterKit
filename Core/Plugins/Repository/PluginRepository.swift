//
//  PluginRepository.swift
//  FilterKit 0.1-E1 Plugin Data Foundation（E1-04 仓库协议）
//
//  管理器只读数据入口。页面不直接持有诊断引擎；Repository 内部缓存一次扫描的
//  统一快照，列表 / 详情 / 关联页消费同一份。本轮不定义任何写操作协议。
//
//  说明：备忘录模板标注 async throws；当前 ReadOnlyDiagnosticsEngine.scan()
//  为同步签名且不抛错，本协议按真实签名落地，后续批次再评估异步迁移。
//

import Foundation

public protocol PluginRepository {
    /// 当前缓存快照；尚未 refresh 时为 nil。
    func currentSnapshot() -> PluginSnapshot?

    /// 触发一次引擎扫描并重建快照；重复调用才会再次扫描。
    @discardableResult func refresh() -> PluginSnapshot

    /// 按标识取插件；读缓存，不二次扫描。
    func plugin(id: String) -> FKPlugin?

    /// 全部 App；读缓存，不二次扫描。
    func applications() -> [FKApplication]
}
