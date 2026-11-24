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


