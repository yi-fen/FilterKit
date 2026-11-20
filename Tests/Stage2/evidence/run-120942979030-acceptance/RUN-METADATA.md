# RUN-METADATA.md — 0.1-D 统一 Runner 验收（离线/CI 可验证部分通过；真机门禁挂起）

- Workflow run：`120942979030`；仓库 `yi-fen/FilterKit`，分支 `main`；工作流 `.github/workflows/filterkit-build.yml@refs/heads/main`。
- 检出 SHA：`cb130c36719f7b21414f3797bb10a902c8e07f6d`（environment / build / test / isolation 四个 job 同一 SHA，fetch-depth 1）。
- 本地基线：HEAD `021abd2`（三轮断言修复，未推送）。本轮核对：`metadata/Package.swift`、`Makefile`、`control`、`project.yml`、`metadata/filterkit-build.yml` 与本地逐文件 diff 一致；Runner 检出 SHA 与本地 HEAD 不同名（历史远程经网页上传），归档结论以 Runner 实际日志为准，不声称本地 HEAD 已被本轮 Runner 逐行重新编译验证。
- 时间（UTC）：2026-11-20 05:28:51 ~ 05:31:19；environment 05:28:55 录工具链；isolation 05:28:58；build 05:29:16 → 05:29:55；test 05:30:02 起，全量套件 05:31:05 passed；artifact 05:31:15 → 05:31:19。
- 环境：macOS 26.7.2（25G332）/ `macos-26-arm64` 20261117.0516.1 / runner 2.338.2 / westus MacCloud；Xcode 26.6（17F113）；Apple Swift 6.3.3（swiftlang-6.3.3.1.3 clang-2100.1.1.101）；swift-driver 1.148.6；iOS SDK 26.5 / iOS Simulator SDK 26.5；测试目标 `arm64e-apple-macos14.0`；Testing Library 1902。
- 上传产物：`filterkit-build-metadata`（ID 14605105589）、`filterkit-non-ui-build`（ID 14604785944）、`filterkit-test-log`（ID 14604367253）、`filterkit-isolation`（ID 14604232423）。

## 1. 门禁结论（离线 / CI 可验证部分）

| 验收门 | 结论 | 证据 |
|---|---|---|
| 环境与工具链录档 | ✅ macOS 26.7.2 / Xcode 26.6 / Swift 6.3.3 / SDK 26.5 全部记录在案 | `logs/environment/3_Record toolchain versions.txt` |
| 非 UI Build（Models / Adapters / AppPresentation / Core + ReportRoundtripValidator） | ✅ `Build complete! (15.69s)`，0 error / 0 warning；Models/Adapters/AppPresentation/Core emit，validator 链接 | `build/swift-build.log`、`logs/build/3_Build non-UI targets (Models _ Adapters _ Core).txt` |
| 全量 Swift 测试 | ✅ Executed **448 tests，0 failures（0 unexpected）**；`All tests` passed；日志无 skipped 记录 | `test-log/test-log.txt`、`logs/test/3_Run full Swift test suite.txt` |
| S1-05 配对映射独立过滤 | ✅ `PluginPairingS105FixtureTests` 15 tests，0 failures | `test-log/test-log-s105.txt`、`logs/test/4_Run S1-05 pairing mapping tests (independent filter).txt` |
| 探针专项套件（D1～D7） | ✅ 43 例 0 failure，见 §2 分列 | `test-log/test-log.txt` |
| 既有回归无损伤（0.1-A Engine C2 / 0.1-B Reporting / 0.1-C GUI Foundation 基线） | ✅ 含在 448 例内，0 failure；无损伤记录 | `test-log/test-log.txt` |
| Adapter / 路线 / Core / App 隔离静态检查（Runner 实际执行） | ✅ 七项（1a/1b/2a/2b/3/4/4b）`passed`，`failed: 0`；脚本由 CI `isolation` job 实际执行，非本机自检 | `isolation/isolation-summary.json`、`isolation/isolation-output.log`、`logs/isolation/3_Adapter isolation check.txt` |
| 全量日志错误扫描 | ✅ 无 `##[error]`、无 `Process completed with exit code 1`、无 `FAILED`；Build 0 warning、测试日志无 warning / unhandled | `logs/` 全量 job 文本 |
| App Build / 模拟器存活 / XCUITest 交互 | ⏭ 本轮不判定 | `app-build`、`ui-acceptance` 按 0.1-D 摘出口径置 `if: false`（`metadata/filterkit-build.yml` 104/206 行）；五个 XCUITest 源文件、`FilterKitUITests` target、往返校验器、App 工程定义全部保留，后续移除 `if: false` 接回 |

## 2. 探针专项用例分列（43 例，0 failure）

| 套件 | 覆盖项 | 用例 | fail |
|---|---|---:|---:|
| `PermissionProbeStatusTests` | 六态分类、notExecuted 不计 failed | 4 | 0 |
| `PermissionProbeEvidenceTests` | 证据 id/operation 往返、可选 nil/null、错误字段保留 | 5 | 0 |
| `PermissionProbeReportTests` | 归集统计、notExecuted 不计 failed、generatedAt | 6 | 0 |
| `PermissionProbeProbeTests` | D2 JBROOT / D3 ElleKit / D4 文件·plist·dpkg / D5 entitlement·sandbox / D6 jbroot() 接缝 / 服务抛错隔离与身份保留 | 24 | 0 |
| `PermissionProbePresentationTests` | nil 空态、八分类分组、六态分级映射、unknown 不升级、denied → failure | 4 | 0 |

- 三轮修复点本轮复核：`testDpkgProbePassesNonEmptyStatusFile`（11 bytes 断言）`passed (0.000s)`；证据字典键兜底、errno `POSIXErrorCode.` 前缀用例随套件全绿；`Stage2Tests` 无 UITests unhandled 告警。

## 3. 未通过 / 挂起项（不计 passed，不得以 CI 替代）

### 3.1 真机门禁 D-G10～D-G15（pending / unknown）

| 编号 | 缺口 | 本轮状态 |
|---|---|---|
| D-G10 | GUI 进程内访问 JBROOT（`.jbroot-*`）权限 | ⬜ 未取证，pending/unknown |
| D-G11 | TweakInject 目录/文件可达 | ⬜ 未取证，pending/unknown |
| D-G12 | dylib / plist / dpkg status 真机读取 | ⬜ 未取证，pending/unknown |
| D-G13 | 进程 / 签名 entitlement、sandbox 放行 | ⬜ 未取证，pending/unknown；D5 仍占位实现 |
| D-G14 | `jbroot()` 函数声明 / 链接 / 调用安全性与返回路径一致性 | ⬜ 未取证，pending/unknown；D6 仍占位 resolver，禁止伪造 C 声明 / 弱链接 / dlsym |
| D-G15 | 冷启动后权限保持复验 | ⬜ 未取证，pending/unknown |

- 上述各项须 RootHide 真机真实 GUI 进程取证；模拟器 / CI / 合成桩不得替代；未取证项保持 pending/unknown，不判 passed。
- D5 进程/签名 entitlement 受支持读取接口、D6 `jbroot()` 签名与链接方式未核实，当前为占位实现；接口核实后替换实现，协议快照与证据模型不变。

### 3.2 既有未决项（继续挂起）

- `OwnershipResolver` 未迁移；`loaded` 恒 `.unknown`；`permission.decision` 恒 undetermined；`pluginID` 稳定标识规则 0.2.0 定稿；PARSE-009-B 挂起。
- 0.1-C G10（Share Sheet / 空态复核）缺口作为已知限制带入，不豁免不签署。

## 4. 验收判定

- **离线 / CI 口径 L2 切片：通过。** 非 UI Build 0 error / 0 warning；全量 448 例 + S1-05 15 例 0 failure；隔离七项 passed；探针 43 例全绿；既有回归无损伤；工具链版本已录档。
- **0.1-D 里程碑：未闭环。** 真机门禁 D-G10～G15 未取证，App Build / 模拟器 / XCUITest 本轮按摘出口径未执行；不生成 0.1-D 签署结论，不进入 0.1-E。
- 本报告仅代表离线 / CI / 合成桩口径，不构成真机权限、真实加载或 Rootless 真机兼容证据。

## 5. 归档清单

- `logs/`：environment / build / test / isolation / artifact 五个 job 的分步文本日志与 `system.txt`。
- `metadata/`：Runner 检出树的 `Package.swift`、`Makefile`、`control`、`project.yml`、`filterkit-build.yml`。
- `test-log/`：全量 `test-log.txt` 与 S1-05 `test-log-s105.txt`。
- `build/swift-build.log`：非 UI 目标编译日志。
- `isolation/`：`isolation-summary.json`（机器可读）与 `isolation-output.log`。
