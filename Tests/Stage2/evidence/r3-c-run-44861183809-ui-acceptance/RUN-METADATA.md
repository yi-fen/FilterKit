# R3-C 首轮 Runner 反馈切片 — run `44861183809` / job `ui-acceptance`（cf741b）

> 切片性质：**XCUITest（界面验收）单 job 日志**。本 job 不执行 `swift test` Stage2Tests，
> 新增 8 例桥接用例与既有 590 例回归、iphoneos 编译结论均**不在本切片证据范围**。

## 1. 运行事实

| 项 | 值 |
|---|---|
| Workflow run | `44861183809` |
| Job | `f43a0cef-e238-5410-952e-69318835f38a`，`ui-acceptance` |
| 检出 SHA | `cf741baf65202e8af8856b3b27c1181ba7a16e44`（远端 main，提交信息「上传 源码」） |
| 代码对齐核对 | `App/ Core/ Models/ Adapters/ Tests/ Package.swift/ project.yml` 与本地 HEAD `1f3a73d` 逐文件一致；远端相对本地仅删除 `Research/` 文档与 `0.1.18-device-report.json`，脚本仅权限位差异。**本 job 被测即 R3-C 代码。** |
| 时间（UTC） | 2026-11-21 03:32:25Z ～ 03:43:50Z |
| Runner | 2.338.2；macos-26-arm64 image `20261102.0473.1`；macOS 26.7.2（25G332）；Xcode 26.6；iPhoneSimulator26.5.sdk；target `arm64-apple-ios12.0-simulator` |
| 模拟器 | `98A0BFA3-CEC3-4FD6-9916-5A2149774DBF`（iPhone 17 Pro，OS 26.2）；bundle `com.filterkit.manager`；失败时 app pid 6818 存活 |
| 产物 | Artifact `filterkit-ui-acceptance`，ID `14690462458`，86,848,126 B，1211 文件，SHA256 `f36704f5de168fc57b35c1bed851b9bd3e5d87d0630daeac12fd1e95c8b795c3`；下载页 `https://github.com/yi-fen/FilterKit/actions/runs/44861183809/artifacts/14690462458` |
| 日志 | `job-logs.txt`，2421 行，SHA256 `edaf005601a0cb951d1275c422d522ed34d92217b5ffe49c9f5c130837084b48` |

## 2. 编译结论（iphonesimulator，本 job 可观察部分）

- R3-C 源码进入编译清单：`Core/Diagnostics/Export/DiagnosticsExportModels.swift`、`DiagnosticsReportMapper.swift`、`Core/Reporting/CombinedReportEncoder.swift`、`App/AppEntry/DiagnosticsReportStore.swift`。
- App 成功构建并安装启动（pid 6818）；除 `appintentsmetadataprocessor` 的 AppIntents 依赖缺失提示外，**无 Swift `warning:` / `error:`**。
- xcodebuild test 最终退出码 65（TEST FAILED）。
- 未观察到 iphoneos 编译；未观察到 `swift build` / `swift test`。

## 3. UI 用例结果（8 executed，1 failure，0 unexpected，244.880s）

| 用例 | 结论 | 耗时(s) | 说明 |
|---|---|---|---|
| `EmptyStateTests.testExportDisabledWithoutEnvelope` | ❌ failed | 101.051 | `EmptyStateTests.swift:22` `XCTAssertTrue` 失败：5s 内未找到 `settings.exportButton`（「导出入口应在位」）。 |
| `ExportFlowTests.testExportProducesShareLinkWithoutError` | ✅ passed | 24.548 | 非信封预览态：导出按钮在位、点按后 `settings.shareLink` 出现、无错误文案。 |
| `NavigationFlowTests.testDashboardBaselineVisible` | ✅ passed | 13.170 | |
| `NavigationFlowTests.testDiagnosticsSectionsVisible` | ✅ passed | 20.862 | |
| `NavigationFlowTests.testPluginDetailOpensFromRow` | ✅ passed | 26.854 | |
| `NavigationFlowTests.testPluginsListSegmentsAndSearch` | ✅ passed | 26.435 | 基线五轮的搜索框先聚焦修复在本轮生效。 |
| `NavigationFlowTests.testSettingsVisible` | ✅ passed | 14.270 | 非空态 Settings 导出按钮在位。 |
| `ShareSheetTests.testShareSheetOpensAfterExport` | ✅ passed | 17.689 | |

## 4. 后置往返校验（G9）结果

- 测试结束后 `xcrun simctl get_app_container … data` 拉取 `tmp/FilterKit-Report-*.json`：**容器临时目录未发现导出样本** → workflow `::warning::未在容器临时目录找到导出 JSON`。
- 校验器步骤：`::error::缺少导出 JSON 样本，无法往返校验`，exit 1（`ReportRoundtripValidator` 本次未拿到输入，未执行往返判等）。
- 注意：`ExportFlow` / `ShareSheet` 两例观察到分享入口出现；按 VM 口径 `exportedFileURL` 仅在 `write(to:)` 成功后置位。样本为何未落在被扫描的容器 tmp，**本轮未定位**，与失败用例分列记录，不合并归因。

## 5. 失败分析（证据边界内）

### 5.1 对照基线

- 基线切片 `Tests/Stage2/evidence/c-f5-fifth-run/`（run `44543099338`，SHA `71bc6b0`，2026-11-19）：同一 `EmptyStateTests.testExportDisabledWithoutEnvelope` **passed 51.522s**；同 Xcode 26.6、同模拟器、同 runner 2.338.2。
- R3-C 对 Settings 接线的 diff：`SettingsView` 仅补传 `diagnosticsStore`；`SettingsViewModel` 增加 Store 与 `CombinedReportEncoder`，导出按钮在视图层级中**无条件渲染**，`canExport=false` 只置 `.disabled`，不移除元素；静态核对 `SettingsView / SettingsViewModel / DashboardViewModel / InfoRowView` 未发现 nil 信封下的强制解包或崩溃点。

### 5.2 本轮轨迹（冷启动首跑）

- automation session 建立 54.22s（基线 32.97s）。
- Settings 按钮 t=64.12s 点按请求 → 合成事件 t=89.09s（间隔约 25s；基线间隔 0.52s）→ idle 后 5s 等待导出按钮，t=96.74s 仍不存在，断言失败。
- 基线同一 5s 等待内按钮约 4.9s 才出现，窗口本就临界；本轮首跑渲染/事件调度明显更慢。
- 同一构建的非空态启动（ExportFlow / SettingsVisible / ShareSheet）按钮均在位。

### 5.3 未取得的关键证据

- 失败时刻的 AX 层级快照与截图封在 artifact `14690462458` 的 xcresult Data blob 内；本 Linux 会话下载产物被 403（限流/需鉴权）阻断，无法判读「按钮禁用但在位」还是「Settings 视图未切换/未渲染」。

### 5.4 待验证假设（未定论，不改代码）

- **H1（时序/抖动，优先排除）**：冷首跑渲染滞后超过 5s 存在性等待窗口；基线该等待本就临界。复跑若通过，按时序抖动归档。
- **H2（空态运行期渲染）**：nil 信封下切到 Settings 后内容未渲染；需 xcresult 层级快照或复跑复现后定位。静态核对未见崩溃点。

## 6. 本轮未闭环项

1. 待 `swift test` job 日志：新增 8 例桥接用例通过 + 既有 590 例无回归；本切片不含此结论。
2. 待 iphoneos / iphonesimulator 两侧编译日志回填；本切片仅见模拟器侧成功构建启动。
3. 待取得 artifact xcresult 快照复核 EmptyState 失败层级；必要时复跑 `ui-acceptance`。
4. G9：导出样本未落入被扫描容器 tmp 的原因待查（tmp 路径 / 用例间终止清理 / 编码异常被遮罩）。
5. A6 真机验收未发生：新构建包 → 设备安装 → 现场扫描 → 首份含真实 `diagnostics` 段 JSON。

## 7. 冻结边界复核

本轮仅日志判读与证据归档，未改 plist / 未增删移文件 / 未改规则 / 未装卸 / 未碰 dpkg 写 / 未改软链 / 未注入 / 未加常驻 daemon·Helper·IPC / 未放宽 entitlement 与沙盒 / 未重写签名链路；未推送远端。
