# Stage 2.8 — 0.1-E2 Plugin List & Discovery（规格冻结）

状态：**规格冻结，进入 E2 实现**
授权：用户授权 E2 插件列表、搜索与筛选；E1～E4 作为连续开发批次，E1～E3 只做静态检查与局部测试，**E4 统一完整 Runner 验收**；本轮不推送 GitHub。
基线：HEAD `cfc3a9a`（E1 已本地落地待 Runner）；E1 模型/Repository/快照以磁盘源码为准，备忘录代码为模板，不直接合并。

---

## §1 批次安排与 E2 定位

### §1.1 批次调整（附件一）

| 阶段 | 内容 | 验证方式 |
| --- | --- | --- |
| E1 | Plugin Data Foundation | 已本地完成，待 E4 统一复验 |
| E2 | Plugin Browser：列表 / 搜索 / 筛选 / 排序 | 本地静态检查 + 查询层离线测试 |
| E3 | Plugin Details & Associations | 本地静态检查 + 局部测试 |
| E4 | App DI、真实快照接线、空错态、统一验收 | 完整 Runner 验收（E4-01～12 矩阵） |

- E1～E3 不分别跑完整 Runner；每阶段必须完成：源码静态检查、新增文件与 `Package.swift` 对应、依赖方向检查、只读边界检查、基础测试代码。
- 架构错误立即修正，不带入 E4。
- 0.1-D 验收状态独立：E4 全部通过不自动关闭 0.1-D；A6 完整 JSON、DEB 安装启动、EmptyState 根因仍 pending。

### §1.2 E2 目标

E2 不只把 E1 数据展示成列表，而是建立一套**纯内存、无副作用、可测试**的插件查询层，供 E3 详情/关联与 E4 DI 复用。核心链路：

```
ReadOnlyDiagnosticsEngine → FKDiagnosticReport → PluginDataMapper
  → PluginSnapshot → DiagnosticPluginRepository → PluginListQueryEngine
  → PluginBrowserViewModel → PluginBrowserView
```

### §1.3 E2 不做

- 不直接调用 `ReadOnlyDiagnosticsEngine`；不自行重新扫描文件系统；不创建第二套插件缓存。
- 不接 Repository 真实数据（E4）；ViewModel 以注入 entries 方式工作。
- 不实现 E3 详情数据读取；详情入口仅占位导航。
- 不做启用/禁用/删除/Filter 修改；不引入合成插件回退。
- 不改 `ReportEnvelope`、导出 JSON 结构、R3-C 桥接链路。

## §2 架构约束（强制）

1. E2 不绕开 E1 Repository 自行读取诊断数据。
2. 搜索、筛选、排序全部基于 E1 已生成的 `PluginSnapshot` 投影，不触发重新扫描。
3. 不为填充列表生成 Synthetic Plugin；扫描失败/空快照走空态或错误态。
4. 静态匹配不把 `loaded` 从 unknown 改为 loaded。
5. 列表展示不把 installed / configured / loaded 合并成一个状态，三态分行展示。
6. `loaded` 是运行时状态，**不进入普通证据筛选维度**；未来取得可靠运行时证据再单独设计 Runtime State Filter。

## §3 Core 查询层（`Core/Plugins/Query/`）

### §3.1 `PluginListFilter.swift`

```swift
public enum PluginConfigurationFilter: String, CaseIterable {
    case all, configured, notConfigured, unverified, unknown
}
public enum PluginAssociationFilter: String, CaseIterable {
    case all, associated, unassociated, globalRule, unmatched, invalid, unresolved
}
public enum PluginEvidenceFilter: String, CaseIterable {
    case all, confirmed, absent, unverified, unknown
}
public struct PluginListFilter: Equatable {
    public var configuration: PluginConfigurationFilter
    public var association: PluginAssociationFilter
    public var evidence: PluginEvidenceFilter
    public init(configuration: .all, association: .all, evidence: .all)
    public static let all: PluginListFilter
}
```

**状态映射口径（基于 E1 真实类型，不使用含义相近的猜测字符串）：**

- 配置筛选作用于 `FKPlugin.status.configured`：
  - `configured` ↔ `.confirmed`；`notConfigured` ↔ `.absent`；`unverified` ↔ `.unverified`；`unknown` ↔ `.unknown`。
- 证据筛选作用于 `FKPlugin.status.installed`：`confirmed / absent / unverified / unknown` 一一对应。
- 关联筛选作用于条目 `associationCategories: Set<FKAssociationType>`：
  - `associated` ↔ 含 `.exactMatch`；`unassociated` ↔ 无任何关联条目；
  - `globalRule` ↔ 含 `.globalRule`；`unmatched` ↔ 含 `.unmatchedTarget`；
  - `invalid` ↔ 含 `.invalidConfiguration`；`unresolved` ↔ 含 `.unresolved`。
  - 一条插件可同时命中多个分类；筛选为「含该分类」语义。

**偏差记录**：备忘录模板的 `evidence.inferred` 在 E1 无对应来源置信度字段（`FKPluginSource` 未携带 Confidence），本轮不开放；待来源置信度接入后再补。

### §3.2 `PluginListSort.swift`

```swift
public enum PluginListSort {
    case nameAscending
    case nameDescending
    case evidence   // 内部扩展项，E2 不开放 UI；证据等级排序优先级待 E3/E4 确认
}
```

E2 第一版 UI 只开放名称升序/降序。

### §3.3 `PluginListQuery.swift`

```swift
public struct PluginListQuery: Equatable {
    public var searchText: String
    public var filter: PluginListFilter
    public var sort: PluginListSort
    public init(searchText: "", filter: .all, sort: .nameAscending)
    public static let empty: PluginListQuery
}
```

Query 本身不执行扫描、不修改 Repository。

### §3.4 `PluginListEntry.swift`（列表投影模型）

不替代 `FKPlugin`，不改变原始诊断报告；保留回查原始模型所需标识。

- `id: String`（沿用 `FKPlugin.id`）
- `displayName: String`
- `fileName: String`（dylib 基名 → plist 基名 → 名称回退）
- `filePath: String`（dylib 路径 → plist 路径 → 空串）
- `version: String?`
- `packageIdentifier: String?`
- `bundleIdentifiers: [String]`（关联 App Bundle ID + 包标识，去重排序）
- `installed: FKPluginState` / `configured: FKPluginState` / `loaded: FKPluginState`（原样透传 E1 三态，不合并）
- `associationCategories: Set<FKAssociationType>`
- `exactMatchCount: Int`（仅 `.exactMatch` 计数，行内「关联 App 数量」口径）
- `searchTokens: [String]`（名称/文件名/包标识/来源原值/版本）

### §3.5 `PluginListProjection.swift`

`PluginListEntry.entry(from: FKPlugin)` 纯映射；`entries(from: [FKPlugin])` 批量投影。原始 `raw` 证据不进投影层丢弃——E3 详情经 `pluginByID` 回查快照取原始记录。

### §3.6 `PluginListQueryEngine.swift`

纯结构体，无状态、无副作用：

- `execute(entries:query:) -> [PluginListEntry]`：搜索 → 条件筛选 → 排序。
- 搜索：关键词 trim 后为空返回全量；大小写 + 变音符号不敏感；命中 `displayName / fileName / filePath / bundleIdentifiers / searchTokens` 任一。
- 筛选：三维度 AND 组合。
- 排序：名称 `localizedStandardCompare` 升/降序；`.evidence` 暂按 installed 状态原始顺序稳定返回（不开放 UI）。

## §4 App 浏览器层（`App/Features/Plugins/Browser/`）

> 目录沿用现有 `App/Features/Plugins/` 规范；既有信封版 `PluginListView` / `PluginListViewModel`（XCUITest 标识 `plugins.list` / `plugins.segment` / `plugins.row.*`）本轮**不改**，E4 统一切换到浏览器层。

### §4.1 `PluginBrowserViewModel.swift`

- `@Observable`，`@MainActor` 语义由 App 层保证；持有 `cachedEntries: [PluginListEntry]` 与查询引擎。
- 发布状态：`entries: [PluginListEntry]`（查询结果）、`searchText`、`filter`、`sort`、`loadState`、`errorMessage: String?`。
- `loadState`：`neverLoaded / loading / loaded / empty / failed(String)`；`empty` 与 `failed` 严格区分。
- `setEntries(_:)`：注入快照投影结果（E4 由 Repository 快照喂入）；注入后重放当前查询。
- `applyQuery()`：仅在内存缓存上执行引擎查询，**不调用 Repository/引擎**。
- `clearFilters()`：清空关键词、筛选、排序回默认。
- 本轮不持有 Repository 实例；不触发 `refresh()`。

### §4.2 Views

- `PluginBrowserView.swift`：NavigationStack；按 `loadState` 分流 loading / failed / empty / 列表；`.searchable` 接 `searchText`；筛选入口绑定 `filter`；详情导航为 E3 占位。
- `PluginBrowserRow.swift`：名称 + 版本、文件名、三态分行标签（installed/configured/loaded）、精确关联数量；loaded unknown 文案为「Unknown / Runtime state not verified」，**不得显示「Not Loaded」**。
- `PluginSearchBar.swift`：搜索框封装（占位文案「Search plugins, file name or Bundle ID」）。
- `PluginFilterView.swift`：配置 / 关联 / 证据三维筛选选择器；loaded 不出现为筛选项。

### §4.3 文案口径

内部状态 → 展示文案沿用既有英文 UI 体系；未知不等于未加载。颜色分级只做界面表达，不改写 Core 状态语义；unknown / unverified 不统一降级为红色错误。

## §5 离线测试矩阵（`Tests/Stage2/Plugins/PluginListQueryTests.swift`）

| 编号 | 测试 | 预期 |
| --- | --- | --- |
| E2-01 | 空搜索 | 返回全部条目 |
| E2-02 | 按名称搜索 | 正确命中 |
| E2-03 | 大小写搜索 | 不区分大小写 |
| E2-04 | 按 dylib 名称搜索 | 正确命中 |
| E2-05 | 按路径搜索 | 正确命中 |
| E2-06 | 按 Bundle ID 搜索 | 正确命中 |
| E2-07 | 配置状态筛选 | 只返回对应配置态 |
| E2-08 | 关联状态筛选 | 只返回对应关联分类 |
| E2-09 | 证据状态筛选 | 只返回对应 installed 态 |
| E2-10 | 多条件组合 | 三维 AND 同时生效 |
| E2-11 | 名称升序 | 排序正确 |
| E2-12 | 名称降序 | 排序正确 |
| E2-13 | 无搜索结果 | 返回空数组 |
| E2-14 | 空插件快照 | 不生成假数据，条目为空 |
| E2-15 | loaded 状态 | 未经运行时验证仍为 unknown |
| E2-16 | 搜索期间不扫描 | Repository `refreshCount` 在查询前后不变 |

夹具经 E1 `PluginDataMapper.mapSnapshot` 构造快照，再投影为条目，覆盖 E1→E2 链路；不访问文件系统。

## §6 兼容性与只读边界

- 不改 `Models.Plugin` / `ReportEnvelope` / `CombinedReportEncoder` / 导出 Mapper / 既有信封 ViewModel 与视图。
- 新增 Core 查询类型不进入合并导出；App 浏览器层不接合成桩数据。
- 全程只读：无 plist/dylib/dpkg/软链写入、无注入、无 Helper/IPC/daemon、无 entitlement 放行。
- 依赖方向：App → Core → Models/Adapters；Core 查询层不反向依赖 App/Presentation。

## §7 E2 验收层次（本地静态，E4 统一 Runner 复核）

- **G1 Core 查询层**：Query/Filter/Sort/Entry/Projection/Engine 编译通过；搜索/筛选/排序/空结果测试通过。
- **G2 App 展示层**：视图模型查询行为正确；空态 / 搜索无结果 / 错误态分流正确；列表数据不含 Synthetic Plugin（真实数据注入留 E4）。
- **G3 架构与安全**：无第二套快照；查询不重复扫描；不改 E1 原始数据；loaded=unknown 语义不变；不改信封与导出 JSON；不触碰越狱文件；无启停/删除操作。

## §8 待 E4 闭环

- Repository 单一实例接入、同一快照供列表/详情/App 页消费；手动刷新计数口径。
- 浏览器视图替换既有信封版列表并挂入 Tab；真实空/错态接 Repository 失败分支。
- 完整 Runner 矩阵 E4-01～12：Core/Device/Simulator 编译、598 既有 + E1 9 + E2 查询 + E3 测试、单次扫描、无合成回退、状态语义、只读隔离、UI 自动化。

## §9 本轮本地静态核对（2026-11-21，待 Runner 复验）

- Core 查询层 6 枚（Filter/Sort/Query/Entry/Projection/Engine）+ 离线测试 1 枚 + App 浏览器层 6 枚（ViewModel/Labels/Row/SearchBar/FilterView/View）；`Package.swift` Core 与 Stage2Tests 显式 sources 与磁盘一一对应；App 目录由 XcodeGen glob 纳入，不进 SPM sources。
- 括号 / 圆括号配平逐文件复核；Core 查询层仅 `import Foundation`；依赖方向 App → Core → Models/Adapters，查询层不反向依赖 App/Presentation。
- 无 FileManager 写接口、无 `removeItem`/`createDirectory`、无 `dlsym`/`jbroot()`/注入/dpkg 写/软链改动；引擎为纯结构体无状态；E2-16 验证搜索 / 筛选 / 排序前后 Repository `refreshCount` 不变。
- 状态映射核对：配置筛选作用于 `configured`、证据筛选作用于 `installed`、关联筛选作用于 `associationCategories`；三维 AND；`loaded` 不进入筛选维度；`loaded` 恒 unknown，展示文案不出现「Not Loaded」。
- 偏差 / 遗留：搜索框为独立封装 `PluginSearchBar`（非 `.searchable` modifier），绑定同一 `searchText`；`.evidence` 排序内部稳定保留原序、不开放 UI；`evidence.inferred` 因 E1 无来源置信度字段未开放；既有信封版 `PluginListView` / `PluginListViewModel` 本轮不改，E4 统一切换。
- 本机 Linux 无 Swift/Xcode；emit-module、598 既有 + E1 9 + E2 16 例离线测试与 iOS 两侧编译结论以 Runner 下一轮日志为准；无 Runner 日志前不认定编译通过、不标注真机验收。
