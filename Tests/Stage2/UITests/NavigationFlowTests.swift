//
//  NavigationFlowTests.swift
//  C-F5 P1：G8 五页面导航取证（C-F3 §2～§4 观察项）
//
//  覆盖 Dashboard / Plugins / Detail / Diagnostics / Settings 可达性、
//  分段筛选、列表推入详情；只读界面，无启停/编辑/写入入口。
//

import XCTest

final class NavigationFlowTests: FilterKitUITestBase {

    /// 仅匹配包含 `plugins.row.` 前缀标识主列文本的插件行 Cell；排除分段
    /// Picker 所在的列表行。行标识落在主列 StaticText 上、不挂在 Cell 本身，
    /// 故按“Cell 内含匹配标识的后代”取行，点按目标仍是链接行。
    private func pluginRowEntries() -> XCUIElementQuery {
        app.cells.containing(
            NSPredicate(format: "identifier BEGINSWITH 'plugins.row.'")
        )
    }

    // MARK: - Dashboard

    func testDashboardBaselineVisible() throws {
        XCTAssertTrue(app.navigationBars["FilterKit"].waitForExistence(timeout: 5),
                      "Dashboard 导航栏未出现")
        XCTAssertTrue(element(identifier: "dashboard.count.total").waitForExistence(timeout: 3))
        XCTAssertTrue(element(identifier: "dashboard.count.paired").exists)
        XCTAssertTrue(element(identifier: "dashboard.count.missing").exists)
        XCTAssertTrue(element(identifier: "dashboard.count.parse-failed").exists)
        archiveScreenshot(named: "dashboard.png")
    }

    // MARK: - Plugins 列表

    func testPluginsListSegmentsAndSearch() throws {
        openTab("Plugins")
        let list = element(identifier: "plugins.list")
        XCTAssertTrue(list.waitForExistence(timeout: 5), "Plugins 列表未出现")

        // ALL 段：合成基线 3 行（不含分段 Picker 行）。
        let allRows = pluginRowEntries().count
        XCTAssertEqual(allRows, 3, "ALL 段应显示 3 个插件")

        // PAIRED 段：2 行。
        app.segmentedControls.buttons["PAIRED"].tap()
        XCTAssertEqual(pluginRowEntries().count, 2, "PAIRED 段应显示 2 个插件")

        // ISSUES 段：异常项在位。
        app.segmentedControls.buttons["ISSUES"].tap()
        XCTAssertGreaterThanOrEqual(pluginRowEntries().count, 1, "ISSUES 段应至少 1 个异常项")

        // 回到 ALL；搜索命中关键词。
        app.segmentedControls.buttons["ALL"].tap()
        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 2) {
            // CI 模拟器上 `.searchable` 搜索框默认不是第一响应人；直接 typeText
            // 会报 “Neither element nor any descendant has keyboard focus”。
            // 先点按使其获得键盘焦点，再输入关键词。
            searchField.tap()
            searchField.typeText("Preview")
            XCTAssertGreaterThanOrEqual(pluginRowEntries().count, 1, "搜索「Preview」应命中")
        }

        archiveScreenshot(named: "plugins.png")
    }

    // MARK: - Detail 推入

    func testPluginDetailOpensFromRow() throws {
        openTab("Plugins")
        let firstRow = pluginRowEntries().firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()

        let pluginID = element(identifier: "detail.plugin-id")
        XCTAssertTrue(pluginID.waitForExistence(timeout: 5), "Detail 页未推入")

        let sectionIDs = [
            "detail.section.status",
            "detail.section.files",
            "detail.section.pairing",
            "detail.section.filter",
            "detail.section.ownership",
            "detail.section.evidence"
        ]
        for id in sectionIDs {
            XCTAssertTrue(element(identifier: id).waitForExistence(timeout: 2),
                          "Detail 分区 \(id) 缺失")
        }
        archiveScreenshot(named: "plugin-detail.png")
    }

    // MARK: - Diagnostics 七组

    func testDiagnosticsSectionsVisible() throws {
        openTab("Diagnostics")
        XCTAssertTrue(app.navigationBars["Diagnostics"].waitForExistence(timeout: 5))

        let sectionIDs = [
            "diagnostics.section.environment",
            "diagnostics.section.jbroot",
            "diagnostics.section.dynamic-libraries",
            "diagnostics.section.enumeration",
            "diagnostics.section.parsing",
            "diagnostics.section.warnings",
            "diagnostics.section.unknown-items"
        ]
        for id in sectionIDs {
            XCTAssertTrue(element(identifier: id).waitForExistence(timeout: 2),
                          "Diagnostics 分区 \(id) 缺失")
        }
        archiveScreenshot(named: "diagnostics.png")
    }

    // MARK: - Settings 导出前

    func testSettingsVisible() throws {
        openTab("Settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(identifier: "settings.exportButton").waitForExistence(timeout: 3))
        archiveScreenshot(named: "settings.png")
    }
}
