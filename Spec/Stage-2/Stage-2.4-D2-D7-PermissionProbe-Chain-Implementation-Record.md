# Stage 2.4-D2～D7：Permission Probe 只读链路实现记录

- 日期：2026-11-20
- 授权依据：用户上传两份 0.1-D MD，授权 D1～D7 连续开发、D7 完成后统一 Runner 验收；检查点 A/B/C 仅 L1 静态自检，不逐批启动 Runner。冻结规格 `Stage-2.4-D2-D7-PermissionProbe-Chain-Spec.md`。
- 基线：本地归档提交 `e221989`（D1 Foundation，未推送）。0.1-C 未闭环，G10 缺口作为已知限制带入。
- 状态标记：**Implementation Landed / Local L1 Static Review Passed / Runner Build & Test Pending**。本机 Linux 无 Swift/Xcode，本轮未编译、未执行 XCTest；编译与用例结论以在线 Runner 为准。

## 1. 本轮授权边界

### 允许

1. D2～D6 只读探针与文件访问抽象落地到 `Core` target；
2. D7 探针报告纯 Foundation 映射落地到 `AppPresentation`，诊断装配接缝接入 `App`；
3. 统一编排服务与报告装配器；合成桩单测接入 `Stage2Tests`；
4. 只读静态检查、接口核对、隔离脚本复跑。

### 禁止（本轮均未触碰）

1. 未访问真实 JBROOT / TweakInject / 插件文件 / dpkg 数据库；未加载 dylib、未执行插件代码；
2. 未调用 `jbroot()` 或任何 RootHide 私有 API；未写 C 桥接声明、弱链接或 dlsym；
3. 未修改冻结 Models 信封、Adapter 七方法协议、Plist Parser 语义、Stage1 fixtures；
4. 未在 App/Presentation 内新增扫描/解析/路径解析私有逻辑；未开发启停、写入、归属迁移；`loaded` 继续恒 `.unknown`；
5. 未修改 entitlement、签名配置、安装位置或沙盒例外；未调度真机验证。

## 2. 文件清单

### 2.1 模型补齐（`Models/PermissionProbe/`，隐式源集）

| 路径 | 说明 |
|---|---|
| `ProbeOperation.swift` | 操作类型：`resolve / stat / list / read / inspect / invoke`；元数据/枚举/内容读取/API 调用分开 |
| `ProbeEvidence.swift` | 增补 `id: String`（默认 UUID）与 `operation: ProbeOperation`（默认 `.inspect`）；`id/probeID/status` 必填解码，其余可选 `decodeIfPresent` |

### 2.2 文件访问抽象（`Core/PermissionProbe/FileAccess/`）

| 路径 | 说明 |
|---|---|
| `FileAccessChecking.swift` | `FileAccessResult` 事实位 + `inspect/listDirectory/read` 只读接缝 |
| `FoundationFileAccessChecker.swift` | FileManager/Foundation 只读实现；保留域/码/errno；目录类型经 `FileAttributeType` 判定 |
| `ProbeStatusClassifier.swift` | 纯函数错误分类：不存在 / 拒绝 / 其他 I/O / 未知，拒绝与不存在不合并 |

### 2.3 探针（`Core/PermissionProbe/Probes/`）

| 路径 | 批次 | 说明 |
|---|---|---|
| `JBRootProbe.swift` | D2 | 已确认 JBROOT 目录 stat + list；未确认 `notExecuted`；抽象 target 标签 |
| `ElleKitDirectoryProbe.swift` | D3 | TweakInject stat + 软链 resolve + list；路线标签摘要；无路径 `notExecuted` |
| `PluginFileProbe.swift` | D4 | dylib 元数据 stat；目录记 failed；空输入 `notExecuted` |
| `PlistReadProbe.swift` | D4 | 复用 `PlistDataReading`；Reader 四态映射；读取成功仅记字节数 |
| `DpkgDatabaseProbe.swift` | D4 | status 文件 stat + 非空 read；不执行 dpkg/apt 命令 |
| `EntitlementProbe.swift` | D5 | 进程 + 代码签名两条证据；占位不可用落 unavailable |
| `SandboxAccessProbe.swift` | D5 | 逐资源可达取证；不笼统判定沙盒关闭 |
| `JBRootAPIProbe.swift` | D6 | 符号/调用/路径/一致性四层证据；占位落 unavailable/unknown |

### 2.4 接缝与占位（`Core/PermissionProbe/Entitlement/`、`JBRootAPI/`）

| 路径 | 说明 |
|---|---|
| `EntitlementInspecting.swift` | `EntitlementSnapshot` + `EntitlementInspecting` / `CodeSignInspecting` 接缝 |
| `UnavailableEntitlementInspector.swift` | 进程 / 签名占位检查器，`available = false`，不触私有 API |
| `JBRootResolving.swift` | `JBRootAPISnapshot` + `JBRootResolving` 接缝（独立于 Adapter 协议） |
| `UnavailableJBRootResolver.swift` | 占位解析器：符号不可用、未调用、无返回路径 |

### 2.5 服务与共享（`Core/PermissionProbe/Services/`、`Shared/`）

| 路径 | 说明 |
|---|---|
| `PermissionProbeReportBuilder.swift` | 证据归集（不排序/不裁剪），写入 `generatedAt` |
| `PermissionProbeService.swift` | 探针数组逐条执行；抛错保留原 probeID 的 failed 证据，不中断后续探针 |
| `Shared/ProbeTimestamp.swift` | ISO8601/RFC3339 字符串时刻；不使用 `Date` 进入 Models |

### 2.6 展示层（`App/Presentation/`、`App/`）

| 路径 | 说明 |
|---|---|
| `ProbeDiagnostics.swift` | `ProbeDiagnosticsMapper`：报告 → 八分类分区；六态 → 展示分级；空态 unknown |
| `AppDependencies.swift` | 增补 `probeReport: PermissionProbeReport?`（缺省 nil），信封不改 |
| `DiagnosticsViewModel.swift` | 合并信封分区与探针分区 |
| `DiagnosticsView.swift` | 注入 `dependencies.probeReport` |
| `App/PermissionProbe/PermissionProbe.swift` | 旧 `ProbeItem`/`PermissionProbeService` 占位退役，仅留迁移说明注释 |

### 2.7 测试（`Tests/Stage2/`）

| 路径 | 覆盖 |
|---|---|
| `PermissionProbeProbeTests.swift` | D2～D6 探针链路 + 服务异常隔离（合成桩，不触真机） |
| `PermissionProbePresentationTests.swift` | 分组、六态映射、空态、unknown 不升级 |
| `PermissionProbeEvidenceTests.swift` | 随模型补齐：`id`/`operation` 往返与 JSON fixture 补 `id` 键 |

### 2.8 接线

- `Package.swift`：Core `sources` 增补 18 条新文件；`Stage2Tests` `sources` 增补 `PermissionProbeProbeTests.swift`、`PermissionProbePresentationTests.swift`。Models 与 AppPresentation 为隐式源集，无需清单改动。

## 3. L1 静态自检记录（检查点 A/B/C）

### 检查点 A（D1～D3）

- 模型稳定：`ProbeStatus` 六态 / `ProbeCategory` 八分类 / `ProbeEvidence` 字段冻结，未为探针批次新增状态语义；
- 复用 JBROOT：`JBRootProbe` 只接收已确认路径，无候选收集/定位逻辑；
- 双路线隔离：探针代码不 import Adapters，路线仅以摘要标签出现；
- 无重复解析：D3 不重新推导 TweakInject 路径。

### 检查点 B（D4～D6）

- 复用 Reader：`PlistReadProbe` 仅依赖 `PlistDataReading`，未重写 plist 解析；
- 元数据与内容分开：`.stat` 与 `.read` 证据分条；
- entitlement 与访问证据分开：D5 不承载文件访问结论，实际访问归 D2～D4；
- 不伪造 API：D5/D6 占位实现无外部符号声明/弱链接/dlsym；
- API 不可用 ≠ 路径不存在：占位落 unavailable/unknown，不记 unavailable 资源不存在。

### 检查点 C（D7）

- 复用统一报告：Presentation 只消费 `PermissionProbeReport`；
- 无私有扫描：`App/Presentation/` 无 `FileManager`/`Data(contentsOf:)`/目录枚举；
- 状态准确：unknown/notExecuted 不升级 success；denied 映射 failure；
- `loaded` 口径不变；服务失败不中断其他探针。

### 静态检查结果

- 隔离脚本 `scripts/check-adapter-isolation.sh` 本地复跑：1a/1b/2a/2b/3/4/4b 全 passed，`failed: 0`；
- 探针目录递归检索：无 `/var/jb`、`/usr/lib/TweakInject` 候选路径硬编码（既有 `SyntheticReportFactory` 预览 fixture 路径不在探针目录）；
- 探针目录无 `createDirectory`/`write(to:)`/`removeItem`/`dlopen`/`posix_spawn`/私有 entitlement API 调用；
- Core PermissionProbe 文件清单与 `Package.swift` 登记一一对应（20 条）。

## 4. 待 Runner 复核

1. Core `swift build` 0 error / 0 warning；`Stage2Tests` 既有回归无损伤，新增探针/展示用例全绿；
2. 模型补齐后 D1 三文件 Codable 往返、可选 nil/null、统计口径在 Runner 工具链下复核；
3. 隔离脚本在 CI 复跑通过；App target 编译与 UITests 链路本轮随 §5.1 摘出主流程，留待后续阶段接回复核；
4. 真机证据缺口 D-G10～D-G15 不在本轮 Runner 范围；未取证项保持 pending/unknown。

## 5. 后续与未决项

### 5.1 CI 链路摘出（2026-11-20 补充）

0.1-C GUI 验收时期加入的重编译/模拟器取证链路，本轮 0.1-D 离线门禁不纳入主流程，验证代码全部保留：

- `app-build` job（xcodegen → xcodebuild App 编译 → simctl 启动/存活复查 → `dashboard.png` 截图）置 `if: false`；`ui-acceptance` job（XCUITest 导航/导出/分享面板取证、容器 JSON 拉取、往返校验）置 `if: false`；`artifact` job 的 `needs` 去掉 `app-build`。
- 保留未删：`Tests/Stage2/UITests/` 五个 XCUITest 源文件、`project.yml` 的 `FilterKitUITests` target、`Tools/ReportRoundtripValidator` 校验器、App target 工程定义。
- 摘出后主流程仅 `environment → build → test` 与并行 `isolation`；`swift build`/`swift test` 本就不编译 UITests（`Package.swift` 测试清单未引用 `Tests/Stage2/UITests`）。
- 后续阶段接回：移除两个 job 的 `if: false`，恢复 `artifact` 对 `app-build` 的依赖即可；源码与 target 无需重建。

### 5.2 其余未决项

- D5 进程/签名 entitlement 受支持读取接口、D6 `jbroot()` 签名/链接方式待真机环境核实；核实后替换占位实现，协议快照与证据模型不变。
- 既有未决项继续挂起：`OwnershipResolver` 未迁移、`loaded` 恒 `.unknown`、`permission.decision` 恒 undetermined、`pluginID` 规则 0.2.0 定稿、PARSE-009-B。
- 0.1-E 未进入；0.1-C G10 缺口记录在 `Tests/Stage2/evidence/c-f5-seventh-run/C-F5-Gate-Status.md` §3.2。

### 5.3 首轮 Runner build 编译修复（2026-11-20 补充）

0.1-D 链路首轮 Runner（build job，`workflow-job-run-5a0ac726-c438-5707-9f45-ae42b7484734`，checkout SHA `967d815200f91273ecae54ea6eea3b1cc6334455`，macOS 26.7.2 / `macos-26-arm64` 20261102.0473.1）`swift build` exit 1；test / isolation 未触发。证据归档：`Tests/Stage2/evidence/0.1-d-run-logs/`（`job-logs.txt` + `RUN-METADATA.md`）。

**诊断（两类，并行编译重复报出，根因各一处）：**

1. `Core/PermissionProbe/Probes/PlistReadProbe.swift:45:28` error：`'nil' cannot be assigned to type 'String'`。根因：局部量 `observed` 声明为非可选 `String`，而 notFound / accessDenied / readFailed 三分支赋 `nil`；模型字段 `observedValue` 本就是 `String?`。
2. `Core/PermissionProbe/Services/PermissionProbeService.swift:31:15` warning：`'catch' block is unreachable because no errors are thrown in 'do' block`。根因：协议 `run()` 原为非抛出，服务 do/catch 不可达。

**本地修复（4 个文件，待下一轮 Runner 复验）：**

- `Core/PermissionProbe/Probes/PlistReadProbe.swift`：`let observed: String` → `let observed: String?`；三分支 nil 合法，可选透传 `observedValue`。
- `Core/PermissionProbe/Protocols/PermissionProbing.swift`：`func run() -> [ProbeEvidence]` → `func run() throws -> [ProbeEvidence]`；头注释同步抛错由编排服务捕获语义。
- `Core/PermissionProbe/Services/PermissionProbeService.swift`：`probeEvidence = probe.run()` → `probeEvidence = try probe.run()`；do/catch 与失败证据（保留原 probeID）保留。
- `Tests/Stage2/PermissionProbeProbeTests.swift`：抛错桩 `ThrowingProbe` 补 `throws`；并修正服务隔离用例对照桩——原 nil 路径 JBRoot 探针仅 1 条证据，与断言总数 3 不符（测试阶段未执行，日志未暴露），改为可枚举目录桩返回 2 条证据，合计 3。

**复核口径：** 协议改 throws 后，8 个探针实现保持非抛出 `run()`，Swift 允许非抛出方法满足抛出协议要求；已逐一核对探针签名、证据构造标签、Models 枚举原始值、AppPresentation 映射与测试断言。本机 Linux 无 Swift/Xcode，未本地编译；编译与用例结论以下一轮 Runner 日志为准。未增删文件，`Package.swift` 源清单无需改动。

### 5.4 第二轮 Runner test 目标编译修复（2026-11-20 补充）

第二轮 Runner（test job，`workflow-job-run-92462907-2290-5911-9e3c-13c8ed4102dd`，checkout SHA `92127cd1`，macOS 26.7.2 / `macos-26-arm64`）：Models / Adapters / AppPresentation / Core 全部 emit 成功（首轮 §5.3 修复编译通过），`ReportRoundtripValidator` 链接成功；Stage2Tests 测试目标编译失败，用例未执行。证据归档：`Tests/Stage2/evidence/0.1-d-run-2-logs/`（`job-logs.txt` + `RUN-METADATA.md`）。

**诊断与修复（3 个文件，待下一轮复验）：**

1. `Tests/Stage2/PermissionProbeEvidenceTests.swift:46`：`object?.keys ?? []` 中 `Keys?` 与 `[Any]` 不能用 `??` 合并；改为 `let keys: Set<String> = object.map { Set($0.keys) } ?? []`，对齐既有 `ReportExporterTests` 写法。
2. `Tests/Stage2/PermissionProbeProbeTests.swift:117/131`：`errno: .ENOENT/.EACCES.rawValue` 在 `Int32?` 上下文查不到 POSIX 成员；补显式前缀 `POSIXErrorCode.ENOENT.rawValue` / `POSIXErrorCode.EACCES.rawValue`，对齐既有 `PlistReaderTests` 写法。
3. 同文件 122/123/135 行 `Equatable has no member unavailable/notExecuted/permissionDenied` 为第 2 项的类型级联：errno 初始化失败使 `FileAccessResult`/桩/探针/证据类型退化到 `Equatable`；第 2 项修复后类型链恢复，断言口径未改。
4. `Package.swift`：`Stage2Tests` `exclude` 增补 `"UITests"`，消除 5 个 XCUITest 源文件「unhandled」资源告警；源码与 `FilterKitUITests` target 保留，未纳入 SwiftPM 编译。

**复核口径：** 未改 Core/Models 源码与探针业务预期；其余四个探针测试文件（Status / Report / Presentation）本轮编译未报错。本机 Linux 无 Swift/Xcode，未本地编译；测试目标编译与用例结论以下一轮 Runner 日志为准。

### 5.5 第三轮 Runner test 断言修复（2026-11-20 补充）

第三轮 Runner（test job，`workflow-job-run-d2b6f5e1-d971-501a-a635-baefb8eedca7`，checkout SHA `c657da5d`，macOS 26.7.2 / `macos-26-arm64`）：Models / AppPresentation / Adapters / Core 全部 emit，ReportRoundtripValidator 链接成功；Stage2Tests 编译并链接通过（二轮类型错误与 UITests unhandled 告警未复现）；全量 448 例 1 失败。证据归档：`Tests/Stage2/evidence/0.1-d-run-3-logs/`（`job-logs.txt` + `RUN-METADATA.md`）。

**诊断与修复（1 个测试文件，待下一轮复验）：**

1. `Tests/Stage2/PermissionProbeProbeTests.swift:254`：`testDpkgProbePassesNonEmptyStatusFile` 期望 `"readable: 12 bytes"`，实际 `"readable: 11 bytes"`。夹具 `Data("Package: x\n".utf8)` 实为 11 字节；探针按 `data.count` 报告（`DpkgDatabaseProbe.swift:71`），口径与 `PlistReadProbe` 的 `data-readable: 3 bytes` 一致，探针正确、测试期望值偏移 1。断言改为 `"readable: 11 bytes"`；探针实现、夹具、证据状态口径不改。

**复核口径：** 未改 Core/Models 源码与探针业务预期；同套件其余 dpkg 用例及 D2/D3/D5/D6 探针、Presentation 映射用例全部 passed。隔离脚本 7/7 passed。本机 Linux 无 Swift/Xcode，未本地编译；全量用例结论以下一轮 Runner 日志为准。

### 5.6 统一 Runner 验收（2026-11-20 补充，离线/CI 切片通过，真机门禁挂起）

验收 Runner（run `120942979030`，checkout SHA `cb130c36`，macOS 26.7.2 / Xcode 26.6 / Swift 6.3.3 / SDK 26.5）四 job（environment / build / test / isolation）同一 SHA；证据归档 `Tests/Stage2/evidence/run-120942979030-acceptance/`（`RUN-METADATA.md` + 分步日志 + metadata + test-log + build/isolation 产物）。

**离线 / CI 口径 L2 切片结论：通过。**

- 非 UI Build：`Build complete! (15.69s)`，0 error / 0 warning；Models / Adapters / AppPresentation / Core emit，ReportRoundtripValidator 链接成功。
- 全量 Swift 测试：**448 tests，0 failures（0 unexpected）**；S1-05 独立过滤 15 tests，0 failure。
- 探针专项 43 例全绿：Status 4 / Evidence 5 / Report 6 / Probe 24 / Presentation 4；三轮修复点（dpkg 11 bytes 断言、字典键兜底、errno 前缀）本轮复核 passed；无 UITests unhandled 告警。
- 隔离静态检查：1a/1b/2a/2b/3/4/4b 七项 passed，`failed: 0`（CI isolation job 实际执行）。
- 既有回归（0.1-A / 0.1-B / 0.1-C 基线）含在 448 例内，0 failure、无损伤。
- 工具链版本已由 environment job 录档；全量日志无 `##[error]` / exit 1 / FAILED。

**未闭环项（不计 passed，不得以 CI 替代）：**

- 真机门禁 D-G10～D-G15 全部 pending/unknown：JBROOT 权限、TweakInject 可达、dylib/plist/dpkg 读取、entitlement/sandbox、`jbroot()` 调用与一致性、冷启动权限保持；须 RootHide 真机真实 GUI 进程取证。D5/D6 仍占位 unavailable/unknown。
- App Build / 模拟器存活 / XCUITest 交互本轮按摘出口径未执行（`app-build`、`ui-acceptance` 置 `if: false`）；源码、target、往返校验器保留。
- 既有未决项继续挂起：`OwnershipResolver` 未迁移、`loaded` 恒 unknown、`permission.decision` 恒 undetermined、`pluginID` 规则 0.2.0、PARSE-009-B；0.1-C G10 缺口不豁免不签署。

**判定：** 0.1-D 离线/CI 切片通过，里程碑未闭环；不生成 0.1-D 签署结论，不进入 0.1-E。本报告仅代表离线 / CI / 合成桩口径，不构成真机权限、真实加载或 Rootless 真机兼容证据。

### 5.7 R1-A/B 分批收口（2026-11-20 补充，接线恢复 + API 核实，Runner/真机仍 Pending）

- **R1-A**：`.github/workflows/filterkit-build.yml` 恢复 `app-build`（needs `[build, isolation]`）、`ui-acceptance`（needs `[app-build]`，XCUITest）与 `artifact` 对 `app-build` 的依赖；移除两处摘出期间的 `if: false`。本地 YAML 解析通过，Job 链 `environment→build→test / isolation→app-build→ui-acceptance→artifact`。G7 App Build、G8 Diagnostics 页面、G9 JSON 导出须待 Runner 实跑日志判定，本轮不预写通过。
- **R1-B**：`jbroot()` 上游源码核实完成（libroothide，`-lroothide`，C/Obj-C 重载声明、默认导出符号、rootful/rootless 静态桩行为、无零参取基目录接口）；iOS 进程内 entitlement 公开读取接口核实为不可用（`SecTask*` 仅 macOS/Catalyst）。D5/D6 占位未替换，未写任何真实调用、弱链接或 dlsym；冻结 Models/ReportEnvelope/Adapter 七方法协议未改。完整七项核实、三分拆证据口径、未决项与 R1-C 真机准备清单见 `Stage-2.4-R1B-APIPermission-Feasibility-Record.md`。
- **判定不变：** 0.1-D 仍未闭环；R1-A/B 仅为接线恢复与技术核实，不构成 G7～G15 通过证据。

### 5.8 R1-A 接线恢复后 Runner 实跑验收（2026-11-20 补充，G1～G9 通过；真机 G10～G15 挂起）

验收 Runner（run `120957775572`，检出 SHA `4b08fe1a0c20bbd08dac40d0a58190d186e1a737`，macOS 26.7.2 / Xcode 26.6（17F113）/ Swift 6.3.3 / swift-driver 1.148.6 / SDK 26.5）七 job 同一工作流；证据归档 `Tests/Stage2/evidence/run-120957775572-acceptance/`（`RUN-METADATA.md` + 分步日志 + metadata + test-log + 隔离产物 + app-build 日志与截图 + XCUITest `ui-test.log` + 导出信封；xcresult 数据束与 DerivedData 二进制按交付惯例不入库、不进包，结论以日志与 `RUN-METADATA.md` 记录为准）。本轮为 R1-A 恢复 `app-build` / `ui-acceptance` / `artifact` 依赖后，D7 之后第一次 XcodeGen + xcodebuild 全量 App target 构建与 Simulator 交互验证。

**Runner / Simulator 口径 G1～G9：通过（日志实测值）。**

- **G1 非 UI Build：** `Build complete! (13.28s)`，0 error / 0 warning；Models / Adapters / AppPresentation / Core emit，ReportRoundtripValidator 编译并链接。
- **G2/G6 全量 Swift 测试：** **448 tests，0 failures（0 unexpected）**；既有 0.1-A / 0.1-B / 0.1-C 基线含在 448 例内，0 failure、无损伤。
- **G3 S1-05 配对映射：** 独立过滤 **15 tests，0 failures（0 unexpected）**。
- **G4 探针专项 43 例全绿：** Status 4 / Evidence 5 / Report 6 / Probe 24 / Presentation 4；三轮修复点（dpkg 11 bytes 断言、字典键兜底、errno `POSIXErrorCode.` 前缀）复核 passed；无 UITests unhandled 告警。
- **G5 隔离静态检查：** 1a/1b/2a/2b/3/4/4b 七项 `passed`，`failed: 0`；Runner isolation job 实际执行，本地脚本复跑 exit 0 结论一致。
- **G7 App Build：** `** BUILD SUCCEEDED **`，0 error；唯一 1 条 warning 为 `appintentsmetadataprocessor`「No AppIntents.framework dependency found」元数据跳过系统噪声，非 Swift 编译告警。`FilterKit.app` 产物保留于 DerivedData：`FilterKit` 123808B、`FilterKit.debug.dylib` 8944448B、`__preview.dylib` 83952B、`Info.plist` 756B、`PkgInfo` 8B、`_CodeSignature/CodeResources` 2321B；dylib 与 bundle 均 `codesign --sign -` 签名并 Validate/Touch 通过。模拟器设备 `EED6FB0A-…`，`com.filterkit.manager` launch PID 4029，3 秒后存活；`dashboard.png` 1206×2622 RGBA。
- **G8 Diagnostics / 导航页面：** XCUITest **8 例 0 failure（192.521s）**；Dashboard 基线、Diagnostics 分区（`testDiagnosticsSectionsVisible`）、列表分段/搜索、详情页、设置页全 passed。
- **G9 JSON 导出 / 往返校验 / Share Sheet：** 导出 `FilterKit-Report-0-1-0-preview.json`（5295B，`schemaVersion 0.1.0` / `generatorVersion 0.1.0-preview` / `profile roothide-preview·roothide`，plugins 3 / unknownItems 1 / warnings 1）；往返校验 `decodable=true`、`equalIgnoringGeneratedAt=true`、`messages=[]`；`SHA256SUMS` 落盘且复算一致；导出无错误、Share Sheet、空态禁用导出三例 passed。
- 全量日志无 `##[error]`、无 exit code 1、无 `FAILED`、无 `Assertion Failure` / `XCUITestError`；六份 Runner artifact 全部上传并 finalized。

**未闭环项（不计 passed，不得以 CI / Simulator 替代）：**

- 真机门禁 **G10～G15 全部 pending/unknown**：JBROOT GUI 进程访问、TweakInject 可达、dylib/plist/dpkg 真机读取、entitlement/sandbox 放行、`jbroot()` 声明/链接/调用与路径一致性、冷启动权限保持；须 RootHide 真机真实 GUI 进程取证。D5/D6 仍占位 unavailable/unknown。
- Dashboard 截图与导出 JSON 均为 `SyntheticReportFactory` 合成预览桩，不构成真机权限、真实加载或真实扫描证据；本轮 Simulator G9 通过不能替代 0.1-C G10 真机缺口。
- 既有未决项继续挂起：`OwnershipResolver` 未迁移、`loaded` 恒 unknown、`permission.decision` 恒 undetermined、`pluginID` 规则 0.2.0、PARSE-009-B；D6 一致性比较当前为原始字符串 `==`，路径规范化 / 软链解析细化列为未决。

**判定：** 0.1-D Runner / Simulator 切片 G1～G9 通过，里程碑**仍未闭环**；不生成 0.1-D 签署结论，不进入 0.1-E。本报告仅代表 Runner / Simulator / 合成桩口径，不构成真机权限、真实加载、`jbroot()` 真机可调用性或 Rootless 真机兼容证据。本轮无新增源码改动；未改 Adapter 七方法协议、冻结 Models / ReportEnvelope、Core 业务语义；未触真机写操作与插件管理。

### 5.9 R2-A/B：D5 三类证据分离与 D6 路径一致性修复（2026-11-20 补充，Runner 复验 Pending）

授权：用户授权「FilterKit 0.1-D-R2-A/B」。目标为 D5 Entitlement 技术实现准备（Signed / Runtime / Resource Access 三类证据显式分离）与 D6 RootHide `jbroot()` 真实 API 复核及路径一致性修复（标准化、软链解析、分层一致性证据），补 D5/D6 单测与错误态测试；保持 RootHide / Rootless Adapter 独立，不改 Adapter 七方法协议、冻结 Models 与 `ReportEnvelope`，不改 `loaded` / `installed` / `configured` 既有语义。本授权不含 0.1-E 正式开发、发布打包与签署。

**上游复核（2026-11-20 重新抓取 libroothide 当前 main，结论与 R1-B 记录一致，无漂移）：**

- `roothide.h`：C `const char* jbroot(const char* path);`；Obj-C `NSString* _Nonnull __attribute__((overloadable)) jbroot(NSString* _Nonnull path);`；另有 alloc 变体 `jbroot_alloc` / `jbrootat_alloc`、`rootfs` / `rootfs_alloc`、`jbrand`。
- `module.modulemap`：`module roothide { header "roothide.h"; link "roothide"; export * }`，链接 `-lroothide`。
- `jbroot.c`：`jbroot(const char*)` 经 `jbroot_alloc` 走进程内静态 `cache_path` 缓存返回；alloc 变体 malloc/strdup 后由调用方释放；空 / NULL path 在 alloc 层返回 NULL；`__private_jbrootat_alloc` 做词法 `.` / `..` 解析、去尾斜杠、stat JBROOT 与 `/` 并比对 inode/dev，处理 `/rootfs` 前缀剥离。
- `stub.h`：非 roothide 构建静态桩，`jbroot(path)` 原样返回 path、`jbrand()` 返回 0；不提供真实 JBROOT 信息。
- `common.h`：`EXPORT = __attribute__((visibility("default")))`；`extern const char* __roothideinit_JBRAND; extern const char* __roothideinit_JBROOT;`；`JB_ROOT_PARENT "/var/containers/Bundle/Application"`。无零参取基目录接口，基目录由 extern `__roothideinit_JBROOT` 承载；`jbroot("/")` 取基目录行为仍属待真机验证推断。
- Apple 文档复核：`SecTaskCopyValueForEntitlement` / `SecTaskCreateFromSelf` 官方可用平台为 Mac Catalyst 13.0+ / macOS 10.0+，不含 iOS；Runtime entitlement 在 iOS GUI 进程无公开稳定读取接口，保持 unavailable/unknown。

**代码修改清单：**

| 路径 | 改动 |
|---|---|
| `Core/PermissionProbe/Entitlement/EntitlementEvidenceSource.swift` | 新增：`EntitlementEvidenceSource`（signed / runtime / resourceAccess）枚举与 Core 层 `EntitlementEvidenceRecord` 事实记录；仅 Core 内部归类与测试断言，不进入冻结 Models。 |
| `Core/PermissionProbe/JBRootAPI/JBRootPathComparison.swift` | 新增：`JBRootPathComparison` 四层事实位（raw / normalized / symlink / accessible）、`JBRootConsistencyVerdict`（passed / failed / unknown）与 `JBRootPathComparator`：词法规范化（`URL.standardizedFileURL`）、软链解析（`URL.resolvingSymlinksInPath()`）、可选 `FileAccessChecking` 实测可达；verdict 规则：normalized 失配 → failed；normalized 匹配且 symlink 失配 → failed；normalized 匹配且 symlink 未知或匹配 → passed；路径缺失 → unknown。 |
| `Core/PermissionProbe/Entitlement/UnavailableEntitlementInspector.swift` | 占位默认原因来源化：runtime 检查器注明 iOS GUI 进程公开稳定读取接口未核实（SecTask API 仅 macOS/Catalyst）；signed 检查器原因不变口径。协议与快照结构未改。 |
| `Core/PermissionProbe/Probes/EntitlementProbe.swift` | 两条证据显式标注来源前缀：process → `[runtime]`，code-sign → `[signed]`；通过仅代表接口读取成功，不记权限放行。`ProbeEvidence` 字段未加。 |
| `Core/PermissionProbe/Probes/SandboxAccessProbe.swift` | 资源访问证据标注 `[resourceAccess]` 前缀；可达 / 拒绝 / 不存在分类口径不变。 |
| `Core/PermissionProbe/Probes/JBRootAPIProbe.swift` | 一致性证据由原始字符串 `==` 改为 `JBRootPathComparator` 分层比较；初始化器新增可选 `fileAccess: FileAccessChecking? = nil`（默认 nil 兼容既有调用与测试）；resolver 协议与 `JBRootAPISnapshot` 未改；摘要按 raw / normalized / symlink / accessible 四层输出，不回显完整私有路径。 |
| `Package.swift` | Core `sources` 显式清单登记上述两个新 Core 文件；测试源清单未变（新用例并入既有 `PermissionProbeProbeTests.swift`）。 |
| `Tests/Stage2/PermissionProbeProbeTests.swift` | 更新受来源前缀影响的既有断言；新增 10 例：D5 3 例（runtime/signed 来源不混淆、runtime 不可用原因含平台口径、三类来源枚举与记录结构）；D6 7 例（尾斜杠 / 双斜杠 / `.` / `..` 规范化、raw 失配但 normalized 匹配仍 passed、无访问器 accessible=unknown、有访问器可达匹配、不可达 accessible:false 且不反向改写 verdict、确认路径缺失 unknown、verdict 规则四分支）。 |

**冻结与未触碰边界：** Adapter 七方法协议未改；RootHide / Rootless Adapter 独立编译、互不引用；冻结公共 Models、`ReportEnvelope`、Core 业务语义、Plist Parser 语义、Stage1 fixtures 未改；`loaded` / `installed` / `configured` 既有语义未改（不互推，loaded 无独立运行时证据恒 unknown）；未链接 libroothide、未写 C 桥接声明、未弱链接、未 dlsym、未调用任何未验证私有 API；未做插件启停、plist 写入、dylib 删除 / 移动、dpkg 写操作、注入规则修改、自动修复、常驻 daemon；未触真机。

**Runner 状态（待下一轮在线 CI 日志判定，本轮不预写通过）：** 本机 Linux 无 Swift/Xcode，新增 Core 文件与测试未在本地编译；新增 10 例与既有探针专项用例（上轮 43 例口径）须由下一轮 Runner `swift test` 日志复核；上轮 448 例全量 + 15 例 S1-05 + 43 例探针 + 7 项隔离 + 8 例 XCUITest 基线不得被本轮改动回归。

**未解决技术限制：**

1. GUI 进程内 libroothide 符号可解析性、调用成功、返回路径有效性、与 D2 一致性均待 RootHide 真机；`jbroot("/")` 取基目录行为属待真机验证推断。
2. 词法规范化不等于真实 inode / dev 文件身份验证；`resolvingSymlinksInPath()` 对不存在路径仅作词法解析；真实身份比对须真机 stat 取证。
3. D5 Runtime entitlement iOS 无公开稳定读取接口；真机 entitlement / sandbox 结论须 RootHide 真机 GUI 进程取证。
4. accessible 层为独立证据层：不可达（accessible:false）不反向改写一致性 verdict，二者分开记录。

**RootHide 真机验证准备清单（沿用 R1-B §7，本轮不执行）：** 设备 / 越狱 / 架构录档；签名与部署形态拍板；libroothide devkit 头库、链接参数与 `__roothideinit_JBROOT/JBRAND` 进程内存在性核实；独立真机证据模型不修改冻结 Models；只读边界复核（lstat/stat/opendir/readdir/open/read，不 dlopen、不写越狱目录、不 dpkg/apt 写）；测试顺序 JBROOT → TweakInject → dylib/plist → dpkg → D5/D6；冷启动复测；证据归档且 unavailable/unknown/pending 不得改写 passed。

### 5.10 R2-A/B Runner 复验（2026-11-20 补充，G1～G9 通过；真机 G10～G15 挂起）

验收 Runner（run `121082423820`，检出 SHA `59f3eb96a296c5ca8db908635275fc6f5b69c07f`，origin/main；本地基线提交 `10d74a4` 未推送，metadata 五文件与本地逐文件 diff 一致；macOS 26.7.2（25G332）/ Xcode 26.6（17F113）/ Swift 6.3.3（swiftlang-6.3.3.1.3 clang-2100.1.1.101）/ SDK 26.5）；证据归档 `Tests/Stage2/evidence/run-121082423820-acceptance/`（`RUN-METADATA.md` + 分步日志 + metadata + test-log + 隔离产物 + app-build 日志与截图 + XCUITest `ui-test.log` + 导出信封；xcresult 数据束与 DerivedData 二进制按惯例不入库、不进包）。本轮为 §5.9 R2-A/B 改动（D5 三类证据分离、D6 四层路径比较器、新增 10 例）落地后的第一次 Runner 复验。

**Runner / Simulator 口径 G1～G9：通过（日志实测值）。**

- **G1 非 UI Build：** `Build complete! (26.89s)`，0 error / 0 warning；`JBRootPathComparison.swift`（步骤 39/90）、`EntitlementEvidenceSource.swift`（步骤 86/114）参与编译。
- **G2/G6 全量 Swift 测试：** **458 tests，0 failures（0 unexpected）**，0.212 (0.269) 秒；恰为 R1 基线 448 + R2 新增 10；既有 0.1-A / 0.1-B / 0.1-C / R1 基线含在 458 例内，0 failure、无损伤。
- **G3 S1-05 配对映射：** `PluginPairingS105FixtureTests` **15 tests，0 failures（0 unexpected）**。
- **G4 探针专项 53 例全绿：** Status 4 / Evidence 5 / Report 6 / Probe 34（基线 24 + R2 新增 10）/ Presentation 4。
- **G5 隔离静态检查：** 1a/1b/2a/2b/3/4/4b 七项 `passed`，`failed: 0`。
- **G7 App Build：** `** BUILD SUCCEEDED **`，0 error；唯一 1 条 warning 为 `appintentsmetadataprocessor` 元数据跳过系统噪声，非 Swift 编译告警。产物保留于 DerivedData：`FilterKit` 123,808B、`FilterKit.debug.dylib` 9,082,672B、`__preview.dylib` 83,952B、`Info.plist` 756B、`PkgInfo` 8B、`_CodeSignature/CodeResources` 2,321B；dylib 与 bundle 均签名并 Validate/Touch 通过。模拟器设备 `5AB3DACF-C352-49D1-BF9A-3C0104FA4ED3`，`com.filterkit.manager` launch PID 6302 存活；`dashboard.png` 1206×2622 RGBA，843,228B。
- **G8 Diagnostics / 导航页面：** XCUITest **8 例 0 failure（238.195s）**；EmptyState 1 / ExportFlow 1 / NavigationFlow 5 / ShareSheet 1 全 passed（明细见归档 `RUN-METADATA.md` §4）。
- **G9 JSON 导出 / 往返校验 / Share Sheet：** 导出 `FilterKit-Report-0-1-0-preview.json`（5,295B，plugins 3 / unknownItems 1 / warnings 1，`baselineGeneratorVersion 0.1.0-preview`）；往返 `decodable=true`、`equalIgnoringGeneratedAt=true`、`messages=[]`；`SHA256SUMS` 落盘且本地复算一致；导出无错误、Share Sheet、空态禁用导出三例 passed。
- **R2 新增 10 例**（D5 ×3：三类来源覆盖、runtime 不可用平台原因、runtime/signed 来源分标；D6 ×7：规范化、raw 失配 normalized 匹配、无访问器 accessible=unknown、有访问器可达匹配、不可达 accessible:false、确认路径缺失 unknown、verdict 规则四分支）在 test-log 中逐一出现并 passed。
- 全量日志无 `##[error]`、无 exit code 1、无 `FAILED`、无 `Assertion Failure` / `XCUITestError`；六份 Runner artifact 全部上传并 finalized。

**未闭环项（不计 passed，不得以 CI / Simulator 替代）：**

- 真机门禁 **G10～G15 全部 pending/unknown**：JBROOT GUI 进程访问、TweakInject 可达、dylib/plist/dpkg 真机读取、entitlement/sandbox 放行、`jbroot()` 声明/链接/调用与路径一致性、冷启动权限保持；须 RootHide 真机真实 GUI 进程取证。D5 runtime 证据在 iOS 仍为 unavailable/unknown；D6 symlink 层真机解析与 accessible 层真机文件访问仍待 G10/G14 取证。
- Dashboard 截图与导出 JSON 均为 `SyntheticReportFactory` 合成预览桩，不构成真机权限、真实加载或真实扫描证据；本轮 Simulator G9 通过不能替代 0.1-C G10 真机缺口。
- 既有未决项继续挂起：`OwnershipResolver` 未迁移、`loaded` 恒 unknown、`permission.decision` 恒 undetermined、`pluginID` 规则 0.2.0、PARSE-009-B。§5.8 记录的「D6 原始字符串 `==`、规范化 / 软链解析细化列为未决」一项，本轮已由四层比较器（raw / normalized / symlink / accessible）替换；真机身份比对仍待取证。

**判定：** 0.1-D Runner / Simulator 切片 G1～G9 通过，里程碑**仍未闭环**；不生成 0.1-D 签署结论，不进入 0.1-E。本报告仅代表 Runner / Simulator / 合成桩口径，不构成真机权限、真实加载、`jbroot()` 真机可调用性或 Rootless 真机兼容证据。本轮归档仅回填证据与结论；未改 Adapter 七方法协议、冻结 Models / ReportEnvelope、Core 业务语义；未触真机写操作与插件管理。

### 5.11 R3-A：RootHide 真机验证方案冻结（2026-11-20 补充，真机批次待设备）

授权：用户授权进入 **0.1-D-R3**，本轮先落地 **R3-A 真机测试准备**（方案冻结）；R3-B～E 真机只读探针、冷启动复验与归档须在具备 RootHide 真机与 FilterKit GUI 进程上下文的环境分批授权执行；0.1-E 仅预冻结设计设想，不进入正式实现。依据用户 R3 建议稿（2026-11-20 上传归档）与 R2 归档 `204ef12`。规格：`Spec/Stage-2/Stage-2.4-R3-Device-Validation-Plan.md`。

- **批次拆分**：R3-A 方案冻结 → R3-B JBROOT/TweakInject 访问 → R3-C 插件文件与 dpkg 只读 → R3-D Entitlement/`jbroot()` 真机验证 → R3-E 冷启动复验、Diagnostics 接入与归档；0.1-C G10 独立补证（独立门禁/独立证据，不并入 0.1-D 判定）；其后才是 0.1-D Final 签署与 0.1-E。R3-B～D 复用 R2 已落地探针，不另造扫描器。
- **执行矩阵**：G10 JBROOT（`jbroot.directory.access`）、G11 TweakInject（`ellekit.directory.access`）、G12 dylib/plist/dpkg（`plugin.file.metadata` / `plugin.plist.read` / `package.database.read`）、G13 Entitlement/Sandbox（`entitlement.inspect` / `sandbox.resource.access`）、G14 `jbroot()` 与四层一致性（`jbroot-api.inspect`）、G15 冷启动复测。stat/list/read/parse/inspect/invoke 各成独立证据，不得跨操作推断成功；读取≠解析≠加载，`loaded` 继续恒 unknown。
- **证据模型**：复用冻结 `ProbeStatus` 六态、`ProbeOperation`、`ProbeCategory`、`ProbeEvidence`、`PermissionProbeReport`；R3 局部包装层（DeviceValidationEvidence / Gate / Report）仅在 R3-B 落地 Swift 类型，不扩展冻结公共 Models；证据须可追溯门禁/探针/操作/commit/runID/环境/文件 SHA256/时刻/设备与进程上下文（`processContext = FilterKit.GUI`）。
- **Preflight 与门禁**：设备档案、部署形态 A/B/C 冻结、commit 对齐、目标版本 libroothide 头文件/符号/链接核实、只读边界、样本基线、GUI 进程上下文、环境纯净、证据通道、工具链兼容性逐项确认后才进 R3-B。验收分 Runner 离线切片（458 基线不回退、模型往返、状态传播、映射、导出、隔离、App Build、Simulator 回归）与 RootHide 真机 G10～G15 两类；CI/Simulator 证据不替代真机，未完成项保持 pending/unknown。
- **边界不变**：不调用真实 `jbroot()`、不写桥接声明/弱链接/dlsym；不做插件启停、plist 写入、dylib 删移、dpkg 写、注入规则修改、自动修复、常驻 daemon；不改 entitlement/签名/沙盒；本规格不编译、不建工程、不写真机调用代码。
- **既有挂起项维持**：OwnershipResolver 未迁移、`loaded` 恒 unknown、`permission.decision` 恒 undetermined、`pluginID` 规则 0.2.0、PARSE-009-B；0.1-C G10 为既有搁置项，重启复核须明确授权推翻 2026-11-20 搁置决定，R3-A 不自动重启。

### 5.12 R3-A2 / R3-F：部署包规格冻结与总方案补全（2026-11-20 补充，离线规格，真机批次仍待设备）

授权：依据用户两份 R3 建议稿（批次连续推进 / DEB 部署口径，归档 `Tests/Stage2/evidence/r3-device-validation/R3-proposal-batch-sequencing.md`、`R3-proposal-deployment-deb.md`）。本轮仅做离线规格冻结，不在 Linux 云主机继续开发真机探针，不产出可安装包。规格：`Stage-2.4-R3-Device-Validation-Plan.md` §2/§3/§5/§6/§8 修订；`Stage-2.4-R3-A2-Deployment-Package-Spec.md` 新建。

- **批次补全**：R3-A 方案冻结 → **R3-A2 部署包规格** → R3-B JBROOT/TweakInject → R3-C 文件与 dpkg 只读 → R3-D Entitlement/`jbroot()` → R3-E 冷启动复验与留证 → **R3-F R3 总体验收**（Runner 切片 + 真机门禁统一复核，门禁状态由证据重算）；其后才是 0.1-C G10 独立补证、0.1-D Final、0.1-E。R3-B～E 不做批次间正式 Runner 验收，但各自完成执行记录与证据归档。
- **内部检查点**：检查点 A（R3-B 后：路径正确、目录可达、确为 FilterKit GUI 进程、未拿 shell 结果充当 GUI 结果）；检查点 B（R3-C/D 后：读取与解析分离、Entitlement 三类分离、`jbroot()` 用真实 API、四层比较可追溯、无新增私有扫描器）；检查点 C（R3-E 后：冷启动前后设备/形态/代码版本一致、复测独立留证、证据 SHA256 一致、门禁状态可由证据重算）。
- **环境五冻结**：设备环境（型号/iOS/架构/RootHide 版本/ElleKit 版本/bootstrap/JBROOT 路径摘要）、部署形态、代码版本基线（commit SHA/Build Number/Bundle ID/部署 profile，中途变更须记新 SHA 并重判受影响门禁）、测试样本基线、证据环境；全程只读。
- **部署形态口径更新**：A 普通 IPA / B 特殊权限 App / C Bootstrap 通道 / **B+C 组合**（优先验证，最终真机证据决定）。DEB 为正式真机测试主载体，IPA 仅辅助对照；安装成功≠权限放行，安装位置/签名/entitlement/sandbox 四项分别验证。
- **R3-A2 规格范围**：DEB 建议结构（`Applications/FilterKit.app` + `DEBIAN/control`/`postinst`）；Bundle ID/版本/架构/Deployment Target 草案口径（B2/B3 仍未冻结）；control 最小字段口径；postinst 仅允许 uicache 注册、禁止改插件/注入规则/系统配置/起 daemon；entitlement 候选四枚（`platform-application`、`no-sandbox`、`AppBundles`、`AppDataContainers`）为参考清单，签名出现≠运行时放行；CI 静态检查与构建元数据（commitSHA/buildNumber/bundleID/scheme/ARCHS/SDK/builtAt/artifactSHA256）口径先行。
- **证据字段扩列**：DeviceValidationEvidence 按建议稿补 deviceID/deviceModel/iOSVersion/RootHideVersion/ElleKitVersion/filterKitCommitSHA/filterKitBuildNumber/deploymentProfile，与既有 gateID/probeID/operation/status/errorDomain/errorCode/executedAt/processContext/processIdentifier/artifactSHA256 等字段一并落契约；Swift 类型仍待 R3-B 落地。
- **边界不变**：本轮不改写现有 `control`/`Makefile`/`project.yml` 占位；不写落盘安装脚本、不打包、不签名、不真机安装；G10～G15 继续 pending/unknown；0.1-D 未闭环不签署、不进 0.1-E。

### 5.13 R4-A0：Device Build & Deployment 规格冻结与离线脚手架（2026-11-20 补充，待 Runner 离线复验）

授权：依据用户 R4 建议稿（归档 `Tests/Stage2/evidence/r4-device-build/R4-proposal-device-build-deployment.md`）。思路：开发不停在真机验收上，但 0.1-D 未完成的真机问题不带进 0.1-E；两条路线并行独立——产品开发路线推进 R4 设备构建/部署，发布验收路线保留真机门禁不降低。规格：`Spec/Stage-2/Stage-2.4-R4-Device-Build-Deployment-Plan.md`。

- **现状审计**：Core/Models、Enumeration/Pairing/Parser、Reporting/Export、GUI Foundation、PermissionProbe 离线口径已验收；D5 三类证据分离、D6 四层路径比较已落地待真机；缺口明确为仅有模拟器构建链，无 iOS 设备构建与 RootHide 部署链（Device Build / Signing / IPA / DEB / Package Validation / 部署文档）。
- **批次拆分**：R4-A 设备构建（`Release-iphoneos`，arm64 主目标，平台 iPhoneOS 校验）→ R4-B 签名与 entitlement 配置（Developer 证书与 ldid 两条路线区分，候选四枚键仅清单）→ R4-C IPA 结构打包（对照，未签名只能称结构包）→ R4-D DEB 打包（优先方向，`Applications/FilterKit.app` + `DEBIAN/control`/`postinst`，路径/架构名/Depends 待 bootstrap 实测）→ R4-E 包静态校验（平台/架构/Bundle ID/结构/签名状态/entitlement/control/postinst/SHA256）→ R4-F 部署文档；R4-G 真机启动冒烟门禁（8 项：安装/SpringBoard 识别/主屏启动/Dashboard/Diagnostics/Settings/不崩溃/Probe 从 GUI 启动，启动失败如实记 failed，后续探针证据无效）。
- **0.1-E 拆分**：0.1-E-A Release Acceptance Engine 可提前开发（门禁注册/证据索引/SHA256/RunnerID/CommitSHA/环境检查/状态传播/验收 JSON，不访问真实 JBROOT，不产生发布通过结论）；0.1-E-B Final Release Acceptance 必须等 0.1-C/0.1-D 闭环后执行。R4 先于 R3-B～E。
- **本轮落地的离线脚手架草案**：`Config/Signing/FilterKit.entitlements`（四枚候选键草稿）、`FilterKit.Debug.xcconfig` / `FilterKit.Release.xcconfig`（签名占位，离线构建 `CODE_SIGNING_ALLOWED=NO`）；`Config/DEB/control`、`Config/DEB/postinst` 草稿；`scripts/validate-device-build.sh`、`validate-ipa.sh`、`validate-deb.sh`、`validate-entitlements.sh` 静态校验脚本（沿用隔离脚本文本 + JSON 摘要约定）；`scripts/package-ipa.sh`、`package-deb.sh` 打包草稿。全部 `bash -n` 语法通过、entitlements plist 良构；**未编译设备包、未签名、未产出可安装包、未连真机**。
- **边界不变**：不真机安装、不签名放行验证、不 Bootstrap 部署、不 entitlement 真机权限验证、不 `jbroot()` 真机调用、不插件写操作、不 0.1-E-B 签署；不改冻结 Models/Adapter 七方法协议/Core 语义/既有模拟器 CI 链路；脚手架接入 CI 与 Runner 离线复验前不视为可构建/可打包/可安装；G10～G15 与 R4-G 继续 pending/unknown。

### 5.14 R4-A～E：CI 设备构建/打包/静态校验链路接线（2026-11-20，待 Runner 离线复验）

授权：依据用户授权稿《建议授权开发……利用 macOS Runner 建立真实》（归档 `Tests/Stage2/evidence/r4-device-build/R4-A-to-E-authorization.md`），范围限定 0.1-D-R4-A～E，明确不授权 R4-G、不授权 0.1-E-B。

- **CI 接线（`.github/workflows/filterkit-build.yml`，macos-latest，复用既有 checkout/xcodegen/artifact 惯例）**：新增 `device-build`（R4-A：`Release -sdk iphoneos -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO`，产物 `Release-iphoneos/FilterKit.app`，跑 `validate-device-build.sh`）；`signing-prep`（R4-B：`validate-entitlements.sh` 静态格式与清单校验，Developer 证书 / ldid 两路线在 `Config/Signing/README.md` 分开记录）；`package-ipa`（R4-C：`package-ipa.sh` 出未签名结构包，`validate-ipa.sh` 校 Payload 结构）；`package-deb`（R4-D：`package-deb.sh` 出测试 DEB，`validate-deb.sh` 校 control/postinst/包内 App）；`package-validation`（R4-E：下载四类产物，`collect-package-metadata.sh` 归集 SHA256、平台/架构/Bundle ID/最低系统版本与三态标签）。既有模拟器 `app-build`/`ui-acceptance` 链路未改，模拟器产物不作为设备构建证据。
- **脚本与配置修订**：新增 `scripts/collect-package-metadata.sh`（SHA256 + 元数据 JSON，三态 `Build Passed` / `Package Passed` / `Device Install Pending`）；`validate-entitlements.sh` 在无 plutil 时键名提取记 unavailable（不计 failed）；`package-deb.sh` 检查 `dpkg-deb --build` 退出码，失败即清残缺包并 exit 1；`Config/DEB/control` 去掉 dpkg-deb 不接受的 `#` 注释行与空 `Depends:` 字段，字段说明移入 `Config/DEB/README.md`；新增 `Config/Signing/README.md`（两路线区分 + 四条独立验证结论）。
- **本地离线演练（Linux 占位桩，非设备构建证据）**：`bash -n` 八脚本全过；YAML 解析 12 jobs；entitlements plist 经 plistlib 良构；占位假 App 演练 IPA：p1/p2 结构 passed，p3 因占位二进制非 Mach-O 如实 failed；DEB：e1～e4 全 passed（control 字段齐、postinst 无越界动作、包内 `Applications/FilterKit.app` 存在）；元数据脚本空输入产出可解码 JSON，三态均 Pending。本机无 xcodebuild/swift/plutil/lipo，平台/架构/Bundle ID/最低系统版本的设备侧判定待 Runner。
- **未取得与待 Runner**：未编译 `iphoneos` 设备产物、未签名、无可安装 IPA/DEB、未连真机；R4-A～E 原始 Runner 日志、产物 SHA256、平台/架构/Deployment Target 实测值待 workflow_dispatch 调度后回填；G10～G15 与 R4-G 继续 pending/unknown；**0.1-D 里程碑未闭环，不签署、不进入 0.1-E**。

### 5.15 R4 Runner 首轮（run 44758871580）失败诊断与脚本/CI 容错修复（2026-11-20，待复验）

Runner 基线 commit `460a9906ffa51d4b317169e285c3c846290d1baf`；诊断归档 `Tests/Stage2/evidence/r4-device-build/run-44758871580-round1-failure-diagnosis.md`。

- **device-build 失败（非编译失败）**：`xcodebuild ... CODE_SIGNING_ALLOWED=NO build` **BUILD SUCCEEDED**，产物 `Release-iphoneos/FilterKit.app`（Mach-O arm64，3,294,752B）；中断于 `validate-device-build.sh` d3：`line 86: supported�: unbound variable`。机理为裸变量 `$supported` 后直接紧跟全角右括号 `）`，Runner shell/区域设置下多字节字符被并入变量名，`set -u` 引用未绑定变量退出；`CFBundleSupportedPlatforms` 系数组，标量读取本就不适用。
- **package-validation 失败（下游 + 归集无容错）**：`package-ipa`/`package-deb` 因 `needs: [device-build]` 被跳过，无 IPA/DEB 产物；归集步骤 `find build/r4-artifacts/filterkit-ipa` 对缺失目录非零退出，`pipefail` + `bash -e` 下 step exit 1，元数据 JSON 未产出。
- **修复（本地，未编译未签名未装机）**：`validate-device-build.sh` d3 去掉数组取值、OK 行只报 `DTPlatformName=iphoneos`，d6 `$min_os` 改 `${min_os}`；`package-ipa.sh` / `package-deb.sh` 三处同类裸变量 `$STAGE` 改 `${STAGE}`；workflow `package-validation` 新增 `find_first()`（目录缺失返回空、stderr 丢弃），七个产物定位改走该函数，缺产物由归集脚本记 Pending 不中断归档。
- **本地静态演练**：八脚本 `bash -n` 全过；裸变量紧邻非 ASCII 扫描脚本与 YAML 无命中；YAML 12 jobs 良构；元数据脚本空输入 JSON 可解码、三态 Pending、exit 0；`find_first` 缺失/存在两路径模拟 exit 0。设备产物实测值仍待 Runner 复验；G10～G15、R4-G、0.1-E-B 状态不变，**0.1-D 未闭环不签署**。

### 5.16 R4 Runner 第二轮（run 44766814111）打包 job 失败诊断与产物归档层级修复（2026-11-20，待复验）

Runner 基线 commit `211365cbf039f525a0bbc4f8608f44ca3c5e84e3`；诊断归档 `Tests/Stage2/evidence/r4-device-build/run-44766814111-round2-failure-diagnosis.md`。

- **失败现象**：`package-ipa`（job run `614a21ed-12d8-59f5-9f6e-abe3021a8644`）与 `package-deb`（job run `67d8538d-43e0-5221-9e6e-3fd7812f6e54`）均成功下载 `filterkit-device-build`（ID `14645672385`，901,844B，digest `ae0b5ef2…02fb7`），但定位步骤 `find build/device-artifact -name 'FilterKit.app' -maxdepth 4` 返回空，`::error::device app missing from filterkit-device-build artifact` exit 1；IPA/DEB 上传均 No files found。`package-deb` 侧 `brew install dpkg` 1.23.11 成功，`dpkg-deb` 可用。
- **根因（CI 归档层级，非编译/链接失败）**：`device-build` 上传路径中三条日志在 `build/device/`，`.app` 在 `build/DerivedData-device/Build/Products/Release-iphoneos/FilterKit.app`；`upload-artifact@v7` 多路径取最小公共祖先 `build/` 为 artifact 根（同轮上传日志 LCA 原文佐证），下载后 `.app` 位于第 5 层，下游 `find -maxdepth 4` 只到第 4 层，命不中 `.app` 标记目录。
- **修复（本地）**：`device-build` 新增 "Stage app bundle into evidence directory" 步骤，上传前 `cp -R` 暂存到 `build/device/FilterKit.app`；上传路径改 `build/device/FilterKit.app`，四条路径 LCA 收窄到 `build/device/`，artifact 内 `.app` 位于根层（下载后第 1 层）。下游定位步骤与 `find_first()` 不改；打包 job 对缺 `.app` 保持硬失败，缺产物容错仍归 `package-validation` 归集层。
- **产物版本口径**：当前 CI 不区分 RootHide/Rootless 版本——单份未签名 `.app`/IPA/DEB，包名与 control 无路线维度，无双 scheme 矩阵；双路线仅体现在 `Adapters/RootHide`、`Adapters/Rootless` 两套独立适配器。前期默认只对 RootHide 路线负责（R4 规格即 RootHide Deployment Plan，唯一真机为 RootHide；Rootless 无设备，仅离线/合成验证，不得以 RootHide 结果覆盖）。Rootless 版本包待 Theos rootless scheme 接线与真机/样本到位后再分叉。
- **本地静态演练**：八脚本 `bash -n` 全过；YAML 12 jobs 良构，`device-build` 步骤序含 Stage 步骤；`/tmp` 层级模拟证实旧嵌套布局 `maxdepth 4` 落空、新 staged 布局第 1 层命中；`postinst` 越界扫描无命中。设备产物/IPA/DEB 实测值待下一轮 Runner；G10～G15、R4-G、0.1-E-B 状态不变，**0.1-D 未闭环不签署**。

### 5.17 R4 Runner 第三轮（run 44772873717）DEB RootHide 隐根口径修复（2026-11-21，待复验）

Runner 基线 commit `128f4c10d7f821bddafcdb152b14892e2d45c92e`；诊断归档 `Tests/Stage2/evidence/r4-device-build/run-44772873717-round3-deb-roothide-diagnosis.md`。

- **第三轮离线结果**：第二轮层级修复生效，设备 `.app` Build Passed（iphoneos / Non-fat arm64 / MinOS 17.0 / Bundle ID `com.filterkit.manager`）；IPA Package Passed（sha256 `a198e927…00b5b`）；DEB 静态 Package Passed（旧 arm64 命名包，sha256 `2c059442…e1d0`，e1～e4 passed）。用户陈述：IPA 真机安装成功；DEB 经 RootHide 隐根转换后安装失败；日志包内无真机转换/dpkg 报错原文。
- **同机对照取证**（0.1.18 设备报告，只读归档）：366 包中二进制档 83 个全部 `iphoneos-arm64e`、`iphoneos-arm64` 为 0；五个已装 App 包 control 均为 arm64e + `Depends: firmware (>= 15.0)`，数据归档为 rootfs 相对 `/Applications/*.app` 布局（无 `var/jb/` 前缀）。
- **离线修复（H1 架构档 / H2 firmware 依赖 / H3 属主 root:root）**：`Config/DEB/control` Architecture 改 `iphoneos-arm64e`、补 `Depends: firmware (>= 15.0)`；`package-deb.sh` 默认产物名改 arm64e 档，`dpkg-deb --build --root-owner-group` 强制 root:root（标量flag 兼容 bash 3.2 `set -u`，旧版降级告警）；`validate-deb.sh` e2 锁定 arm64e + firmware，e4 拦截 rootless `var/jb/` 前缀泄漏，新增 e5 root:root 属主校验；workflow 三处产物名同步。
- **未闭环（H4/H5）**：设备二进制 Non-fat `arm64` 与 control 目标 arm64e 的切片一致性、arm64e 切片/弱链接 libroothide/roothide rpath、签名与 entitlement 放行、postinst uicache 行为与 JBROOT 映射，均属 R4-A/R4-G 真机门禁；打包层不伪造切片/签名。本地正向桩 e1～e5 全 passed，反向样例（旧 control / rootless 布局 / 非 root 属主）对应检查 FAIL；待下一轮 Runner 复验与真机报错原文补采。

### 5.18 R4 Runner 第四轮（run 44783839130）e5 属主校验 bsdtar 误判修复 + DEB 真机闪退待证（2026-11-21，待复验）

Runner 基线 commit `e02da08362755670470c876beee00f3bb21d5da0`；诊断归档 `Tests/Stage2/evidence/r4-device-build/run-44783839130-round4-deb-crash-ownership-falsepositive.md`。

- **第四轮离线结果**：H1/H2 修复在 Runner 生效，DEB 命名 `iphoneos-arm64e`、e2 解出 arm64e + `firmware (>= 15.0)`；设备 Build Passed（Non-fat arm64 / MinOS 17.0）；IPA Package Passed（内包 sha256 `68b96cf7…f6e8b5`）；DEB Package Failed——e1/e2/e3/e4 passed，**e5 failed**。全量 Swift 测试 0 failures、隔离七项 passed、XCUITest All tests passed；dpkg 1.23.12。
- **e5 误判定性**：Runner macOS bsdtar 列表为 `perms links owner group` 分列（`0 root root`），原 awk 按 GNU tar `owner/group` 单字段取 `$2`，拿到链接数 `0` 误判非 root；日志列出条目属主/属组实为 root:root，`--root-owner-group` 生效。修复为双格式解析：`$2` 含 `/` 按 GNU 拆分，否则取 `$3`/`$4`；owner/group 归一化接受 `root`/`0`。本地 awk 单测混合格式正向 exit 0，GNU `1000/1000`、bsdtar `runner staff`、bsdtar 数值 `501 20` 三反向样例 exit 1 并列出；本地桩包正向 e1～e5 passed、非 root 反向 e5 仍 FAIL。
- **真机闪退待证**：用户陈述同一版本 IPA 可启动、DEB 打开闪退；日志包无 `.ips`/系统日志。离线对照：IPA/DEB 包装同一未签名 `.app`，CI `CODE_SIGNING_ALLOWED=NO`，entitlement 仅静态 plist 校验未嵌入签名页；DEB data tar 仅 5 条目，未见 Frameworks/PlugIns/`_CodeSignature`。闪退假设 C1 签名/entitlement 封印缺失、C2 切片/弱链接/rpath、C3 布局/uicache 注册/权限、C4 Bundle 完整性、C5 应用自身异常，须 `.ips` 终止原因与解包对比复核；本轮不碰运气追加 entitlement、不改 GUI/Core 代码。
- **未闭环不变**：arm64e 切片、弱链接 libroothide、roothide rpath、签名路线（Developer 证书 / ldid）、entitlement 嵌入二进制、uicache/JBROOT 映射归 R4-A/R4-B/R4-G 门禁；G10～G15、R4-G 仍 pending/unknown，0.1-D 未闭环不签署、不进 0.1-E-B。

### 5.19 R4 Runner 第五轮（run 44797390321）App/DEB 版本不一致中止诊断与版本单一源修复（2026-11-21，待复验）

Runner 基线 commit `a0cc234f1f8948a901d9b959a01cc705228b10f3`；诊断归档 `Tests/Stage2/evidence/r4-device-build/run-44797390321-round5-version-mismatch-diagnosis.md`。

- **第五轮离线结果**：第四轮权限保真 TAR 链路在 Runner 生效——artifact 下载、TAR 解包通过，主程序执行位保留（`-rwxr-xr-x 755 build/device-restored/FilterKit.app/FilterKit`）。唯一失败在 `package-deb` 前置一致性校验：`App version=1.0 does not match control Version base=0.0.1`，exit 1；e1～e9 未到达，DEB artifact 约 209B 为失败日志，非可安装包。原始 job-logs 签名链接过期未取回，事实按用户笔记与 R4-D2 快照源码转录。
- **根因分级**：R1 版本校验 fail-closed 拦截漂移（行为正确，未删除/未放宽）；R2 `project.yml` 文件型 `info.properties` 未显式携带 `CFBundleShortVersionString`/`CFBundleVersion`，`MARKETING_VERSION` 构建设置不回填文件型 plist，缺键被 Xcode 回退默认 `1.0`/`1`；R3 control 基线沿用旧工程占位 `0.0.1`，而活跃 Models/Envelope/Factory/测试口径已是 `0.1.0`。
- **版本单一源修复**：`project.yml` `info.properties` 增补 `CFBundleShortVersionString: $(MARKETING_VERSION)`、`CFBundleVersion: $(CURRENT_PROJECT_VERSION)`，`MARKETING_VERSION=0.1.0`、`CURRENT_PROJECT_VERSION=1`；`Config/DEB/control` Version `0.1.0-1`（基线 `0.1.0` + 修订号 `-1`）；`Config/DEB/README.md` 写明版本单一源口径。预检可见性：device-build 步骤打印 App 版本/构建号，package-deb 步骤打印 control Version/基线；`package-deb.sh` 预检打印两侧实际值、版本错误行带构建号与完整 Version；`validate-deb.sh` e2 OK/FAIL 行带 `AppVersion`/`ControlVersion`。
- **快照回填**：R4-D2 快照中已在 Runner 运行的打包实现同步回本地——`Config/DEB/roothide.env` 档案元数据单一源、`compare-app-bundles.py` parity 对照、`package-deb.sh` 档案/可执行位/Bundle ID/版本基线校验与 ditto 暂存、`validate-deb.sh` e1～e9 链、`collect-package-metadata.sh` profile 字段归集、workflow TAR 往返与同源 parity、`Stage-2.4-R4-D2-Implementation-Record.md` 归档。
- **本地演练**：正向桩包（`0.1.0`/build `1`）打包 exit 0，e1～e7 passed、e8/e9 Linux unavailable、parity `equal=true`；反向 App `1.0`、App `0.0.1`、Bundle ID 错误三种样例均在打包前置校验 exit 1 并打印两侧值；八脚本 `bash -n`、Python 编译、YAML 解析、元数据空输入 JSON 解码全过。
- **待复验与未闭环不变**：下一轮 Runner 须确认生成 plist 实测 `0.1.0`/`1`、DEB 正常出包且 e1～e7 passed；H4 切片一致性、H5 uicache/JBROOT 映射、真机闪退 C1～C5 仍待设备取证；G10～G15、R4-G 仍 pending/unknown，0.1-D 未闭环不签署、不进 0.1-E-B。
