//
//  PluginDataMapper.swift
//  FilterKit 0.1-E1 Plugin Data Foundation（E1-03 行 → 快照）
//
//  纯函数映射：FKDiagnosticReport 扁平化行 → PluginSnapshot。
//  不访问文件系统、不触发扫描、不写任何持久化；原始键值在 raw 中保留。
//  配对键取路径末段去扩展名，大小写不敏感归并（与引擎 buildAssociations 口径一致）。
//

import Foundation

public enum PluginDataMapper {

    public static func mapSnapshot(report: FKDiagnosticReport) -> PluginSnapshot {
        // MARK: 索引 filter 行
        var filtersByBase: [String: [String: String]] = [:]
        for row in report.filters {
            let key = baseKey(row["plist_path"] ?? row["plugin"])
            filtersByBase[key] = row
        }

        // MARK: 插件行
        var plugins: [FKPlugin] = []
        var basesByPluginID: [String: String] = [:]

        let pluginBases: Set<String> = Set(report.plugins.map {
            baseKey($0["path"] ?? $0["name"])
        })

        for row in report.plugins {
            let base = baseKey(row["path"] ?? row["name"])
            let filter = filtersByBase[base]
            let source = mapSource(row)
            let installed = mapInstalled(row)
            let configured = mapConfigured(filter)
            let configuration = filter.map { mapConfiguration($0, evidence: configured) }
            let status = FKPluginStatus(installed: installed, configured: configured, loaded: .unknown)
            let id = resolveID(packageIdentifier: source.packageIdentifier, base: base)
            basesByPluginID[id] = base

            plugins.append(FKPlugin(
                id: id,
                name: row["name"] ?? row["path"] ?? base,
                dylibPath: nonEmpty(row["path"]),
                plistPath: configuration?.filterPath,
                source: source,
                status: status,
                configuration: configuration,
                associations: [],
                fileSize: parseSize(row["size"]),
                version: nonEmpty(row["version"]),
                packageIdentifier: source.packageIdentifier,
                raw: row
            ))
        }

        // MARK: 孤立 plist（无插件行）：installed 证据缺失 → unknown
        for (base, filter) in filtersByBase where !pluginBases.contains(base) {
            let configured = mapConfigured(filter)
            let configuration = mapConfiguration(filter, evidence: configured)
            let status = FKPluginStatus(installed: .unknown, configured: configured, loaded: .unknown)
            let id = "filter:\(base)"
            basesByPluginID[id] = base

            plugins.append(FKPlugin(
                id: id,
                name: filter["plugin"] ?? base,
                dylibPath: nil,
                plistPath: configuration.filterPath,
                source: FKPluginSource(raw: "unknown", packageIdentifier: nil,
                                       packageOwners: [], exactPackageRecord: false, evidence: nil),
                status: status,
                configuration: configuration,
                associations: [],
                fileSize: nil,
                version: nil,
                packageIdentifier: nil,
                raw: filter
            ))
        }

        // MARK: 关联行
        var associationLookup: [String: String] = [:]
        for plugin in plugins {
            if let base = basesByPluginID[plugin.id] {
                associationLookup[base] = plugin.id
                associationLookup[plugin.name.lowercased()] = plugin.id
            }
        }

        let associations: [FKPluginAssociation] = report.associations.map { row in
            let label = row["plugin"] ?? ""
            let resolvedID = associationLookup[baseKey(label)]
                ?? associationLookup[label.lowercased()]
                ?? label
            let type = FKAssociationType.from(category: row["category"])
            return FKPluginAssociation(
                pluginID: resolvedID,
                appBundleID: nonEmpty(row["bundle_id"]),
                matchType: row["match_type"] ?? "none",
                type: type,
                isGlobal: row["is_global"] == "true",
                matchedAppCount: parseCount(row["matched_app_count"]),
                unmatchedTargetCount: parseCount(row["unmatched_target_count"]),
                evidence: row["evidence"] ?? "static_filter_match_only",
                loaded: row["loaded"] ?? "unknown"
            )
        }

        // 关联回挂插件（顺序赋值，避免重复键触发 trap）
        var pluginsByID: [String: FKPlugin] = [:]
        for plugin in plugins { pluginsByID[plugin.id] = plugin }
        var pluginIDsByApp: [String: [String]] = [:]
        for association in associations {
            pluginsByID[association.pluginID]?.associations.append(association)
            if let bundleID = association.appBundleID, !bundleID.isEmpty {
                pluginIDsByApp[bundleID, default: []].append(association.pluginID)
            }
        }

        // MARK: App 行
        let applications: [FKApplication] = report.applications.map { row in
            let bundleID = row["bundle_id"] ?? ""
            let associated = Array(Set(pluginIDsByApp[bundleID] ?? [])).sorted()
            return FKApplication(
                bundleID: bundleID,
                name: row["name"] ?? bundleID,
                version: nonEmpty(row["version"]),
                executable: nonEmpty(row["executable"]),
                isSystem: row["is_system"] == "true",
                associatedPluginIDs: associated
            )
        }

        let resolvedPlugins = Array(pluginsByID.values).sorted { $0.id < $1.id }
        var pluginByID: [String: FKPlugin] = [:]
        for plugin in resolvedPlugins { pluginByID[plugin.id] = plugin }
        var applicationByID: [String: FKApplication] = [:]
        for app in applications { applicationByID[app.bundleID] = app }

        return PluginSnapshot(
            generatedAt: report.generatedAt,
            environment: report.environment,
            plugins: resolvedPlugins,
            applications: applications,
            associations: associations,
            findings: report.findings,
            pluginByID: pluginByID,
            applicationByID: applicationByID
        )
    }

    // MARK: - 私有映射

    private static func mapInstalled(_ row: [String: String]) -> FKPluginState {
        if row["exists"] == "true" || row["readable"] == "true" { return .confirmed }
        if row["exists"] == "false" { return .absent }
        return .unknown
    }

    private static func mapConfigured(_ filter: [String: String]?) -> FKPluginState {
        guard let filter else { return .absent }
        return filter["valid"] == "true" ? .confirmed : .unverified
    }

    private static func mapConfiguration(_ filter: [String: String],
                                         evidence: FKPluginState) -> FKPluginConfiguration {
        FKPluginConfiguration(
            filterPath: nonEmpty(filter["plist_path"]),
            bundles: splitList(filter["bundles"]),
            executables: splitList(filter["executables"]),
            classes: splitList(filter["classes"]),
            otherKeys: splitList(filter["other_keys"]),
            isGlobalRule: filter["global"] == "true",
            parseStatus: nonEmpty(filter["parse_status"]),
            evidence: evidence
        )
    }

    private static func mapSource(_ row: [String: String]) -> FKPluginSource {
        let owners = splitList(row["package_owners"])
        return FKPluginSource(
            raw: row["source"] ?? "unknown",
            packageIdentifier: owners.first,
            packageOwners: owners,
            exactPackageRecord: row["exact_package_record"] == "true",
            evidence: nonEmpty(row["source_evidence"])
        )
    }

    private static func resolveID(packageIdentifier: String?, base: String) -> String {
        if let packageIdentifier, !packageIdentifier.isEmpty {
            return "\(packageIdentifier):\(base)"
        }
        return base
    }

    // MARK: - 解析工具

    private static func baseKey(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "" }
        let base = (path as NSString).lastPathComponent
        return (base as NSString).deletingPathExtension.lowercased()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func splitList(_ value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        return value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func parseSize(_ value: String?) -> Int64? {
        guard let value, let number = Int64(value.trimmingCharacters(in: .whitespaces)) else { return nil }
        return number
    }

    private static func parseCount(_ value: String?) -> Int {
        guard let value, let number = Int(value.trimmingCharacters(in: .whitespaces)) else { return 0 }
        return number
    }
}
