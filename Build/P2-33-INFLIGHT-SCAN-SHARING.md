# P2-33 — 应用扫描在飞任务合并与首屏提速（离线优化轮）

## 录屏对比结论

- 新版 `RPReplay_Final1795700410.MP4`（4.83s）：2.4s 才出首页占位；切到应用 tab 后经蓝色"正在加载"过渡，3.6s 才出 114 个应用。
- 旧版 `RPReplay_Final1795700779.MP4`（2.77s）：0.3s 首页仪表盘已带 266 Apps 计数；1.8s 应用列表直接上屏，无加载过渡页。
- 本轮目标是**加速首屏上屏**，不补首页仪表盘内容；不改变列表契约与 Provider/ViewModel/View 分层。

## 根因

旧版 `FKApplicationDiscoveryService` 用 `isLoading` 标志 + `completionWaiters` 队列：预热、应用页、插件页共享同一个在飞枚举，结果一次性分发给所有等待者；缓存结果可同步读取。

新版 `CachedAppDiscoveryProvider` 虽有 TTL 缓存，但**没有在飞任务合并**：

- 根 `.task` 的 `prewarm()` 启动一次 detached 扫描；
- 进入 AppsView `.task` 的 `load()` 发现缓存为空，又发起一次独立枚举；
- PluginsView 的关联名映射/选择器加载再各自调用。

预热尚未完成时，多个调用方各自触发 LaunchServices 枚举，重复 IPC 与磁盘 plist 读取，拉长首屏等待并出现全屏加载过渡。

## 改动文件与目录

1. `Sources/Environment/CachedAppDiscoveryProvider.swift`（`Sources/Environment/`）
   - 新增 `inFlight: Task<[InstalledApp], Error>?`，`sharedRefresh()` 复用已有在飞任务，无在飞才启动 detached 枚举。
   - 所有并发调用方 await 同一任务；任务完成后由 `finalizeRefresh(result:)` 一次性写缓存、清在飞；枚举失败不写缓存，下次请求重试。
   - `scanInstalledApps()` 命中 TTL 缓存直接返回，否则复用/启动在飞任务；`refreshInstalledApps()` 走同一在飞复用路径。
   - `prewarm()` 外层 detached 非阻塞语义不变，内部经合并路径刷新。
2. `Tests/UnitTests/AppDiscoveryTests.swift`（`Tests/UnitTests/`）
   - 新增 `testConcurrentScansShareOneInFlightSourceCall`：两个并发 `scanInstalledApps()` 共享同一在飞任务，底层 source 仅被调用一次。

## 行为与边界

- 预热、应用页、插件页在同一缓存窗口内只发起一次 LaunchServices 枚举；后续调用复用结果。
- 缓存命中（TTL 60s）仍直接返回；显式刷新不读缓存，但会复用当前在飞任务，不中断预热。
- 首次冷启动无快照、在飞尚未完成时，应用页仍走 loading 态（无数据可渲染）；这是上一轮 A2 已记录的诚实边界。
- 未做：LS 枚举期先吐轻量壳行再后台补全 plist/图标的流式 provider 改造（触碰列表装配契约，留待单独评审）；未补首页仪表盘数据；未新增任何写门禁。

## 静态核对（本机 Linux，无 Xcode/SwiftPM）

- 缓存层与测试文件花括号配平通过；`verify-project-config.sh` PASS，`verify-architecture.py` PASS。
- 协议方法签名、`InstalledApp` 字段、Apps/Plugins 两屏复用 `AppDiscoveryProviderRegistry.shared` 不变。
- 既有 TTL/显式刷新绕缓存/去重/快照测试断言不破坏：串行调用下在飞任务已完成，行为与原语义一致。

## 未闭环 / 待 Runner 与真机复验

- 本机未做编译与 XCTest 回归；编译、并发复用结论以下次 Runner `xcodebuild` 为准。
- 真机复核：冷启动预热命中表现、应用/插件页切换是否只触发一次枚举、首屏到列表的实际耗时。
- DEB 安装/签名放行/jbroot API/真机注入验证仍 pending；0.1 未真机闭环不签署。
