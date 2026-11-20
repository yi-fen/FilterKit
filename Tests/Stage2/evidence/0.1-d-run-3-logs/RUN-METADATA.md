# RUN-METADATA.md — 0.1-D 第三轮 Runner test：448 用例 1 例断言失败（dpkg 探针字节数期望值偏移）

- Run 作业：`workflow-job-run-d2b6f5e1-d971-501a-a635-baefb8eedca7`；仓库 `FilterKit` / 分支 `main`；job 名 `test`（`swift test 2>&1 | tee .build/test-log.txt`）。
- Runner SHA：`c657da5dfd0f098aa0dcfd18d538c17f30a39f7e`（fetch-depth 1；用户同步时变基/压缩属正常）。
- 时间：2026-11-20 05:13:56Z 起；`swift test` 05:14:00 启动，05:15:16 exit 1。
- Runner：macOS 26.7.2（25G332），镜像 `macos-26-arm64` 20261102.0473.1；runner 2.338.2（Hosted Compute Agent 20261028.624，commit `54898b74`）；git 2.56.0。
- 工具链版本：本链接仅含 test job，未含 environment job，Swift/Xcode/SDK 版本未在本日志出现（`swift-version-7974D3F7F03D5E95.txt` 缓存哈希），待 environment job 补录。
- 原始日志：`job-logs.txt`（165100 字节，UTF-8 BOM，含 ANSI 转义序列）；下载链接 SAS 票据已过期，以本落盘副本为准。

## 1. Job 结果

| 模块 / Job | 结论 | 证据 |
|---|---|---|
| Models | ✅ emit | `[15/29] Emitting module Models` |
| AppPresentation | ✅ emit | `[25/39] Emitting module AppPresentation` |
| Adapters | ✅ emit | `[26/41] Emitting module Adapters` |
| ReportRoundtripValidator | ✅ 链接 | `[40/93] Linking ReportRoundtripValidator` |
| Core | ✅ emit | `[67/117] Emitting module Core`（首轮 §5.3、二轮 §5.4 修复在本轮编译通过） |
| Stage2Tests | ✅ 编译/链接 | `[157/193] Emitting module Stage2Tests` → `[194/195] Linking FilterKitPackageTests`；二轮类型错误与 UITests unhandled 告警均未复现 |
| 测试用例执行 | ❌ 448 例 1 失败 | `Executed 448 tests, with 1 failure (0 unexpected) in 0.642 (0.717) seconds`；前端 exit 1 |
| isolation / app-build / ui-acceptance | ⏭ 未在本日志 | 本链接仅 test job；UI 链路仍置 `if: false` 摘出主流程 |

## 2. 断言诊断（runner 路径 `/Users/runner/work/FilterKit/FilterKit/`）

### 2.1 `Tests/Stage2/PermissionProbeProbeTests.swift:254`（error，运行时断言）

- 诊断：`XCTAssertEqual failed: ("Optional("readable: 11 bytes")") is not equal to ("Optional("readable: 12 bytes")")`；用例 `testDpkgProbePassesNonEmptyStatusFile` failed（0.322 秒）。
- 夹具：`Data("Package: x\n".utf8)`，UTF-8 字节数 = 11（`Package: x` 10 字符 + 换行 1）。
- 探针口径：`DpkgDatabaseProbe.swift:71` 证据 `observedValue` 为 `data.isEmpty ? "empty" : "readable: \(data.count) bytes"`，按 `Data.count` 报告字节数；与 `PlistReadProbe` 的 `data-readable: 3 bytes`（`Data([1,2,3])`）同一口径。
- 根因：探针 `data.count = 11` 正确；测试断言硬编码期望 `12 bytes`，偏移 1。属测试期望值错误，非探针业务缺陷。
- 改法：断言 `"readable: 12 bytes"` → `"readable: 11 bytes"`；探针实现、夹具内容、证据状态口径均不改。

### 2.2 其余用例

- `PermissionProbeProbeTests` 套件 24 例，仅上述 1 例失败；同套件 `testDpkgProbeFailsEmptyFile` / `testDpkgProbeNotExecutedWhenNoPath` 及 D2/D3/D5/D6 探针用例、Presentation 映射用例全部 passed。
- 全量 448 例仅 1 失败（0 unexpected）；日志无编译 error、无 warning、无 unhandled 文件告警。

## 3. 本地修复（待下一轮 Runner 复验）

| 文件 | 修改 |
|---|---|
| `Tests/Stage2/PermissionProbeProbeTests.swift` | 第 254 行 dpkg 非空状态文件用例期望 `"readable: 12 bytes"` → `"readable: 11 bytes"`，对齐夹具 UTF-8 字节数与探针 `data.count` 口径 |

- 未改 Core/Models 源码、未改探针业务预期与测试桩；其余断言口径不变。
- 静态核对：`"Package: x\n".utf8` 长度 11；`DpkgDatabaseProbe` 与 `PlistReadProbe` 字节数均以 `Data.count` 为准；隔离脚本 `check-adapter-isolation.sh` 7/7 passed（1a/1b/2a/2b/3/4/4b，`failed: 0`）。

## 4. 边界核对（本轮未越界）

- 未改 Models 公共字段 / 枚举原始值；未改 Stage 1 Reader / Adapter 协议 / 既有 fixtures。
- 未触真机文件、未调 `jbroot()`、未改 entitlement/签名；D5/D6 仍占位 unavailable/unknown。
- 未改 CI workflow；`app-build` / `ui-acceptance` 仍置 `if: false`。

## 5. 待下一轮 Runner 复验

1. `swift test` 全量 448 例 0 失败（本轮唯一失败断言修复后应转绿）；
2. 测试目标编译 0 error / 0 warning，UITests 未处理告警不复发；
3. isolation 三向通过（本日志未含 isolation job）；
4. environment job 工具链（Swift / Xcode / SDK 版本）补录；
5. 真机证据缺口 D-G10～D-G15 不在本轮 Runner 范围；未取证项保持 pending/unknown。

> 下一轮结果未出前，0.1-D 探针链路状态仍为「待复验」；不宣布 0.1-D 闭环，不进入 0.1-E。
