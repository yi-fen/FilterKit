//
//  PluginFeatureState.swift
//  FilterKit 0.1-E4 Plugin Feature Integration & Dependency
//
//  插件功能统一加载状态。五态严格区分：从未扫描（neverLoaded）≠ 扫描成功
//  零插件（empty）≠ 扫描失败（failed）；未知证据不强转失败或不存在。
//

import Foundation

/// 插件功能页面统一状态。
public enum PluginFeatureState: Equatable, Sendable {
    /// 尚未执行扫描（等待读取）。
    case neverLoaded
    /// 正在扫描。
    case loading
    /// 扫描成功，存在插件。
    case loaded
    /// 扫描成功，插件数为 0。
    case empty
    /// 扫描失败，且无可用旧数据。
    case failed(String)

    /// 是否处于扫描中。
    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// 失败提示；非 `.failed` 为 nil。
    public var errorMessage: String? {
        if case let .failed(message) = self { return message }
        return nil
    }

    /// 是否已经历过一次扫描终态（loaded / empty / failed）。
    public var hasLoaded: Bool {
        switch self {
        case .loaded, .empty, .failed:
            return true
        case .neverLoaded, .loading:
            return false
        }
    }
}
