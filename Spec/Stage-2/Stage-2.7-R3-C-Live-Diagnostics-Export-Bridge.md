# Stage 2.7 — R3-C Live Diagnostics Export Bridge（路线 A：引擎诊断段并入单文件导出）

> 授权输入：用户提案《先选路线 A，暂时不做路线 B》（归档 `Tests/Stage2/evidence/r3-c-pre-d70c131-ci-slice/R3-C-authorization-input.md`）。
> 决策：**路线 A 最小闭环**——打通 `Diagnostics 页面 → 引擎 scan → 共享 Store → 单文件 JSON 导出`；**不做路线 B**（ReportService 全链路活信封、Dashboard/Plugins 真实数据化、归属推断重构）。导出形态：**单文件合并**，既有信封字段顶层原样保留，新增 `diagnostics` 扩展段。
> 前置基线：CI 切片 `d70c131c6ebc0daf0a26ac920f2db5c050960ead`，590 tests / 0 failures，非界面构建 0 warning/error（见 `Tests/Stage2/evidence/r3-c-pre-d70c131-ci-slice/RUN-METADATA.md`）。

## 1. 审计断点（改代码前核实）

| 断点 | 核实结论 |
|---|---|
| 引擎是否在真机按钮里运行 | 是。`DiagnosticsViewModel.runReadOnlyDiagnostics()` → `ReadOnlyDiagnosticsEngine().scan()` → `FKDiagnosticReport`，仅渲染 Diagnostics 页下半段。 |
| 导出按钮消费什么 | `FilterKitApp.init` 注入 `StaticReportProvider(SyntheticReportFactory.previewEnvelope())`；`SettingsViewModel.exportReport()` 只序列化该信封。 |
| 引擎报告是否进入导出 | **否**。`ReportBuildInput(` 在 App/Core 零构造调用；`FKDiagnosticReport` 除 DiagnosticsViewModel 内联调用外无其他引用；`ReportProviding` 唯一实现是 `StaticReportProvider`。 |
| 结果 | 诊断页扫到的引擎行未进导出 JSON；导出永远是三条合成插件。R3-C 只补这条桥，不重构 Reporting 管线。 |

## 2. 链路与落地清单

```
Diagnostics 页面按钮（显式触发，只读）
        │
        ▼
ReadOnlyDiagnosticsEngine.scan() → FKDiagnosticReport
        │
        ▼
DiagnosticsReportMapper.section(from:) → DiagnosticsExportSection
        │
        ▼
DiagnosticsReportStore（App 内存唯一实例，Diagnostics 写 / Settings 读）
        │
        ├─ Diagnostics 页面区段（既有展示不变）
        ▼
CombinedReportEncoder.encode(envelope:diagnostics:)
        │
        ▼
单文件 JSON：信封顶层字段 + 新增 diagnostics 段
```

| 文件 | 职责 | 层 |
|---|---|---|
| `Core/Diagnostics/Export/DiagnosticsExportModels.swift` | 独立 Codable 导出模型：`DiagnosticsScanState` / `DiagnosticsExportItem` / `DiagnosticsExportSection`；neverRun / failed / running 工厂。 | Core |
| `Core/Diagnostics/Export/DiagnosticsReportMapper.swift` | 引擎报告 → 导出段纯映射；原始行键值整体进 `payload`，不丢字段。 | Core |
| `Core/Reporting/CombinedReportEncoder.swift` | 信封 + 诊断段合并编码；信封键不回写不删除；诊断段 nil 按 neverRun 空段导出。 | Core |
| `App/AppEntry/DiagnosticsReportStore.swift` | 运行期共享内存快照；状态机 `neverRun / running / completed / failed`；不持久化。 | App |
| `App/AppEntry/AppDependencies.swift` | 注入唯一 Store 实例。 | App |
| `App/AppEntry/FilterKitApp.swift` | 组合根创建 Store 并注入。 | App |
| `App/Features/Diagnostics/DiagnosticsViewModel.swift` | 扫描开始置 running；完成后映射段写入 Store；空结果记 completed。 | App |
| `App/Features/Settings/SettingsViewModel.swift` | 导出经 `CombinedReportEncoder` 合并信封与 Store 投影段。 | App |
| `App/Features/Diagnostics/DiagnosticsView.swift` / `App/Features/Settings/SettingsView.swift` | 把依赖内同一 Store 传入对应 VM。 | App |
| `Tests/Stage2/Diagnostics/DiagnosticsExportBridgeTests.swift` | 离线夹具与往返 / 兼容 / 三态用例。 | Tests |

## 3. 导出模型口径

### 3.1 `DiagnosticsScanState`

`neverRun`（从未扫描）/ `running`（进行中，不导出半成品）/ `completed`（完成，允许空条目）/ `failed`（失败，本次空条目）。

### 3.2 `DiagnosticsExportItem`

| 字段 | 口径 |
|---|---|
| `id` | `<category>:<index>` 稳定标识。 |
| `category` | roots / dynamicLibraries / plugins / filters / injectorEvidence / packages / fileOwnership / integrity / helperCandidates / helperRegistrations / applications / associations / finding。 |
| `title` | 类别主标识（路径 / 名称 / 标题）；缺失记 `Unknown`。 |
| `status` | 类别状态键取值；无状态口径为 nil，不写空串冒充结论。 |
| `detail` | 其余键按键名排序拼接 `key=value`；无剩余键为 nil。 |
| `payload` | 引擎原始行全量键值，往返不裁剪。 |

### 3.3 `DiagnosticsExportSection`

| 字段 | 口径 |
|---|---|
| `schemaVersion` | 固定 `1`。 |
| `evidenceScope` | 固定 `read-only`。 |
| `scanState` | 见 3.1。 |
| `generatedAt` | 本次扫描时间；未扫描 / 失败 / 进行中为 nil。 |
| `environment` | 引擎环境键值；未扫描为空字典。 |
| `items` | 诊断条目；未扫描 / 失败 / 进行中为空数组。 |
| `previousCompletedAt` | 上一次成功扫描时间，仅追溯；失败段不得用历史成功冒充本次结果。 |

### 3.4 类别映射键

| category | 标签键 | 状态键 |
|---|---|---|
| roots | path | status |
| dynamicLibraries | path | enumerable |
| plugins | name | source |
| filters | plugin | parse_status |
| injectorEvidence | type | scope |
| packages | package_id | status |
| fileOwnership | path | — |
| integrity | path | status |
| helperCandidates | path | executable |
| helperRegistrations | label | program_exists |
| applications | name | version |
| associations | plugin | match_type |
| finding | title | state（payload = finding.payload） |

## 4. 兼容导出口径

- 信封既有顶层键（`schemaVersion` / `generatorVersion` / `profile` / `environment` / `plugins` / `unknownItems` / `warnings`）保持原样；`diagnostics` 为新增扩展键，不覆盖旧字段。
- 未扫描：`diagnostics.scanState=neverRun`，`items=[]`，不生成 Preview/Broken/Orphan 替代数据。
- 失败与成功但为空必须区分：失败 `scanState=failed`；空结果 `scanState=completed` + 空条目。
- 重复扫描：第二次结果覆盖第一次；导出段时间戳为本次 `generatedAt`。
- `loaded` 无独立运行时证据恒 `unknown`，本桥不推断已加载。
- 日期编码 / 解码统一 ISO8601；除 `generatedAt` 外相同输入两次导出字节一致（键排序）。

## 5. 冻结边界与本轮排除

**保留只读边界**：不改 plist / 不增删移文件 / 不改规则 / 不装卸 / 不碰 dpkg 写 / 不改软链 / 不注入 / 无常驻 daemon·Helper·IPC / 不放宽 entitlement 与沙盒 / 不重写签名模块。

**本轮明确不做**：
- 路线 B：ReportService 全面接线、活信封替换合成 provider、Dashboard/Plugins 真实数据化。
- 真实插件归属推断重构；dpkg 精确清单匹配待真机取证。
- D-R2-06 真机只读诊断验收；#331 截图计数 / 去重（D1～D5）。
- 任何插件启用 / 禁用 / 注入 / 文件修改；签名模块重写；GitHub 推送。

## 6. 测试清单（A5 离线）

| # | 用例 | 状态 |
|---|---|---|
| 1 | 完成态报告全类别映射，payload 保留全部原始键值 | 离线用例已写，待 Runner 复测 |
| 2 | 空报告记 completed + 空条目，与失败态区分 | 同上 |
| 3 | 未扫描段空条目，无合成插件名 | 同上 |
| 4 | 失败段保留 `previousCompletedAt`，不冒充本次结果 | 同上 |
| 5 | 重复扫描以最新结果为准 | 同上 |
| 6 | 合并 JSON 诊断段编码 / 解码字段一致 | 同上 |
| 7 | 信封既有字段兼容保留，`diagnostics` 为新增键 | 同上 |
| 8 | `loaded=unknown` 往返后仍为 unknown | 同上 |

## 7. 待闭环（不在本轮离线认定范围）

- Runner 复测：macOS Debug `swift test` 新增 8 例通过且既有 590 例无回归；iphoneos / iphonesimulator 两侧编译结论待日志回填。
- A6 真机验收：Runner 出新构建包 → 设备安装 → 现场扫描 → 导出首份含真实 `diagnostics` 段的 JSON；当前设备所装仍是 0.1-C 旧 GUI 桩。
- 本机 Linux 无 Swift/Xcode/plutil/lipo/ldid：本轮仅完成括号配平、符号引用、残留 API 与 Package 接线静态核对，编译通过与否以 Runner 为准。

## 8. Runner 反馈切片（run `44861183809` / job `ui-acceptance`，cf741b）

> 完整事实与轨迹见 `Tests/Stage2/evidence/r3-c-run-44861183809-ui-acceptance/RUN-METADATA.md`。

- 检出 `cf741b`，代码与本地 R3-C 工作树一致；iphonesimulator 侧 R3-C 四枚新文件进入编译清单并构建启动成功，除 AppIntents 元数据提示外无 Swift warning/error。
- XCUITest 8 例：**7 passed / 1 failure**。失败唯一落在 `EmptyStateTests.testExportDisabledWithoutEnvelope`（空信封冷首跑，5s 内未找到 `settings.exportButton`）；非空态 ExportFlow / SettingsVisible / ShareSheet 均在位通过。
- 对照基线五轮（`71bc6b0`）同一空态用例通过；R3-C diff 未移除导出按钮（按钮无条件渲染，禁用只置 `.disabled`）。本轮冷首跑 session 54.22s、点按→合成事件间隔约 25s，明显慢于基线；假设 H1 冷启动时序临界 / H2 空态渲染未切换，**均未定论**——失败层级快照封在 xcresult 产物内，本会话取不到。
- 后置 G9：容器 tmp 未拉到导出 JSON 样本，校验器步骤 exit 1；样本未落盘原因待查，与空态失败分列归因。
- 本 job **不含** `swift test`：新增 8 例桥接用例与 590 例回归、iphoneos 编译结论仍待对应 job 日志回填。
- 处置：本轮不改代码、不推送；待复跑或取得 xcresult 快照后再定 H1/H2。

## 9. 真机诊断载荷基线（中间证据，非 A6 验收）

> 定位记录：`Tests/Stage2/evidence/r3-c-real-device-payload-baseline/BASELINE-METADATA.md`。设备报告本体按隐私边界不入库、不进包、不作 fixture。

- 一份真机形态的单文件导出 JSON（14,029 条诊断行，13 类齐全）被接受为 **Real Device Diagnostics Payload Baseline**：证明引擎在真机环境产出规模完整的只读诊断数据；**不证明** R3-C Store/编码器/Settings 导出链路在该次导出中运行，Build provenance 与 Export bridge provenance 均记 unknown/unverified，A6 not passed。
- 信封顶层仍是合成 preview；诊断段为独立来源。两段环境不一致属路线 A 既定边界，本轮不改顶层环境、归属或 Dashboard 数据来源；环境统一与真实信封构建归路线 B。
- 基线计数（对照值，非硬指标）：fileOwnership 9,255 / integrity 3,466 / packages 376 / applications 266 / helperRegistrations 534 / dynamicLibraries 16 / injectorEvidence 28 / associations 8 / finding 10，另有 roots 5、plugins 8、filters 8。
- 往返验收（R3-C-A6-Codable Round-Trip）留待 Runner：全量解码、13 类保留、nil status 不补默认、payload 键值一致、`loaded=unknown` 不变、无兜底伪数据；按模型字段语义比较而非 JSON 字符串比较；另补空扫描/失败扫描 fixture。
- `environmentSource` 建议字段当前模型不存在；后续若加须为可选且单独授权，本轮不动冻结模型。
- R3-C2 真实信封闭环（C2-01～C2-07）仅记录方向，未授权编码；D-R2-06、#331 继续冻结。
