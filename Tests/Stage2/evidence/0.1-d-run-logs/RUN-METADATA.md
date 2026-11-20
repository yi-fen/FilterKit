# RUN-METADATA.md — 0.1-D 首轮 Runner build 失败（PlistReadProbe 可选类型 / 服务 catch 不可达）

- Run 作业：`workflow-job-run-5a0ac726-c438-5707-9f45-ae42b7484734`；仓库 `FilterKit` / 分支 `main`；job 名 `build`（仅执行 `swift build`）。
- Runner SHA：`967d815200f91273ecae54ea6eea3b1cc6334455`（fetch-depth 1；用户同步时变基/压缩属正常）。
- 时间：2026-11-19 17:25:58Z 起；`swift build` 17:26:01 启动，17:26:24 exit 1。
- Runner：macOS 26.7.2（25G332），镜像 `macos-26-arm64` 20261102.0473.1；runner 2.338.2；region westus，Cloud MacCloud；git 2.56.0。
- 工具链版本：本链接仅含 build job，未含 environment job，Swift/Xcode/SDK 版本未在本日志出现，待下一轮 environment job 补录。
- 原始日志：`job-logs.txt`（60125 字节，UTF-8 BOM，含 ANSI 转义序列）；下载链接 SAS 票据已于 2026-11-19T17:42:18Z 过期，以本落盘副本为准。

## 1. Job 结果

| Job | 结论 | 证据 |
|---|---|---|
| build（Models / Adapters / Core / AppPresentation / ReportRoundtripValidator） | ❌ exit 1 | Models、AppPresentation、Adapters 模块 emit 成功；Core 并行编译报两类诊断后中断 |
| test（Stage2Tests） | ⏭ 未执行 | 依赖 build 通过，build 失败后未触发；日志无 `swift test` / Test Suite 记录 |
| isolation | ⏭ 未执行 | 同上 |
| app-build / ui-acceptance / artifact | ⏭ 未执行 | 0.1-C 验收链路已置 `if: false` 摘出主流程（见实现记录 §5.1） |

编译进度：Models（含 ProbeEvidence / ProbeOperation / ProbeStatus / ProbeCategory / PermissionProbeReport）emit 成功 → AppPresentation emit 成功 → Adapters emit 成功 → Core 并行编译至 `[35/88] Compiling Core ProbeStatusClassifier.swift` 起报诊断；后续 Core 文件继续并行编译至 `[136/136]`，`ReportRoundtripValidator` 完成链接，但 build 整体 exit 1。

## 2. 编译诊断（runner 路径 `/Users/runner/work/FilterKit/FilterKit/`）

| # | 位置 | 级别 | 诊断 | 根因 |
|---|---|---|---|---|
| 1 | `Core/PermissionProbe/Probes/PlistReadProbe.swift:45:28` | error | `'nil' cannot be assigned to type 'String'` | switch 前局部量声明为非可选 `let observed: String`，而 `.notFound` / `.accessDenied` / `.readFailed` 三分支执行 `observed = nil`；类型应为可选 `String?` |
| 2 | `Core/PermissionProbe/Services/PermissionProbeService.swift:31:15` | warning | `'catch' block is unreachable because no errors are thrown in 'do' block` | 协议 `PermissionProbing.run()` 原为非抛出 `func run() -> [ProbeEvidence]`，服务内 `do { probe.run() } catch` 中 do 块不抛错，catch 不可达 |

两类诊断被并行编译的多个 Core 编译单元重复报出：error 行 48 条、warning 行 48 条，实际根因各一处。日志无其他错误类型；无测试断言失败记录（test 阶段未执行）。

## 3. 本地修复（待下一轮 Runner 复验）

### 3.1 日志驱动修复（4 个文件）

| 文件 | 修改 |
|---|---|
| `Core/PermissionProbe/Probes/PlistReadProbe.swift` | 第 37 行 `let observed: String` → `let observed: String?`；三分支 `observed = nil` 合法；return 时 `observedValue: observed` 可选透传，证据模型字段本就为 `String?` |
| `Core/PermissionProbe/Protocols/PermissionProbing.swift` | 协议方法 `func run() -> [ProbeEvidence]` → `func run() throws -> [ProbeEvidence]`；头注释同步为「探针可抛错，由编排服务捕获为保留原 probeID 的失败证据，不中断其他探针」 |
| `Core/PermissionProbe/Services/PermissionProbeService.swift` | 第 30 行 `probeEvidence = probe.run()` → `probeEvidence = try probe.run()`；do/catch 保留，单项抛错仍落 `Self.failureEvidence(probe:error:)`，失败证据保留原 probeID |
| `Tests/Stage2/PermissionProbeProbeTests.swift` | 内部桩 `ThrowingProbe` 的 `func run() -> [ProbeEvidence]` → `func run() throws -> [ProbeEvidence]`；体内 `throw NSError(domain: "test-probe", code: 99)` 不变（原非抛出函数体内 throw 本身亦会编译报错） |

- 协议改 `throws` 后，现有 8 个探针实现保持非抛出 `func run() -> [ProbeEvidence]`；Swift 允许非抛出方法满足抛出协议要求，无需改方法体。已逐一核对 8 个探针签名与测试桩。
- 备选「直接删 do/catch」未采用：删去会失去单项失败保留原 probeID 的防御隔离语义，抛错桩与异常隔离用例也无法成立。

### 3.2 本地静态复核发现（非日志报错，待 Runner 测试阶段复验）

- `Tests/Stage2/PermissionProbeProbeTests.swift` 的 `testServiceContinuesAfterThrowingProbeAndPreservesIdentity`：原对照探针 `JBRootProbe(confirmedJBRoot: nil, ...)` 仅返回 1 条 notExecuted 证据，而断言期望 `report.totalCount == 3`；测试阶段未执行，未在本轮日志暴露。已将对照探针改为可枚举目录桩（exists / isDirectory，1 条目录条目），返回 stat + list 2 条证据；合计抛错失败证据 1 条 + 对照证据 2 条 = 3，与断言一致；失败证据 probeID / errorDomain / errorCode 断言与既有前缀过滤不变。

### 3.3 静态核对范围（本机 Linux 无 Swift/Xcode，不本地编译）

- 8 个探针（JBRoot / ElleKitDirectory / PluginFile / PlistRead / DpkgDatabase / Entitlement / SandboxAccess / JBRootAPI）证据构造标签、操作类型、分类、状态枚举与 `ProbeEvidence` 模型字段逐一核对一致；
- `FileAccessChecking`（inspect / listDirectory throws / read throws）、`EntitlementInspecting` / `CodeSignInspecting`、`JBRootResolving` 协议与占位实现签名核对一致；
- Models `ProbeOperation`（resolve/stat/list/read/inspect/invoke）、`ProbeCategory`（八分类原始值）、`ProbeStatus`（六态原始值）与探针 / 展示映射 / 测试引用一致；
- AppPresentation `ProbeDiagnosticsMapper` 分区 / 分级映射与 `PermissionProbePresentationTests` 断言一致；
- `Package.swift` Core 与 Stage2Tests 为显式 sources 清单；本轮未增删文件，清单无需改动。

## 4. 边界核对（本轮未越界）

- 未改 Models 公共字段 / 枚举原始值；未改 Stage 1 Reader / Adapter 协议 / 既有 fixtures；未改既有测试业务预期（仅修正服务隔离用例的对照桩与计数前提）。
- 未接入真机文件访问；D5 entitlement / D6 jbroot() 占位实现仍落 unavailable/unknown，未写入虚构 C 声明 / 弱链接 / dlsym。
- 未改 CI workflow；`app-build` / `ui-acceptance` 仍置 `if: false`。

## 5. 待下一轮 Runner 复验

1. `swift build` Models / Adapters / Core / AppPresentation 0 error / 0 warning；
2. `swift test` Stage2Tests 全量回归无损伤，新增探针 / 展示映射 / 服务隔离用例全绿；
3. isolation 三向通过；
4. environment job 工具链（Swift / Xcode / SDK 版本）补录；
5. 真机证据缺口 D-G10～D-G15 不在本轮 Runner 范围；未取证项保持 pending/unknown。

> 下一轮结果未出前，0.1-D 探针链路状态仍为「待复验」；不宣布 0.1-D 闭环，不进入 0.1-E。
