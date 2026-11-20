//
//  ExportFlowTests.swift
//  C-F5 P2：G9 JSON 导出 UI 链路取证（C-F3 §5 ST-1～ST-4）
//
//  点按 Export → 经 ReportExporting 接缝落临时目录 → 分享入口出现、无错误文案。
//  导出 JSON 样本由工作流步骤从模拟器容器临时目录拉出，往返解析校验由
//  ReportRoundtripValidator 完成；本用例不读写越狱目录。
//

import XCTest

final class ExportFlowTests: FilterKitUITestBase {

    func testExportProducesShareLinkWithoutError() throws {
        openTab("Settings")

        let exportButton = element(identifier: "settings.exportButton")
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5), "导出入口未出现")
        XCTAssertTrue(exportButton.isEnabled, "合成信封在位时导出入口应可用")

        exportButton.tap()

        let shareLink = element(identifier: "settings.shareLink")
        XCTAssertTrue(shareLink.waitForExistence(timeout: 5),
                      "导出成功后未出现分享入口")

        let errorMessage = element(identifier: "settings.error")
        XCTAssertFalse(errorMessage.exists, "导出链路出现错误文案：\(errorMessage.label)")

        archiveScreenshot(named: "settings-exported.png")
    }
}
