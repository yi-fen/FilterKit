//
//  FKPluginSource.swift
//  FilterKit 0.1-E1 Plugin Data Foundation（E1-01 来源模型）
//
//  归属信息保留全量证据，不在此层合并为单一来源；原始 source 值不做枚举收窄。
//

import Foundation

public struct FKPluginSource: Equatable, Codable {
    /// 引擎 `source` 原值（dpkg_sileo / filterkit / manual / unknown 等）。
    public var raw: String
    /// 归属包标识（首个 package_owners）。
    public var packageIdentifier: String?
    /// 全量归属包列表。
    public var packageOwners: [String]
    /// 是否存在精确包记录（exact_package_record）。
    public var exactPackageRecord: Bool
    /// 来源证据（source_evidence 原值）。
    public var evidence: String?

    public init(raw: String, packageIdentifier: String?, packageOwners: [String],
                exactPackageRecord: Bool, evidence: String?) {
        self.raw = raw
        self.packageIdentifier = packageIdentifier
        self.packageOwners = packageOwners
        self.exactPackageRecord = exactPackageRecord
        self.evidence = evidence
    }
}
