# P2-39 — init 同步快照时机对齐 R16（消除预热已完成时的壳闪现）

## 背景

对照 R16 `ApplicationDiscoveryView`：视图 `init` 即把 `service.currentResult()` 喂成 `@State` 初值，`onAppear` 再补加载；库存 `cached` 由 NSLock 保护，`currentResult()` 可同步读取。NEW 的 `CachedAppDiscoveryProvider` 是 actor，`currentSnapshot()` 必须 `await`；`AppsViewModel` 在 `init` 时为空，直到 `.task` 触发 `load()` 首帧才异步读快照。

差距：预热已完成、缓存已有库存时，首帧仍先按 `isLoading && apps.isEmpty` 渲染行内进度壳，待 `await currentSnapshot()` 恢复后才上列表——多一次壳闪现。

## 本轮改动

### 1. 缓存层：线程安全同步快照镜像
- `Sources/Environment/CachedAppDiscoveryProvider.swift`
- 新增 `mirrorLock`（NSLock）与 `nonisolated(unsafe) var mirror: [InstalledApp]?`，作为上次成功库存的同步只读镜像。actor 仍是唯一写者：`finalizeRefresh` 成功后写镜像，`invalidateCache` 清镜像；枚举失败保留旧镜像，与缓存失败不改动一致。
- 新增 `nonisolated func currentSnapshotSync() -> [InstalledApp]?`：加锁读镜像，不触发 LaunchServices 枚举。
- 保留原 actor 隔离的 `currentSnapshot()`（await 通路），协议 `AppDiscoveryProvider` / `AppDiscoveryRefreshing` 未改。

### 2. App 页：初始化同步填入预热库存
- `Sources/Features/Apps/AppsView.swift`
- `AppsViewModel.init()` 调 `currentSnapshotSync()` 同步填 `apps`：预热已完成时首帧即有列表；预热未完成返回 nil，`apps` 为空，仍走行内进度兜底。
- `load()` 首帧两段式兜底保留：`apps.isEmpty` 时再 `await currentSnapshot()`；库存非空则后台扫描期间保留快照列表，不进壳分支。

### 3. 测试
- `Tests/UnitTests/AppDiscoveryTests.swift`
- `testCurrentSnapshotReflectsCacheAndInvalidation` 增补同步镜像断言：扫描后 `currentSnapshotSync()` 有值，失效后为 nil。

## 刻意未改 / 边界

- 冷启动首次、预热尚未跑完、镜像为 nil 时，无旧库存可上屏，行内进度态是诚实边界，本轮不改；这一点 R16 同样存在（其 `cached` 也是纯内存、不落盘）。
- 插件页由 `PluginScanRegistry.shared`（MainActor 单例）直接持有 `result`，视图观察 `registry.result`，无需同步镜像。
- 不改扫描算法、枚举口径、模型字段、配对/归属判定；不做库存磁盘持久化（属新增缓存契约，需单独评审陈旧数据/失效问题）。
- 枚举总重量（LS 枚举 + plist 读取耗时）留待真机剖面。

## 静态核对（本机 Linux，无 Xcode/SwiftPM）

- 三处 Swift 源文件花括号配平通过；`currentSnapshotSync()` 仅缓存层定义、`AppsView.init` 调用、测试断言引用。
- 本机未编译；编译与 XCTest 结论以下次 Runner `xcodebuild` 为准。

## 待 Runner / 真机复验

- 预热命中场景：进 App 页首帧直接出列表，不闪行内进度壳。
- 首次冷启动：预热未完成时仍显示行内进度，库存返回后替换。
- 同步镜像与 actor 缓存一致性：刷新、失效、失败保留旧值路径。
