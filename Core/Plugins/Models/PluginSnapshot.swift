//
//  PluginSnapshot.swift
//  FilterKit 0.1-E1 Plugin Data Foundation（E1-05 统一快照）
//
//  一次扫描生成的统一只读视图：插件 / App / 关联 / findings 同属一份快照，
//  列表、详情与关联页后续消费同一份；一个页面刷新不得触发多次独立扫描。
//  快照不可变：Mapper 产出后由 Repository 缓存。
//

import Foundation

public struct PluginSnapshot: Equatable, Codable {
    public var generatedAt: Date
    public var environment: [String: String]
    public var plugins: [FKPlugin]
    public var applications: [FKApplication]
    public var associations: [FKPluginAssociation]
    public var findings: [FKDiagnosticFinding]
    public var pluginByID: [String: FKPlugin]
    public var applicationByID: [String: FKApplication]

    public init(generatedAt: Date, environment: [String: String],
                plugins: [FKPlugin], applications: [FKApplication],
                associations: [FKPluginAssociation],
                findings: [FKDiagnosticFinding],
                pluginByID: [String: FKPlugin],
                applicationByID: [String: FKApplication]) {
        self.generatedAt = generatedAt
        self.environment = environment
        self.plugins = plugins
        self.applications = applications
        self.associations = associations
        self.findings = findings
        self.pluginByID = pluginByID
        self.applicationByID = applicationByID
    }
}
