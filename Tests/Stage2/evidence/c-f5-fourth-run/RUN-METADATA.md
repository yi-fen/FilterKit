# C-F5 四轮 Runner 复核记录（run `44490042909` / job `ui-acceptance`，新运行于 main `a23eaba`）

- 时间：2026-11-19 08:51:20Z ～ 09:01:50Z；Worker `{62356e00-f211-47b9-88a7-38cbfaa85b49}`；runner version 2.338.2；macOS 26.7.2（25G332），Xcode 26.6（`/Applications/Xcode_26.6.app`），iPhoneSimulator26.5.sdk；模拟器 iPhone 17 Pro `5AB3DACF-C352-49D1-BF9A-3C0104FA4ED3`，OS 26.2。
- 检出 SHA：**`a23eaba703e39a300eb0fb7efcc0414f9a9b5b32`**（forced-update 快照，对应本地三轮修复树；`git diff FETCH_HEAD` 对 App/Tests/工作流无源码差异，确认三轮三项修复已上 Runner）。
- 本附件仅含 `ui-acceptance` 单 job 日志；stdout 未内嵌 AX 层级快照文本，AX 实态需解包 xcresult/artifact 核验。

## 用例执行结果（8 tests，3 failures，0 unexpected，227.763s）

| 用例 | 结论 | 耗时 | 说明 |
|---|---|---|---|
| EmptyStateTests.testExportDisabledWithoutEnvelope | ✅ passed | 57.666s | 空信封下导出入口禁用、无分享入口 |
| ExportFlowTests.testExportProducesShareLinkWithoutError | ✅ passed | 66.441s | 点 Export → 分享入口出现、无错误文案（G9 UI 链路） |
| NavigationFlowTests.testDashboardBaselineVisible | ❌ failed | 14.687s | `dashboard.count.total` 等待 3s 不存在（`NavigationFlowTests.swift:25` XCTAssertTrue）；导航栏 "FilterKit" 7.24s 已出现 |
| NavigationFlowTests.testDiagnosticsSectionsVisible | ✅ passed | 22.427s | 诊断七组卡片标识在位 |
| NavigationFlowTests.testPluginDetailOpensFromRow | ❌ failed | 17.708s | 行 Cell 等待 5s 不存在，Detail 未推入，`detail.plugin-id` 未出现（`NavigationFlowTests.swift:67`） |
| NavigationFlowTests.testPluginsListSegmentsAndSearch | ❌ failed | 13.067s | `plugins.row.` 前缀谓词匹配 0 个 Cell，计数 0 ≠ 3（`NavigationFlowTests.swift:41` XCTAssertEqual） |
| NavigationFlowTests.testSettingsVisible | ✅ passed | 12.776s | Settings 导出入口在位 |
| ShareSheetTests.testShareSheetOpensAfterExport | ✅ passed | 22.991s | Share Sheet 调起，附件 `share-sheet.png` 入 xcresult（G10 UI 取证） |

## 三处失败根因（四轮复核定位）

三轮把计数标识从内层 VStack 移到数值 `Text`、把行选择器改为 `plugins.row.` 前缀谓词后，三处仍失败，说明问题不在“标识挂在哪一层视图”，而在 AX 暴露范式：

1. **卡片容器标识向下覆盖子级叶子标识**：`SectionCardView` 根 VStack 直接挂 `.accessibilityIdentifier(identifier ?? title)`。按 SwiftUI AX 语义，容器根标识会向下传播并覆盖后代叶子上的自有标识；`dashboard.count.*` 数值 Text 虽挂了标识，仍被 Plugins 卡片根标识覆盖，故不可匹配。诊断卡片只锚定根标识本身、不依赖子级叶子，所以通过。
   - 处置：卡片根先 `.accessibilityElement(children: .contain)` 再挂标识（顺序不可反），保留根锚点的同时让子级叶子保留自有标识。
2. **列表行标识落在 NavigationLink 容器上，不进入 Cell/StaticText 的 identifier**：`plugins.row.*` 挂在 `NavigationLink` 上，四轮实测 `.cell` 谓词匹配 0 个；行标识实际应落在主列 `Text(summary.name)`（StaticText）上。
   - 处置：标识从 NavigationLink 移到行名 Text；测试选择器改为“包含匹配标识后代的 Cell”（`app.cells.containing(identifier BEGINSWITH 'plugins.row.')`），计数与点按目标仍是链接行。
3. **Detail 未推入是 #2 的连带结果**：行 Cell 选不中 → 点按未触发链接 → Detail 页未到达，`detail.plugin-id` 无从断言。行选择修复后随链路复核。

## G9 链路缺口（本轮仍未取证）

- `Pull exported report from simulator container`：`xcodebuild test` 结束后模拟器被置为 **Shutdown**，`get_app_container` 报 `SimError 405: Unable to lookup in current state: Shutdown`，步骤 exit **149**；容器数据目录未查到，导出 JSON 未拉出。
- `Validate exported report round-trip`：缺样本，`缺少导出 JSON 样本，无法往返校验`，exit **1**；无 `roundtrip-result.json`。
- 处置：拉取步骤先 `xcrun simctl boot "$DEVICE_ID"`（已启动则 `|| true` 容错）再查容器；导出落盘契约已核对一致——`SettingsViewModel.exportReport()` 写入 `FileManager.default.temporaryDirectory`，文件名 `FilterKit-Report-<sanitized version>.json`，与工作流 glob `$CONTAINER/tmp/FilterKit-Report-*.json` 对齐。样本是否真实落盘待五轮容器拉起后复核。

## 产物

- Artifact `filterkit-ui-acceptance`，ID `14513387629`，84702582 B；下载页 `https://github.com/yi-fen/FilterKit/actions/runs/44490042909/artifacts/14513387629`。
- 本地归档：`job-logs.txt`（371K，2115 行，SHA256 `2444e5764dcf1973cc34845af634c6e937f407331ecfe142bec5d62fee486034`）。

## 门禁初判（待五轮复核）

- G8 导航：部分可达（Diagnostics / Settings / Plugins Tab 通过）；Dashboard 计数、Detail 推入、分段计数三项待五轮按新 AX 范式复核。
- G9 导出：UI 链路通过；容器样本与往返解析本轮因模拟器 Shutdown 未取证，待五轮 boot 后复核。
- G10 分享：Share Sheet 调起通过，`share-sheet.png` 已入 xcresult；待产物解包核验截图本体。
- G1～G7 既有判定不变；0.1-C 不予闭环。

## 本轮源码/清单改动（本地未推送，待五轮最新 main 新建运行）

- `App/Shared/Components/SectionCardView.swift`：根锚点补 `.accessibilityElement(children: .contain)`，顺序先于标识挂载。
- `App/Features/Plugins/PluginListView.swift`：行标识由 NavigationLink 移到主列行名 Text。
- `Tests/Stage2/UITests/NavigationFlowTests.swift`：行选择器由 `.cell` 直匹配标识改为 `cells.containing(...)` 匹配含行标识后代的 Cell；辅助方法更名 `pluginRowEntries()`。
- `.github/workflows/filterkit-build.yml`：拉取样本前先 boot 模拟器。
- 本轮无需物理重命名源文件/目录；既有文件、目录与 target/产物名（`FilterKitUITests`、`ReportRoundtripValidator`、`Tests/Stage2/UITests`、`Tools/ReportRoundtripValidator`）经核对一致。
