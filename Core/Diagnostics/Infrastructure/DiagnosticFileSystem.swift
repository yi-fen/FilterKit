//
//  DiagnosticFileSystem.swift
//  FilterKit Stage 2.6 R3-A1 — 只读文件系统协议（D-R2-03）
//
//  诊断引擎对文件系统的唯一接缝。协议只暴露只读访问：不存在写入、删除、
//  移动、复制、属性修改或目录创建接口。便利布尔接口用于辅助判断；
//  需要区分失败原因的操作必须走 throws 接口，禁止把访问失败压缩成 false。
//
//  冻结边界：不改公共 Models / 报告信封 / Adapter 七方法协议 / Stage1 fixtures；
//  路径规范化沿用引擎既有纯函数，协议不做路径解析。
//

import Foundation

/// 只读诊断文件系统接缝。生产实现包装 Foundation `FileManager`；
/// 测试实现使用临时目录或内存替身注入失败类别。
protocol DiagnosticFileSystem {

    /// 路径是否存在（不区分目录/文件；目录类型以 `attributes` 的 `.type` 为准）。
    /// 仅作辅助判断，存在性证据不足以区分「不存在」与「不可访问」。
    func fileExists(atPath path: String) -> Bool

    /// 路径存在且当前进程可读。不可读不等于不存在，调用方须保留拒绝类别。
    func isReadableFile(atPath path: String) -> Bool

    /// 读取整个文件内容；失败抛 `DiagnosticFileSystemError`，不吞错为空数据。
    func readData(atPath path: String) throws -> Data

    /// 读取文件属性（类型/大小/权限位等）；失败抛 `DiagnosticFileSystemError`。
    func attributes(atPath path: String) throws -> [FileAttributeKey: Any]

    /// 列出目录直接子项名称（不递归、不跟随符号链接做二次解析）；
    /// 失败抛 `DiagnosticFileSystemError`，不回落为空列表。
    func listDirectory(atPath path: String) throws -> [String]
}
