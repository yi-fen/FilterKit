# P2-40 — 修复 Runner 编译：actor 内 NSLock 警告 + 环境探测表达式类型检查超时

## Runner 环境

- 镜像 `macos-26-arm64`，Xcode 26.6，iPhoneOS 26.5 SDK，`-swift-version 5`，arm64 Release，`CODE_SIGNING_ALLOWED=NO`。
- 结果：exit 65，`** BUILD FAILED **`，前端编译整批失败；日志计 3 处（1 error + 2 warning）。

## 日志问题与定位

1. `Sources/Environment/CachedAppDiscoveryProvider.swift:47`
   - warning（Swift 6 语言模式下将成为 error）：`instance method 'lock'/'unlock' is unavailable from asynchronous contexts`。
   - 根因：P2-39 为同步快照镜像加的 `NSLock` 在 actor 的 `async` 方法 `invalidateCache()` 内加锁；actor 方法属异步上下文，NSLock 不可跨 suspension 使用。
2. `Sources/Environment/ReadOnlyEnvironmentProvider.swift:90:28`
   - error：`the compiler is unable to type-check this expression in reasonable time`。
   - 根因：`selectedRoots.flatMap { root in [ 12 条 root + "..." 路径字面量 ] }` 单条闭包内大数组拼接，类型推断负担过重。

## 改动文件与目录

### 1. `Sources/Environment/CachedAppDiscoveryProvider.swift`（`Sources/Environment/`）
- 删除 `mirrorLock`（NSLock）与所有 `lock()/unlock()` 调用。
- 镜像 `mirror` 保留 `private nonisolated(unsafe) var [InstalledApp]?`：actor 为唯一写者（`finalizeRefresh` 成功写、`invalidateCache` 清、失败保留），nonisolated 读侧直读。
- `InstalledApp` 为全 `let` 值类型，读侧观察到的是旧数组引用或新数组引用之一，不会读到半成品；无锁即消除异步上下文加锁告警。
- `currentSnapshotSync()` 由加锁读取改为直读 `mirror`；对外签名、协议、缓存 TTL/在飞逻辑不变。

### 2. `Sources/Environment/ReadOnlyEnvironmentProvider.swift`（`Sources/Environment/`）
- 抽出私有静态方法 `private static func elleKitCandidatePaths(for root: String) -> [String]`，承载原 12 条候选路径。
- `flatMap` 闭包简化为 `selectedRoots.flatMap { Self.elleKitCandidatePaths(for: $0) }`，拆分超长表达式，类型推断不再超时。
- 候选路径清单、探测口径、返回模型均未改；12 条路径逐条保留。

## 刻意未改

- 不改扫描算法、枚举口径、模型字段、配对/归属判定。
- 本轮未动 `.github/workflows/build.yml`：与上传基线存在 runner 镜像 / action 版本差异（工作树 `macos-15`/`checkout@v4`/`upload-artifact@v4`，基线包 `macos-latest`/`v6`/`v7`，本次 Runner 实跑 `macos-26-arm64`）。该配置漂移与本轮源码编译错误无关，留待单独核对，不在本轮擅自回退或覆盖。

## 静态核对（本机 Linux，无 Xcode/SwiftPM）

- 两文件花括号配平通过；`ReadOnlyEnvironmentProvider` 候选路径仍为 12 条；`elleKitCandidatePaths` 定义与调用一致；`currentSnapshotSync()` 仅定义、`AppsView.init` 调用、测试断言引用。
- 无 `mirrorLock`/`NSLock` 残留（仅注释说明为何不用锁）。
- 本机未编译；编译与 XCTest 结论以下次 Runner `xcodebuild` 为准。

## 待 Runner / 真机复验

- Swift 5 编译通过，无 `unavailable from asynchronous contexts` 告警；`ReadOnlyEnvironmentProvider:90` 类型检查超时消除。
- 同步快照镜像在刷新/失效/失败保留路径下行为与 P2-39 一致；预热命中首帧出列表。
