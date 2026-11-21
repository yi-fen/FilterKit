//
//  PluginDetailViewModel.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer
//
//  只管理已投影好的详情数据，不扫描、不接 Repository；loaded 状态由 E1
//  原始证据提供，ViewModel 不设置 loaded = true/false。
//

import Foundation
import Core

@Observable
final class PluginDetailViewModel {

    private(set) var detail: PluginDetailEntry?
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    init(detail: PluginDetailEntry? = nil) {
        self.detail = detail
    }

    func setDetail(_ detail: PluginDetailEntry?) {
        self.detail = detail
        errorMessage = nil
    }

    func setLoading(_ value: Bool) {
        isLoading = value
    }

    func setError(_ message: String?) {
        errorMessage = message
    }
}
