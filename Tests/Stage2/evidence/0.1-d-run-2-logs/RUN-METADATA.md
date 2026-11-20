# RUN-METADATA.md — 0.1-D 第二轮 Runner test 目标编译失败（证据测试字典键兜底 / POSIX errno 成员前缀）

- Run 作业：`workflow-job-run-92462907-2290-5911-9e3c-13c8ed4102dd`；仓库 `FilterKit` / 分支 `main`；job 名 `test`（`swift test 2>&1 | tee .build/test-log.txt`）。
- Runner SHA：`92127cd19eff8586a0c7df6ce245c681037839ae`（fetch-depth 1；用户同步时变基/压缩属正常）。
- 时间：2026-11-19 18:16:54Z 起；`swift test` 18:16:56 启动，18:17:20 exit 1。
- Runner：macOS 26.7.2（25G332），镜像 `macos-26-arm64` 20261102.0473；runner 2.338.2（Hosted Compute Agent 20261028.624）；region westus，Cloud MacCloud；git 2.56.0。
- 工具链版本：本链接仅含 test job，未含 environment job，Swift/Xcode/SDK 版本未在本日志出现（`swift-version-7974D3F7F03D5E95.txt` 缓存哈希），待下一轮 environment job 补录。
- 原始日志：`job-logs.txt`（78520 字节，UTF-8 BOM，含 ANSI 转义序列）；下载链接 SAS 票据已过期，以本落盘副本为准。

## 1. Job 结果

| 模块 / Job | 结论 | 证据 |
|---|---|---|
| Models | ✅ emit | `[19/29] Emitting module Models`（含 ProbeEvidence/ProbeOperation/ProbeStatus/ProbeCategory/PermissionProbeReport） |
| Adapters | ✅ emit | `[28/42] Emitting module Adapters` |
| AppPresentation | ✅ emit | `[35/42] Emitting module AppPresentation` |
| Core | ✅ emit | `[41/122] Emitting module Core`（首轮 PlistReadProbe 可选类型 / 协议 throws 修复在本轮编译通过） |
| ReportRoundtripValidator | ✅ 链接 | `[41/141] Linking ReportRoundtripValidator` |
| Stage2Tests（测试目标） | ❌ 编译失败 | 两个探针测试文件类型错误；前端 `error: fatalError` 退出 1 |
| 测试用例执行 | ⏭ 未执行 | 编译失败中断，日志无 Test Suite / Executed 记录 |
| isolation / app-build / ui-acceptance | ⏭ 未在本日志 | 本链接仅 test job；UI 链路仍置 `if: false` 摘出主流程 |

## 2. 编译诊断（runner 路径 `/Users/runner/work/FilterKit/FilterKit/`）

### 2.1 `Tests/Stage2/PermissionProbeEvidenceTests.swift:46:33`（error）

- 诊断：`binary operator '??' cannot be applied to operands of type 'Dictionary<String, Any>.Keys?' and '[Any]'`。
- 根因：`object?.keys` 类型为 `Dictionary<String, Any>.Keys?`，而 `?? []` 中空数组被推断为 `[Any]`；`Keys` 与 `Array<Any>` 不能用 `??` 合并。
- 改法：`let keys = object?.keys ?? []` → `let keys: Set<String> = object.map { Set($0.keys) } ?? []`；键断言 `keys.contains(...)` 在 `Set<String>` 上成立。模式对齐既有 `ReportExporterTests` 的 `object.map { Set($0.keys) } ?? []` 写法。

### 2.2 `Tests/Stage2/PermissionProbeProbeTests.swift:117:53 / 131:53`（error）

- 诊断：`type 'Int32?' has no member 'ENOENT'` / `'EACCES'`。
- 根因：`errno:` 参数类型为 `Int32?`，`.ENOENT` / `.EACCES` 在 `Int32?` 上下文中查找不到成员；POSIX 常量属于 `POSIXErrorCode` 枚举，须显式前缀。
- 改法：`.ENOENT.rawValue` → `POSIXErrorCode.ENOENT.rawValue`；`.EACCES.rawValue` → `POSIXErrorCode.EACCES.rawValue`。模式对齐既有 `PlistReaderTests` 的 `POSIXErrorCode.EACCES.rawValue` 写法。

### 2.3 `Tests/Stage2/PermissionProbeProbeTests.swift:122:45 / 123:45 / 135:45`（error，级联）

- 诊断：`type 'Equatable' has no member 'unavailable' / 'notExecuted' / 'permissionDenied'`。
- 根因：2.2 的 errno 成员查找失败使 `FileAccessResult(...)` 初始化类型无法确定，级联导致 `FakeFileAccess` / 探针 / `evidence` 类型退化为 `Equatable` 协议，状态字面量无法推断 `ProbeStatus`。2.2 修复后类型链恢复，本组级联错误随之消除；未改断言口径。

### 2.4 资源告警（warning，非阻断）

- 告警：`'filterkit': found 5 file(s) which are unhandled`，列出 `Tests/Stage2/UITests/` 五个 XCUITest 源文件。
- 处置：测试目标 `sources` 为显式清单，本就不编译 UITests；在 `Package.swift` 的 `Stage2Tests` `exclude` 增补 `"UITests"`，消除未处理文件告警。五个源文件、`project.yml` 的 `FilterKitUITests` target、往返校验器均保留，后续接回 UI 链路时不删除。

两类 error 被并行编译单元重复报出；日志无其他测试文件错误、无断言失败记录（用例未执行）。

## 3. 本地修复（待下一轮 Runner 复验）

| 文件 | 修改 |
|---|---|
| `Tests/Stage2/PermissionProbeEvidenceTests.swift` | 第 46 行字典键兜底改为 `Set<String>` 映射写法 |
| `Tests/Stage2/PermissionProbeProbeTests.swift` | 第 117 / 131 行 errno 常量补 `POSIXErrorCode.` 前缀 |
| `Package.swift` | `Stage2Tests` `exclude` 增补 `"UITests"` |

- 未改 Core/Models 源码、未改探针业务预期；测试桩与断言口径不变。
- 静态核对：`ProbeStatus` 六态、`FileAccessResult.errno: Int32?`、`POSIXErrorCode` 原始值类型与既有测试用法一致；其余四个探针测试文件（Status / Report / Presentation）本轮编译未报错。

## 4. 边界核对（本轮未越界）

- 未改 Models 公共字段 / 枚举原始值；未改 Stage 1 Reader / Adapter 协议 / 既有 fixtures。
- 未触真机文件、未调 `jbroot()`、未改 entitlement/签名；D5/D6 仍占位 unavailable/unknown。
- 未改 CI workflow；`app-build` / `ui-acceptance` 仍置 `if: false`。

## 5. 待下一轮 Runner 复验

1. `swift test` 测试目标编译 0 error / 0 warning（含 UITests 未处理告警消除）；
2. Stage2Tests 全量回归无损伤，新增探针 / 展示映射 / 服务隔离用例全绿；
3. isolation 三向通过；
4. environment job 工具链（Swift / Xcode / SDK 版本）补录；
5. 真机证据缺口 D-G10～D-G15 不在本轮 Runner 范围；未取证项保持 pending/unknown。

> 下一轮结果未出前，0.1-D 探针链路状态仍为「待复验」；不宣布 0.1-D 闭环，不进入 0.1-E。
