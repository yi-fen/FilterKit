# Stage 2.8 — 0.1-E3 Plugin Detail & App Association Explorer（规格冻结）

## §1 批次安排与 E3 定位

### §1.1 批次口径（沿用附件一）

- E1 Plugin Data Foundation：本地落地，待 E4 统一 Runner 复验。
- E2 Plugin List & Discovery：本地落地，待 E4 统一 Runner 复验。
- **E3 Plugin Detail & App Association Explorer（本轮）**：本地静态检查 + 局部离线测试，不提前要求完整 Runner。
- E4：Repository 单实例接入、页面统一接线、真实空/错态、完整 Runner 矩阵（E4-01～12）。
- E5 启用/禁用/删除/Filter 修改/注入不授权；0.1-D 验收状态独立，E4 通过不自动关闭 0.1-D。

### §1.2 E3 目标

在 E1 `PluginSnapshot` 之上做只读投影与双向关联浏览：

1. 插件详情投影：基本信息、三态、文件信息、来源/证据、关联信息。
2. App 详情投影：Bundle ID、名称、可执行文件、版本、关联插件。
3. 双向关联 Resolver：插件 → App、App → 插件，共用同一份快照投影。
4. SwiftUI 详情/列表页面骨架；Repository 注入与页面挂入 Tab 留 E4。

### §1.3 E3 不做

- 不重新从诊断报告构造第二套插件数据；不新增/修改 E1 公共模型字段。
- 不扫描设备、不访问文件系统、不触发 Repository `refresh()`；不接 Repository 实例。
- 不推断 loaded 状态；不把全局规则/未匹配/无效/未确认规则折算成「已关联 App 数量」。
- 不做启停/删除/编辑/注入；不放行 entitlement 与沙盒；不推送远端。

## §2 架构约束（强制）

1. E3 Core 只使用 Foundation；不依赖 SwiftUI、不依赖 Repository 实现、不访问文件系统。
2. 详情与 App 详情均由 E1 `PluginSnapshot` 投影得到；E2 `PluginListEntry` 不作为 E3 完整数据来源。
3. 双向浏览方向消费同一份快照投影；禁止两个页面分别取不同快照。
4. 关联记录只展示 E1 已建立的证据；E3 不根据 Bundle ID 自行推断新关联，不重新解释注入规则。
5. installed / configured / loaded 三态分行展示，不合并；loaded 无运行时证据恒 unknown，文案不得出现「Not Loaded」。
6. 关联五类语义保留：exactMatch 才计入精确关联数量；globalRule 单独展示；unmatchedTarget 不冒充已关联；invalidConfiguration 不当有效规则；unresolved 不强制归类。

## §3 Core Detail 层（`Core/Plugins/Detail/`）

### §3.1 枚举复用（偏差记录）

- 关联分类直接复用 E1 `FKAssociationType`（exactMatch / globalRule / unmatchedTarget / invalidConfiguration / unresolved），**不新增第二套公共关联枚举**。
- 状态直接复用 `FKPluginState`（confirmed / absent / unknown / unverified）；投影层不把状态收窄成字符串再由 Core 解释。
- 备忘录模板的 `evidence.inferred` 在 E1 无来源置信度字段，本轮不开放（沿用 E2 偏差记录）。

### §3.2 `PluginAssociationEntry.swift`

E1 `FKPluginAssociation` → 关联展示投影，不制造新的关联事实：

- `id: String`（沿用 `FKPluginAssociation.id`）
- `pluginID: String`
- `applicationID: String?`（`appBundleID`，空串归 nil）
- `category: FKAssociationType`
- `matchType: String`（原值 bundle / executable / none）
- `isGlobal: Bool`
- `matchedAppCount: Int` / `unmatchedTargetCount: Int`
- `evidenceDescription: String?`（`evidence` 原值）
- `loaded: String`（原值，本轮恒 unknown）

### §3.3 `PluginDetailEntry.swift`

- `id / displayName / fileName / filePath`：id 沿用 `FKPlugin.id`；fileName 回退链 dylib 基名 → plist 基名 → 名称；filePath dylib → plist → 空串。
- `installed / configured / loaded: FKPluginState`：原样透传，不合并、不升级。
- `fileSize: Int64?`、`fileHash: String?`（插件行 raw 无 hash 键时为 nil，不虚构）。
- `packageIdentifier: String?`、`packageOwners: [String]`、`sourceRaw: String`、`sourceEvidence: String?`、`parseStatus: String?`、`isGlobalRule: Bool`。
- `integrityState: FKPluginState`：E1 快照未链接插件级完整性记录，本轮恒 `.unknown`；完整性行接入留 E4。
- `associations: [PluginAssociationEntry]`。
- 计算属性：`exactMatchCount`（仅 `.exactMatch`）；`count(of:)` 按分类计数；不提供合并后的「关联 App 总数」。

### §3.4 `ApplicationDetailEntry.swift`

- `id: String`（= bundleID）、`displayName`、`bundleIdentifier`、`executable: String?`、`version: String?`、`isSystem: Bool`。
- `associations: [PluginAssociationEntry]`；`exactMatchCount` 仅统计 `.exactMatch`。
- associations 只代表静态关联证据，不代表 App 运行时真的加载了对应插件。

### §3.5 `PluginDetailProjection.swift` / `ApplicationDetailProjection.swift`

- `PluginDetailProjection.entry(from: FKPlugin)` 纯映射；`detail(forPluginID:snapshot:)` 经 `pluginByID` 回查，缺失返回 nil（不生成虚构详情）。
- `ApplicationDetailProjection.entry(from: FKApplication, associations: [FKPluginAssociation])`；`detail(forAppID:snapshot:)` 经 `applicationByID` 回查，缺失返回 nil。
- `ApplicationDetailProjection.allAssociationEntries(from:)`：快照关联行 → 关联投影数组，供 Resolver 两个方向共用。
- 原始 `raw` 证据不在投影层裁剪：E3 不展示的原始键保留在 E1 `FKPlugin.raw`，后续批次回查。

### §3.6 `PluginAssociationResolver.swift`

纯结构体、无状态、Sendable：

- `associations(forPluginID:from:)` / `associations(forApplicationID:from:)`：按方向过滤。
- `exactMatches(forPluginID:from:)` / `exactMatches(forApplicationID:from:)`：方向 + exactMatch 过滤。
- 结果按 `id` 去重保序；输入顺序稳定，重复查询结果确定。
- Resolver 只在投影数组上过滤，不回查快照、不重新配对。

## §4 App 浏览器层（`App/Features/Plugins/Detail/`）

> 既有信封版 `PluginDetailView(plugin: Models.Plugin)` 与 E2 浏览器层本轮不改；E3 页面接收已投影条目，Repository 快照喂入与导航挂接留 E4。

### §4.1 ViewModels（`Detail/ViewModels/`）

- `PluginDetailViewModel` / `ApplicationDetailViewModel`：`@Observable`；持有 `detail`、`isLoading`、`errorMessage`；`setDetail` / `setLoading` / `setError`。
- 不持有 Repository、不触发扫描；不设置 `loaded = true/false`，loaded 状态由 E1 证据提供。

### §4.2 Views（`Detail/Views/`）

- `PluginDetailView.swift`：Plugin 头（名称/文件名）、Installation 三态分行、File Information（路径/大小/Hash/所属包）、Evidence（来源原值/来源证据/解析状态）、App Associations 分段。
- `ApplicationListView.swift`：诊断发现的 App 列表，行展示名称/Bundle ID/精确关联数，点击进 App 详情。
- `ApplicationDetailView.swift`：Application 段（名称/Bundle ID/可执行文件/版本）、Plugin Associations 分段；点击关联插件回插件详情（导航目的地 E4 接线，本轮占位）。
- `PluginAssociationSection.swift`：按五类分组展示与分类计数；无关联记录显示「No association evidence found」（诊断事实，不写「不支持任何 App」）。
- `PluginEvidenceSection.swift` / `PluginFileInformationSection.swift`：详情分区封装。

### §4.3 Components（`Detail/Components/`）

- `PluginStatusCard.swift`：installed/configured/loaded 三枚 `StatusBadgeView` 分行，分级文案复用 E2 `BrowserLabels`。
- `AssociationRow.swift`：分类标题（英文 UI 体系）+ Bundle ID + 证据说明；分类标题唯一落点。
- `ApplicationRow.swift`：App 名称 + Bundle ID + 精确关联数。

### §4.4 文案口径

沿用既有英文 UI；unknown / unverified 不等于失败；颜色分级只做界面表达，不改写 Core 状态语义；loaded unknown 显示「Unknown / Runtime state not verified」，不显示「Not Loaded」。

## §5 离线测试矩阵（`Tests/Stage2/Plugins/PluginDetailTests.swift`）

| 编号 | 测试 | 验收标准 |
| --- | --- | --- |
| E3-01 | 插件详情映射 | FKPlugin 字段正确映射到 PluginDetailEntry |
| E3-02 | App 详情映射 | FKApplication 字段正确映射到 ApplicationDetailEntry |
| E3-03 | 文件信息 | 路径/大小/Hash 正确透传；无 hash 键时为 nil |
| E3-04 | 软件包归属 | 无归属证据时不虚构包标识/归属列表 |
| E3-05 | installed 状态 | 原始证据透传，不反推 |
| E3-06 | configured 状态 | 原始证据透传，不反推 |
| E3-07 | loaded 状态 | 无运行时证据仍为 unknown |
| E3-08 | exactMatch | 只计算精确关联 |
| E3-09 | globalRule | 不计入精确关联数量 |
| E3-10 | unmatchedTarget | 保留未匹配分类，不显示为已关联 |
| E3-11 | invalidConfiguration | 保留无效配置分类 |
| E3-12 | unresolved | 保留未确认分类，不强制归类 |
| E3-13 | 插件 → App | Resolver 正确按插件方向查询关联 |
| E3-14 | App → 插件 | Resolver 正确按 App 方向查询关联 |
| E3-15 | 无关联记录 | 投影为空数组，空态事实成立 |
| E3-16 | 不存在的插件 ID | 详情返回 nil，不生成虚构详情 |
| E3-17 | 不存在的 App ID | 详情返回 nil，不生成虚构详情 |
| E3-18 | 重复关联 | 同 id 关联不重复展示 |
| E3-19 | 多插件关联一个 App | App 方向结果完整 |
| E3-20 | 多 App 关联一个插件 | 插件方向结果完整 |
| E3-21 | Snapshot 一致性 | 两个浏览方向使用同一份快照投影 |
| E3-22 | 只读隔离 | 投影/Resolver 纯函数；不触发 Repository 扫描，无文件/配置/dpkg 写入 |

夹具经 E1 `PluginDataMapper.mapSnapshot` 构造快照，再由 E3 投影；不访问文件系统。

## §6 兼容性与只读边界

- 不改 `Models.Plugin` / `ReportEnvelope` / `CombinedReportEncoder` / 导出 Mapper / 既有信封视图与 E2 浏览器层。
- 新增 Core Detail 类型不进入合并导出；App 详情层不接合成桩数据。
- 全程只读：无 plist/dylib/dpkg/软链写入、无注入、无 Helper/IPC/daemon、无 entitlement 放行。
- 依赖方向：App → Core → Models/Adapters；Core Detail 层不反向依赖 App/Presentation。

## §7 E3 验收层次（本地静态，E4 统一 Runner 复核）

- **G1 Core Detail**：投影/Resolver 编译通过；映射、双向查询、去重、空态与缺失 ID 测试通过。
- **G2 App 展示层**：详情 VM 查询行为正确；三态分行；关联五类分段；空关联事实态正确；列表数据不含 Synthetic Plugin。
- **G3 架构与安全**：无第二套快照；双向方向同源；不重复制造关联；不改 E1 原始数据；loaded=unknown 语义不变；不改信封与导出 JSON；不触碰越狱文件；无启停/删除操作。

## §8 待 E4 闭环

- Repository 单一实例接入；同一快照供 E2 列表、E3 插件详情、App 详情与 Dashboard 消费；手动刷新计数口径。
- 详情/列表页面挂入导航；E2 浏览器行 → 插件详情、插件详情 ↔ App 详情双向导航接线；真实空/错态接 Repository 失败分支。
- 插件级 Hash/完整性记录、来源置信度（Confidence）接入后回填详情字段。
- 完整 Runner 矩阵 E4-01～12：Core/Device/Simulator 编译、598 既有 + E1 9 + E2 16 + E3 22 测试、单次扫描、无合成回退、状态语义、只读隔离、UI 自动化。

## §9 本轮本地静态核对（2026-11-21，待 Runner 复验）

- Core Detail 6 枚（AssociationEntry/PluginDetailEntry/ApplicationDetailEntry/两个 Projection/Resolver）+ 离线测试 1 枚 + App Detail 11 枚（2 ViewModel / 6 View / 3 Component）；`Package.swift` Core 与 Stage2Tests 显式 sources 与磁盘一一对应；App 目录由 XcodeGen glob 纳入，不进 SPM sources。
- 括号 / 圆括号配平逐文件复核；Core Detail 仅 `import Foundation`；依赖方向 App → Core → Models/Adapters，Detail 层不反向依赖 App/Presentation。
- 关联分类复用 E1 `FKAssociationType`，状态复用 `FKPluginState`，未新增第二套公共枚举；无 FileManager 写接口、无 `dlsym`/`jbroot()`/注入/dpkg 写/软链改动；Resolver 为纯结构体无状态；E3-22 验证投影/Resolver 前后 Repository `refreshCount` 不变。
- 字段口径核对：插件级 Hash 取 `raw["hash"]`（无键为 nil）；完整性状态本轮恒 `.unknown`（E1 快照未链接插件级完整性记录，待 E4 回填）；归属取 `FKPluginSource.packageIdentifier/packageOwners`，无证据不虚构；loaded 恒 unknown。
- 偏差 / 遗留：备忘录模板的 `evidence.inferred` 因 E1 无来源置信度字段未开放；App 可执行文件字段为 `FKApplication.executable`（E1 无全量应用路径）；插件详情 ↔ App 详情双向导航目的地由 E4 统一接线，本轮关联行不挂插件导航；既有信封版 `PluginDetailView(plugin:)` 与 E2 浏览器层不改。
- 本机 Linux 无 Swift/Xcode；emit-module、598 既有 + E1 9 + E2 16 + E3 22 例离线测试与 iOS 两侧编译结论以 Runner 下一轮日志为准；无 Runner 日志前不认定编译通过、不标注真机验收。
