//
//  ShareSheetTests.swift
//  C-F5 P3：G10 Share Sheet 调起取证（C-F3 §5 ST-5）
//
//  导出成功后点按 ShareLink，等待系统分享面板渲染并截图；不实际发送或上传。
//  无窗口 Runner 上面板渲染稳定性以首轮实测为准；断言失败按缺口如实记录，不硬判绿。
//

import XCTest

final class ShareSheetTests: FilterKitUITestBase {

    func testShareSheetOpensAfterExport() throws {
        openTab("Settings")

        let exportButton = element(identifier: "settings.exportButton")
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()

        let shareLink = element(identifier: "settings.shareLink")
        XCTAssertTrue(shareLink.waitForExistence(timeout: 5), "导出后分享入口未出现")
        shareLink.tap()

        // 系统分享面板在 XCUI 层级中通常为 sheet / 其他元素，标识或标签含 "Share"。
        let sheetPredicate = NSPredicate(format:
            "identifier CONTAINS[c] 'Share' OR label CONTAINS[c] 'Share'")
        let sheet = app.descendants(matching: .any).containing(sheetPredicate).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5),
                      "系统 Share Sheet 未调起")

        archiveScreenshot(named: "share-sheet.png")
    }
}
