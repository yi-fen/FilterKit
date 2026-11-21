# Stage 2.8 — 0.1-E4 Plugin Feature Integration & Dependency（规格冻结）

状态：**规格冻结，进入 E4 实现**
授权：用户授权 E4 插件功能统一接入与依赖注入；E1～E4 为连续开发批次，E1～E3 本地落地待本轮统一 Runner 复验；本轮不推送 GitHub。
基线：HEAD `d9dabeb`（E3 已本地落地待 Runner）；E1/E2/E3 模型、投影、Repository、ViewModel 以磁盘源码为准，备忘录代码为集成参考，不直接合并。

---

## §1 批次安排与 E4 定位

### §1.1 批次口径（沿用附件）

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| E1 | Plugin Data Foundation（模型 / Mapper / Repository / Snapshot） | 本地完成，待 E4 统一复验 |
| E2 | Plugin List & Discovery（纯内存查询层 + 浏览器视图骨架） | 本地完成，待 E4 统一复验 |
| E3 | Plugin Detail & App Association Explorer（详情投影 + 双向 Resolver + 详情视图骨架） | 本地完成，待 E4 统一复验 |
| **E4** | **Plugin Feature Integration & Dependency：Repository 单实例、统一快照共享、页面接线、统一导航、真实空/错态、集成测试与 Runner 验收准备** | 本轮 |
| E5 | 启用 / 禁用 / 删除 / Filter 修改 / 注入 | **不授权**；仅留边界 |

- E4 核心原则（备忘录原文口径）：**一个 Repository、一次诊断扫描、一份 PluginSnapshot、多个页面共享、统一导航**。
- E4 仍为只读阶段：不提前实现启用 / 禁用 / 删除 / 改 Filter / 安装 / 注入；0.1-D 验收状态独立，E4 通过不自动关闭 0.1-D。
- 0.1-D 既有 pending 项（A6 真机完整 JSON、DEB 真机安装启动、EmptyState 根因、H4/H5、C1～C5、G10～G15/R4-G）沿用 pending/unknown，E4 不代为签署。

### §1.2 E4 目标

1. Repository 全 App 插件功能唯一实例；Store 持有统一快照与三类投影，E2 列表、E3 插件详情、App 详情、App 列表消费同一份数据。
2. 统一数据加载：初次进入插件功能执行一次 `refresh()`；搜索 / 筛选 / 详情跳转 / App 浏览 / 多次导航均不重复扫描；手动刷新有明确入口，页面 `onAppear` 不自动 `refresh()`。
3. E2 浏览器接真实 E1 数据：列表 / 搜索 / 筛选 / 排序 / 加载 / 空 / 错态；不再使用 Preview 或 Synthetic Plugin 填充。
4. E3 详情接线：插件详情、App 列表、App 详情、插件 → App、App → 插件双向导航；两方向同源快照与关联投影。
5. 真实状态管理：`neverLoaded / loading / loaded / empty / failed` 五态严格区分；扫描失败 ≠ 无插件；从未扫描 ≠ 空数据；未知状态不强转失败 / 不存在，不显示成未安装 / 未加载。
6. 统一导航：一个插件功能入口，内部单一 `NavigationStack`；E2/E3 不各自建导航容器；详情 / App 详情不单独开 Tab。

### §1.3 E4 不做

- 不重写 E1 Repository、不重建 E2 查询引擎、不重建 E3 Resolver；不改 `FKPlugin` 等 E1 公共模型；不改 `ReportEnvelope` / 导出 Mapper / `CombinedReportEncoder`。
- 不新增 Synthetic Plugin；不把 `loaded` 自动设为 loaded；页面不单独创建 Repository；页面 `onAppear` 不自动 refresh。
- 不实现启用 / 禁用 / 删除 / 改 Filter plist / 改 dpkg 状态 / 注入 dylib / Helper / IPC / daemon；不放行 entitlement 与沙盒。
- 不接入 Dashboard 插件计数信封来源切换（本轮 Dashboard 维持既有信封投影，留后续）；不做插件级完整性记录与来源置信度补造。

## §2 架构约束（强制）

1. 依赖方向：App → Core → Models/Adapters；Core Integration 层只使用 Foundation / Observation，不依赖 SwiftUI、不访问文件系统。
2. 快照唯一：`PluginFeatureStore` 是插件功能唯一快照持有者；E2/E3 ViewModel 不各自缓存完整插件数据，只消费 Store 投影出的条目。
3. 投影同源：列表条目、插件详情、App 详情、关联条目在 Store 一次重建内由同一份 `PluginSnapshot` 经 E2/E3 现有公开映射接口生成；禁止两个页面分别取不同快照。
4. 只读边界：Store 与接线层不暴露任何写操作接口；无 FileManager 写、无 plist/dylib/dpkg/软链改动、无注入、无 daemon/Helper/IPC。
5. 证据口径不变：`loaded` 无运行时证据恒 unknown；Hash 无证据 nil；Integrity 未关联恒 `.unknown`；来源不明确不虚构软件包归属；五类关联语义保留，exactMatch 才计精确关联数。
6. 测试夹具经 E1 `PluginDataMapper.mapSnapshot(report:)` 构造快照；离线测试不访问文件系统、不触发真实目录枚举。

## §3 Core Integration 层（`Core/Plugins/Integration/`）

> 落地位置偏差记录（D3）：备忘录建议 Store 落 App 层；本轮 Store 与状态枚举落 Core，使 Stage2Tests 可 `@testable import Core` 完成离线集成测试；路由与根视图属 SwiftUI 接线，落 App 层。Core 内不引入 SwiftUI。

### §3.1 `PluginFeatureState.swift`

统一五态（Equatable、Sendable），与备忘录 §3 一致：

- `neverLoaded`：尚未扫描（等待读取）。
- `loading`：正在扫描（ProgressView）。
- `loaded`：扫描成功且存在插件。
- `empty`：扫描成功、插件数为 0。
- `failed(String)`：扫描失败且无可用旧数据。

计算属性：`isLoading`（仅 `.loading`）、`errorMessage`（仅 `.failed`）、`hasLoaded`（`.loaded/.empty/.failed` 为 true）。

### §3.2 失败结果接缝（D1，偏差记录）

E1 真实协议为**同步、非 throwing**：`refresh() -> PluginSnapshot`，引擎 `scan()` 同步不抛错；权限拒绝 / 目录不可达在引擎内部兜住，体现为 findings 条目与空 / 部分快照。备忘录示例的 `try await repository.refresh()` 不适用真实签名，**E4 不修改 E1 公共接口迁就示例**。

Core 内定义结果枚举（与 Store 同文件）：

```swift
public enum PluginRefreshOutcome: Equatable, Sendable {
    case snapshot(PluginSnapshot)
    case failure(String)
}
```

`PluginFeatureStore` 初始化可注入 `refreshProvider: () -> PluginRefreshOutcome?`；默认实现包装 `repository.refresh()` 返回 `.snapshot`。真实 App 路径不会走到 `.failure`（引擎 / Repository 错误通道尚未开放，留后续批次）；`.failure` 分支供离线测试落地 failed / 旧数据保留语义，真机错误信号待引擎开放错误通道后回填。

### §3.3 `PluginFeatureStore.swift`

`@Observable public final class`，持有：

- `state: PluginFeatureState`（初始 `.neverLoaded`）
- `snapshot: PluginSnapshot?`
- `pluginEntries: [PluginListEntry]`
- `pluginDetails: [PluginDetailEntry]`
- `applicationDetails: [ApplicationDetailEntry]`
- `associationEntries: [PluginAssociationEntry]`（Resolver 双向共用输入）
- `lastRefreshError: String?`
- 私有：`repository: any PluginRepository`、`resolver: PluginAssociationResolver`、`refreshProvider`、`hasStartedInitialLoad`、`isRefreshing`。

方法：

- `loadIfNeeded()`：守卫 `hasStartedInitialLoad`，初次进入只触发一次 `refresh()`；重复调用直接返回。
- `refresh()`：并发守卫 `isRefreshing`（D4：协议同步，守卫布尔位即可；备忘录 `refreshTask` async 复用形态待 Repository 异步迁移后再评估）；置 `.loading` → 取 `refreshProvider()` 结果：
  - `.snapshot`：替换 `snapshot`，重建三类投影；`pluginEntries` 为空 → `.empty`，否则 `.loaded`。
  - `.failure`：记录 `lastRefreshError`；无旧快照 → `.failed(message)`；有旧快照 → **保留旧快照与旧投影**，状态 `.loaded`，由 UI 展示「无法刷新插件数据，正在显示上一次成功读取的数据」。
- 查询辅助（全部读缓存，不二次扫描）：`pluginDetail(id:)`、`applicationDetail(id:)`、`associations(forPluginID:)`、`associations(forApplicationID:)`，后两者经 E3 Resolver 在同一份 `associationEntries` 上双向过滤。

投影重建（`rebuildProjections(from:)`，集中单一方法）：

- 列表：`PluginListProjection.entries(from: snapshot.plugins)`。
- 插件详情：`snapshot.plugins.compactMap { PluginDetailProjection.detail(forPluginID:snapshot:) }`。
- App 详情：`snapshot.applications.compactMap { ApplicationDetailProjection.detail(forAppID:snapshot:) }`。
- 关联条目：`ApplicationDetailProjection.allAssociationEntries(from:)`。

投影类型为静态 enum，无实例；Store 不持有投影实例（偏离备忘录示例的投影实例注入）。

## §4 App 接线层（`App/Features/Plugins/Integration/` 与既有目录改造）

### §4.1 DI 扩展（D2）

既有 DI 是 struct `AppDependencies`（`App/AppEntry/AppDependencies.swift`），在 `FilterKitApp.init()` 创建一次向下传递；本轮**扩展现有容器**，不新建第二套 `DependencyContainer`。

- `AppDependencies` 新增 `pluginFeatureStore: PluginFeatureStore` 字段与 init 入参（带默认构造接缝，保持既有 Preview 构造可编译）。
- `FilterKitApp.init()` 创建**唯一** `DiagnosticPluginRepository(engine: ReadOnlyDiagnosticsEngine())` 与唯一 `PluginFeatureStore(repository:)`，装配进 `AppDependencies`；Repository / Store 不在 View、不在 Tab、不在 ViewModel 内重复创建。
- 其余既有构造点（Dashboard/Diagnostics/Settings/旧信封 Preview）经默认参数或既有入参兼容，不接 Repository。

### §4.2 `PluginNavigationRoute.swift`

```swift
enum PluginNavigationRoute: Hashable {
    case plugin(String)
    case application(String)
    case applicationList
}
```

- String 为稳定模型 ID（插件 id / App bundleID），禁用显示名作 ID。
- `.applicationList` 为 D5 偏差：备忘录仅两例；App 库存列表需要一个根栈内入口，故追加第三例；`plugin/application` 两例与备忘录一致。

### §4.3 `PluginFeatureRootView.swift`

- 插件功能唯一根视图，内部单一 `NavigationStack(path:)`；`navigationDestination(for: PluginNavigationRoute.self)` 统一解析目的地。
- 根视图 `onAppear` 调用 `store.loadIfNeeded()`（守卫保证只初次扫描一次）；不在子页面 `onAppear` 触发 refresh。
- 目的地解析：
  - `.plugin(id)`：`store.pluginDetail(id:)` 命中 → `PluginDetailView(detail:)`；缺失 → 缺失态 `ContentUnavailableView`。
  - `.application(id)`：`store.applicationDetail(id:)` 命中 → `ApplicationDetailView(detail:)`；缺失 → 缺失态。
  - `.applicationList`：`ApplicationListView(entries: store.applicationDetails)`。
- 备忘录建议的 `PluginFeatureCoordinator.swift` 不单列文件：目的地解析收口在根视图内（D 偏差记录），职责不扩散到 E2/E3 ViewModel。

### §4.4 E2 浏览器接线（`App/Features/Plugins/Browser/`）

- `PluginBrowserViewModel` 保留既有查询接口（`setEntries` / `setLoading` / `setError` / `applyQuery` / `clearFilters` / 搜索词 / 筛选 / 排序）；只负责查询条件与列表展示，不持有 Repository、不触发扫描。
- `PluginBrowserView`：移除自身 `NavigationStack`（根栈统一）；状态分流改读 `store.state`（neverLoaded/loading → ProgressView；failed → 读取失败态；empty → 没有发现插件；loaded → 列表）；`onChange(of: store.pluginEntries)` 重放注入 VM。
- 列表行 `NavigationLink(value: .plugin(entry.id))`；工具栏提供 App 库存入口 `NavigationLink(value: .applicationList)`；保留既有 `PluginSearchBar` / `PluginFilterView` / `PluginBrowserRow`，不重写组件。
- `loaded` 存在 `lastRefreshError` 时列表顶部展示刷新失败提示（旧数据保留）。

### §4.5 E3 详情与双向关联接线（`App/Features/Plugins/Detail/`）

- `PluginDetailView`：追加可选 `associationRoute: (PluginAssociationEntry) -> PluginNavigationRoute?`（默认 nil = 纯展示）；根视图注入 `{ $0.applicationID.map { .application($0) } }`。
- `ApplicationDetailView`：追加同型闭包；根视图注入 `{ .plugin($0.pluginID) }`。
- `PluginAssociationSection`：关联行按闭包结果挂 `NavigationLink(value:)`；无路由则保持 `AssociationRow` 纯展示；五类分组与计数口径不变。
- `ApplicationListView`：行 `NavigationLink(value: .application(entry.id))`；条目由 Store 注入。
- 插件详情 → App、App 详情 → 插件两方向共用 `store.associationEntries` 与同一 Resolver 实例。

### §4.6 旧信封视图重名处理（D6）

既有信封版 `App/Features/Plugins/PluginListView.swift`（struct `PluginListView`）与 `App/Features/Plugins/PluginDetailView.swift`（struct `PluginDetailView`）与 E2/E3 新视图同名，同模块编译存在重名风险。本轮：

- 旧信封类型改名为 `LegacyPluginListView` / `LegacyPluginDetailView`；文件保留不删，内部 `PluginListViewModel` / `Models.Plugin` / `ReportEnvelope` 接线不动。
- Plugins Tab 切换到 `PluginFeatureRootView`；旧信封视图不再被 Tab 引用（Preview 构造同步改名），导出 / 既有信封链路零改动。

### §4.7 Tab 接入

`RootTabView` Plugins Tab 由旧信封 `PluginListView` 换成 `PluginFeatureRootView(store: dependencies.pluginFeatureStore)`；不新建平行 TabView；Plugin Detail / App Detail / App List 均为 Plugins 内部页面，不单独开 Tab。

## §5 集成测试矩阵（`Tests/Stage2/Plugins/PluginFeatureIntegrationTests.swift`）

计划新增 39 例；夹具经 `PluginDataMapper.mapSnapshot` 构造快照；测试内 Fake Repository 遵循 `PluginRepository` 协议并暴露 `refreshCount`；失败分支经 Store `refreshProvider` 接缝注入。

### A. Repository 与 Snapshot（E4-01～10）

| 编号 | 测试 | 预期 | 离线可测 |
| --- | --- | --- | --- |
| E4-01 | DI 创建 Repository | Store 持有唯一 Repository，快照与其缓存一致 | 是 |
| E4-02 | 初次加载 | 只执行一次 refresh | 是 |
| E4-03 | 多页面访问 | 重复读取详情 / App 详情不重复 refresh | 是 |
| E4-04 | 搜索操作 | 查询不触发 refresh | 是（Store 读取计数口径） |
| E4-05 | 筛选操作 | 筛选不触发 refresh | 是 |
| E4-06 | 插件详情打开 | 不触发 refresh | 是 |
| E4-07 | App 详情打开 | 不触发 refresh | 是 |
| E4-08 | 手动刷新 | 一次手动刷新只执行一次 refresh | 是 |
| E4-09 | 并发初次加载 | 重复 `loadIfNeeded` 合并为一次扫描 | 是（同步守卫） |
| E4-10 | Snapshot 一致性 | 列表 / 插件详情 / App 详情 / 关联条目同源同 ID 集合 | 是 |

### B. 状态处理（E4-11～18）

| 编号 | 测试 | 预期 | 离线可测 |
| --- | --- | --- | --- |
| E4-11 | 初始状态 | `.neverLoaded` | 是 |
| E4-12 | 扫描中 | provider 调用时状态为 `.loading` | 是 |
| E4-13 | 有插件 | `.loaded` | 是 |
| E4-14 | 无插件 | `.empty` | 是 |
| E4-15 | 首次扫描失败 | 无旧数据 → `.failed(message)` | 是（provider 接缝） |
| E4-16 | 刷新失败且存在旧数据 | 保留旧 Snapshot / 旧投影，状态 `.loaded`，记录 `lastRefreshError` | 是（provider 接缝） |
| E4-17 | 刷新成功 | 新快照替换旧快照与投影 | 是 |
| E4-18 | 未知数据 | unknown / unverified 证据不强转失败或不存在，状态正常落位 | 是 |

### C. 页面与导航（E4-19～25）

| 编号 | 测试 | 预期 | 离线可测 |
| --- | --- | --- | --- |
| E4-19 | Plugins Tab | 正常显示插件功能根视图 | Runner G7/G8 |
| E4-20 | 插件列表 → 详情 | 路由 ID 与详情 ID 一致 | 是（Store 解析层） |
| E4-21 | 插件详情 → App | 路由 App ID 与关联 applicationID 一致 | 是 |
| E4-22 | App 列表 → 详情 | 路由 App ID 与条目 ID 一致 | 是 |
| E4-23 | App 详情 → 插件 | 路由插件 ID 与关联 pluginID 一致 | 是 |
| E4-24 | 不存在的 ID | 详情解析返回 nil，根视图走缺失态 | 是 |
| E4-25 | 多次导航 | 重复路由解析不重复扫描 | 是 |

### D. 数据语义（E4-26～33）

| 编号 | 测试 | 预期 |
| --- | --- | --- |
| E4-26 | loaded 状态 | 无运行时证据仍 `.unknown` |
| E4-27 | globalRule | 不计入 exactMatch 计数 |
| E4-28 | unmatchedTarget | 不显示为精确关联 |
| E4-29 | invalidConfiguration | 保留无效状态分类 |
| E4-30 | unresolved | 保留未确认状态分类 |
| E4-31 | 插件 Hash | 无证据时为 nil |
| E4-32 | Integrity | 未关联时保持 `.unknown` |
| E4-33 | 文件归属 | 无证据不虚构来源 / 包属主 |

### E. 只读隔离（E4-34～39）

| 编号 | 测试 | 预期 |
| --- | --- | --- |
| E4-34 | 文件系统 | 集成层无 FileManager 写接口；操作前后快照 Equatable 不变 |
| E4-35 | plist | 无 plist 写入 / 修改调用 |
| E4-36 | dylib | 无删除 / 移动 dylib 调用 |
| E4-37 | dpkg | 无 dpkg 状态写入调用 |
| E4-38 | Filter | 无 Filter plist 规则修改调用 |
| E4-39 | 插件状态 | 无启用 / 禁用操作接口 |

E 组离线侧为代码面与快照不变性断言；运行时隔离由 Runner G6 隔离与只读检查复核。

## §6 兼容性与只读边界

- `Models.Plugin` / `ReportEnvelope` / `CombinedReportEncoder` / 导出 Mapper / Diagnostics 导出桥接零改动；E1～E4 模型不意外进入导出 JSON；Preview 合成数据不进入真实设备报告。
- 既有信封版列表 / 详情文件保留；改名后不被 Tab 引用；E2 查询引擎、E3 Resolver / 投影不重写。
- 全程只读：无 plist / dylib / dpkg / 软链写入，无注入，无 Helper / IPC / daemon，无 entitlement 放行；不推送远端。
- 插件级 Hash / 完整性记录、来源置信度：本轮在不改公共模型前提下评估现有快照可映射性；证明不了继续 `.unknown` / nil，不猜测补证据。

## §7 E4 验收层次（本地静态 + Runner 统一复核）

计划测试基线：既有 598 + E1 9 + E2 16 + E3 22 + E4 39 = **计划 684**（计划数，不代表已通过）。

| 门禁 | 内容 |
| --- | --- |
| G1 | Core 非 UI 编译 |
| G2 | 全部 Swift Tests |
| G3 | S1-05 回归测试 |
| G4 | iOS Device Build |
| G5 | Simulator Build |
| G6 | 隔离与只读检查 |
| G7 | App 页面构建 |
| G8 | UI Tests |
| G9 | 导出 JSON 回归（ReportEnvelope 不变 / Diagnostics 导出不丢失 / E1～E4 模型不进导出 JSON / Preview 数据不进真实报告） |
| G10 | Repository 单实例 |
| G11 | Snapshot 同源 |
| G12 | 插件详情导航 |
| G13 | App 双向关联导航 |
| G14 | 真实空状态 |
| G15 | 真实错误状态 |

## §8 遗留与待 Runner 闭环

- 引擎 / Repository 错误通道未开放：`.failed` 与「刷新失败保留旧数据」分支经 `refreshProvider` 接缝落地，真机权限拒绝等失败信号待引擎开放错误通道后回填；当前真实路径只产出 `.snapshot`。
- E4-19 与 G7/G8/G14/G15 为 Runner / Simulator / 真机侧结论；本机 Linux 无 Swift/Xcode，emit-module、684 例计划测试与 iOS 两侧编译以 Runner 在线日志为准。
- Dashboard 插件计数仍走既有信封投影；Store 快照向 Dashboard 共享留后续批次。
- 插件级完整性记录、来源置信度接入留后续；E5 操作框架仅留边界不实现。

## §9 本轮本地静态核对（2026-11-21，待 Runner 复验）

- **新增文件**：Core Integration 2 枚（`PluginFeatureState` / `PluginFeatureStore`，含 `PluginRefreshOutcome` 接缝枚举）；App Integration 2 枚（`PluginNavigationRoute` / `PluginFeatureRootView`）；离线测试 1 枚（`PluginFeatureIntegrationTests.swift`，E4-01～39 共 39 例）；规格 1 枚。
- **修改文件**：`AppDependencies`（挂 `pluginFeatureStore`）、`FilterKitApp`（唯一 Repository + Store 装配）、`RootTabView`（Plugins Tab 换根视图）、`PluginBrowserView`（接 Store 状态/条目/路由，移除自有导航栈）、E3 `PluginDetailView` / `ApplicationDetailView` / `ApplicationListView` / `PluginAssociationSection`（关联路由闭包与统一路由链接）；信封版 `PluginListView` / `PluginDetailView` 改名 `LegacyPluginListView` / `LegacyPluginDetailView`，文件保留不删、不再被 Tab 引用；`Package.swift` 登记 Core 2 枚与测试 1 枚。
- **清单一致性**：Core `Plugins/Integration/` 2 枚与 Package Core sources 一一对应；测试 4 枚（E1/E2/E3/E4）与 Stage2Tests sources 一一对应；App 目录由 XcodeGen glob 递归纳入，不进 SPM sources。
- **依赖方向**：Core Integration 仅 `import Foundation` / `import Observation`，无 SwiftUI、无文件系统访问；App → Core → Models/Adapters，Integration 层不反向依赖 App/Presentation。
- **只读接口扫描**：新增/修改接线层无 `FileManager` 写、无 plist/dylib/dpkg/软链写入、无 `dlsym`/`jbroot()`/`dlopen`/注入/Helper/IPC/daemon 调用；Store 不暴露启用/禁用/删除/改 Filter 接口。
- **口径核对**：列表/插件详情/App 详情/关联条目由 Store 单一 `rebuildProjections(from:)` 同源生成；路由 ID 取稳定模型 ID；`loaded` 恒 unknown；Hash 无证据 nil；Integrity 恒 `.unknown`；归属无证据不虚构；五类关联语义保留，exactMatch 才计精确关联数。
- **偏差记录**：D1 Repository 同步非 throwing，失败分支经 `refreshProvider` 接缝落地，真机错误信号待引擎开放错误通道；D2 扩展既有 `AppDependencies`，未新建第二套 DI 容器；D3 Store/状态枚举落 Core 供离线集成测试，路由/根视图落 App；D4 并发守卫为同步布尔位，async `refreshTask` 复用待 Repository 异步迁移；D5 路由追加 `.applicationList` 第三例；D6 旧信封类型改名 Legacy 消除同模块重名；D7 Dashboard 计数仍走既有信封投影，Store 快照向 Dashboard 共享留后续。
- **测试层次**：E4-01～18、20～39 为离线可测（Fake Repository 遵循 E1 协议并暴露 `refreshCount`，失败/旧数据保留经 provider 接缝注入）；E4-19 为 Runner G7/G8 UI 门禁，离线 `XCTSkip`；E 组只读隔离离线侧为快照不变性断言，运行时隔离由 Runner G6 复核。
- **遗留**：本机 Linux 无 Swift/Xcode；emit-module、684 例计划测试（598 既有 + E1 9 + E2 16 + E3 22 + E4 39）与 iOS 两侧编译结论以 Runner 下一轮日志为准；无 Runner 日志前不认定编译通过、不标注真机验收。
