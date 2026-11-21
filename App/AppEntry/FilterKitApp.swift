//
//  FilterKitApp.swift
//  FilterKit App 唯一入口（Stage 2.3 GUI Foundation 组合根）
//
//  职责：装配报告信封来源与导出接缝，挂载四页只读 Tab。本入口不调用 Adapter
//  扫描/读取方法，不实例化 Core 具体扫描器/解析器/Builder/Validator/Service；
//  0.1-C 使用静态合成信封做界面预览，真机快照接入属 0.1-D。
//

import SwiftUI
import Core

@main
struct FilterKitApp: App {
    private let dependencies: AppDependencies

    init() {
        // 启动参数 `-FILTERKIT_PREVIEW_EMPTY`：注入空信封用于空态/禁用态复核（C-F5 P3）；
        // 不触发扫描，不读取真实 JBROOT。默认走静态合成信封预览。
        let provider: ReportProviding
        if ProcessInfo.processInfo.arguments.contains("-FILTERKIT_PREVIEW_EMPTY") {
            provider = StaticReportProvider(envelope: nil)
        } else {
            provider = StaticReportProvider(
                envelope: SyntheticReportFactory.previewEnvelope()
            )
        }
        let diagnosticsStore = DiagnosticsReportStore()
        self.dependencies = AppDependencies(
            reportProvider: provider,
            exporter: ReportExporter(),
            diagnosticsStore: diagnosticsStore
        )
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(dependencies: dependencies)
        }
    }
}
