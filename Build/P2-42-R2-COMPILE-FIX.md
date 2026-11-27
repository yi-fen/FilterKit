# P2-42 — 修复 R2 Runner 编译：4 error + 2 warning（类型转换 / actor 加锁 / let 遮蔽 / 表达式超时 / 类型名）

## Runner 环境

- 镜像 `macos-26-arm64`，Xcode 26.6，iPhoneOS 26.5 SDK，`-swift-version 5`，arm64 Release，`CODE_SIGNING_ALLOWED=NO`。
- 命令：`xcodebuild -scheme FilterKit -configuration Release -destination generic/platform=iOS ARCHS=arm64 ONLY_ACTIVE_ARCH=NO`。
- 结果：exit 65，`** BUILD FAILED **`，`CompileSwift` 整批失败；日志计 4 处 error + 2 处 warning。

## 日志问题与定位

1. `Sources/Features/Apps/AppIconPrivateAPI.swift:18:63`
   - error：`'NSString' is not implicitly convertible to 'String'`。
   - 根因：ObjC 桥接头 `FilterKitAppIconPrivateAPI.h` 在 `NS_ASSUME_NONNULL_BEGIN` 内声明 `NSString *bundleIdentifier`，Swift 桥接为非空 `String`；调用处显式 `as NSString` 反向强转，类型不匹配。
2. `Sources/Environment/CachedAppDiscoveryProvider.swift:51:20 / 51:53`
   - warning（Swift 6 语言模式下将成为 error）：`instance method 'lock'/'unlock' is unavailable from asynchronous contexts`。
   - 根因：actor 的异步方法内对 `NSLock` 加锁；actor 方法属异步上下文，`NSLock` 不可跨 suspension 使用。
3. `Sources/Features/Plugins/PluginsView.swift:732:13`
   - error：`cannot assign to value: 'original' is a 'let' constant`。
   - 根因：`save()` 的 `guard let draft, let original, ...` 解包出的局部常量 `original` 遮蔽了 `@State` 属性 `original`；随后 `original = draft` 写入局部 let，赋值失败。
4. `Sources/Environment/ReadOnlyEnvironmentProvider.swift:90:28`
   - error：`the compiler is unable to type-check this expression in reasonable time`。
   - 根因：`selectedRoots.flatMap { root in [ 12 条 root + "..." 路径字面量 ] }` 单条闭包内大数组拼接，类型推断负担过重。
5. `Sources/Features/Settings/SettingsView.swift:130:29`
   - error：`cannot find 'AppBinaryIdentityInspector' in scope`。
   - 根因：类型名写错。实际类型为 `AppBinaryIdentitySnapshot`（定义于 `Sources/Environment/AppBinaryIdentityInspector.swift`），其静态方法 `inspectMainBundle()` 返回 `AppBinaryIdentitySnapshot?`；属性 `appBinaryIdentity` 类型本就是 `AppBinaryIdentitySnapshot?`。

## 改动文件与目录

### 1. `Sources/Features/Apps/AppIconPrivateAPI.swift`（`Sources/Features/Apps/`）
- 调用 `FKLookupApplicationIcon(...)` 去掉 `as NSString`，直接传 `String` 形参：
  `FKLookupApplicationIcon(bundleIdentifier, scale, &image)`。
- 私有 API 探测、`@try` 异常捕获、结果枚举与诊断记录口径均未改。

### 2. `Sources/Environment/CachedAppDiscoveryProvider.swift`（`Sources/Environment/`）
- 删除 `mirrorLock`（`NSLock`）与所有 `lock()/unlock()` 调用。
- 镜像保留 `private nonisolated(unsafe) var mirror: [InstalledApp]?`：actor 为唯一写者（`finalizeRefresh` 成功写、`invalidateCache` 清、失败保留），`nonisolated currentSnapshotSync()` 直读。
- `InstalledApp` 为全 `let` 值类型，读侧观察到旧数组引用或新数组引用之一，不会读到半成品；无锁即消除异步上下文加锁告警。
- 对外签名、缓存 TTL、在飞合并、预热、失败保留逻辑不变；测试只调用 `currentSnapshotSync()`，API 未变。

### 3. `Sources/Features/Plugins/PluginsView.swift`（`Sources/Features/Plugins/`）
- `save()` 的 guard 局部解包改名以避免遮蔽属性：
  `guard let draft, let baseline = original, let hardBoundID, draft != baseline else { return }`。
- 保存成功后仍写回属性 `original = draft`；比较改用局部只读 `baseline`。其余关联编辑、回滚、失败提示逻辑未改。

### 4. `Sources/Environment/ReadOnlyEnvironmentProvider.swift`（`Sources/Environment/`）
- 抽出私有静态模板 `private static let elleKitRelativePaths: [String]`，承载原 12 条相对候选路径。
- `flatMap` 闭包简化为 `selectedRoots.flatMap { Self.elleKitRelativePaths.map { root + $0 } }`，拆分超长表达式，类型推断不再超时。
- 候选路径清单、探测口径、返回模型均未改；12 条路径逐条保留。

### 5. `Sources/Features/Settings/SettingsView.swift`（`Sources/Features/Settings/`）
- 类型名更正：`AppBinaryIdentityInspector.inspectMainBundle()` → `AppBinaryIdentitySnapshot.inspectMainBundle()`。
- 与属性 `appBinaryIdentity: AppBinaryIdentitySnapshot?` 对齐；环境探测、ElleKit 状态刷新逻辑未改。

## 刻意未改

- 不改扫描算法、枚举口径、模型字段、配对/归属判定、Helper 身份验证规则、生产写入 Gate。
- 文件名 `AppBinaryIdentityInspector.swift` 保留不变（文件名不参与编译解析），未重命名以避免工程引用面扩散。
- 其余普通 class / 静态计数器内的 `NSLock`（Helper 层、诊断计数器、图标缓存）不在 actor 异步上下文，日志未告警，本轮不动。
- 未动 `.github/workflows/build.yml` 的 runner 镜像 / action 版本漂移（与本轮源码编译错误无关，留待单独核对）。

## 静态核对（本机 Linux，无 Xcode/SwiftPM）

- 改动文件花括号配平通过；全仓无 `mirrorLock`、无 `AppBinaryIdentityInspector` 类型名残留。
- `FKLookupApplicationIcon` 头文件经 `FilterKit-Apps-Bridging-Header.h` 引入；`.m` 由 xcodegen `Sources/Features` 递归纳入。
- `elleKitRelativePaths` 仍为 12 条；`inspectMainBundle()` 定义与调用返回类型一致；`currentSnapshotSync()` 仅定义、`AppsView.init` 调用、测试断言引用。
- 测试未引用被删的 `mirrorLock` 或旧类型名；无 UI 管理器用例直接构造 `PluginSoftAssociationManagerSection`。
- 本机未编译；编译与 XCTest 结论以下次 Runner `xcodebuild` 为准。

## 待 Runner / 真机复验

- Swift 5 编译通过：无 `NSString` 转换错误、无 `unavailable from asynchronous contexts` 告警、无 let 遮蔽、无表达式超时、`AppBinaryIdentitySnapshot` 可解析。
- 关联保存成功后基线快照正确更新；预热命中首帧出列表；同步镜像在刷新/失效/失败保留路径下行为与 P2-39/P2-40 一致。
