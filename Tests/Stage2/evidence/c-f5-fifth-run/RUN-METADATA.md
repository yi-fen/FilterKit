# C-F5 五轮 Runner 复核记录（run `44543099338` / job `ui-acceptance`，新运行于 main `71bc6b0`）

- 时间：2026-11-19 14:30:59Z ～ 14:42:44Z；Worker `{0c6d0d9e-000c-4791-8795-3ee801b588dc}`；runner version 2.338.2；macOS 26.7.2（25G332），Xcode 26.6（`/Applications/Xcode_26.6.app`），iPhoneSimulator26.5.sdk；UI 模拟器 `98A0BFA3-CEC3-4FD6-9916-5A2149774DBF`；app-build 模拟器 `EED6FB0A-E273-43C6-B5DE-3DF739543042`，alive PID 4390，bundle `com.filterkit.manager`。
- 检出 SHA：**`71bc6b00efe4db3e666acc1c9e62bcb1a26158bc`**（forced-update 快照；`Package.swift` / `project.yml` / 工作流与本地工作树逐文件 `diff -q` 一致，确认四轮 AX 范式修复已上 Runner）。
- 附件：Artifact `filterkit-ui-acceptance`，ID `14540317760`，86467580 B，retention 14 天；下载页 `https://github.com/yi-fen/FilterKit/actions/runs/44543099338/artifacts/14540317760`。

## 用例执行结果（8 tests，1 failure，0 unexpected，196.324s）

| 用例 | 结论 | 耗时 | 说明 |
|---|---|---|---|
| EmptyStateTests.testExportDisabledWithoutEnvelope | ✅ passed | 51.522s | 空信封导出入口禁用 |
| ExportFlowTests.testExportProducesShareLinkWithoutError | ✅ passed | 18.607s | 导出链路与分享入口出现、无错误文案 |
| NavigationFlowTests.testDashboardBaselineVisible | ✅ passed | 14.554s | Dashboard 四项计数标识在位（四轮卡片根 contain 修复生效） |
| NavigationFlowTests.testDiagnosticsSectionsVisible | ✅ passed | 20.331s | 诊断七组卡片标识在位 |
| NavigationFlowTests.testPluginDetailOpensFromRow | ✅ passed | 24.413s | 行点按推入 Detail，`detail.plugin-id` 与六分区在位 |
| NavigationFlowTests.testPluginsListSegmentsAndSearch | ❌ failed | 25.857s | 分段计数 ALL/PAIRED/ISSUES 断言通过；搜索框 `typeText("Preview")` 报无键盘焦点 |
| NavigationFlowTests.testSettingsVisible | ✅ passed | 18.256s | Settings 导出入口在位 |
| ShareSheetTests.testShareSheetOpensAfterExport | ✅ passed | 22.784s | Share Sheet 调起，附件 `share-sheet.png` 入 xcresult（G10） |

## 失败根因（五轮复核定位）

### 1. 搜索框未先取得键盘焦点（唯一 UI 失败，`ui-test.log:1906`）

- 轨迹：进 Plugins Tab → `plugins.list` 在位 → ALL/PAIRED/ISSUES 分段计数断言通过 → 回到 ALL → SearchField 在位（label/placeholder `Search name or ID`，frame `{{16.0, 169.0}, {370.0, 44.0}}`）→ 直接 `searchField.typeText("Preview")`，合成事件报 `Neither element nor any descendant has keyboard focus`，重试 #2 仍失败。
- 根因：CI 模拟器上 `.searchable` 搜索框默认不是第一响应人；测试未先点按，`typeText` 无从投递键盘事件。分段计数在搜索之前，已通过；失败仅落在输入步骤，且因提前中断未归档 `plugins.png`。
- 处置（本地已落地，待六轮 Runner 复核）：搜索步骤先 `searchField.tap()` 取得焦点，再 `typeText`。

### 2. G9 往返校验器不等义：数组顺序未归一化（validator exit 1）

- 链路：四轮补的 `simctl boot` 修复生效，样本已从容器临时目录拉出并落盘 `export/FilterKit-Report-0-1-0-preview.json`（5295B）；`ReportRoundtripValidator` 编译 55.26s 完成，`decodable: true`，计数 plugins 3 / unknownItems 1 / warnings 1 与基线一致，但 `equalIgnoringGeneratedAt: false`，退出码 1。
- 根因：导出链路经 `ReportSerialization.sortedPlugins` 按 pluginID 确定性排序，导出序 `[broken-plist, orphan-plist, preview-tweak]`；合成基线工厂数组序 `[preview-tweak, broken-plist, orphan-plist]`。`Plugin: Equatable` 对数组顺序敏感，校验器直接整体判等，故仅因顺序不同判不等义；逐字段人工比对两侧其余值一致。
- 处置（本地已落地，待六轮 Runner 复核）：校验器判等前对 `plugins / unknownItems / warnings` 按与导出策略一致的键排序归一化两侧，再做整体 Equatable 判等；不新增 Core 依赖，归一化仅用 Models 公共字段。

## 其他门禁证据（五轮日志口径）

| 门禁 | 结果 | 证据 |
|---|---|---|
| Build（非 UI 目标） | ✅ | `swift-build.log`：110/110 `Build complete! (13.87s)`，0 `error:`、0 `warning:` |
| Test（全量 XCTest） | ✅ | `test-log.txt`：`Executed 405 tests, with 0 failures (0 unexpected)` |
| S1-05 独立过滤 | ✅ | `test-log-s105.txt`：15 tests 0 failures |
| GUI Presentation 单测 | ✅ | `GUIPresentationTests` GUI-01～08 八例全部 passed（含在 405 内） |
| Isolation | ✅ | `isolation-summary.json`：1a/1b/2a/2b/3/4/4b 全 passed，`failed: 0` |
| App Build | ✅ | `app-xcodebuild.log`：`** BUILD SUCCEEDED **` |
| Simulator 启动 | ✅ | `sim-launch.log`：alive check PID 4390，bundle `com.filterkit.manager` |
| Navigation（G8） | ⚠️ 部分 | Dashboard / Detail / Diagnostics / Settings 与分段计数通过；搜索交互未取证，`plugins.png` 未归档 |
| Export（G9） | ⚠️ 部分 | 样本落盘、可解码；往返不等义在本轮未通过（归一化修复待复核） |
| Share（G10） | ✅（日志口径） | ShareSheet 用例 passed，`share-sheet.png` 附件名记录在 xcresult；截图本体封在 xcresult Data blob，本机 Linux 无 xcresulttool，像素本体未解包核验 |

## 归档文件 SHA256

| 文件 | SHA256 |
|---|---|
| `job-logs.txt`（ui-acceptance 全 job 日志） | `c52ff6aff6db75a851862bd2df0f4242a92ec8a15f0c910234220d22b2bfc1b0` |
| `ui-test.log`（xcodebuild UI 测试日志，2060 行） | `6b0793cf16b37f1427166959db845f01556d62bda37fa664ee94ae53915f8a1c` |
| `test-log.txt`（全量 405 例） | `fc4e5d3c2b620e6e6f9c5cde6c498bbebbc9b971f45bc9540b49236756bdda69` |
| `test-log-s105.txt`（S1-05 15 例） | `3bef4fda5d5a54bf8e8486cef041f5c9e06a7cea09a023cfbd16a04c1540fae4` |
| `isolation-output.log` | `bf3d31be4555e77dcb9246535c213324f70c2e04fcd967ebcd642b834f13e733` |
| `isolation-summary.json` | `1ebad9674d94971379b14be71aa63fd77873280d10ae32787eca070c5f7489c2` |
| `swift-build.log` | `923e6c597597b43c56df4c30cff92e217dd8503fb03636dbae16fcb18b087f85` |
| `app-xcodebuild.log` | `c58f4eefb7433f0ea2194b7b21c8910575affe71dd3a755e99988c37666d9cc8` |
| `sim-launch.log` | `92c02a9d7ab44dac515b1c642c6d93595fce8ed60c81948b8c59e90a5245c705` |
| `export/FilterKit-Report-0-1-0-preview.json` | `cfbf36262da34aa089fa58afc03863e370b9a3b40f2a7ac58be813a5807c80d7` |
| `export/roundtrip-result.json` | `5f4a2b71dc59e895387dd763fe84e13f73d6dbdb2cc49e539c39eb5ece8e75bc` |

## 本轮源码/清单改动（本地未推送，待六轮最新 main 新建运行复核）

- `Tests/Stage2/UITests/NavigationFlowTests.swift`：搜索框先 `tap()` 聚焦再 `typeText("Preview")`。
- `Tools/ReportRoundtripValidator/main.swift`：新增 `normalized(_:)` 数组排序归一化；判等两侧先归一化再比较；未改 target 依赖。
- 本轮无物理文件/目录重命名；既有目录与 target 名（`Tests/Stage2/UITests`、`Tools/ReportRoundtripValidator`、`FilterKitUITests`、`ReportRoundtripValidator`）经核对不变。

## 门禁初判（待六轮复核）

- G1～G7 ✅；G8 待搜索输入步骤与 `plugins.png` 最终确认；G9 待归一化后往返等义（`equalIgnoringGeneratedAt: true`、validator exit 0）；G10 日志口径通过，截图本体待产物解包核验。
- **0.1-C 不予闭环**：按 C-F4 §5，G8/G9 未全绿且 G10 截图本体未复核；不回填 0.1-D 结论。本机 Linux 无 Swift/Xcode，编译与渲染结论以 Runner 日志为准。
