//
//  FilterKitUITestBase.swift
//  FilterKit UI 验收测试基座（C-F5）
//
//  仅驱动模拟器界面取证；不访问文件系统、不触发扫描、不读写越狱目录。
//  被测 App 由 UI 测试 target 依赖 FilterKit 自动构建安装。
//

import XCTest

class FilterKitUITestBase: XCTestCase {
    /// 被测 App 实例。
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    /// 按标识在任意元素类型中取首个匹配。
    func element(identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// 归档截图为测试附件（保留至产物打包阶段，归档时从 xcresult 提取）。
    func archiveScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 等待底部 Tab 按钮出现并点按。
    @discardableResult
    func openTab(_ title: String,
                 file: StaticString = #filePath,
                 line: UInt = #line) -> XCUIElement {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 5),
                       "Tab「\(title)」未出现", file: file, line: line)
        tab.tap()
        return tab
    }
}
