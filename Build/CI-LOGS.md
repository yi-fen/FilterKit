# CI 日志归档 — P1-44 轮（xcodegen spec 解析失败）

## 元数据

- 仓库：`yi-fen/FilterKit`，分支 `main`，commit `43edf3601e15eab7e7e538d6c747c12c10097d3e`
- Workflow：`6c8792cc-a9b2-41cc-879d-1aeb66b739a1`；Job：`78b7a8a2-f14e-5de8-9728-f17ac54f25a5`
- Run：https://github.com/yi-fen/FilterKit/actions/runs/45485900625
- Runner：macOS 15.8.2 (24H232)，Xcode 16.4 (16F6)，xcodegen 2.47.0
- 入参（日志 env）：`ENVIRONMENT=RootHide`、`PROFILE=Auto`、`CONFIGURATION=Release`、`ARCHITECTURE=arm64`、`RUN_TESTS=false`、`PACKAGE=IPA`、`CLEAN_BUILD=false`
- Profile 解析成功：`roothide-dopamine-ellekit-1.2-3-16e3e7e (RootHide)`

## 失败现象

`bash Build/Scripts/ci-build.sh` 在 `xcodegen generate --spec Project.yml` 阶段退出，尚未进入 `xcodebuild`：

```
Resolved profile: roothide-dopamine-ellekit-1.2-3-16e3e7e (RootHide)
Parsing project spec failed: Unknown Target type: command-line-tool
Process completed with exit code 1.
```

## 判读

- 错误来自 XcodeGen 解析 `Project.yml` 的 target `type` 枚举，**不是编译错误**，也与构建入参无关。
- 截图/Workflow 入参 `RootHide / Auto / Release / arm64 / No / IPA` 均为 `build.yml` 合法 choice；profile 已正常解析。本轮失败在 spec 生成工程之前，环境、架构、配置、打包格式选项均未被使用到。
- XcodeGen 官方 Product Type 枚举中，命令行工具的合法值是 `tool`；`command-line-tool` 不在枚举内，故报 `Unknown Target type`。

## 修复清单（基于上传包 FilterKit-NEW-P1-44.zip 为基线）

### 修改文件：`Project.yml`

1. `FilterKitHelper` target 的产品类型
   - 改前：`type: command-line-tool`
   - 改后：`type: tool`

2. `FilterKitHelper` target 补入漏列源码目录
   - 新增 source：`Sources/Environment/Helper/Installer`
   - 原因：已列入的 `Execution/HelperRootAtomicActivationExecutor.swift` 引用 `HelperRootReleaseSet`，其定义在 `Installer/HelperRootReleaseSet.swift`；该目录原未列入 Helper target，下一轮编译会缺类型。
   - 依赖闭环核对：`HelperInstallerProvisioningBundle` / `HelperInstallerArtifactDigest`（`Core/Models/Helper/HelperInstallerProvisioning.swift`，已列入）、`HelperInstallerTransactionJournal`（`Runtime/`，已列入）、`HelperPolicy`（`Core/Models/Helper/HelperDeploymentModels.swift`，已列入）、`SHA256Digest`（已列入）。

## 静态核对（本机 Linux，无 Xcode/SwiftPM）

- `Project.yml` YAML 可解析；三个 target 类型：`application / tool / bundle.unit-test`，均为合法枚举。
- Helper target 列入的 52 个 Swift 文件 sources 路径全部存在；跨文件类型引用闭环（`PackageOwnershipEvidence` 为 Helper 内嵌套 enum、`PluginIdentityAnalyzer` 仅为注释文本，均非外部缺引用）。
- `FilterKit` App target 110 文件、`FilterKitTests` 39 文件；Tests 的跨类型引用经 target 链接依赖可见，非文件漏列。
- `Build/Scripts/verify-project-config.sh`：PASS；`Build/Scripts/verify-architecture.py`：PASS（8 required files）。

## 未闭环 / 待下一轮 CI 复验

- 本机为 Linux，无 Xcode、无 iOS SDK、本树无 `Package.swift`，未做编译/测试回归；以下结论以 Runner 下次 `xcodegen generate` + `xcodebuild` 为准。
- `tool` 产品类型配 `platform: iOS` 的组合在 XcodeGen/Xcode 下是否被接受，待生成工程阶段复验。
- Helper target 是否被 `FilterKit` scheme 纳入构建（当前 `FilterKit` target 未声明对 Helper 的 dependency）；若未纳入，Helper 编译问题会延后暴露。
- Helper 其余跨 target/跨目录引用、Darwin 分支与签名行为仍需 macOS 真机/模拟器验证。

---

# CI 日志归档 — round6 轮（xcodebuild App target 编译失败）

## 元数据

- Workflow：`7f366ae4-980c-4d9e-9c58-7e986c3b016c`；Job：`34553347-b15f-5237-afb2-a87c81b98765`
- Runner：macOS 15.8.2 (24H232)，Xcode 16.4 (16F6)，iPhoneOS18.5 SDK，xcodegen 2.47.0
- 入参（日志 env）：`ENVIRONMENT=RootHide`、`CONFIGURATION=Release`、`ARCHITECTURE=arm64`、`PACKAGE=IPA`；Profile 解析成功 `roothide-dopamine-ellekit-1.2-3-16e3e7e (RootHide)`
- 构建命令：`xcodebuild -project FilterKit.xcodeproj -scheme FilterKit -configuration Release -destination generic/platform=iOS ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build`
- 上轮 `xcodegen generate` 已通过（target type 修复生效）；本轮进入 `FilterKit` App target 整模块（WMO）编译，`** BUILD FAILED **`，exit 65，日志汇总 3 failures（含同文件多诊断）。

## 失败错误与修复清单（基线：本地 P1-44 树 + round5 两处 Project.yml 修复）

### 1. `Sources/Environment/Helper/Runtime/HelperSignedReleaseRuntimeLoader.swift`（目录 `Sources/Environment/Helper/Runtime/`）

- 错误：`66:13 / 70:13 error: cannot find '_NSGetExecutablePath' in scope`；连带 `'nil' requires a contextual type`。
- 判读：`_NSGetExecutablePath` 声明在 `<mach-o/dyld.h>`，该 C 头未进入纯 Swift `Darwin` 模块接口，符号在当前 iOS SDK 不可见（同类 libc 函数如 `socket` 可见，差异在头文件是否被 modulemap 收录）；项目无 bridging header 可补声明。
- 修复：`currentExecutablePath()` 改为 `Bundle.main.executableURL?.path`（Foundation 提供、编译可见；main bundle 内部即基于主可执行路径填充）；删除不再使用的 `#if canImport(Darwin) import Darwin` 块与 CChar 缓冲探测逻辑。

### 2. `Sources/Environment/LaunchServicesAppDiscoveryProvider.swift`（目录 `Sources/Environment/`）

- 错误：`26:37 error: binary operator '==' cannot be applied to operands of type 'any Error' and '()'`；`26:41 error: reference to member 'accessRestricted' cannot be resolved without a contextual type`。
- 判读：外层 `catch let error as AppDiscoveryError` 绑定的具名 error，被内层 `catch { ... }` 未绑定变量同名遮蔽；内层块里的 `error` 退化为 `any Error`，无法与 `.accessRestricted` 比较。
- 修复：外层绑定改名为 `lsError`，内层 `catch` 不重新绑定，比较与重抛均使用 `lsError`：`catch { throw lsError == .accessRestricted ? lsError : AppDiscoveryError.noReadableInventory }`。`AppDiscoveryError` 为 `Error, Equatable`，`.accessRestricted` / `.noReadableInventory` case 存在。

### 3. `Sources/Features/Plugins/PluginsView.swift`（目录 `Sources/Features/Plugins/`）

- 错误：`498:21 error: 'LabeledContent' is only available in iOS 16.0 or newer`；`'init(_:value:)' is only available in iOS 16.0 or newer`。部署目标 `IPHONEOS_DEPLOYMENT_TARGET=15.0`。
- 修复：`LabeledContent("plugins.detail.hard_bound", value: ...)` 替换为本文件已有的 iOS 15 兼容辅助视图 `detailRow("plugins.detail.hard_bound", plugin.hardBoundBundleIdentifier ?? "—")`（内部为 `HStack` + `Text`）。全树已无第二处 `LabeledContent`。

### 4. `Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift`（目录 `Sources/Environment/Helper/Transport/`）

- 错误：`86:67 error: cannot convert value of type 'Int' to expected argument type '__darwin_suseconds_t' (aka 'Int32')`。
- 修复：`timeval` 的 `tv_sec` / `tv_usec` 显式转 `Int32`：`timeval(tv_sec: Int32(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))`。同文件 244 行整数字面量自动推断，未改。

## 静态核对（本机 Linux，无 Xcode/iOS SDK）

- 四处改后文件大括号配平；`Project.yml` YAML 可解析；`verify-project-config.sh` PASS；`verify-architecture.py` PASS（8 required files）。
- 复扫无残留 `_NSGetExecutablePath` / `LabeledContent`；全树无其他 iOS 16+ SwiftUI API（`ShareLink`/`Grid`/`NavigationStack`/`.scrollContentBackground`/`Chart` 等）。
- 另两处 `catch let error as ...`（`HelperThreeFileTransaction.swift:157`、`AppsView.swift:40`）无内层 do-catch 遮蔽，未改动。

## 未在本轮处理的编译器 warning（不阻断编译，留待后续）

- `HelperReleaseGenerationStore.swift:61 / 113`：`var query` 未突变，建议改 `let`。
- `LaunchServicesAppDiscoveryProvider.swift:15`：`try await Task.detached` 内无 async/throwing 操作；`try`/`await` 冗余。
- `PluginsView.swift:112`：`catch` 块不可达（do 内无抛错）。

## 未闭环 / 待下一轮 CI 复验

- 本机无 Xcode/iOS SDK，未做编译/测试回归；上述四处以 Runner 下次 `xcodebuild` 编译结果为准。
- `FilterKit` scheme 本轮未单独构建 `FilterKitHelper` target；Helper 侧（tool target、Unix socket、签名）编译与链接问题仍可能延后暴露。
- `Bundle.main.executableURL` 在裸 root helper 进程（无 .app bundle）下的返回路径需真机/Helper 进程复验；若返回 nil 会走 `executablePathUnavailable` 失败闭合，不产生越权行为。
- 部署目标 iOS 15.0 与越狱设备矩阵仍待确认；DEB 打包、签名放行、jbroot API、真机注入验证 pending，0.1 未闭环不签署。

---

# CI 日志归档 — round7 轮（timeval.tv_sec 类型错误）

## 元数据

- Workflow：`a36b48c9-5a20-475d-a47b-ee80b4aef60a`；Job：`53f964c9-fae7-5dfd-9f6f-1ccd864dc114`
- Run：https://github.com/yi-fen/FilterKit/actions/runs/45494774623 ；Artifact ID `14968500642`
- Runner：macOS 15.8.2 (24H232)，Xcode 16.4 (16F6)，iPhoneOS18.5 SDK，xcodegen 2.47.0
- 入参：`ENVIRONMENT=RootHide`、`CONFIGURATION=Release`、`ARCHITECTURE=arm64`、`PACKAGE=IPA`、`CLEAN_BUILD=false`
- 阶段：上轮 4 类编译错误已清除；本轮 `FilterKit` App target WMO 编译仅剩 1 条类型错误，未进入链接阶段，`** BUILD FAILED **`，exit 65。

## 失败错误与修复清单

### `Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift`（目录 `Sources/Environment/Helper/Transport/`）

- 错误：`86:44 error: cannot convert value of type 'Int32' to expected argument type '__darwin_time_t' (aka 'Int')`。
- 判读：`struct timeval` 两个字段宽度不同——`tv_sec` 为 `__darwin_time_t`（`long`，即 Swift `Int`），`tv_usec` 为 `__darwin_suseconds_t`（`int`，即 Swift `Int32`）。round6 修 `tv_usec` 时误把 `tv_sec` 一并转成 `Int32`，本轮在 `tv_sec` 上暴露类型不符。
- 修复（86 行）：`tv_sec` 改回 `Int(timeout)`，`tv_usec` 保留 `Int32(...)`：
  ```swift
  var timeoutValue = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
  ```
- 同文件 244 行 `timeval(tv_sec: 5, tv_usec: 0)` 整数字面量由编译器自动推断，未改动。

## 静态核对（本机 Linux，无 Xcode/iOS SDK）

- 改后文件大括号配平（85/85）；`Project.yml` YAML 可解析；`verify-project-config.sh` PASS；`verify-architecture.py` PASS（8 required files）。
- 全树 timeval 构造仅上述两处，无其他 `Int`/`Int32` 混用。
- 本轮 WMO frontend 仅报这 1 条 error，其余源码类型检查已通过；剩余三条 warning 与 round6 记录相同（`var query` 未突变 ×2、不可达 catch），不阻断编译。

## 未闭环 / 待下一轮 CI 复验

- 本机无 Xcode/iOS SDK，未做编译回归；以 Runner 下次 `xcodebuild` 为准。
- `FilterKitHelper` target 仍未被 `FilterKit` scheme 单独构建，Helper 侧链接/签名问题可能延后暴露。
- `Bundle.main.executableURL` 在裸 root helper 进程下的返回路径待真机复验；warning 清理与 DEB/签名/jbroot/真机注入仍 pending，0.1 未闭环不签署。



## P2-25 — Authorized Transaction Recovery & Ledger Finalization (2026-11-26)

- Focused Helper/Execution/Runtime Linux `swiftc -typecheck`: PASS.
- Modified recovery, transaction, dispatcher, and host-smoke Swift source parse: PASS.
- `Build/Host/run-p225-authorized-recovery-smoke.sh`: PASS (rollback, commit, wrong-Transaction-ID rejection, operator confirmation, audit records, and crash-window retry).
- P2-24 reconciliation smoke: PASS.
- P1-31 three-file transaction/recovery hardening smoke: PASS.
- P2-12 AF_UNIX Health smoke: PASS.
- P2-15 audit sink smoke: PASS.
- Static audits P2-16 through P2-25: PASS (11/11, 11/11, 10/10, 12/12, 12/12, 14/14, 11/11, 10/10, 13/13, 18/18 respectively).
- Apple SDK/Xcode build, XCTest on Apple SDK, and RootHide device recovery tests: NOT RUN in this Linux environment.
- All production deployment and plugin-association write gates remain disabled.


## P2-29 — App Scan Prewarm & DEB Profile Externalization（2026-11-26，离线优化轮）

- 基线：上传包 `FilterKit-P2-28-Plugin-Toggle-Release-Gate.zip`；清除本地旧工作树后仅以该包为准。
- 本轮无 GitHub Actions Runner run；本机 Linux 无 Xcode/iOS SDK/ldid/lipo/otool，未做编译回归，编译结论以下次 Runner `xcodebuild` 为准。

### 改动文件与目录

- `Sources/Environment/CachedAppDiscoveryProvider.swift`（目录 `Sources/Environment/`）：新增 `nonisolated prewarm()`，detached 后台扫描填充缓存，失败静默，不阻塞启动；既有 `init(source:timeToLive:now:)` 与协议方法签名不变。`nonisolated` 保证 SwiftUI `.task` Sendable 闭包可同步触发，detached 任务再跨 actor 刷新。
- `App/MainTabView.swift`（目录 `App/`）：根视图 `.task` 调 `AppDiscoveryProviderRegistry.shared.prewarm()`，启动即后台预热库存。
- `Build/Config/DEB/roothide.env`（目录 `Build/Config/DEB/`，新增）：RootHide 包身份/架构/rootfs 负载/注册路径/依赖/control 元数据外置。
- `Build/Scripts/package-deb.sh`（目录 `Build/Scripts/`）：source 外置 profile，control/postinst 由 profile 变量装配；新增字段非空、负载路径以 bundle 名结尾、注册路径为 rootfs 形式、profile 包名与 App `Info.plist` 包名一致等断言；签名/嵌套 Mach-O 校验/解包复验流程保持不变。
- `Build/Scripts/ci-build.sh`（目录 `Build/Scripts/`）：非 RootHide 的 DEB/Both 拒绝信息补充可行替代（Rootless 用 IPA/None）。
- `.github/workflows/build.yml`（目录 `.github/workflows/`）：表单描述标注 DEB/Both 仅 RootHide；新增 package/environment 兼容性前置校验步骤，Rootless × DEB/Both 在构建前明确失败。

### 静态核对

- `bash -n` 通过：`package-deb.sh`、`ci-build.sh`；`test-deb-packaging.sh` 语法通过。
- workflow YAML 经 PyYAML 解析通过。
- 离线 drill：`roothide.env` 可被 source，必填字段非空，payload/register 路径断言通过。
- `AppDiscoveryTests` 引用的缓存初始化器与方法签名未变；全树缓存/Provider 引用已核对，Apps 与 Plugins 两屏仍复用 `AppDiscoveryProviderRegistry.shared`。
- 未开启任何生产写门禁；未补 Rootless DEB 产物；未注入、未装卸、未改目标 App Bundle。

### 未闭环 / 待下一轮 Runner 与真机复验

- 预热在冷启动首次进入 App 页（预热尚未完成）时仍显示 loading；两段式壳行上屏与在飞扫描去重留待后续单独评审。
- 单数组 LS 枚举对各 rootless/RootHide 组合的覆盖度需真机核对。
- Xcode 编译、XCTest Apple SDK、ldid 签名、`lipo`/`otool` 校验、Sileo 安装、冷启动与重启启动均未在本机执行；静态签名校验不证明 amfid/RootHide 接受与运行时权限。
- `verify-localizations.py` 报 `Resources/en.lproj/Localizable.strings:277` 语法无效；该文件与 P2-28 基线逐字节一致，属基线既有问题，本轮未改 Resources，留待后续单独处理。


## P2-30 — A2/A7 两段式上屏与重复排序收敛（2026-11-26，离线优化轮）

- 基线：P2-29 工作树；本轮落地用户授权的 A2、A7 两项。本机 Linux 无 Xcode/iOS SDK/ldid/lipo/otool，未做编译回归，编译结论以下次 Runner `xcodebuild` 为准。

### 改动文件与目录

- `Sources/Environment/LaunchServicesAppDiscoveryProvider.swift`（目录 `Sources/Environment/`）：删除扫描返回路径的二次 `sorted`，返回去重后的 `Array(apps.values)`；排序统一由缓存层 `deduplicatedAndSorted` 与显示层 `AppInventoryQuery.filter` 完成。
- `Sources/Environment/CachedAppDiscoveryProvider.swift`（目录 `Sources/Environment/`）：新增非扫描 `currentSnapshot() -> [InstalledApp]?`，仅读 `cachedApps`，不触发 LaunchServices 枚举；去重排序仍在 `deduplicatedAndSorted`。
- `Sources/Features/Apps/AppsView.swift`（目录 `Sources/Features/Apps/`）：`AppsViewModel.load(forceRefresh:)` 两段式——先在 `apps` 为空且有快照时上屏快照，再 await 扫描/刷新，完成后替换库存、更新 `scannedAt` 并异步加载关联；View loading/错误/空态条件不变。
- `Tests/UnitTests/AppDiscoveryTests.swift`（目录 `Tests/UnitTests/`）：新增 `testCurrentSnapshotReflectsCacheAndInvalidation`，覆盖快照首次为 nil、扫描后反映库存、失效后回 nil。

### 静态核对

- 三处 Swift 源文件与测试文件花括号配平通过；`currentSnapshot` 仅被缓存层定义与 Apps ViewModel 调用，Plugins 两屏仍只调 `scanInstalledApps()`。
- LS provider 无残留 `sorted`/`localizedStandardCompare`；既有测试不断言扫描侧返回顺序，删排序不破坏现有断言。
- 未开启生产写门禁；未补 Rootless DEB；未注入、未装卸、未改目标 App Bundle；未改 Resources。

### 未闭环 / 待下一轮 Runner 与真机复验

- 首次冷启动无快照、预热在飞未完成时仍走 loading；在飞扫描并发去重与 LS 枚举期流式轻量壳行留待后续单独评审。
- Xcode 编译、XCTest Apple SDK、ldid 签名、`lipo`/`otool` 校验、Sileo 安装、冷启动与重启启动均未在本机执行；静态签名校验不证明 amfid/RootHide 接受与运行时权限。
- `Localizable.strings:277` 为基线既有问题；DEB 安装/签名放行/jbroot API/真机注入验证仍 pending，0.1 未闭环不签署。


## P2-31 — Runner 编译修复：libproc 不可见符号与 Dispatcher 实参顺序（2026-11-26）

- 证据：Runner job `5c0ff41a-f249-5d7c-9d7d-0ad5a4ea287a`（workflow `b99bf07f-043e-432e-989e-9fedc21792c2`，macOS 15.8.2 arm64，FilterKit app target Release-iphoneos）；日志留存 `.tmp/ci-logs/p2-30/job-logs.txt`。编译期失败，未进入 XCTest；DEB 离线 drill 在 Swift 编译前已通过。
- 本机 Linux 无 Xcode/iOS SDK，未做编译回归；编译结论以下次 Runner `xcodebuild` 为准。

### 改动文件与目录

- `Sources/Environment/Helper/Transport/HelperPeerAuthenticationDiagnostics.swift`（`Sources/Environment/Helper/Transport/`）：新增 `hasKernelPeerEvidence`（存活 PID + 完整 audit token 哈希）作为公开平台门禁证据；组合 generation 证据函数保留供诊断展示与纯策略测试。
- `Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift`（`Sources/Environment/Helper/Transport/`）：两处 `auditTokenEvidenceIsSufficient` 改调 `hasKernelPeerEvidence`。
- `Sources/Environment/Helper/Runtime/HelperStartupRecoveryCheck.swift`（`Sources/Environment/Helper/Runtime/`）：恢复授权门禁改调 `hasKernelPeerEvidence`，错误码 `incompleteKernelEvidence` 保留。
- `Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift`（`Sources/Environment/Helper/Transport/`）：删除 `readPIDVersion` 及全部不可用 libproc 引用；identity 返回 `pidVersion: nil`，保留 credentials/audit token 双读比对与 csops CDHash；generation 错误 case 与诊断码字符串保留。
- `Sources/Environment/Helper/Runtime/HelperRuntime.swift`（`Sources/Environment/Helper/Runtime/`）：Dispatcher 调用实参顺序对齐声明（`deploymentIdempotencyLedger` → `deploymentLedgerStore` → `deploymentPipeline`）。
- `Sources/Environment/Helper/Runtime/HelperReleaseGenerationStore.swift`（`Sources/Environment/Helper/Runtime/`）：两处未变异 `var query` 改 `let query`；`var insert` 保留可变。
- `Tests/UnitTests/HelperPeerIdentityBindingTests.swift`（`Tests/UnitTests/`）：新增 `hasKernelPeerEvidence` 纯策略用例（完整 token + 存活 PID 通过；缺 token / PID=0 拒绝）。

### 静态核对

- 全树无 `proc_pidinfo`/`proc_bsdinfo`/`PROC_PIDT*`/`pbi_pidversion`/`readPIDVersion` 代码引用（注释保留 PRIVATE flavor 名说明）。
- 门禁三处均切到 `hasKernelPeerEvidence`；改动 Swift 文件花括号配平通过；`verify-project-config.sh` PASS、`verify-architecture.py` PASS。
- 既有授权夹具：完整 digest peer 通过；root peer 仍被 `peerMustBeUnprivileged` 拒绝；缺 digest incomplete peer 仍被新门禁拒绝，断言不破坏。
- 未开启生产写门禁；未补 Rootless DEB；未注入、未装卸、未改目标 App Bundle；未改 Resources。

### 未闭环 / 待下一轮 Runner 与真机复验

- PID generation 源在公开 SDK 不可用；未来私有头/entitlement 环境接入时复用保留的 `pidVersion` 字段与 `HelperPeerProcessGenerationBindingPolicy`，按平台显式开启，不得在公开路径引用 PRIVATE 结构。
- Xcode 编译、XCTest Apple SDK、ldid 签名、`lipo`/`otool` 校验、Sileo 安装、冷启动与重启启动均未在本机执行；静态校验不证明 amfid/RootHide 接受与运行时权限。
- DEB 安装/签名放行/jbroot API/真机注入验证仍 pending，0.1 未闭环不签署。


## P2-32 — 扫描动作 R16 对齐审计（规格评审，未改扫描源码，2026-11-26）

- 触发：P2-31 交付后，要求把 NEW 的 App 扫描与插件扫描动作口径对齐 R16 设计。本轮仅做双侧源码审计与规格评审，**未改动任何 `Sources/` 扫描代码**。
- 审计基准：R16 只读快照 `FilterKit-R16/`；NEW 工作树 P2-31 交付态。规格文档 `Build/P2-32-SCAN-R16-ALIGNMENT-AUDIT.md`。

### 已核对一致（不改）

- App 线：LS 类枚举与 `allInstalledApplications`→`allApplications` 回退、逐条读取与 Info.plist 单次解码、路径前缀系统判定、图标懒解码、bundleID 首条胜去重、名称本地化排序。
- 插件线：四固定相对目录、单层非递归、软链跳过、后缀小写、stem 小写配对、库存层不哈希/不解析 Mach-O/不查 dpkg、plist `Filter`??顶层解析、只读不写。

### 待对齐缺口（草案，待授权）

- A1 工作区实例获取缺方法存在性校验；A2/A3 容器兜底与关联侧 bundleID 校验过严，需对齐宽松口径。
- P1 静态关联匹配未做全量：`Bundles/Executables` 解析后未对已装 App 匹配，关联仅来自 manifest；P2 缺 R16 五态分类（exact_match/global/unmatched_target/invalid_configuration/unresolved）；P3 缺 `static_filter_match_only`/`loaded=unknown` 证据口径；P4 列表筛选仅所有权开关，未对齐配置/关联/证据三维；P5 条目文件事实位（size/regular/readable）待补；P6 枚举四态与单条目 partial 口径待对齐。
- 待授权开放项：是否保留 NEW 新增层（manifest/Mach-O 身份/所有权/Helper，默认保留）；静态匹配是否补全量（默认补，manifest 优先）；在飞合并与 partial 态是否本轮补；三维筛选模型/引擎与 UI 的落地次序；枚举状态机是否对齐。

### 边界与静态核对

- 红线不变：不改目标 App Bundle、不重签名、不自研注入引擎；库存层不碰 dpkg/哈希/Mach-O；不回退 Helper IPC、备份恢复与授权模型。
- 本机 Linux 无 Xcode/iOS SDK，未做编译回归；编译结论以下次 Runner `xcodebuild` 为准。
- 本轮无源码改动，仅新增规格文档；未开启生产写门禁，未补 Rootless DEB，未注入、未装卸、未改 Resources。

### 交付包（P2-32 规格评审态）

- `FilterKit-NEW-0.1.0-source.zip`：505 条目 / 710,667 B，SHA256 `0b1fad3f54b9b79a16037bf29bcf0023b68e321eda42d76dccc4e56b3960d00d`。
- 待授权落地后按排除口径重打并更新条目数/字节/哈希。


## P2-33 — 应用扫描在飞任务合并与首屏提速（2026-11-26，离线优化轮）

- 证据：两段真机录屏对比——新版 4.83s（2.4s 首页占位、3.6s 才出 114 应用，中间蓝色加载过渡）；旧版 2.77s（0.3s 首页已带 266 计数、1.8s 直接出列表，无过渡）。目标为加速上屏，不补首页仪表盘内容。
- 本机 Linux 无 Xcode/iOS SDK，未做编译回归；编译结论以下次 Runner `xcodebuild` 为准。

### 改动文件与目录

- `Sources/Environment/CachedAppDiscoveryProvider.swift`（目录 `Sources/Environment/`）：新增 `inFlight` 任务与 `sharedRefresh()`，复用同一在飞枚举；`finalizeRefresh` 一次性写缓存并清在飞，失败不写缓存可重试；`scanInstalledApps`/`refreshInstalledApps` 走合并路径；`prewarm` 非阻塞外层不变。
- `Tests/UnitTests/AppDiscoveryTests.swift`（目录 `Tests/UnitTests/`）：新增并发扫描复用用例，断言底层 source 仅调用一次。

### 静态核对

- 缓存层与测试文件花括号配平通过；`verify-project-config.sh` PASS、`verify-architecture.py` PASS。
- 协议签名、`InstalledApp` 字段、Apps/Plugins 两屏共享 `AppDiscoveryProviderRegistry.shared` 不变；既有 TTL/绕缓存/去重/快照断言不破坏。
- 未开启生产写门禁；未补 Rootless DEB；未注入、未装卸、未改目标 App Bundle；未改 Resources；未做流式壳行改造。

### 未闭环 / 待下一轮 Runner 与真机复验

- 首次冷启动无快照、在飞未完成时应用页仍走 loading；LS 枚举期流式轻量壳行留待单独评审。
- 真机复核：预热命中表现、页面切换是否只触发一次枚举、首屏到列表实际耗时。
- Xcode 编译、XCTest Apple SDK、ldid 签名、`lipo`/`otool` 校验、Sileo 安装、冷启动与重启启动均未在本机执行；DEB 安装/签名放行/jbroot API/真机注入验证 pending，0.1 未闭环不签署。

### 交付包（P2-33 在飞合并态）

- `FilterKit-NEW-0.1.0-source.zip`：507 条目 / 714,626 B，SHA256 `8375c3741f987968b99d0cea5b3b6fdac9decf5218e53490d499bc391cb3b108`。

### P2-34 — 重复源文件同名冲突（job 9a609b49，2026-11-26）

- 错误：app target 编译期 `filename "CachedAppDiscoveryProvider.swift" used twice`，`Sources/CachedAppDiscoveryProvider.swift`（仓库根目录旧副本）与 `Sources/Environment/CachedAppDiscoveryProvider.swift`（现行）同时被纳入。
- 根因：CI 纯 `actions/checkout@v4`，仓库根目录残留早期骨架旧副本；`Project.yml` 递归 `- path: Sources` 把两份都编入 target。本地工作树/zip 不含残留，无法本地删除。
- 修复：FilterKit target Sources 改为显式 7 个一级子目录（Core/DesignSystem/Environment/Features/Localization/Persistence/Shared），根层散落旧文件天然不纳入；122 个 Swift 全覆盖。仅改 `Project.yml`。
- 仓库侧待办：删除根目录 `Sources/CachedAppDiscoveryProvider.swift`（保留 Environment 现行版），核对 Sources 根目录有无其他早期骨架 `.swift`。
- 静态核对：PyYAML 解析通过，9 条 source 路径本地均存在；Helper/Tests target 未动。Runner `xcodegen generate`/`xcodebuild` 结论待下轮复验。

### 交付包（P2-34 重复源文件修复态）

- `FilterKit-NEW-0.1.0-source.zip`：509 条目 / 717,797 B，SHA256 `cb4fc9008445c4b3f8555aa014a7b1ac9ee70c5b8ab6c5ebc58dc7b01bc86d60`（回填前一版；文档自引用，覆盖重打包后哈希差一版，以最终文件为准）。
- 包内仅含 `Sources/Environment/CachedAppDiscoveryProvider.swift` 现行版，无根目录旧副本。

### P2-35 — 预热 / 共享快照 / 行内进度（对齐 R16 首屏体验）

- 口径：不删加载态代码；状态标志与加载/错误/空/失败分支全部保留，仅调整扫描时机、快照持有与壳摆放。扫描算法仍用 NEW 自有通路。
- 新增 `Sources/Environment/PluginScanRegistry.swift`：单例持最近成功快照、复用在飞后台扫描、失败保留旧快照；探测与枚举在 detached utility 任务内。
- `PluginsViewModel` 改读 registry，移除页面内自建 scanner 与主线程同步 `makeDiagnosticReport()`；App 名映射后置 enrich。
- `MainTabView.task` 启动预热 App 库存与插件 registry。
- Apps/Plugins 两页首次扫描的整页 loading 壳改为 List 先行 + 行内 ProgressView Section；终态分支保留。
- 静态核对：改动文件括号配平；registry 在飞任务泛型 `Task<PluginScanResult, Error>`；无旧 `model.result/isLoading` 残留；测试未引用新接口。版本号仍 1.0.0。
- 待 Runner/真机复验：编译通过、预热命中、在飞复用、首屏到列表实际耗时；单次枚举重量优化待真机剖面后再定。

### 交付包（P2-35 预热/快照/行内进度态）

- `FilterKit-NEW-0.1.0-source.zip`：512 条目 / 723,558 B，SHA256 `71c313882e450d60a776565f258bfa9f2423361c23dea93676257fdb67fcfe5f`（回填前一版；文档自引用，覆盖重打包后哈希差一版，以最终文件为准）。
- 包内仅含 `Sources/Environment/` 现行源文件，无根目录旧副本；版本号仍 1.0.0。

### P2-36 — DEB 打包 / CI 一致性修复（B1）

- 口径：只修 CI 入口与脚本一致性；不改 DEB 布局、不造 Rootless 路线、不接签名闭环、不动 App/Helper 源码。
- `select-environments` job 新增输入级兼容校验：`package ∈ {DEB, Both}` 且 `environment ≠ RootHide` → exit 30，在生成 matrix 前拦截 `Rootless+DEB/Both` 与 `Both+DEB/Both` 矛盾组合。
- `build` job 节点级兼容校验从装依赖/管线自测之后前移到 `checkout` 之后；作为 matrix 展开后的第二道防线，口径与输入级一致。
- 表单 `environment`/`profile`/`package` 描述如实标注：仅 RootHide 闭环，Rootless/Both profile 未注册；拒绝文案统一，不再暗示 Rootless 可走 IPA/None。`ci-build.sh` DEB 门禁文案对齐 workflow，退出码 30 不变。
- 刻意未改：Rootless DEB 布局、Helper target 进 CI 编译、IPA 签名、arm64e 真切片、Rootless profile 容错（`verify-local-build.sh` 断言要求 Rootless 必须被拒）。
- 静态核对：`bash -n` 三个打包脚本通过；`build.yml` PyYAML 解析通过。Runner `xcodegen`/`xcodebuild`/XCTest/ldid 结论待下轮复验。

### 交付包（P2-36 DEB/CI 一致性修复态）

- `FilterKit-NEW-0.1.0-source.zip`：513 条目 / 726,931 B，SHA256 `82f5ed59c8e67bbcebf3a01178e0264ca58b2c69f817cb2bef5366aeccfedfd6`（回填前一版；文档自引用，覆盖重打包后哈希差一版，以最终文件为准）。
- 包内含 P2-36 规格、更新后的 `build.yml` 与 `ci-build.sh`；无根目录残留 Swift，版本号仍 1.0.0。

### P2-37 — run 124047030764 编译错误修复（PluginScanRegistry 可选解包）

- 环境：macOS 15.8.2 / macos-15-arm64 / Xcode 16.4 (16F6)，仓库 yi-fen/FilterKit@main，RootHide + DEB。
- 失败：`Build and package` 步骤 exit 65，唯一编译错误 `Sources/Environment/PluginScanRegistry.swift:47:46: error: value of optional type 'PluginDirectoryAssessment?' must be unwrapped to a value of type 'PluginDirectoryAssessment'`。
- 根因：`ReadOnlyPluginScanner(assessmentProvider:)` 闭包返回非可选 `PluginDirectoryAssessment`，而 `report.pluginDirectoryAssessment` 为 `PluginDirectoryAssessment?`；P2-35 registry 直接把可选值传入闭包，类型不匹配。
- 修复：先 `if let assessment = report.pluginDirectoryAssessment` 解包；有值才注入 provider；为 nil 时构造无 provider 的 `ReadOnlyPluginScanner()`，走既有 unresolved-directory 通路（不凭空造兜底 assessment）。口径与 `Sources/Features/Apps/AppsView.swift:48-52` 既有解包一致。
- 核对：`PluginDirectoryAssessment` 为 struct 值类型，闭包捕获安全；registry 括号配平通过；PluginsView 无旧 environment 属性/自建 scanner 残留；管线自测 `test-deb-packaging.sh` 在本轮日志 PASS。
- 待 Runner 复验：`xcodegen generate` / `xcodebuild` Release device 编译通过、XCTest、ldid 签名；本机无 Xcode 未实编。

### 交付包（P2-37 registry 可选解包修复态）

- `FilterKit-NEW-0.1.0-source.zip`：513 条目 / 727,601 B，SHA256 `779da57829f07f0c2ecad892435303e0449c2380783b0065f13342072b61bfe1`（回填前一版；文档自引用，覆盖重打包后哈希差一版，以最终文件为准）。
- 本轮仅改 `Sources/Environment/PluginScanRegistry.swift`；版本号仍 1.0.0。

### P2-38 — App/插件扫描装配时序后置（A1–A3）

- 口径：只调装配时序，不改扫描算法/协议/模型/配对归属。
- A1 `PluginsView.swift`：`enrichAppNames()` 不再 `await` 阻塞 `load()`；后台 `@MainActor [weak self]` 先填 `currentSnapshot()` 名字，扫描刷新后覆盖回填；抽出 `applyAppNames`。
- A2 `ReadOnlyPluginAssociationReader.swift`：新增可选 `snapshotApps` 注入，有快照直接用，为 nil 才回退扫描；协议未改，stub 测试走原路径。
- A3 `AppsView.swift`：`loadAssociations` 后台后置，`associatedBundleIDs` 就绪补全；参数类型收窄为 `CachedAppDiscoveryProvider` 以取快照传给 reader。
- 静态核对：三文件括号配平；无旧 `await enrichAppNames` 残留；后台任务均 weak self；测试不引用 ViewModel 私有方法。
- 待 Runner/真机复验：编译与 XCTest 通过；冷启动主库存先上屏、辅助信息后台补全；warm 缓存不触发二次 LS 枚举。

### 交付包（P2-38 装配时序后置态）

- `FilterKit-NEW-0.1.0-source.zip`：514 条目 / 730,844 B，SHA256 `39d3ced898532470210743809370a191e51fc681c41be5333fb6d5f70de75da6`（回填前一版；文档自引用，覆盖重打包后哈希差一版，以最终文件为准）。
- 本轮改 `PluginsView.swift`、`ReadOnlyPluginAssociationReader.swift`、`AppsView.swift`；版本号仍 1.0.0。

### P2-39 — init 同步快照时机对齐 R16

- 口径：只调首帧装配时机，不改扫描算法/协议/模型/枚举口径。
- `CachedAppDiscoveryProvider.swift`：新增 NSLock 保护的 `mirror` 同步只读镜像与 `nonisolated currentSnapshotSync()`；`finalizeRefresh` 成功写镜像、`invalidateCache` 清镜像；原 actor 隔离 `currentSnapshot()` 保留。
- `AppsView.swift`：`AppsViewModel.init()` 同步读 `currentSnapshotSync()` 填 `apps`，预热命中时首帧直接出列表；预热未完成仍走行内进度兜底。
- `AppDiscoveryTests.swift`：增补同步镜像扫描后有值、失效后为 nil 断言。
- 静态核对：三文件括号配平；`currentSnapshotSync()` 仅定义/init 调用/测试引用；插件页由 registry 单例持有快照，未改。
- 待 Runner/真机复验：编译与 XCTest 通过；预热命中不闪壳；首次冷启动无快照仍显行内进度；镜像与 actor 缓存刷新/失效/失败保留一致性。

### 交付包（P2-39 init 同步快照态）

- `FilterKit-NEW-0.1.0-source.zip`：515 条目 / 733,771 B，SHA256 `03988eab434c04831a0a0aa9c393c6ba9846671a19c51df76a08defdd6bd0bd1`（回填前一版；文档自引用，覆盖重打包后哈希差一版，以最终文件为准）。
- 本轮改 `CachedAppDiscoveryProvider.swift`、`AppsView.swift`、`AppDiscoveryTests.swift`；版本号仍 1.0.0。
