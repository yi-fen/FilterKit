# Stage 2.3（0.1-C）：GUI Foundation 实现记录

- 日期：2026-11-18
- 授权依据：用户上传 MD（0.1-B 第四轮 Runner `44224350333` 闭环后授权进入 0.1-C）；冻结规格 `Stage-2.3-GUI-Foundation-Spec.md`（C1～C6，GUI-01～08）。
- 状态标记：**Implementation Landed / Local L1 Static Review Passed / Runner Build & Test Pending**。本机 Linux 无 Swift/Xcode 工具链，本轮未编译、未执行 XCTest；编译、渲染与交互结论以阶段末统一 Runner 为准。

## 1. 本轮授权边界

### 允许
1. 按 C1～C6 批次新增 App Presentation 纯映射层、SwiftUI 视图与 ViewModel、共享组件、导航与组合根；
2. 新增 SwiftPM `AppPresentation` 目标（只依赖 Models）与对应 Presentation 单测；
3. 扩展隔离脚本 GUI 禁止面；
4. 只读静态检查、接口核对与代码审查。

### 禁止（本轮均未触碰）
1. 未修改冻结公共 Models 字段/init/解码契约、七方法 `ElleKitAdapter` 协议、Parser 语义、`ReportEnvelope` 契约与 Stage1 fixtures；
2. 未实现 `OwnershipResolver`；未迁移归属分类器；
3. 未在 App 内实现扫描、枚举、配对、解析、归属补判或运行时取证；
4. 未做启停、装卸、plist/规则/注入规则修改、entitlement 放行、进程内 `jbroot()`；
5. 未接入真机快照 → `ReportBuildInput` → 信封的在线链路（属 0.1-D）；
6. 未调度阶段末统一 Runner，未声称本地编译通过；PARSE-009-B 继续挂起。

## 2. 文件清单

### 2.1 Presentation 纯映射层（`App/Presentation/`，只 import Foundation + Models）

| 路径 | 说明 |
|---|---|
| `DisplayStatus.swift` | `DisplayStatusKind`（success/warning/failure/unknown）与 `DisplayStatus` 展示状态 |
| `ReportLabels.swift` | 冻结枚举 → 展示文案唯一落点；三层状态、配对/来源/归属/证据、解析状态映射 |
| `DashboardOverview.swift` | 环境行、插件统计（Total/Paired/Missing/Parse Failed）、系统状态行；空信封全 0 + Unknown |
| `PluginRowSummary.swift` | 列表行摘要、关键词搜索、ALL/PAIRED/ISSUES 分段筛选 |
| `PluginDetailModel.swift` | 详情六分区模型：状态/文件/配对/Filter/归属/证据 |
| `DiagnosticsSections.swift` | 诊断七分组：Environment/JBROOT/DynamicLibraries/Enumeration/Parsing/Warnings/UnknownItems |
| `SyntheticReportFactory.swift` | 0.1-C 预览用固定合成信封与空信封工厂（不冒充真机扫描） |

### 2.2 App 装配 / 导航 / 视图

| 路径 | 说明 |
|---|---|
| `App/AppEntry/AppDependencies.swift` | `ReportProviding` 接缝、`StaticReportProvider`、`AppDependencies`（报告来源 + `ReportExporting` 接缝） |
| `App/AppEntry/FilterKitApp.swift` | 唯一 `@main` 组合根；静态合成信封 + `ReportExporter()` 注入 |
| `App/Navigation/AppTab.swift` | 四 Tab 枚举（Dashboard/Plugins/Diagnostics/Settings） |
| `App/Navigation/RootTabView.swift` | `TabView` 四页容器 |
| `App/Features/Dashboard/` | `DashboardViewModel` + `DashboardView`（环境卡片、统计、系统状态行） |
| `App/Features/Plugins/PluginListViewModel.swift` | 列表搜索/筛选装配；按 pluginID 回查完整 `Plugin` |
| `App/Features/Plugins/PluginListView.swift` | 搜索框、分段筛选、列表行、详情导航 |
| `App/Features/Plugins/PluginDetailView.swift` | 详情六分区只读展示 |
| `App/Features/Diagnostics/` | `DiagnosticsViewModel` + `DiagnosticsView`（诊断分组） |
| `App/Features/Settings/SettingsViewModel.swift` | 版本信息；经 `ReportExporting.export(_:)` 导出到 App 临时目录；错误文案保留 |
| `App/Features/Settings/SettingsView.swift` | 版本行、导出按钮、Share Sheet、错误提示 |
| `App/Shared/Components/` | `StatusBadgeView` / `InfoRowView` / `SectionCardView` 只读通用组件 |

### 2.3 测试与接线

| 路径 | 说明 |
|---|---|
| `Tests/Stage2/GUIPresentationTests.swift` | GUI-01～08：空态、计数归类、搜索、筛选、三态标签、详情映射、诊断归集、导出接缝往返 |
| `Package.swift` | 新增 `AppPresentation` 库目标（依赖 Models）与产品；`Stage2Tests` 依赖增补 `AppPresentation` 与测试源 |
| `scripts/check-adapter-isolation.sh` | §4 增补 `PluginInventoryBuilder`/`PluginPairingPipeline`/`PluginPairingInputAdapter`/`PluginFilterParseEngine`/`ReportBuilder`/`ReportValidator`/`ReportService` 禁止面；§4b 检查 App 不得 `import Adapters` |

### 2.4 移除的旧骨架

- 删除 `App/FilterKitApp.swift` 旧占位入口（含 `AppAssembly`/`StubAdapterResolver`）与 `App/Views/DashboardView.swift` 骨架页；`App/Views/`、`App/ViewModels/` 目录由 `App/Features/`、`App/Navigation/`、`App/AppEntry/` 取代。`PermissionProbe/` 2.4 预留轮廓保留不动。

## 3. 实现口径要点

### 3.1 C1 架构
- 依赖方向：App Features → Presentation → Models；App 装配层持有 `ReportExporting` 协议接缝，不引用 Core 具体实现。
- `AppPresentation` 不 import SwiftUI/UIKit/Core，可被 SwiftPM 测试目标独立编译。
- 0.1-C 装配为静态信封提供者；无异步 `generateReport()`，`buildReport(input:)` 在线接入延后到 0.1-D。

### 3.2 C2 Dashboard
- 计数：Total=`plugins.count`；Paired=`pairing == .paired`；Missing=其余；Parse Failed=`validation.status ∈ {parse_failed, type_mismatch, read_failed}`，`not_parsed` 不计入。
- JBROOT 取 `environment.jbroot ?? pathEvidence.jbrootCandidates.first`；Permission 恒 undetermined 占位。

### 3.3 C3 列表
- 搜索命中 `name`/`pluginID` 大小写不敏感包含；空关键词全量。
- ISSUES = 配对未成功 或 未配置 或 `validation.status != valid`。
- 行内三层状态标签 + 配对标签；无启停/删除入口。

### 3.4 C4 详情
- 路径缺失展示 Unknown，不拼默认路径；空数组展示 `—`；归属冲突/备注/标记/包版本/架构原样追加。
- `loaded == .unknown` 文案 "Unknown · Runtime state not verified"，不渲染为 Not Loaded。

### 3.5 C5 诊断与导出
- 诊断七分组完整归集 Warnings / UnknownItems，不裁剪字段。
- 导出经 `ReportExporting.export(_:)` 产出 Data；UI 层不构造编码器、不重排键序；文件写 `FileManager.default.temporaryDirectory`，文件名 `FilterKit-Report-<generatorVersion>.json`；无信封时导出入口禁用。

### 3.6 C6 集成
- 空态：列表 `ContentUnavailableView`；诊断空分组 `—`；Dashboard 空信封计数全 0。
- 隔离脚本静态文本检查通过；GUI 禁止面见规格 §10。

## 4. L1 静态自检记录（本机无 Swift 工具链，未本地编译）

| 检查项 | 结果 |
|---|---|
| 隔离脚本 `check-adapter-isolation.sh` 全项 | OK（1a/1b/2a/2b/3/4/4b 均通过，退出码 0） |
| Presentation 导入面 | 仅 Foundation + Models，无 SwiftUI/UIKit/Core |
| `@main` 唯一性 | App 内仅 `AppEntry/FilterKitApp.swift` 一处 |
| App 对 Adapters 的直接依赖 | 无 `import Adapters` |
| App 文件系统/解析 API | 仅 `SettingsViewModel` 读取 `temporaryDirectory`；无目录枚举、plist 解码、解析器调用 |
| 括号配平 | 新增 App 与测试 Swift 文件 `{}`/`()` 配平一致 |
| 旧骨架符号残留 | 无 `AppAssembly`/`StubAdapterResolver`/旧 `DashboardView` 外部引用 |
| 冻结契约 | 未改 Models 字段/init/解码、Adapter 协议、Parser 语义、Stage1 fixtures |

## 5. 待验证与未决项（本阶段不闭合）

1. 阶段末统一 Runner：非 UI `swift build`、`swift test`（既有回归 397 + GUI 新增 8 例）、隔离脚本、App XcodeGen 生成与模拟器构建/启动/四页切换/合成信封渲染/导出落临时目录。
2. 真机快照在线接入（`ReportBuildInput` 组装与注入）属 0.1-D 探针阶段；合成信封通过只证明 UI 映射正确。
3. Deployment Target（草案 iOS 17.0）、Bundle ID（占位 `com.filterkit.manager`）待链接 + 真机证据冻结。
4. `OwnershipResolver` 未迁移；`loaded` 恒 `.unknown`；`pluginID` 稳定标识规则 0.2.0 定稿；PARSE-009-B 挂起。
5. 本阶段产物不构成真机权限、真实加载、Rootless 真机兼容或可写入管理证据。

## 6. 首轮 Runner `swift build` 失败修复（2026-11-18，待下一轮复核）

- Runner：`build` job，检出 SHA `758855cd86c9aaa050d0a5a7fe2272a88cd05a5b`；证据归档 `Tests/Stage2/evidence/run-9b9f00cb-build-failure/`（含完整 job 日志与 `RUN-METADATA.md`）。
- Models / Adapters 编译通过；AppPresentation 两处错误后 Core 刚开始编译即退出，未进入 `swift test` 与 app-build。

| # | 位置 | 错误 | 修复 |
|---|---|---|---|
| 1 | `App/Presentation/PluginDetailModel.swift:82` | `self.filterRows.append` 作用于 `public let` 常量数组，`cannot use mutating member on immutable value` | init 内改为局部 `var filterRows = [...]`，append CoreFoundation 行后 `self.filterRows = filterRows`；属性仍 `let`，沿用 `ownershipRows`/`evidenceRows` 局部 var 范式 |
| 2 | `App/Presentation/SyntheticReportFactory.swift:51` | `FilterRule` 实参 `executables` 先于 `classes`，`argument 'classes' must precede argument 'executables'` | 按冻结 init 顺序改为 `bundles:, classes:, executables:`；未改 init 签名与默认参数 |

- 同类隐患静态排查：全 `App/` 无其他 `self.<row>.append`；其余 `FilterRule` 多参数站点（ModelsCodableTests / ReportExporterTests / FilterParseEngineTests）顺序正确；隔离脚本复跑全项退出码 0；Presentation 导入面仍仅 Foundation + Models。
- 本机 Linux 无 Swift/Xcode 工具链，修复未本地编译；通过与否以下一轮 Runner `swift build` / `swift test` 日志为准。SwiftUI App 视图层不在 SwiftPM 编译面，其风险待 app-build（XcodeGen）步骤暴露。

## 7. 首轮 app-build（XcodeGen/xcodebuild）失败修复（2026-11-18，待下一轮复核）

- Runner：`app-build` job，检出 SHA `386f18cbd528a9ad11f8e690e883a6d76c5f8409`；Xcode 26.6 / Swift 5 / XcodeGen 2.46.0 / iOS Simulator Debug，退出码 65；证据归档 `Tests/Stage2/evidence/run-089d13ea-app-build-failure/`（`RUN-METADATA.md` + `build/job-logs.txt`）。
- 非 UI 包目标（Models/Adapters/Core）随 xcodebuild 依赖图编译未报该层错误；失败集中在 App target 模块发射（`EmitSwiftModule normal arm64`），未产出 `.app`、未进入模拟器启动。

| # | 位置 | 错误 | 修复 |
|---|---|---|---|
| 1 | `App/Features/Dashboard/DashboardView.swift:74` | `#Preview` 内 `ReportExporter()` 报 `cannot find 'ReportExporter' in scope`；文件仅 import SwiftUI/Models | 补 `import Core`（置于 `import Models` 后） |
| 2 | `App/Features/Diagnostics/DiagnosticsView.swift:50` | 同上 | 补 `import Core` |
| 3 | `App/Features/Plugins/PluginListView.swift:91` | 同上 | 补 `import Core` |
| 4 | `App/Features/Settings/SettingsView.swift:72` | 同上 | 补 `import Core` |

- 根因：`ReportExporter` 定义在 Core 模块；SwiftPM `swift build` 不编译 App target，首轮 `build` job 未暴露，XcodeGen 单模块编译后缺导入才在模块发射阶段报错。
- 复核：其余 `ReportExporter`/`ReportExporting` 引用点（`AppDependencies.swift`、`FilterKitApp.swift`、`SettingsViewModel.swift`）导入面完整；`ReportExporter` 不在隔离脚本 §4 禁止面；隔离脚本复跑全项退出码 0；未改装配逻辑、协议、Models 冻结契约。
- 本机 Linux 无 Swift/Xcode 工具链，修复未本地编译；待下一轮 Runner 复核 `** BUILD SUCCEEDED **`、模拟器存活、四页渲染与导出落临时目录。

## 8. 第三轮 Runner 验收（2026-11-18，app-build 全绿；test 明细待补证）

- Runner：workflow run `120016036175`，检出 SHA `f50c284dfe9b6b40a0b877eeb5d6588dbb9f78a4`；Xcode 26.6 / iPhoneSimulator26.5.sdk / Swift 5 / XcodeGen 2.46.0；证据归档 `Tests/Stage2/evidence/run-120016036175-acceptance/`。
- 门禁：artifact job `needs` 映射 `build / test / isolation / app-build` 四 job 均 `result: success`；本批附件仅含 app-build 产物日志与 metadata，build/test/isolation 步骤日志与 test-log 未随包上传，用例计数与隔离输出待补证（见证据归档 `RUN-METADATA.md` §1/§3）。
- app-build 全量取证通过：`** BUILD SUCCEEDED **`，0 条 `error:`（仅 1 条 AppIntents 元数据提取跳过的良性提示）；`FilterKit.app` 定位、安装、启动 PID 13225，3 秒后 alive check 通过；`dashboard.png` 1206×2622，Dashboard 合成信封渲染正确（RootHide / ellekit 1.0.0 / roothide-preview；3 插件 2 配对 1 Missing 1 Parse Failed；JBROOT Confirmed、TweakInject Accessible、Permission Undetermined 2.4 probe；四 Tab，Dashboard 选中）。
- 两轮修复（§6 `549d7ae`、§7 `0a341f8`）在 Runner 检出树编译通过：四视图与 Detail/Entry/Components 全部 App 源码双架构（arm64/x86_64）编入 `FilterKit` 目标，无作用域缺失或实参顺序错误。
- 未闭合取证项：GUI-01～08 八例与既有 397 例的实际执行计数待 `filterkit-test-log` 复核；Plugins/Detail/Diagnostics/Settings 页内交互与 Settings 导出落临时目录未在模拟器内点击取证；真机权限、真实加载、Rootless 真机兼容仍属后续批次。

## 9. 0.1-C-Final 补证批次 C-F1～F4（2026-11-19 授权，规格/归档落地，Runner 执行待调度）

> 路线调整：不提前进入 0.1-D 或插件启停开发；先完成 0.1-C 验收补证与交互验收，闭环后再规划 Permission Probe。

- **C-F1 CI 日志补证**：后补归档 386f18cb 轮次（第二轮 app-build 失败轮）SwiftPM XCTest 日志至 `Tests/Stage2/evidence/run-089d13ea-app-build-failure/test-log/`：全量 **405 tests，0 failures（0 unexpected），0 skipped**，38 套件全 passed；`GUIPresentationTests` 8/8；`PluginPairingS105FixtureTests` 15/15；摘要 `test-summary.json`、`s1-05-summary.txt`。f50c284d 轮次（run `120016036175`）缺项登记于同轮证据目录 `C-F1-GAPS.md`（build 明细 / 全量 test-log / S1-05 结果 / isolation 原始输出），不得以 Job 绿色勾选替代用例计数。
- **C-F2 隔离机器可读摘要**：`scripts/check-adapter-isolation.sh` 保留原文本输出与退出码，结尾追加 JSON 摘要（`checks[].id/name/status` + `failed` 计数），支持 `ISOLATION_SUMMARY_PATH` 落盘；CI `isolation` job 增补 `isolation-output.log` / `isolation-summary.json` 归档。本机复跑 7 项全 passed、`failed=0`，JSON 校验通过。
- **C-F3 五页面交互验收规格**：`Spec/Stage-2/Stage-2.3-CF3-Simulator-Interaction-Acceptance.md` 冻结 Plugins / Detail / Diagnostics / Settings / Share Sheet 观察清单、证据截图清单与导出边界；本机无模拟器，执行待 Runner。
- **C-F4 最终统一验收门禁**：`Spec/Stage-2/Stage-2.3-CF4-Final-Acceptance-Gates.md` 冻结 Build / Test / S1-05 / GUI / Isolation / App Build / Simulator / Navigation / Export / Share 十项门禁与取证口径；计数以真实日志为准，不预写死总数。
- 本批未新增 Swift 业务代码；未改冻结 Models 契约、Adapter 协议、Parser 语义与 Stage1 fixtures；本机 Linux 无 Swift/Xcode，脚本与 YAML 仅做语法/静态复跑，结论待 Runner 日志复核。

## 10. 第三轮回传产物复核（2026-11-19，interim，未签署 0.1-C）

- 用户回传 run `120016036175`（SHA `f50c284d`）四件产物；工作流 yml 哈希与本目录 `metadata/` 旧版一致，确认是远端旧树回传，非 HEAD `9e26a6e` 新 Runner。
- 补归档该轮 SwiftPM 日志至 `run-120016036175-acceptance/test/`：**405 tests，0 failures（0 unexpected），0 skipped**，38 套件；GUI 8/8、S1-05 15/15、Reporting 18 例；摘要 `test-summary.json`、`s1-05-summary.txt`。F1-2 / F1-3 关闭；F1-1 build 明细、F1-4 isolation 原始输出仍缺。
- 门禁逐项核对见 `run-120016036175-acceptance/C-F4-Gate-Status.md`：G2/G3/G4/G6/G7 为旧树通过（🟡 HEAD 待复核）；G1/G5/G8/G9/G10 缺证（❌）。
- 判定：**0.1-C 不予正式验收关闭**。前置：推送 `9e26a6e` 到 `main` → HEAD 基线新统一 Runner 补齐 G1/G5/G8/G9/G10 并复跑 🟡 项 → 全部门禁归档后签署。HEAD 提交无 `.swift` 改动，可降低回归风险，但不替代 Runner 复核。

## 11. 第四轮统一验收复核（run `44426297905` / SHA `2445ef1`，2026-11-19，仍未签署 0.1-C）

- 远端 `main` = `2445ef1f11d1b71ffbff68fd8f9209ed6ffb76f3`；与本地 HEAD `e6845aa` 比对：无 `.swift` 源码与工作流 yml 内容差异，隔离脚本仅远端执行位回退；`Research/` 与设备私有 JSON 未随远端上传。
- 归档目录 `Tests/Stage2/evidence/run-44426297905-acceptance/`：
  - Test：**405 tests，0 failures（0 unexpected），0 skipped**，38 套件；GUI 8/8、S1-05 15/15、Reporting 18 例；摘要 `test/test-summary.json`。
  - Isolation：7 项 OK / 7 passed / `failed=0`，原始日志与 JSON 摘要一致（F1-4 关闭）。
  - App：`** BUILD SUCCEEDED **`，0 error；PID 7094 alive；Dashboard 截图归档（MD5 `c17185ce…`）。
- 门禁判定见 `run-44426297905-acceptance/C-F4-Gate-Status.md`：**G1/G2/G3/G4/G5/G6/G7 ✅**；**G8/G9/G10 ❌ 缺证**。
  - G1：Worker 日志包 `logs_120262177442.zip` 补证 `logs/non-ui-build/swift-build.log`：`Build complete! (11.99s)`，Models/Adapters/Core 全量编译，0 error / 0 warning；environment 工具链版本同步归档。
  - G8：仅 Dashboard 首屏，Plugins/Detail/Diagnostics/Settings 未点击取证。
  - G9：无导出 JSON 样本；G10：无 Share Sheet 截图。
- 判定：**0.1-C 仍不予闭环**。剩余：五页面交互截图 → 导出样本回解析 → Share Sheet 取证，全绿后生成统一 `ACCEPTANCE.md` 签署。

## 12. C-F5：G8/G9/G10 CI 自动化落地（2026-11-19，待 Runner 首轮复核）

- 方案评审稿：`Stage-2.3-CF5-CI-UIAutomation-Plan.md`。拍板默认：D1 可执行校验入口、同意清单装配、分阶段 P1→P2→P3、G1 编译日志随批自动归档。
- 边界：不改 Core / Models / Adapters / Parser / 冻结契约；UI 层只补无障碍标识与启动参数；不触发扫描、不读写越狱目录；不开发 0.1-D。
- **P1 导航取证**：
  - `App/` 补 `accessibilityIdentifier`：Tab、列表/分段/行、Detail 六分区、Diagnostics 七组、Dashboard 计数格、Settings 导出/分享/错误入口；`SectionCardView` 增加可选标识参数。
  - `project.yml` 新增 `FilterKitUITests`（`bundle.ui-testing`，依赖 FilterKit）。
  - `Tests/Stage2/UITests/`：`FilterKitUITestBase`（启动/标识查询/截图附件/Tab 打开）、`NavigationFlowTests`（Dashboard 计数、Plugins ALL/PAIRED/ISSUES/搜索、Detail 推入与六分区、Diagnostics 七组、Settings 在位）。
- **P2 导出往返**：
  - `ExportFlowTests`：Settings 点 Export → 分享入口出现、无错误文案。
  - `Tools/ReportRoundtripValidator/main.swift`（SwiftPM executable target，依赖 Models + AppPresentation）：解码导出 JSON，与 `previewEnvelope()` 基线比对（忽略 `generatedAt`），输出 `roundtrip-result.json`；退出码 0 等义 / 1 不等义或解码失败 / 2 参数缺失。
  - 工作流 `ui-acceptance` job：选模拟器 → `xcodebuild test -scheme FilterKitUITests` → 从容器 `tmp/` 拉出 `FilterKit-Report-*.json` → 跑校验 → 生成 `SHA256SUMS`，归档 `filterkit-ui-acceptance`。
- **P3 分享与空态**：
  - `ShareSheetTests`：导出后点 ShareLink，等待系统分享面板并截 `share-sheet.png`。
  - `EmptyStateTests`：启动参数 `-FILTERKIT_PREVIEW_EMPTY` 注入无信封，断言导出入口禁用、无分享入口；`FilterKitApp` 组合根按参数选择静态提供者（nil 信封）。
- **G1 自动留证**：`build` job 补 `tee .build/swift-build.log` 与 `filterkit-non-ui-build` 产物上传（`if: always()`）。
- 待 Runner 复核（本机 Linux 无 Swift/Xcode，未本地编译）：UITest target scheme 生成、模拟器元素匹配、Share Sheet 在无窗口 Runner 的渲染稳定性、容器路径拉取、校验工具 `swift run` 构建；首轮失败按日志回到对应用例/步骤修正，不预写死通过数量。
- 证据口径：截图以 XCTAttachment 留存于 `FilterKitUITests.xcresult`，归档时从结果包提取；`export/` 样本与 `roundtrip-result.json` 随 `filterkit-ui-acceptance` 归档。

### 12.1 首轮 Runner 复核（run `44471548011` / SHA `b7286a2`，构建失败，待二轮复核）

- 仅 `ui-acceptance` job 日志；XcodeGen 2.46.0 工程生成成功，模拟器 iPhone 17 Pro（26.2）选中，8-target 依赖图解析正常（`FilterKitUITests → FilterKit → Models/Adapters/Core`）。
- 失败：`FilterKitUITests` target 无 Info.plist 且未自动生成，代码签名阶段中止（exit 65，`** TEST FAILED **`）；UI 用例、导出链路、Share Sheet 均未到达执行阶段，无截图/样本/校验结果。
- 定性：工程清单配置缺口，非业务源码或冻结契约问题。
- 修复：`project.yml` 的 `FilterKitUITests` 补 `settings.GENERATE_INFOPLIST_FILE: YES`（UI 测试 bundle 由工程自动生成 Info.plist）。
- 证据归档：`Tests/Stage2/evidence/c-f5-first-run/`（`job-logs.txt` SHA256 `b10a202d…`、`RUN-METADATA.md`；artifact `filterkit-ui-acceptance` ID `14504473558`）。
- 二轮待观察：测试 bundle 签名/标识、XCUITest 元素匹配、容器 `tmp/` 样本拉取、校验工具 `swift run` 构建、Share Sheet 无窗口渲染。G8/G9/G10 仍未取证，0.1-C 不予闭环。

### 12.2 二轮复核（旧 run 重跑，钉在 `b7286a2`，修复未被拾取）

- 二轮仍属 workflow run `44471548011` 的失败 job 重跑（Worker `81e4a215…`，06:39:29Z），检出固定为原始提交 `b7286a2`；构建阶段复现同一 Info.plist 报错，exit 65，用例仍未执行。
- 远端 `main` 已更新至 `5ddd489c…`，`project.yml` 含 `GENERATE_INFOPLIST_FILE: YES` 且与本地一致；失败不是修复无效，而是**重跑旧 run 不拾取 main 上的新提交**。
- 处置：须在 main `5ddd489` 上新建一次 workflow 运行（`workflow_dispatch`/推送触发），不得在旧 run 上再次重跑失败 job。
- 证据：`Tests/Stage2/evidence/c-f5-second-run/`（`job-logs.txt` SHA256 `c7eafd09…`、`RUN-METADATA.md`；artifact `14504924055`，13357 B）。

### 12.3 三轮复核（run `44474790149` / SHA `5ddd489`，8 例 3 失败，用例已执行）

- 首次在含 plist 修复的提交上新建运行：编译进入用例阶段。8 tests / 3 failures / 0 unexpected（211.198s）。
- 通过：空态禁用、导出 UI 链路、Diagnostics 七组、Settings 入口、Share Sheet 调起（`share-sheet.png` 附件入 xcresult）。
- 失败与处置：
  1. Dashboard 计数标识挂内层 VStack 未暴露 → 标识移到数值 `Text`（`DashboardView.countCell`）。
  2./3. 列表 Cell 计数混入分段 Picker 行（4≠3），首行点按落到 Picker 行未推入 Detail → 测试按 `plugins.row.` 标识前缀谓词过滤插件行，计数与点按只取行匹配（`NavigationFlowTests.pluginRowCells()`）。
- 链路缺口：测试退出 65 后，容器样本拉取与 `ReportRoundtripValidator` 步骤被跳过；两步补 `if: always()`，G9 样本/往返结果在无关导航失败时仍归档。
- 证据：`Tests/Stage2/evidence/c-f5-third-run/`（`job-logs.txt` SHA256 `151f20c1…`、`RUN-METADATA.md`；artifact `14507250879`，78.3 MB）。
- 待四轮复核：Dashboard 计数在位、Detail 推入六分区、分段/搜索计数、导出 JSON 样本回解析、Share Sheet 截图本体解包核验。

### 12.4 四轮复核（run `44490042909` / SHA `a23eaba`，8 例 3 失败，修复范式二次调整）

- 检出 `a23eaba703e39a300eb0fb7efcc0414f9a9b5b32`，与本地三轮修复树无源码差异；三轮三项修复已上 Runner。8 tests / 3 failures / 0 unexpected（227.763s），三处失败与三轮同批：Dashboard 计数不可匹配、行 Cell 选不中、Detail 未推入。
- 根因二次定位（AX 暴露范式，而非标识挂在哪一层视图）：
  1. `SectionCardView` 根 VStack 直接挂标识，容器根标识向下覆盖后代叶子自有标识，`dashboard.count.*` 数值 Text 被 Plugins 卡片根标识抹掉。处置：根锚点先 `.accessibilityElement(children: .contain)` 再挂标识（顺序不可反），保留根锚点同时子级叶子保留自有标识。
  2. 列表行标识挂在 `NavigationLink` 容器上，不进入 Cell/StaticText 的 AX identifier（`.cell` 谓词实测 0 匹配）。处置：标识移到主列行名 `Text(summary.name)`；测试选择器改为 `app.cells.containing(identifier BEGINSWITH 'plugins.row.')`，计数与点按目标仍是链接行；辅助方法更名 `pluginRowEntries()`。
  3. Detail 未推入是 #2 连带结果，行选择修复后随链路复核。
- G9 链路：`xcodebuild test` 结束后模拟器 Shutdown，`get_app_container` 报 SimError 405（exit 149），样本未拉出；Validator 缺样本 exit 1。处置：拉取步骤先 `xcrun simctl boot` 再查容器；落盘契约已核对一致（`tmp/FilterKit-Report-<version>.json`）。
- 证据：`Tests/Stage2/evidence/c-f5-fourth-run/`（`job-logs.txt` SHA256 `2444e576…`、`RUN-METADATA.md`；artifact `14513387629`，84.7 MB）。
- 待五轮复核：Dashboard 四计数在位、Detail 推入六分区、分段/搜索计数、容器样本拉出与往返解析、Share Sheet 截图本体解包核验。本轮无需物理重命名源文件/目录。

### 12.5 五轮复核（run `44543099338` / SHA `71bc6b0`，8 例 1 失败；分段/导航转绿，剩搜索聚焦与往返排序）

- 检出 `71bc6b00efe4db3e666acc1c9e62bcb1a26158bc`；`Package.swift` / `project.yml` / 工作流与本地树逐文件一致，四轮 AX 范式修复已上 Runner。8 tests / **1 failure** / 0 unexpected（196.324s）。
- 转绿项：Dashboard 四计数（卡片根 contain 生效）、Detail 推入六分区、Diagnostics 七组、Settings、空态、导出 UI 链路、ShareSheet；分段计数 ALL/PAIRED/ISSUES 断言在搜索前通过。
- 失败 1（唯一 UI 失败，`ui-test.log:1906`）：`testPluginsListSegmentsAndSearch` 对在位 SearchField 直接 `typeText("Preview")`，报 `Neither element nor any descendant has keyboard focus`。根因：CI 模拟器 `.searchable` 搜索框默认非第一响应人，未先点按。处置：先 `searchField.tap()` 取得焦点再输入；因提前中断，本轮未归档 `plugins.png`。
- G9 部分取证：`simctl boot` 修复生效，样本已落盘 `export/FilterKit-Report-0-1-0-preview.json`；Validator `decodable: true`，计数 3/1/1 与基线一致，但 `equalIgnoringGeneratedAt: false`、exit 1。根因：导出经 `ReportSerialization` 确定性排序，基线工厂数组保持构造序，`Equatable` 对数组顺序敏感；逐字段比对其余值一致，仅顺序不同。处置：校验器判等前对 `plugins / unknownItems / warnings` 按同键排序归一化两侧再比较；不新增 Core 依赖。
- 旁证：非 UI `swift build` 110/110 `Build complete! (13.87s)` 0 error/warning；全量 405 tests 0 failures；S1-05 15/15；隔离 7/7 `failed: 0`；App `** BUILD SUCCEEDED **`；alive PID 4390；`GUIPresentationTests` GUI-01～08 八例 passed。
- 证据：`Tests/Stage2/evidence/c-f5-fifth-run/`（`RUN-METADATA.md`、`job-logs.txt`、`ui-test.log`、`test-log.txt`、`test-log-s105.txt`、隔离摘要/输出、`swift-build.log`、`app-xcodebuild.log`、`sim-launch.log`、`export/` 两份 JSON；artifact `14540317760`，86.5 MB）。
- 本轮源码改动（本地未推送，待六轮最新 main 新建运行复核）：`Tests/Stage2/UITests/NavigationFlowTests.swift`（先 tap 聚焦再输入）；`Tools/ReportRoundtripValidator/main.swift`（`normalized(_:)` 排序归一化比对）。无物理文件/目录重命名；target 与目录名不变。
- 待六轮复核：搜索输入命中并归档 `plugins.png`；Validator `equalIgnoringGeneratedAt: true`、exit 0；G10 截图本体从 xcresult blob 解包核验。0.1-C 仍不予闭环。

### 12.6 六轮复核（run `44552220558` / SHA `8954cdf`，build job 编译失败，待七轮复核）

- 检出 `8954cdf171ff93cf94dfdc1eae0c7e0df050d756`，与本地五轮修复树对 `.swift` / yml 无差异；本附件仅含 `build` job（非 UI `swift build`）日志，UI/test/isolation/app-build 各 job 本轮未随附。
- 失败：`ReportRoundtripValidator` 编译两处类型错误——`main.swift:32:66` `(String, String, String?)`、`main.swift:36:61` `(String?, String, String)` 均无法应用二元 `<`。根因：五轮归一化用元组字面量做字典序比较，Swift 元组比较算子对含 `String?` 元素的元组不提供（元组未整体满足 `Comparable`）；本机 Linux 无 Swift 工具链，该类型错误本地未暴露。
- 处置（本地已落地）：移除元组 `<`，新增 `compare(_:_:) -> Bool?` 可选字符串比较器（`nil` 排前、相等返 `nil` 落下一键），与 `ReportSerialization.compare` 同口径；三个数组排序改 `compare(...) ?? compare(...) ?? ... ?? false` 显式回退链。未新增 target 依赖。
- 证据：`Tests/Stage2/evidence/c-f5-sixth-run/`（`job-logs.txt` SHA256 `d7914ea3…`、`RUN-METADATA.md`；artifact `14542534836`，1055 B）。
- 待七轮复核：G1 `swift build` 0 error/warning；五轮 UITest 搜索聚焦修复在 ui-acceptance job 的 XCUITest target 上复核；G9 往返等义、G10 截图本体解包核验。0.1-C 仍不予闭环。

### 12.7 七轮复核（run `44555812135` / SHA `35674fec`，G1～G9 通过；G10 面板可见性证据不足）

- 检出 `35674fec7960292ff30edc551785c2b151db3b86`；metadata 包内 `control` / `Makefile` / `Package.swift` / `project.yml` / 工作流与本地工作树逐文件 `diff -q` 一致；六轮 `compare(_:_:)` 比较器修复与五轮搜索 `tap()` 聚焦修复已上 Runner。环境：macos-26-arm64 镜像 20261112.0504，Xcode 26.6（17F113），Swift 6.3.3，iPhoneSimulator26.5.sdk；UI 模拟器 `5AB3DACF…`（iPhone 17 Pro，iOS 26.2），app-build 模拟器 `98A0BFA3…`，alive PID 7622。
- 门禁复跑结果：G1 非 UI `swift build` 110/110 `Build complete! (17.17s)`，0 error / 0 warning；G2 全量 `Executed 405 tests, with 0 failures (0 unexpected)`；G3 S1-05 15/15；G4 `GUIPresentationTests` GUI-01～08 八例 passed；G5 隔离 1a/1b/2a/2b/3/4/4b 全 passed，`failed: 0`；G6 `** BUILD SUCCEEDED **`；G7 PID 7622 alive，bundle `com.filterkit.manager`。
- G8 转绿：UI 自动化 8 tests / 0 failure / 0 unexpected（203.223s）；五轮遗留 `testPluginsListSegmentsAndSearch` 先 `tap()` 聚焦再 `typeText("Preview")` 命中并归档 `plugins.png`。七张附件已从 xcresult Data blob 解包，按活动段 `payloadRef` 哈希与大小一一映射，目视核验：Dashboard 3/2/1/1 基线一致；Diagnostics Environment/JBROOT/Dynamic Libraries 分组在位；Detail Status 五态 + Files 路径在位；Plugins 搜索命中 Preview Tweak、分段 ALL/PAIRED/ISSUES 在位；Settings 导出前/后两态在位。
- G9 转绿：样本 `export/FilterKit-Report-0-1-0-preview.json`（5295 B）落盘；`roundtrip-result.json` `decodable: true`、`equalIgnoringGeneratedAt: true`、`messages: []`，计数 plugins 3 / unknownItems 1 / warnings 1；SHA256 与 `SHA256SUMS` 逐字一致；`set -euo pipefail` 下 validator 后 `shasum` 步骤执行，exit 0。六轮 compare 回退链编译通过、归一化判等生效。
- G10 部分通过（不判绿）：`ShareSheetTests.testShareSheetOpensAfterExport` passed，`share-sheet.png` 归档并解包（193441 B）；App `[ShareSheet]` 子系统日志记录为临时目录 JSON 配置活动项，表明分享控制器已触发配置。缺口：截图本体为 Settings 底层视图，未见系统面板浮层/活动图标行；AX 谓词 `identifier/label CONTAINS 'Share'` 宽松，命中元素不能确证为系统面板；活动项 provider 拉取返回 null。本轮只能证明分享入口触发与控制器配置尝试，不能证明面板正常可见呈现。
- 证据：`Tests/Stage2/evidence/c-f5-seventh-run/`（`RUN-METADATA.md`、`C-F5-Gate-Status.md`、五份 job 日志、`ui-test.log`、全量/S1-05 测试日志、隔离摘要与输出、`swift-build.log`、`app-xcodebuild.log`、`sim-launch.log`、`export/` 样本与往返结果及清单、`screenshots/` 七张 UI 截图 + app-build Dashboard、`metadata/` 配置副本）；artifact `14548602225`（ui-acceptance，3.99 MB）等六份附件 ID 见元数据。
- 本轮无源码改动；本地归档提交 `97ac6a8`（未推送），工作树未新增 `.swift` / 清单改动。**0.1-C 仍不予闭环**；不回填 0.1-D 结论。

### 12.8 G10 搁置决定（2026-11-20）

- 决定：G10 剩余验证不再排程（搁置），不视为通过，也不作豁免签署；0.1-C 维持未闭环，不生成统一 `ACCEPTANCE.md`。
- G10 缺口以 `Tests/Stage2/evidence/c-f5-seventh-run/C-F5-Gate-Status.md` §3.2 记录为准（截图本体无系统面板浮层、AX 谓词宽松自匹配、活动项 provider null），作为已知限制/观察项带入后续阶段；若未来重启复核，技术方向见该文件 §3.3。
- 此前排定的八轮 G10 补证任务已撤销；本机 Linux 不编译，后续若重启仍以在线 Runner 日志为准。



