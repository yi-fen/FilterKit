# C-F5 三轮 Runner 复核记录（run `44474790149` / job `ui-acceptance`，新运行于 main `5ddd489`）

- 时间：2026-11-19 06:57:33Z ～ 07:05:50Z；Worker `{4008524b-983d-4b8f-a90d-564a68786bc7}`，westus，MacCloud；macOS 26.7.2（25G332），Xcode 26.6，iPhoneSimulator26.5.sdk；模拟器 iPhone 17 Pro `5AB3DACF-C352-49D1-BF9A-3C0104FA4ED3`，OS 26.2。
- 检出 SHA：**`5ddd489c01e90de563cc436268fd40e7ecd88ab7`**（首次在含 plist 修复的提交上新建运行；非旧 run 重跑）。
- 本附件仅含 `ui-acceptance` 单 job 日志。

## 用例执行结果（8 tests，3 failures，0 unexpected，211.198s）

| 用例 | 结论 | 耗时 | 说明 |
|---|---|---|---|
| EmptyStateTests.testExportDisabledWithoutEnvelope | ✅ passed | 38.460s | 空信封下导出入口禁用、无分享入口 |
| ExportFlowTests.testExportProducesShareLinkWithoutError | ✅ passed | 69.432s | 点 Export → 分享入口出现、无错误文案（G9 UI 链路） |
| NavigationFlowTests.testDashboardBaselineVisible | ❌ failed | 13.508s | `dashboard.count.total` 等待 3s 不存在（line 18 XCTAssertTrue） |
| NavigationFlowTests.testDiagnosticsSectionsVisible | ✅ passed | 23.069s | 诊断七组标识在位 |
| NavigationFlowTests.testPluginDetailOpensFromRow | ❌ failed | 20.748s | 首 Cell 点按后 Detail 未推入，`detail.plugin-id` 未出现（line 64） |
| NavigationFlowTests.testPluginsListSegmentsAndSearch | ❌ failed | 11.513s | Cell 计数 4 ≠ 3（line 34 XCTAssertEqual） |
| NavigationFlowTests.testSettingsVisible | ✅ passed | 15.096s | Settings 导出入口在位 |
| ShareSheetTests.testShareSheetOpensAfterExport | ✅ passed | 19.371s | Share Sheet 调起，附件 `share-sheet.png` 入 xcresult（G10 UI 取证） |

## 三处失败根因

1. **Dashboard 计数标识未暴露**：`dashboard.count.total/paired/missing/parse-failed` 标识挂在 `countCell` 的内层 VStack（嵌套于 HStack + 卡片内），未进入可匹配的 AX 元素；已改为挂到数值 `Text`（与 `detail.plugin-id` 同范式）。
2. **Detail 点到分段 Picker 行**：列表首个 Cell 是 `plugins.segment` 所在的 Picker 行，不是插件行；`app.cells.firstMatch.tap()` 点按它不触发推入。
3. **Cell 计数混入 Picker 行**：`app.cells.count` = 1（Picker 行）+ 3（插件行）= 4，与基线 3 不符。
   - 处置：测试改用 `identifier BEGINSWITH 'plugins.row.'` 谓词过滤插件行，计数与点按都只取行匹配。

## 链路缺口（本轮未取证）

- `Pull exported report from simulator container` 与 `Validate exported report round-trip` 两步**被跳过**：`Run UI acceptance tests` 退出 65 后，无 `if: always()` 的后续步骤不再执行。本轮未拉出容器 `tmp/` 导出 JSON，`ReportRoundtripValidator` 未运行，无 `roundtrip-result.json`。
- 处置：两步补 `if: always()`，保证无关导航用例失败时 G9 样本与往返结果仍归档；校验退出码语义不变（缺样本仍报错）。

## 产物

- Artifact `filterkit-ui-acceptance`，ID `14507250879`，18 文件目录、78266656 B；SHA256 `7e9c3ade50110d9804f755cb929d988449ff3c06690ab3b359b1ed0f454f255a`；下载页 `https://github.com/yi-fen/FilterKit/actions/runs/44474790149/artifacts/14507250879`。
- 本地归档：`job-logs.txt`（369K，2096 行，SHA256 `151f20c10a9d1c024d65f43b24f8a5d60783667ee63c45ece72167dbe5f2d45c`）。

## 门禁初判（待四轮复核）

- G8 导航：部分可达（Diagnostics / Settings / Plugins Tab 通过）；Dashboard 计数、Detail 推入、分段计数三项未取证。
- G9 导出：UI 链路通过；容器样本与往返解析未取证（步骤被跳过）。
- G10 分享：Share Sheet 调起通过，`share-sheet.png` 已入 xcresult；待产物解包核验截图本体。
- G1～G7 既有判定不变；0.1-C 不予闭环。
