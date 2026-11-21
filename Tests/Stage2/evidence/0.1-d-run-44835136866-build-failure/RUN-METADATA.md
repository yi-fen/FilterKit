# RUN-METADATA.md — 0.1-D Diagnostics-Port 首轮 Runner 编译反馈：Core emit-module 失败（run 44835136866）

- Run 作业：`workflow-job-run-f8f6dd02-117a-5f5b-8613-99c7c439ee36`；仓库 `yi-fen/FilterKit` / 分支 `main`；job 名 `build`（`mkdir -p .build && swift build 2>&1 | tee .build/swift-build.log`）。
- Runner SHA：`828e69f9fcd90c4ea99c7e5cf73471ffd5eb00ab`（fetch-depth 1；本地链未含该对象，以 Runner 检出为准）。
- 时间：2026-11-20 23:13:24Z 起；`swift build` 23:13:28 启动，23:14:08 exit 1（`Process completed with exit code 1`）。
- Runner：macOS 26.7.2（25G332），镜像 `macos-26-arm64` 20261117.0516.1；runner 2.338.2（Hosted Compute Agent 20261111.635，commit `b8a594ea514ff44cadb5342986c68b1eac6e22ed`），region westus，Cloud MacCloud。
- 原始日志：`job-logs.txt`（76337 字节，UTF-8 BOM，含 ANSI 转义序列）；下载 SAS 票据已过期，以本落盘副本为准。
- 产物：artifact `filterkit-non-ui-build`（Artifact ID 14676389058，2757 字节，SHA256 `71400283c23aa213521a2fca05b3cd98bc1e2154aec6e099b0ffc3f0b3fe2905`）；下载 `https://github.com/yi-fen/FilterKit/actions/runs/44835136866/artifacts/14676389058`。
- build 失败后 job 直接 cleanup，**未执行 `swift test`**。

## 1. Job 结果

| 模块 / 阶段 | 结论 | 证据 |
|---|---|---|
| Models | ✅ emit | `[13/24] Emitting module Models` |
| Adapters | ✅ emit | `[23/35] Emitting module Adapters` |
| AppPresentation | ✅ emit | `[29/37] Emitting module AppPresentation` |
| ReportRoundtripValidator | ✅ 编译/链接 | `[35/81] Emitting module ReportRoundtripValidator` → `[38/101] Linking ReportRoundtripValidator` |
| Core | ❌ emit-module 失败 | `[38/81] Emitting module Core`；同一引擎文件在多个 Core 编译单元重复报错 |
| Stage2Tests / 测试执行 | ⏭ 未到达 | build exit 1，日志无 `swift test` 阶段 |

## 2. 报错诊断（Runner 路径 `/Users/runner/work/FilterKit/FilterKit/`，均位于 `Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift`）

### 2.1 E1/E2 — magicFormat 元组模式长度错配（84 条同源 error）

- 报错：`tuple pattern has the wrong length for tuple type '(UInt8, UInt8, UInt8, UInt8)'`。
- Runner 802:14：`case (0xFF, 0xD8, 0xFF): return "jpeg"`；Runner 804:14：`case (0x1F, 0x8B): return "gzip"`。
- 根因：switch 对象是 4 元组 `(b0, b1, b2, b3)`，jpeg/gzip 分支只写 3 / 2 个元素；Swift 要求模式元组长度与类型一致。两类签名缓冲长度本就短于 4 字节，原写法在 `guard bytes.count >= 4` 之后亦属不可达。
- 修复：短缓冲签名（jpeg 3 字节、gzip 2 字节）在 4 元组 switch 之前按字节位置单独 `if` 判定；switch 内两分支改为 4 元组通配 `case (0xFF, 0xD8, 0xFF, _)` / `case (0x1F, 0x8B, _, _)`；其余 4 元素分支（mach_o / fat_macho / elf / png / zip / pdf）与 switch 后的 bplist / sqlite 位置判定保持原样。

### 2.2 E3 — String 误用 NSString 路径属性（42 条同源 error）

- 报错：`value of type 'String' has no member 'standardizingPath'`。
- Runner 933:22：内嵌 `logicalPath(_:)` 闭包末尾 `return p.standardizingPath`；`p` 为 `String`，`standardizingPath` 是 `NSString` 属性。
- 根因：与同文件 339 / 718 / 930 行既有正确写法不一致，漏了 `as NSString` 桥接。
- 修复：`return (p as NSString).standardizingPath`。

### 2.3 W1 — 非 UIKit 编译单元图标三元死分支（1 条 warning，2 行日志）

- 报错：`warning: will never be executed` / `note: condition always evaluates to false`。
- Runner 1071:50：`"icon_source": iconDecoded ? "bundle_file" : (...)`。非 UIKit 编译单元下 `#else` 侧 `iconDecoded` 固定为 `false`，`bundle_file` 分支不可达。
- 修复：在 `#if canImport(UIKit)` 两侧分别计算 `iconSource`——UIKit 侧保留原三元；非 UIKit 侧直接走 `iconPath.isEmpty ? "unresolved" : "bundle_file_candidate"`；返回字典字段名 `icon_source` / `icon_decoded` 与保守口径不变，不新增 UIKit 运行时假设。

## 3. 本地静态核对（2026-11-21，本机 Linux 无 Swift 工具链）

- 引擎文件括号配平：花括号 279/279、圆括号 703/703、方括号 450/450；`#if` 12 / `#endif` 12 配平。
- 全仓 `*.swift` 扫描：无未桥接 `as NSString` 的 `.standardizingPath`；其余 2 元组 switch（`ReportSerialization.swift`、`ReportRoundtripValidator/main.swift`）模式长度匹配；`research/` 第三方上游克隆不参与构建。
- 未在本机执行 Swift 编译/测试；编译结论以下一轮 Runner 复测为准。

## 4. 边界保持

- 未改 Adapter 七方法协议、冻结公共 Models、`ReportEnvelope`、Plist Parser 语义、Stage1 fixtures；未改 `loaded` / `installed` / `configured` 语义。
- 未触插件启停、plist/规则写入、dylib 删移、dpkg 写、注入规则、自动修复、常驻 daemon；未 dlopen / 未执行插件代码；未改 entitlement / 签名 / 沙盒例外。
