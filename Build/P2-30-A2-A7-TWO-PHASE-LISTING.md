# P2-30 — A2/A7 收尾：两段式上屏与重复排序收敛（离线优化轮）

## 范围

承接 P2-29 遗留的 A2、A7 两项：

- **A7 重复排序收敛**：扫描侧不再做 `displayName/bundleIdentifier` 二次排序，去重与排序统一由缓存层 `deduplicatedAndSorted` 完成；最终可见列表顺序仍由显示层 `AppInventoryQuery.filter` 排序。
- **A2 两段式上屏**：进入 App 页时先上屏已有的缓存快照（不触发扫描），后台扫描/刷新完成后再替换为最新库存并补全关联；首次冷启动缓存为空、无快照可渲染时，仍走 loading 态直到库存返回。

## 不变契约

- `InstalledApp` 公开字段、两个初始化器、`AppDiscoveryProvider` / `AppDiscoveryRefreshing` 协议签名不变。
- Provider / ViewModel / View 分层不变；Apps 与 Plugins 两屏仍复用 `AppDiscoveryProviderRegistry.shared`。
- 不开启任何生产写门禁；不改目标 App Bundle、不重签名、不自研注入引擎；不新增 Rootless DEB 路线。

## 改动文件与目录

1. `Sources/Environment/LaunchServicesAppDiscoveryProvider.swift`（`Sources/Environment/`）
   - 删除扫描返回路径上的 `sorted { displayName → bundleIdentifier }`；返回去重后的 `Array(apps.values)`，排序交由缓存层与显示层。
2. `Sources/Environment/CachedAppDiscoveryProvider.swift`（`Sources/Environment/`）
   - 新增非扫描方法 `currentSnapshot() -> [InstalledApp]?`：仅读取 `cachedApps`，不触发 LaunchServices 枚举；供首屏先行渲染。
   - 去重与排序保持在 `deduplicatedAndSorted`，是缓存层唯一排序点。
3. `Sources/Features/Apps/AppsView.swift`（`Sources/Features/Apps/`）
   - `AppsViewModel.load(forceRefresh:)` 改为两段式：先在 `apps` 为空且存在快照时上屏 `currentSnapshot()`，再 `await` 扫描/刷新；完成后替换 `apps`、更新 `scannedAt`，再异步加载关联。
   - View 条件 `isLoading && apps.isEmpty` 与错误/空态判断不变：有快照时 `apps` 非空，不被全屏 loading 或错误态遮挡；后台失败仍保留快照列表。
4. `Tests/UnitTests/AppDiscoveryTests.swift`（`Tests/UnitTests/`）
   - 新增 `testCurrentSnapshotReflectsCacheAndInvalidation`：断言快照在首次读取为 `nil`、扫描后反映库存、`invalidateCache()` 后回到 `nil`。

## 行为与边界

- **预热命中**：P2-29 `prewarm()` 已在根任务后台填缓存；进入 App 页 `load()` 读到快照即先出列表，后台再以最新库存替换。
- **刷新**：`forceRefresh` 绕缓存刷新，旧列表在新库存返回前保留，不先清空。
- **首次冷启动**：缓存为空、`currentSnapshot()` 为 `nil`，仍显示 loading 直到首次枚举返回——此时没有可渲染的数据，属诚实边界。
- **在飞扫描**：预热/上一次扫描尚未完成时首进页面，快照为 `nil`，仍走 loading；本轮未做在飞任务合并（同一 inventory 的并发去重复用），留待后续评审。
- **流式壳行**：在 LS 枚举过程中先吐 `bundleID/displayName` 轻量行、再后台补全版本/图标的 provider 分段改造，触碰列表装配契约，本轮边界外，留待单独评审。

## 静态核对（本机 Linux，无 Xcode/SwiftPM）

- 三处 Swift 源文件与测试文件花括号配平通过。
- `currentSnapshot` 仅被缓存层定义与 `AppsViewModel` 调用；Plugins 两屏仍只调 `scanInstalledApps()`，未受影响。
- LS provider 内无残留 `sorted` / `localizedStandardCompare`；排序点收敛到缓存层与 `AppInventoryQuery.filter`。
- 现有测试仅断言分类、去重 count、TTL 与刷新绕缓存，不断言扫描侧返回顺序；删除扫描侧排序不破坏既有断言。

## 未闭环 / 待 Runner 与真机复验

- 本机无 Xcode/iOS SDK/ldid/lipo/otool，未做编译与 XCTest 回归；编译、测试结论以下次 Runner `xcodebuild` 为准。
- 冷启动预热命中表现、在飞扫描场景、单数组 LS 枚举对 rootless/RootHide 组合的覆盖度需真机核对。
- 既有 `Resources/en.lproj/Localizable.strings:277` 本地化语法问题为基线既有，本轮未改 Resources。
- DEB 安装/签名放行/jbroot API/真机注入验证仍 pending；0.1 未真机闭环不签署。
