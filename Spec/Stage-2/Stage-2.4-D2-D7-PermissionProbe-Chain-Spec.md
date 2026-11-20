# Stage 2.4-D2～D7 — Permission Probe 只读链路规格冻结

> 阶段：0.1-D（Permission Probe & RootHide Real Device Validation）第二批起，D2～D7 连续落地，D7 完成后统一 Runner 验收，不逐批启动 Runner。
> 基线：本地归档提交 `e221989`（D1 Foundation，未推送）；0.1-C 未闭环，G10 缺口作为已知限制带入。
> 授权依据：用户上传两份 0.1-D MD（连续开发授权 + 探针链路设计）；检查点 A（D1～D3）/ B（D4～D6）/ C（D7）仅做 L1 静态自检。
> 工具链：本机 Linux 无 Swift/Xcode；代码、规格、证据归档在本地落盘，编译与用例结论以在线 Runner 日志为准。

## 1. 目标与非目标

### 1.1 目标

- 在 D1 模型/协议接缝之上落地 D2～D6 只读探针与 D7 诊断展示映射；
- 探针全部复用 Stage 1 已确认路径、既有 Reader/Parser 与 Core 编排，不另写扫描/解析引擎；
- 单项探针失败不中断其他探针；错误以结构化证据保留原探针身份；
- 接口未核实项（进程 entitlement 读取、`jbroot()` 签名/链接）只留协议接缝与占位实现，结果落 `unavailable`/`unknown`，不伪造 API。

### 1.2 非目标（本批禁止）

- 不启停插件、不改 Filter plist、不加 Bundle ID、不删 dylib、不改 DynamicLibraries 软链、不装卸包、不写 dpkg 数据库；
- 不加载 dylib、不执行插件代码；不改 entitlement/签名/安装位置/沙盒例外；不开发常驻 daemon；
- 不修改冻结 Models 信封、Adapter 七方法协议、Plist Parser 语义；探针报告独立于 `ReportEnvelope`；
- 不把探针通过记为插件 installed/configured/loaded；`loaded` 继续恒 `.unknown`；
- 不在探针内硬编码三条路线路径，不做回退猜测；未知 Profile 由上游不提供路径，探针记 `notExecuted`。

## 2. 架构定位

```
Core/PermissionProbe/
  ├── Protocols/        PermissionProbing（run() throws -> [ProbeEvidence]）/ PermissionProbeServiceProtocol
  ├── FileAccess/       FileAccessChecking 接缝 + Foundation 实现 + 状态分类器
  ├── Shared/           ProbeTimestamp（ISO8601 字符串）
  ├── Entitlement/      EntitlementInspecting / CodeSignInspecting 接缝 + 占位检查器
  ├── JBRootAPI/        JBRootResolving 接缝 + 占位解析器
  ├── Probes/           D2～D6 各探针
  └── Services/         PermissionProbeService 编排 + PermissionProbeReportBuilder 汇总

App/Presentation/ProbeDiagnostics.swift   纯 Foundation 报告 → 诊断分区映射
```

- 探针输入为上游已解析路径/候选清单；探针不重复定位 JBROOT、不重复枚举插件目录、不重复解析 plist 内容合法性。
- plist 读取复用 `PlistDataReading`（Stage 1 Reader）；读取成功仅代表 Data 可读，不代表 plist 配置合法。
- App 层只消费 `PermissionProbeReport`；Presentation 不 import SwiftUI/UIKit，不持有文件访问句柄。

## 3. D2 — JBROOT 目录访问探针

### 3.1 文件访问抽象（`FileAccess/`）

| 类型 | 职责 |
|---|---|
| `FileAccessResult` | `exists: Bool`；`isDirectory: Bool?`；`isSymlink: Bool?`；`readable: Bool?`；`errorDomain/errorCode/errno`；`nil` = 未验证，不填 `false` 冒充结论 |
| `FileAccessChecking` | `inspect(_:)` 元数据/类型（不枚举、不读体）；`listDirectory(_:) throws -> [URL]`；`read(_:) throws -> Data`（不加载/执行 dylib） |
| `FoundationFileAccessChecker` | FileManager/Foundation 只读实现；错误保留 NSError 域/码与 POSIX errno |
| `ProbeStatusClassifier` | 纯函数：ENOENT/ENOTDIR → `unavailable`；EACCES/EPERM → `permissionDenied`；其他 I/O → `failed`；无法定论 → `unknown`；`unavailable` 与 `permissionDenied` 不合并 |

### 3.2 `JBRootProbe`（`Probes/JBRootProbe.swift`）

- 输入：`confirmedJBRoot: String?` + `FileAccessChecking`。
- 路径空/未确认：单条 `.stat` 证据 `notExecuted`，target 标签 `confirmed-jbroot`。
- 证据两条：`.stat`（存在性/类型）、`.list`（可枚举与条目数）；stat 未通过时 list 记 `notExecuted`。
- 元数据通过 ≠ 目录可枚举；target 用抽象标签，不向诊断摘要回显完整私有路径；observedValue 只存类型/条目数摘要。

## 4. D3 — ElleKit 目录探针

### 4.1 `ElleKitDirectoryProbe`（`Probes/ElleKitDirectoryProbe.swift`）

- 输入：`resolvedDirectory: String?`、`route: String?`、`FileAccessChecking`；路径来自 Adapter/PathResolver 已解析结果。
- 证据三条：`.stat`（存在/类型/软链）、`.resolve`（软链落点可达性）、`.list`（可枚举与条目数）。
- 未知 Profile 上游不提供路径 → `notExecuted`；探针内不硬编码 RootHide/Rootless/Rootful 三条候选路径。
- inspect 成功 ≠ 枚举成功；软链不可达单独记录，不把断链记为目录存在。

## 5. D4 — 插件文件 / plist / dpkg 探针

### 5.1 `PluginFileProbe`（元数据，`.stat`）

- 输入：`dylibPaths: [String]` + `FileAccessChecking`；逐路径记录存在性/类型；目录记 `failed`；空输入 `notExecuted`。
- 不读取 dylib 内容、不解析 Mach-O、不加载符号。

### 5.2 `PlistReadProbe`（内容读取，`.read`）

- 输入：`plistPaths: [String]` + `PlistDataReading`；复用 Stage 1 Reader，不重写解析器。
- 状态映射：`success` → `passed`（observed 仅记字节数）；`notFound` → `unavailable`；`accessDenied` → `permissionDenied`；`readFailed` → `failed`。
- 读取成功 ≠ plist 配置成功；内容合法性由既有 Parser 五态裁决。

### 5.3 `DpkgDatabaseProbe`（包数据库只读）

- 输入：`statusFilePath: String?` + `FileAccessChecking`；证据两条：`.stat` 元数据、`.read` 非空可读性。
- 不执行 `dpkg -i/-r`、`apt` 或任何包装卸命令；路径由装配注入，探针不硬编码 `/var/lib/dpkg`、不回退猜测。

## 6. D5 — Entitlement / Sandbox 探针

### 6.1 接缝（`Entitlement/`）

| 类型 | 职责 |
|---|---|
| `EntitlementSnapshot` | `available: Bool`；`observedKeys: [String]`（仅键名摘要，不回显值）；`reason: String?` |
| `EntitlementInspecting` | 进程 entitlement 检查接缝 |
| `CodeSignInspecting` | 代码签名 entitlement 检查接缝 |
| `UnavailableEntitlementInspector` / `UnavailableCodeSignInspector` | 接口未核实前占位：`available = false`，不触碰私有 API |

### 6.2 `EntitlementProbe`

- 两条证据：进程 entitlement、代码签名 entitlement；三类证据（签名 / 进程 / 实际文件访问）分开，实际文件访问由 D2～D4 目录/文件探针承载。
- 检查通过仅代表接口读取成功，不代表权限放行；不把 entitlement 字典存在某键记为 passed 权限。

### 6.3 `SandboxAccessProbe`

- 输入：`[SandboxTarget]`（label + path）+ `FileAccessChecking`；逐资源记录可达/拒绝/不存在。
- 不笼统判定沙盒「已关闭」；访问失败不中断其他目标；只做只读 inspect，不申请额外权限。

## 7. D6 — `jbroot()` API 探针接缝

### 7.1 接缝（`JBRootAPI/`）

| 类型 | 职责 |
|---|---|
| `JBRootAPISnapshot` | `symbolAvailable / invoked / resolvedPath: String? / errorReason: String?` |
| `JBRootResolving` | RootHide 专用解析接缝，独立于 Adapter 七方法协议 |
| `UnavailableJBRootResolver` | 占位：符号不可用、未调用、无返回路径 |

### 7.2 `JBRootAPIProbe`

四层证据分开：`.inspect` 符号可用；`.invoke` 调用成功；`.resolve` 返回路径有效；`.resolve` 与已确认 JBROOT 一致性。

- 前置未决：`jbroot()` 函数声明、返回类型、所属库/符号导出、链接或运行时解析方式、头文件/弱链接需求、GUI 进程调用安全性均无证据；未核实前禁止写虚构 C 函数声明、弱链接或 dlsym 符号名。
- API 一致 ≠ 内容可访问；内容可达性由 D2 目录探针独立取证。一致性比对任一侧缺失 → `unknown`；路径不等 → `failed`。

## 8. D7 — Diagnostics 展示接入

### 8.1 `ProbeDiagnosticsMapper`（`App/Presentation/ProbeDiagnostics.swift`）

- 输入 `PermissionProbeReport?`；按八分类顺序分组为 `DiagnosticsSection`；六态映射 `DisplayStatusKind`：passed→success、failed/permissionDenied→failure、unavailable→warning、notExecuted/unknown→unknown。
- 空报告/nil 走 unknown 空态；unknown/notExecuted 不升级为 success。

### 8.2 装配接缝

- `AppDependencies` 增补 `probeReport: PermissionProbeReport?`（缺省 nil）；`DiagnosticsViewModel` 合并信封分区与探针分区；探针报告独立于 `ReportEnvelope`，不并入既有信封。
- 旧 `App/PermissionProbe/PermissionProbe.swift` 占位 `ProbeItem`/`PermissionProbeService` 已退役，避免第二套探针结果模型。

## 9. 统一服务装配（`Services/`）

- `PermissionProbeService` 持有 `[PermissionProbing]`，逐条执行；探针抛错时生成保留原 `probeID` 的 `.failed` 证据，不中断后续探针。
- `PermissionProbeReportBuilder` 归集证据数组（不排序、不裁剪），写入 `generatedAt`。

## 10. 测试矩阵（`Tests/Stage2/`，接入 `Stage2Tests`）

| 测试文件 | 覆盖项 |
|---|---|
| `PermissionProbeProbeTests.swift` | D2 未确认/目录通过/不存在/拒绝；D3 未解析/目录通过/软链可达；D4 文件元数据/目录失败/空输入、Reader 四态映射、dpkg 非空/空/无路径；D5 占位不可用/键数记录/沙盒可达与缺失/空目标；D6 占位全 unknown/一致通过/不一致失败；服务抛错隔离与身份保留、builder 写 generatedAt |
| `PermissionProbePresentationTests.swift` | nil 空态；分类分组与标题；六态分级映射；unknown 不升级；denied → failure |
| D1 既有三文件 | 模型补齐后回归：`id`/`operation` 往返、可选 nil/null、统计口径 |

## 11. 边界与未决项

- 真机证据缺口（D-G10～D-G15）：JBROOT 权限、TweakInject 访问、dylib/plist/dpkg 读取、entitlement/sandbox、`jbroot()` 调用、冷启动复验，均须 RootHide 真机真实 GUI 进程取证；模拟器/CI 不得替代；未取证项保持 pending/unknown，不判 passed。
- D5 进程/签名 entitlement 受支持读取接口未确认；D6 `jbroot()` 签名/链接未确认；两者当前为占位实现，接口核实后替换实现，协议快照与证据模型不变。
- 既有未决项继续挂起：`OwnershipResolver` 未迁移、`loaded` 恒 `.unknown`、`permission.decision` 恒 undetermined、`pluginID` 规则 0.2.0 定稿、PARSE-009-B。

## 12. 架构约束映射（A1～A8）

| 编号 | 约束 | 本批落地 |
|---|---|---|
| A1 | 双路线 Adapter 独立 | 探针不引用 Adapter 具体类型；路线标签仅作摘要；D6 解析接缝独立于七方法协议 |
| A2 | GUI 不直接访问 Adapter | Presentation 只映射报告；文件访问句柄留在 Core 探针 |
| A3 | 探针只读 | 无创建/写入/删除/加载/命令调用；FileAccess 仅 inspect/list/read |
| A4 | 复用 Stage 1 Core | plist 复用 `PlistDataReading`；路径来自上游解析结果，不重复定位/扫描 |
| A5 | 不改冻结 Parser | 未触碰 `Core/PlistParser/` 解码/裁决语义 |
| A6 | `loaded` 恒 unknown | 探针不产出运行时加载结论 |
| A7 | 单项独立记录 | 服务逐条执行，抛错保留原 probeID，不中断其他探针 |
| A8 | 未知 Profile 禁止回退猜测 | 无路径输入 → `notExecuted`；探针内无候选路径硬编码 |
