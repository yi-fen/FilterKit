# R4-B2 Diagnostics Port — 非界面层 `swift build` 编译失败诊断（run 44820826563，2026-11-21）

> 范围：0.1-D-R4-B2「0.1.18 只读诊断端口」在 macOS runner 上的 SwiftPM 非界面层编译 job（Models / Adapters / AppPresentation / Core）。不涉及 R4-G 真机冒烟、签名放行、entitlement 注入，不涉及 0.1-E-B 发布验收。
> 证据来源：GitHub Actions `build` job 原始 `job-logs.txt`（Azure blob，SAS 于 2026-11-21 00:26:59Z 过期前取回全文核对）。Runner 检出基线 commit `f13989a0846aa82c4dda6f813b16a9a08bdab93c`（`origin/main`，仓库 `yi-fen/FilterKit`），与用户上传快照 `FilterKit-0.1-D-R4-B2-Source-Diagnostics-Port.zip` 内 `Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift` 逐字节一致。

## 1. Runner 实跑结果

| 项目 | 结果 |
|---|---|
| Workflow run ID | `44820826563` |
| Job | `build`（非界面层 `swift build`，与 R4 设备构建 / IPA / DEB 打包链路为不同 job） |
| Job run UUID | `e041a6b8-bd60-5af1-91a8-a54d6423e596` |
| Checkout SHA | `f13989a0846aa82c4dda6f813b16a9a08bdab93c`（`origin/main`，fetch-depth 1） |
| Runner | 2.338.2，westus / MacCloud；macOS 26.7.2（25G332），image `macos-26-arm64` `20261102.0473.1` |
| 工具链 | Xcode `Xcode_26.6`，SDK `MacOSX26.5.sdk`，git 2.56.0，swift-version `7974D3F7F03D5E95.txt` |
| 失败命令 | `set -o pipefail` → `mkdir -p .build` → `swift build 2>&1 | tee .build/swift-build.log` |
| Models 模块 | emit-module 通过 |
| Adapters 模块 | emit-module 通过 |
| AppPresentation 模块 | emit-module 通过 |
| Core 模块 | **失败**：`error: emit-module command failed with exit code 1` |
| 退出码 | `##[error]Process completed with exit code 1` |
| 失败产物 | artifact `filterkit-non-ui-build.zip`（仅 `.build/swift-build.log`，4106 B，Artifact ID `14671841990`，SHA256 `e30629f8f96e813729d198ce1271a24b887979e9367839ea277788c612cc4cd8`）；下载地址 `https://github.com/yi-fen/FilterKit/actions/runs/44820826563/artifacts/14671841990` |

- 编译进度：141 个 Core 源文件全部进入编译队列；日志全文按 `error:` / 文件路径检索，报错**仅此一个文件**，无第二个报错源文件。
- 本轮是 B2 端口代码首次在 Apple 工具链下编译。端口记录中此前的 `swiftc -typecheck` 仅在 Linux 工具链完成，Darwin / CommonCrypto / UIKit / Objective-C 条件分支未在 Apple 侧 typecheck，因此这四类门槛问题此前未暴露。

## 2. 报错清单（四条独立诊断，同一文件）

失败文件：`Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift`（Runner 路径 `/Users/runner/work/FilterKit/FilterKit/Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift`）。

| # | 位置 | 报错原文 | 附注 |
|---|---|---|---|
| E1 | L275:34，`roothideJBRoot()`（`#if canImport(Darwin)` 内） | `error: cannot find 'RTLD_DEFAULT' in scope` | `dlfcn.h:97:9: note: macro 'RTLD_DEFAULT' unavailable: structure not supported`；`#define RTLD_DEFAULT ((void *) -2)` |
| E2 | L288:34，`roothideJBrand()`（`#if canImport(Darwin)` 内） | `error: cannot find 'RTLD_DEFAULT' in scope` | 同上，`dlfcn.h:97` 宏不可用 |
| E3 | L554:33，`fileCategory(path:physicalPath:)` | `error: 'close()' is only available in macOS 10.15 or newer` | 建议 `if #available` 版本检查，或给类 / 方法加 `@available` |
| E4 | L555:39，`fileCategory(path:physicalPath:)` | `error: 'read(upToCount:)' is only available in macOS 10.15.4 or newer` | 同上可用性建议 |

日志中 E1～E4 随每个编译通道重复打印，诊断种类与行号以上表为准；`dlsym` 符号本身已被 Darwin overlay 导入，未报「cannot find dlsym」。

## 3. 根因分析

### R1（E1/E2）：`RTLD_DEFAULT` 是指针转换 C 宏，Swift Clang importer 不导入

- `dlfcn.h:97` 定义 `#define RTLD_DEFAULT ((void *) -2)`，属指针字面量转换宏；Swift 导入层对这类 cast 宏给出 `macro unavailable: structure not supported`，宏名不在 Swift 作用域内，故两处 `dlsym(RTLD_DEFAULT, …)` 编译期找不到 `RTLD_DEFAULT`。
- 常规绕法不依赖宏导入：按位模式 `-2` 在 Swift 侧构造 `UnsafeMutableRawPointer` 句柄，传给 `dlsym` 首参（类型 `UnsafeMutableRawPointer?`）。位模式与 `dlfcn.h:97` 宏值一致，语义等同默认搜索算法。

### R2（E3/E4）：现代 FileHandle API 抬高了 macOS 可用性门槛，Package 未声明 platforms

- `FileHandle.close()` 自 macOS 10.15 起可用；`FileHandle.read(upToCount:)` 自 macOS 10.15.4 起可用。
- `Package.swift`（`swift-tools-version:5.7`）未声明 `platforms:`，SwiftPM 默认部署目标低于上述门槛，编译器对两处现代 API 报可用性错误。
- 同目录 `ReadOnlyFileHasher.swift` 使用的是 `InputStream` 旧式接口（`stream.close()` / `stream.read(&buffer, maxLength:)`），本轮通过编译。

### 排除项（本轮未成立）

- 不是 dlsym 未导入、不是符号名拼写错误、不是 `import Darwin` 缺失。
- 不是 Models / Adapters / AppPresentation 层问题；三模块 emit-module 均通过。
- 不是部署目标被主动抬高；`Package.swift` 无 `platforms:` 声明，Deployment Target（B1/B2/B5）仍为待冻结项。

## 4. 修复方案与落地位置

**唯一改动源码文件：`Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift`**（相对基线 `f13989a`，+16 / -6）。

### 4.1 E1/E2 — 用位模式常量替代 `RTLD_DEFAULT` 宏

在 `ReadOnlyDiagnosticsEngine` 类内新增私有静态句柄：

```swift
// RTLD_DEFAULT is the C macro `((void *) -2)` in dlfcn.h. Swift does not
// import pointer-cast macros, so reconstruct the handle from its bit
// pattern instead of referencing the unavailable `RTLD_DEFAULT` symbol.
// The optional type matches dlsym's handle parameter (`UnsafeMutableRawPointer?`).
private static let rtldDefaultHandle: UnsafeMutableRawPointer? = UnsafeMutableRawPointer(bitPattern: -2)
```

两处调用点由 `dlsym(RTLD_DEFAULT, …)` 改为 `dlsym(Self.rtldDefaultHandle, …)`：

- `roothideJBRoot()`：`dlsym(Self.rtldDefaultHandle, "jbroot")`
- `roothideJBrand()`：`dlsym(Self.rtldDefaultHandle, "jbrand")`

不改动符号名、`@convention(c)` 函数类型别名、`unsafeBitCast` 调用结构；符号查找仍为可选失败（返回 `nil`），不构成真实注入或弱链接。

### 4.2 E3/E4 — FileHandle 改用旧式兼容接口，不抬高平台基线

`fileCategory(path:physicalPath:)` 内由现代 throwing API 改为旧式 Foundation 接口：

| 原写法（门槛） | 改后写法（旧式可用） |
|---|---|
| `defer { try? handle.close() }`（10.15） | `defer { handle.closeFile() }` |
| `let sample = (try? handle.read(upToCount: 4096)) ?? nil`（10.15.4） | `let sample = handle.readData(ofLength: 4096)` |
| `[UInt8]((sample ?? Data()).prefix(16))`；`String(data: sample ?? Data(), …)` | `sample` 改为非可选 `Data`，同步去掉两处 `?? Data()` |

- `closeFile()` / `readData(ofLength:)` 为 macOS / iOS 早期即有的旧式 FileHandle 接口，不受 10.15 / 10.15.4 门槛约束。
- **未**在 `Package.swift` 追加 `platforms: .macOS(.v10_15_4)`，**未**给类 / 方法加 `@available`，**未**引入 `if #available` 分支；Deployment Target 维持待冻结状态。
- 读写语义不变：最多读取前 4096 字节、只取前 16 字节判 Mach-O / ELF magic 与 UTF-8 文本；文件不存在 / 不可读时仍走扩展名兜底分类。

## 5. 改动文件目录清单

| 路径 | 改动 |
|---|---|
| `Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift` | 唯一源码改动：新增 `rtldDefaultHandle` 常量；两处 `dlsym` 句柄替换；FileHandle 读取 / 关闭改旧式接口；`sample` 可选包装清理 |

未改动：`Package.swift`、`Models/`、`Adapters/`、`App/Presentation/`、`App/Features/`、`Core/` 其余子目录、`Tests/`、`Tools/`、CI 工作流与打包脚本。

## 6. 边界与未改项

- 全程只读语义不变：不写 plist / 配置，不装卸插件，不改 dpkg，不启动 / 通信 helper，不注入，不改软链。
- 端口内 `jbroot()` / `jbrand()` 运行时签名、私有 `LSApplicationWorkspace` selector 行为、RootHide arm64e 与 Rootless 路径映射仍归真机门禁（R4-G / 0.1-E-B）；本轮静态编译修复不构成上述真机证据。
- 未新增弱链接、未伪造外部 C 函数声明、未放行 entitlement、未改签名配置。
- 本机为 Linux 环境，无 `swift` / `swiftc` / Xcode / ldid / codesign；本轮仅做静态核对：括号 / 圆括号配平、全树残留现代 API 扫描、`dlsym` / `RTLD_` 引用复核。编译通过与否以下一轮 macOS Runner `swift build` 日志为准。

## 7. 静态核对记录（本机离线）

- 残留扫描：`Core/`、`Models/`、`Adapters/`、`App/Presentation/`、`Tools/` 内不再出现 `RTLD_DEFAULT`、`read(upToCount:`、`try? handle.close()`；`readData(ofLength:)` / `closeFile()` 为本轮新引入的旧式接口。
- 全树未发现 `Task` / `async` / `await` / `Continuation` / `URLSession` / `Process(` / `NSWorkspace` 等其余高门槛并发或平台 API。
- `AssociationSnapshotStore.swift` 的 `Data.write(to:options: [.atomic])` 为旧式 Foundation 接口；`ReadOnlyFileHasher.swift` 保持 `InputStream` 旧式读取，本轮 Runner 日志未对其报错。
- 括号配平：engine 文件 `{`/`}` 169/169，`(`/`)` 479/479。

## 8. 待下一轮 Runner 复验与沿用未闭环项

1. 下一轮 `build` job 复验：Core emit-module 通过，`swift build` 退出码 0；`test` job 随后跑 `swift test` 全套（本轮 `build` 失败，`test` 未到达）。
2. 待真机 / 上游复核：`jbroot()` / `jbrand()` 签名与私有 Workspace selector 在 RootHide arm64e 设备上的返回；Rootless 路径 / dpkg 映射；校验和差异分桶与真实 patched / resigned Mach-O、Conffiles 夹具比对。
3. 沿用既有未闭环（本轮未触碰）：H4 切片 / 弱链接 / rpath / 签名与 entitlement 嵌入；H5 `uicache` 与 `/Applications`→JBROOT 映射；真机闪退 C1～C5 无 `.ips` / 系统日志待设备取证；G10～G15、R4-G 保持 pending/unknown。0.1-D 未闭环不签署、不进入 0.1-E-B。
