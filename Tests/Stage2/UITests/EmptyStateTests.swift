//
//  EmptyStateTests.swift
//  C-F5 P3：空信封复核（C-F3 §5 ST-6）
//
//  经启动参数注入无信封状态：导出入口应禁用并说明空态；不产生导出文件。
//

import XCTest

final class EmptyStateTests: FilterKitUITestBase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments.append("-FILTERKIT_PREVIEW_EMPTY")
        app.launch()
    }

    func testExportDisabledWithoutEnvelope() throws {
        openTab("Settings")

        let exportButton = element(identifier: "settings.exportButton")
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5), "导出入口应在位")
        XCTAssertFalse(exportButton.isEnabled, "无信封时导出入口应禁用")

        let shareLink = element(identifier: "settings.shareLink")
        XCTAssertFalse(shareLink.exists, "无信封时不应出现分享入口")
    }
}
