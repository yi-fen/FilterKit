//
//  DiagnosticPluginRepository.swift
//  FilterKit 0.1-E1 Plugin Data Foundation（E1-04 诊断实现）
//
//  包一层 ReadOnlyDiagnosticsEngine：refresh() 扫描一次并经 PluginDataMapper
//  产出快照缓存；其余读取接口全部命中缓存，不触发二次独立扫描。
//  本轮为只读实现：不暴露启用 / 禁用 / 配置写入等任何操作接口。
//

import Foundation

public final class DiagnosticPluginRepository: PluginRepository {
    private let engine: ReadOnlyDiagnosticsEngine
    private var cached: PluginSnapshot?

    /// 测试接缝：累计 refresh 触发的扫描次数，供离线测试断言「一次扫描」。
    public private(set) var refreshCount: Int = 0

    public init(engine: ReadOnlyDiagnosticsEngine) {
        self.engine = engine
    }

    public func currentSnapshot() -> PluginSnapshot? {
        cached
    }

    @discardableResult
    public func refresh() -> PluginSnapshot {
        let report = engine.scan()
        let snapshot = PluginDataMapper.mapSnapshot(report: report)
        cached = snapshot
        refreshCount += 1
        return snapshot
    }

    public func plugin(id: String) -> FKPlugin? {
        cached?.pluginByID[id]
    }

    public func applications() -> [FKApplication] {
        cached?.applications ?? []
    }
}
