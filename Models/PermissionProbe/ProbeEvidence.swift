//
//  ProbeEvidence.swift
//  FilterKit Models — PermissionProbe（Stage 2.4-D1）
//
//  单条探针证据。可选字段缺省 nil：编码省略键，解码缺失键 / JSON null 均落 nil。
//  target 只记录检测目标摘要，不写入敏感设备信息或完整私有路径；observedValue
//  不回显完整文件内容。
//  规格：Spec/Stage-2/Stage-2.4-D1-PermissionProbe-Foundation-Spec.md §3.3。
//

import Foundation

/// 单条探针证据。
public struct ProbeEvidence: Codable, Equatable {
    /// 证据稳定标识（默认 UUID；服务层异常记录须保留原探针身份）。
    public var id: String
    /// 探针稳定标识（如 `DIRECTORY-ACCESS`、`DYLIB-METADATA`）。
    public var probeID: String
    /// 探针操作类型。
    public var operation: ProbeOperation
    /// 所属分类；D1 允许缺失，后续批次必填。
    public var category: ProbeCategory?
    /// 探针结论状态。
    public var status: ProbeStatus
    /// 实际检测目标（路径 / 符号名等摘要）。
    public var target: String?
    /// 观测到的可读摘要（条目数、大小等）。
    public var observedValue: String?
    /// 错误域（NSError.domain 映射）；无错误为 nil。
    public var errorDomain: String?
    /// 错误码（NSError.code 映射）；无错误为 nil。
    public var errorCode: Int?
    /// 执行时刻 ISO8601/RFC3339 字符串；未执行可为 nil。
    public var executedAt: String?

    public init(id: String = UUID().uuidString,
                probeID: String,
                operation: ProbeOperation = .inspect,
                category: ProbeCategory? = nil,
                status: ProbeStatus,
                target: String? = nil,
                observedValue: String? = nil,
                errorDomain: String? = nil,
                errorCode: Int? = nil,
                executedAt: String? = nil) {
        self.id = id
        self.probeID = probeID
        self.operation = operation
        self.category = category
        self.status = status
        self.target = target
        self.observedValue = observedValue
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.executedAt = executedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, probeID, operation, category, status, target, observedValue
        case errorDomain, errorCode, executedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        probeID = try c.decode(String.self, forKey: .probeID)
        operation = try c.decodeIfPresent(ProbeOperation.self, forKey: .operation) ?? .inspect
        category = try c.decodeIfPresent(ProbeCategory.self, forKey: .category)
        status = try c.decode(ProbeStatus.self, forKey: .status)
        target = try c.decodeIfPresent(String.self, forKey: .target)
        observedValue = try c.decodeIfPresent(String.self, forKey: .observedValue)
        errorDomain = try c.decodeIfPresent(String.self, forKey: .errorDomain)
        errorCode = try c.decodeIfPresent(Int.self, forKey: .errorCode)
        executedAt = try c.decodeIfPresent(String.self, forKey: .executedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(probeID, forKey: .probeID)
        try c.encode(operation, forKey: .operation)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(target, forKey: .target)
        try c.encodeIfPresent(observedValue, forKey: .observedValue)
        try c.encodeIfPresent(errorDomain, forKey: .errorDomain)
        try c.encodeIfPresent(errorCode, forKey: .errorCode)
        try c.encodeIfPresent(executedAt, forKey: .executedAt)
    }
}
