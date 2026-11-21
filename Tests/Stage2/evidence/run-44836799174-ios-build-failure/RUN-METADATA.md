# RUN-METADATA.md — 0.1-D Diagnostics-Port 第二轮 Runner：iOS device/simulator 构建 dyld 符号不可见（run 44836799174）

- Run 作业：GitHub Actions run `44836799174`；仓库 `yi-fen/FilterKit` / 分支 `main`；日志包 `logs_121358275123.zip`（77 个文件，含 9 个 job 的分步日志）。
- Runner SHA：`fb8a6932bfe7d9f1f21bfe8b9cf68f167dd08790`（fetch-depth 1；本地链未含该对象，以 Runner 检出为准）。
- 时间：2026-11-20 23:26:27Z 起；environment 23:26:30，build 23:27:24–23:27:37，device-build 23:28:44 exit 65，app-build 23:29:02 exit 65，package-validation 23:28:59，artifact 23:29:55。
- Runner：macOS 26.7.2（25G332），镜像 `macos-26-arm64` 20261117.0516.1；Xcode 26.6（17F113）；Swift 6.3.3（swiftlang-6.3.3.1.3 clang-2100.1.1.101）；swift-driver 1.148.6；iOS SDK 26.5（iphoneos26.5 / iphonesimulator26.5）。
- 证据：本目录完整保留日志包解包结构（顶层 `*.txt` 聚合日志 + 各 job 分步目录）；下载 SAS 票据已过期，以本落盘副本为准。

## 1. Job 结果矩阵

| Job | 目标 / 命令 | 结论 | 证据 |
|---|---|---|---|
| environment | 环境与工具链记录 | ✅ 通过 | Xcode 26.6 / Swift 6.3.3 / iOS 26.5 SDK 记录完整 |
| build | 非 UI macOS SwiftPM `swift build` | ✅ 通过 | `Build complete! (27.62s)`，0 error / 0 warning；Models / AppPresentation / Adapters / ReportRoundtripValidator / Core emit 与链接通过；上一轮 run 44835136866 的三类修复在 macOS 编译单元复测通过 |
| isolation | Adapter / parser / App 隔离静态检查 | ✅ 通过 | 1a/1b/2a/2b/3/4/4b 七项 `passed`，`failed: 0`；artifact `filterkit-isolation`（ID `14679710223`，891 B，SHA256 `fdf5038eb43334dc52619afa86d4eebb453b2718069d84e25f5d60562cb29cb7`） |
| signing-prep | entitlements 静态校验 | ✅ 通过 | t1 plist 可解析 / t2 候选键在位 / t3 无未批准键，`failed: 0`；artifact `filterkit-signing-prep`（ID `14679271562`，5689 B，SHA256 `d0ee761fae1809779836dc6a76c155dbb6d301b24f4d7e747e67bb0c43dabd42`） |
| test | 全量 Swift 测试 + S1-05 独立过滤 | ✅ 通过 | 全量 **458 tests，0 failures（0 unexpected）**；`PluginPairingS105FixtureTests` **15 tests，0 failures**；artifact `filterkit-test-log`（ID `14678024877`，12779 B，SHA256 `abb4000c8e26742521b54a6f6d47e047816fe1b3fcf604625d94f71bb7d8e3fe`） |
| device-build | `xcodebuild -sdk iphoneos -destination generic/platform=iOS ARCHS=arm64 Release` | ❌ exit 65 | `** BUILD FAILED **`；Core 目标两个 dyld 符号报错（见 §2）；artifact `filterkit-device-build` 仅失败日志 |
| app-build | `xcodebuild -destination generic/platform=iOS Simulator Debug`（arm64 + x86_64 两切片） | ❌ exit 65 | `** BUILD FAILED **`；同一对 dyld 符号在两切片各报一次；artifact 仅失败日志 |
| package-validation | 元数据归集与 JSON 解码 | ⚠️ 门禁 Pending | Build `Pending`、IPA Package `Pending`、DEB Package `Pending`（device/app 构建失败无产物，sha256 `unavailable`）；Entitlements Static Passed；metadata JSON decodable；artifact `filterkit-package-validation`（ID `14677989984`，SHA256 `1a3c61d9007e6331011d0c25dce6b9e99deb36ca0a29d6ee6ed522b7bd2fa8dc`） |
| artifact | 构建元数据归集上传 | ✅ 通过 | artifact `filterkit-build-metadata`（ID `14678902142`，46595 B，SHA256 `f3d7073ad79a5a432a37ec8bdc84a23b4d4c4ee6f2ce23ed38fd2341c6e3dee6`） |

## 2. 编译错误诊断（Runner 路径 `/Users/runner/work/FilterKit/FilterKit/`）

### E1/E2 — iOS 编译单元找不到 dyld 镜像枚举符号（device-build 1 切片 + app-build 2 切片，各 2 条，共 6 条同源 error）

- 报错（`Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift:454:26`）：`error: cannot find '_dyld_image_count' in scope`。
- 报错（同文件 `:455:33`）：`error: cannot find '_dyld_get_image_name' in scope`。
- 出错方法：`private static func runtimeInjectorImages()`，枚举当前进程已加载镜像并按 ellekit / substrate / substitute / libhooker / sandy 关键词归类，证据 `scope: current_process_only`（对照参考实现 `reference/0.1.18-src/Sources/Core/FKScanner.m` `FKRuntimeInjectorImages()`）。
- 根因：这两个 C 符号声明于 `<mach-o/dyld.h>`，属于 `MachO.dyld` 子模块。macOS SwiftPM 的 Darwin 伞头将其透出，故非 UI `swift build`（build job）可解析；iOS device / Simulator SDK 不经 Darwin 伞头重导出该子模块，Xcode 显式模块编译单元下 `import Darwin` 后符号不在作用域内，报 `cannot find in scope`。日志无 `no such module`、无 availability 标注、无链接期未定义符号（编译期即失败）。
- 对照：开源 iOS Swift 工程（IOSSecuritySuite `import MachO // dyld`；CallStackReporter / InterposeKit `import MachO.dyld`）均需显式导入该模块后方可调用 `_dyld_image_count` / `_dyld_get_image_name`。

### 修复（唯一源码文件 `Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift`，+4/-0）

- 在既有 `#if canImport(Darwin)` 块内追加 `import MachO.dyld`（含注释说明模块归属与 iOS 伞头不重导出的原因）；调用点、函数签名、证据字段与保守口径均不变。
- 未改用 dlsym 动态解析：符号为 dyld 公开导出、模块导入为 Apple 平台标准做法；非 Darwin 平台由 `canImport(Darwin)` 整块排除，Linux 编译单元不引用该子模块。

## 3. 本地静态核对（2026-11-21，本机 Linux 无 Swift 工具链）

- 引擎文件括号配平：花括号 279/279、圆括号 704/704、方括号 450/450；`#if` 12 / `#endif` 12 配平。
- 全仓 `*.swift`（排除 `research/`）扫描：直接 dyld 下划线符号 / `mach_header` / `MH_*` / `getsegbyname` 仅命中本文件 454/455 两行；无其他待导入 MachO 子模块符号。
- 十枚 `scripts/*.sh` `bash -n` 通过；`compare-app-bundles.py` `py_compile` 通过；workflow YAML 解析通过。
- 未在本机执行 Swift 编译/测试；device-build / app-build 编译结论以下一轮 Runner 复测为准。

## 4. 边界保持

- 未改 Adapter 七方法协议、冻结公共 Models、`ReportEnvelope`、Plist Parser 语义、Stage1 fixtures；未改 `loaded` / `installed` / `configured` 语义。
- 未触插件启停、plist/规则写入、dylib 删移、dpkg 写、软链改动、注入、Helper 启动/IPC/`launchctl`、常驻 daemon、entitlement/签名/沙盒例外放行；未 dlopen 插件、未执行插件代码、未写伪造 C 声明/弱链接/dlsym 伪造符号。
- 当前进程 dyld 镜像证据仍仅限当前进程；静态包指纹与运行时镜像两条证据线不互相替代；缺证据项保持 unknown/unverified。
