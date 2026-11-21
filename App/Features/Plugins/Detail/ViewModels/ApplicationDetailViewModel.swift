//
//  ApplicationDetailViewModel.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer
//
//  只管理已投影好的 App 详情数据，不扫描、不接 Repository；关联证据为静态
//  匹配结果，不代表 App 运行时真的加载了对应插件。
//

import Foundation
import Core

@Observable
final class ApplicationDetailViewModel {

    private(set) var detail: ApplicationDetailEntry?
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    init(detail: ApplicationDetailEntry? = nil) {
        self.detail = detail
    }

    func setDetail(_ detail: ApplicationDetailEntry?) {
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
