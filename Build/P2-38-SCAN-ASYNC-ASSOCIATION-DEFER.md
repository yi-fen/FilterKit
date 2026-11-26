# P2-38 — App/插件扫描装配时序后置（A1–A3，减少首屏加载等待）

## 背景

在 P2-35 预热 / 共享快照 / 行内进度态基础上，对照 R16 `FastPluginInventoryEngine` 与 `FKApplicationDiscoveryService` 的"主库存先上屏、辅助信息后台补全"时序，复核 NEW 两条扫描通路的剩余等待点。本轮只调整装配时序，不改扫描算法、协议、模型字段或配对/归属口径。

## 本轮改动

### A1. 插件页 App 名映射不再阻塞首屏
- `Sources/Features/Plugins/PluginsView.swift`
- 原 `load()` `await enrichAppNames()`：插件列表虽由后台 registry 回填，但名字映射要等一次 App 枚举完成才返回。
- 改为：`enrichAppNames()` 同步触发后台 `Task { @MainActor [weak self] }`，不阻塞 `load()`。先读 `currentSnapshot()` 已有字典回填名字；后台 `scanInstalledApps()` 刷新后再覆盖回填。快照为空且扫描失败时才清空字典；有快照则保留快照名字。
- 抽出 `applyAppNames(_:)` 统一填 `appNamesByBundleID` / `appNamesByExecutable`。

### A2. 关联 reader 优先复用 App 快照
- `Sources/Environment/ReadOnlyPluginAssociationReader.swift`
- 新增可选注入 `snapshotApps: [InstalledApp]?`（默认 nil）。`readAssociations` 有快照直接用快照字典；为 nil 才回退 `scanInstalledApps()`，避免 warm 缓存上再发起一次 LaunchServices 枚举。
- 协议 `AppDiscoveryProvider` / `PluginAssociationReadingProvider` 未改；既有 stub 测试不传该参数，走原扫描路径，断言不变。

### A3. App 页关联步骤后置补全
- `Sources/Features/Apps/AppsView.swift`
- 原 `load()` 在 App 库存赋值后 `await loadAssociations(...)` 串行做插件扫描 + 关联。
- 改为后台 `Task { @MainActor [weak self] in await loadAssociations(...) }`：App 列表一到就渲染，`associatedBundleIDs` 就绪后置补。
- `loadAssociations(using:)` 参数类型由协议 `AppDiscoveryProvider` 收窄为具体 `CachedAppDiscoveryProvider`，以便取 `currentSnapshot()` 传给 reader（A2）。

## 刻意未改

- 不改 `InstalledApp` / `PluginScanItem` / `PluginScanResult` 等模型；不改配对状态机、归属判定、排序口径。
- 不引入二进制读取、dpkg 归属、CDHash 校验进库存通路。
- B 类扫描内部重量优化（plist 懒解析、文件属性聚合、manifest 降频、版本/可执行名懒读）未动，待真机剖面确认占比后单独评审。
- 无新增测试夹具改动；本机无 Xcode，编译 / XCTest 结论以 Runner 日志为准。

## 静态校验（Linux 主机）

- 三文件花括号 / 圆括号配平通过。
- 全树复核：无旧 `await enrichAppNames()` 残留；reader 仅 AppsView 与两处测试构造；测试不引用 ViewModel 私有方法。
- `CachedAppDiscoveryProvider.currentSnapshot()` 为 actor 异步方法，后台 `@MainActor` 闭包内 `await` 调用安全；后台任务均 `[weak self]`，页面释放后中止、不残留写入。

## 改动文件

| 目录 | 文件 | 改动 |
| --- | --- | --- |
| `Sources/Features/Plugins/` | `PluginsView.swift` | A1 名映射后台化，快照先填、后台回填；抽出 `applyAppNames` |
| `Sources/Environment/` | `ReadOnlyPluginAssociationReader.swift` | A2 可选快照注入，warm 缓存不再二次枚举 |
| `Sources/Features/Apps/` | `AppsView.swift` | A3 关联步骤后台后置；reader 传入快照；参数类型收窄 |

## 待 Runner / 真机复验

- `xcodegen generate` / Release device 编译通过；XCTest 通过。
- 冷启动：App 库存与插件列表先上屏，名字映射 / 关联标记后台补全；预热命中时不触发二次 LS 枚举。
- 后台任务在页面释放后不写回已销毁 ViewModel。
