# P2-31 — Runner 编译修复：libproc 不可见符号与 Dispatcher 实参顺序（离线修复轮）

## 证据

- Runner job 日志：`workflow-job-run-5c0ff41a-f249-5d7c-9d7d-0ad5a4ea287a`（workflow run `b99bf07f-043e-432e-989e-9fedc21792c2`，macOS 15.8.2 / arm64，FilterKit app target，Release-iphoneos arm64）。
- 本机留存：`.tmp/ci-logs/p2-30/job-logs.txt`（147,074 B）。
- 编译期失败，未进入 XCTest 阶段；DEB 离线打包 drill 在 Swift 编译前已通过。

## 阻断错误与根因

### 1. `DarwinPeerIdentityProvider.swift` libproc 符号/类型不可见（5 处）

日志：
- `cannot find 'proc_bsdinfo' in scope`
- `cannot find type 'proc_bsdinfo' in scope`
- `cannot find 'proc_pidinfo' in scope`
- `cannot find 'PROC_PIDTBSDINFO' in scope`

根因（对照 XNU `bsd/sys/proc_info.h` 原文核实）：

- `proc_pidinfo` / `struct proc_bsdinfo` / `PROC_PIDTBSDINFO` 未被公开 iOS SDK 的 Darwin module 导出给 Swift。
- 现代 XNU 的 `struct proc_bsdinfo` **并不包含 PID version 字段**；原代码引用的 `pbi_pidversion` 字段不存在。
- PID generation 计数器在 `struct proc_uniqidentifierinfo.p_idversion`，仅由 `#ifdef PRIVATE` 块内的 flavor `PROC_PIDUNIQIDENTIFIERINFO = 17` / `PROC_PIDT_BSDINFOWITHUNIQID = 18` 返回，公开头不导出、布局不可在不反编译的前提下稳定复刻。

结论：该采集路径在公开 iOS SDK 下既不可编译、也无可移植的稳定替代头；属于预留增强证据被误接成了编译期硬依赖。

### 2. `HelperRuntime.swift:85` Dispatcher 实参顺序错误

日志：`argument 'deploymentIdempotencyLedger' must precede argument 'deploymentPipeline'`。

`HelperRequestDispatcher.init` 形参声明顺序为 `… deploymentIdempotencyLedger → deploymentLedgerStore → clockSkewLimit → deploymentPipeline …`，调用处把 `deploymentPipeline` 放到了 `deploymentIdempotencyLedger` 之前。

### 3. 非阻断告警（顺手清理）

- `HelperReleaseGenerationStore.swift:61/113`：`var query` 从未变异，改为 `let`。

## 修复口径

### 证据模型回归预留语义

- `pidVersion: UInt64?` 字段、`HelperPeerProcessGenerationBindingPolicy` 纯策略与诊断标记 `hasProcessGenerationEvidence` 全部保留，供未来私有/真机可用源接入与诊断展示。
- 公开 Darwin SDK 下不再采集 generation，`pidVersion` 记为 `nil`，不伪造值。
- peer 接受的硬门禁内核证据改为：**完整 LOCAL_PEERTOKEN audit token 哈希 + 存活 PID**（新策略 `hasKernelPeerEvidence`）。generation 不再作为公开平台的接受条件。

### 保留的其他绑定层（未削弱）

- 前后两次 `getpeereid`/credentials 读取一致（`credentialsAreStable`）。
- identity 的 uid/gid/pid 与 socket credentials 匹配（`identity(matches:)`）。
- 前后两次 LOCAL_PEERTOKEN 读取一致（`auditTokenChanged` 拒绝）。
- csops CDHash 读取 + trust evaluator 的 CDHash pin 校验。
- 与旧版 R16 相比仍多保留 audit token 双读与 CDHash 绑定；旧版本就不采集 PID generation。

## 改动文件与目录

1. `Sources/Environment/Helper/Transport/HelperPeerAuthenticationDiagnostics.swift`（`Sources/Environment/Helper/Transport/`）
   - 新增 `hasKernelPeerEvidence(_:)`：`pid > 0 && hasKernelAuditTokenEvidence(_:)`，作为公开平台门禁用内核证据。
   - 保留 `hasCompleteDarwinProcessGenerationEvidence(_:)`，仅用于诊断展示 `hasProcessGenerationEvidence` 与组合证据纯策略测试。
2. `Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift`（`Sources/Environment/Helper/Transport/`）
   - 两处 `auditTokenEvidenceIsSufficient` 由组合 generation 证据改为 `hasKernelPeerEvidence`。
3. `Sources/Environment/Helper/Runtime/HelperStartupRecoveryCheck.swift`（`Sources/Environment/Helper/Runtime/`）
   - 恢复授权门禁由组合 generation 证据改为 `hasKernelPeerEvidence`；错误码 `incompleteKernelEvidence` 保留。
4. `Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift`（`Sources/Environment/Helper/Transport/`）
   - 删除 `readPIDVersion` 及其对 `proc_pidinfo`/`proc_bsdinfo`/`PROC_PIDTBSDINFO`/`pbi_pidversion` 的全部引用。
   - `identity(...)` 移除 generation 前后读取与 `isStable` 比对，返回 `pidVersion: nil`；保留 audit token 双读比对与 CDHash 读取。
   - generation 相关 `IdentityError` case 与诊断码字符串保留，稳定诊断枚举；当前无源码路径抛出。
5. `Sources/Environment/Helper/Runtime/HelperRuntime.swift`（`Sources/Environment/Helper/Runtime/`）
   - Dispatcher 调用实参顺序对齐声明：`deploymentIdempotencyLedger → deploymentLedgerStore → deploymentPipeline`。
6. `Sources/Environment/Helper/Runtime/HelperReleaseGenerationStore.swift`（`Sources/Environment/Helper/Runtime/`）
   - 两处未变异 `var query` 改为 `let query`；`var insert = query` 保持可变。
7. `Tests/UnitTests/HelperPeerIdentityBindingTests.swift`（`Tests/UnitTests/`）
   - 新增 `testKernelPeerEvidenceRequiresLivePIDAndCompleteAuditTokenDigest`：完整 token + 存活 PID 通过；缺 token、PID=0 拒绝。

## 静态核对（本机 Linux，无 Xcode/SwiftPM）

- 全树无 `proc_pidinfo` / `proc_bsdinfo` / `PROC_PIDT*` / `pbi_pidversion` / `readPIDVersion` 代码引用（仅注释中保留 PRIVATE flavor 名说明）。
- 门禁三处（transport ×2、recovery check ×1）均切到 `hasKernelPeerEvidence`；组合证据函数仅诊断/测试引用。
- 改动 Swift 文件花括号配平通过；`verify-project-config.sh` PASS，`verify-architecture.py` PASS。
- 既有 `HelperRequestDispatcherTests` 授权夹具：有效 peer 带完整 64-hex digest 通过；root peer 仍被 `peerMustBeUnprivileged` 拒绝；缺 digest 的 incomplete peer 仍被新门禁拒绝，断言不破坏。

## 未闭环 / 待下一轮 Runner 与真机复验

- 本机未做编译与 XCTest 回归；编译、测试结论以下次 Runner `xcodebuild` 为准。
- 若未来在具备私有头/ entitlement 的真机环境接入 generation 源，应复用保留的 `pidVersion` 字段与 `HelperPeerProcessGenerationBindingPolicy`，并在门禁策略中按平台显式开启，不得在公开 SDK 路径引用 PRIVATE 结构。
- DEB 安装/签名放行/jbroot API/真机注入验证仍 pending；0.1 未真机闭环不签署。
- `Resources/en.lproj/Localizable.strings:277` 本地化语法问题为基线既有，本轮未改 Resources。
