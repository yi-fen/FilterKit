# Stage 2.4-D1 — PermissionProbe Foundation 规格冻结

> 阶段：0.1-D（Permission Probe & RootHide Real Device Validation）首批次 D1。
> 基线：本地归档提交 `5557f10`（未推送）；0.1-C 未正式签署，G10 缺口作为已知限制带入（见 `Tests/Stage2/evidence/c-f5-seventh-run/C-F5-Gate-Status.md`）。D1 为纯离线模型/协议层，不依赖 G10 面板证据。
> 授权口径：本批仅授权 D1；D2～D7（JBROOT / ElleKit / Plugin File / Entitlement-Sandbox / jbroot() / Diagnostics 集成）须单独授权，不在本批落地。
> 工具链：本机 Linux 无 Swift/Xcode，本批代码与测试在本地落盘，编译与用例结果以在线 Runner 日志为准。

## 1. 目标与非目标

### 1.1 目标

建立独立的权限探针数据模型与协议接缝，供 D2～D7 各探针统一产出结构化证据；完成对应 XCTest（Codable 往返、可选字段、状态统计）。

### 1.2 非目标（本批禁止）

- 不访问真实 JBROOT / TweakInject / 插件文件；不读取真实 dylib、plist、dpkg 数据库。
- 不调用 `jbroot()` 或任何 RootHide 私有 API；不写 C 桥接声明。
- 不实现任何具体探针访问逻辑（目录枚举、元数据读取、签名/entitlement/sandbox 查询均属后续批次）。
- 不修改冻结 Models 信封、Adapter 七方法协议、Plist Parser；不新增 GUI 私有扫描逻辑。
- 不开发插件启停、写入、归属迁移；`loaded` 继续恒 `.unknown`。
- 不修改 entitlement、签名配置、安装位置或沙盒例外。

## 2. 架构定位

```
PermissionProbe（D1 模型/协议接缝）
  ├── Models/PermissionProbe/   纯 Foundation 模型：状态、分类、证据、报告
  └── Core/PermissionProbe/    协议接缝：PermissionProbing / PermissionProbeServiceProtocol
```

- 模型只在 `Models` target；协议接缝在 `Core` target，仅依赖 `Models` 类型，不引用具体 Adapter/Scanner/Parser。
- PermissionProbe 不是第二套插件扫描引擎：枚举、配对、解析继续由现有 Core 完成；探针只记录 GUI 进程对资源的访问证据。
- RootHide / Rootless 路线差异不在 D1 模型内表达；路线专属解析实现留待 D2/D3/D6 各自 Adapter 接缝。

## 3. 数据模型契约

### 3.1 `ProbeStatus`（`Models/PermissionProbe/ProbeStatus.swift`）

六态枚举，`String, Codable, Equatable`；JSON 原始值为 snake_case。

| 枚举值 | JSON 原始值 | 含义 |
|---|---|---|
| `passed` | `passed` | 探针执行并验证成功 |
| `failed` | `failed` | 检测执行失败（其他 I/O / 解析等错误） |
| `permissionDenied` | `permission_denied` | 明确遭遇权限拒绝 |
| `unavailable` | `unavailable` | 目标资源或 API 不存在 |
| `notExecuted` | `not_executed` | 前置条件不满足而未执行 |
| `unknown` | `unknown` | 无法得出可靠结论 |

口径约束：

- `unavailable` 与 `permissionDenied` 不得合并：路径不存在 = unavailable；路径存在但不可读 = permissionDenied；其他 I/O 错误 = failed。
- `notExecuted` 不计入 failed 统计；`unknown` 不升级为 passed/failed。
- 未知原始值解码行为：与既有枚举口径一致（观察记录，不在本批锁定容错默认值）。

### 3.2 `ProbeCategory`（`Models/PermissionProbe/ProbeCategory.swift`）

探针分类枚举，`String, Codable, Equatable`。

| 枚举值 | JSON 原始值 | 对应后续批次 |
|---|---|---|
| `environment` | `environment` | D2 环境探针 |
| `jbroot` | `jbroot` | D2 JBROOT 探针 |
| `ellekit` | `ellekit` | D3 ElleKit 目录探针 |
| `pluginFiles` | `plugin_files` | D4 插件文件探针 |
| `packageDatabase` | `package_database` | D4 dpkg 读取探针 |
| `entitlement` | `entitlement` | D5 签名/entitlement 探针 |
| `sandbox` | `sandbox` | D5 沙盒探针 |
| `jbrootAPI` | `jbroot_api` | D6 jbroot() API 探针 |

### 3.3 `ProbeEvidence`（`Models/PermissionProbe/ProbeEvidence.swift`）

单条探针证据，`Codable, Equatable`；字段全部 `public var`，可选字段缺省 `nil`。

| 字段 | 类型 | 说明 |
|---|---|---|
| `probeID` | `String` | 探针稳定标识（如 `DIRECTORY-ACCESS`、`DYLIB-METADATA`）；命名由各批次规格冻结 |
| `category` | `ProbeCategory?` | 所属分类；D1 允许缺失，后续批次必填 |
| `status` | `ProbeStatus` | 探针结论状态 |
| `target` | `String?` | 实际检测目标（路径/符号名等）；不写入敏感设备信息或完整私有路径到普通日志 |
| `observedValue` | `String?` | 观测到的可读摘要（如条目数、大小）；不回显完整文件内容 |
| `errorDomain` | `String?` | 错误域（NSError.domain 映射）；无错误为 nil |
| `errorCode` | `Int?` | 错误码（NSError.code 映射）；无错误为 nil |
| `executedAt` | `String?` | 执行时刻 ISO8601/RFC3339 字符串；沿用仓库「日期为字符串」惯例，不使用 `Date`；未执行可为 nil |

编码口径：可选字段 `nil` 时按 `encodeIfPresent` 省略键；解码侧 `decodeIfPresent`，缺失键与 JSON `null` 均落 `nil`。

### 3.4 `PermissionProbeReport`（`Models/PermissionProbe/PermissionProbeReport.swift`）

探针汇总报告，`Codable, Equatable`。

| 字段 | 类型 | 说明 |
|---|---|---|
| `schemaVersion` | `Int` | 报告模型版本，缺省 `1` |
| `generatedAt` | `String?` | 生成时刻字符串；不参与确定性比较（对齐 `ReportEnvelope.generatedAt` 惯例） |
| `evidence` | `[ProbeEvidence]` | 探针证据数组；顺序由产出方保持，模型层不做排序（确定性排序留待导出层） |

派生统计（只读计算属性，不编码进 JSON）：

- `passedCount`：`status == .passed` 条数。
- `failedCount`：`status == .failed` 条数。
- `deniedCount`：`status == .permissionDenied` 条数。
- `unavailableCount` / `notExecutedCount` / `unknownCount`：对应状态条数，供 D7 界面六态展示。
- `totalCount`：证据总条数。

口径：`overall.granted` 类综合判定不在 D1 建模；探针事实汇总不等于管理授权（对齐 Stage-2 计划 §6.2 备注）。

## 4. 协议接缝（`Core/PermissionProbe/Protocols/`）

### 4.1 `PermissionProbing`

单个探针的执行接缝；D1 仅定义协议，不提供具体实现。

```swift
public protocol PermissionProbing {
    /// 探针稳定标识，与 `ProbeEvidence.probeID` 一致。
    var probeID: String { get }
    /// 执行只读探测并返回证据；可抛错由编排服务捕获为保留原 probeID 的失败证据，
    /// 不中断其他探针；常规错误以证据状态承载。
    func run() throws -> [ProbeEvidence]
}
```

### 4.2 `PermissionProbeServiceProtocol`

探针编排接缝；D1 仅定义协议，具体装配在 D2 之后。

```swift
public protocol PermissionProbeServiceProtocol {
    /// 运行已装配探针并汇总为报告；单项失败不中断其他探针（约束 A7）。
    func runProbes() -> PermissionProbeReport
}
```

约束：协议只引用 `Models` 探针类型；Core 不实例化具体 Adapter；App 不直接 import Adapters（沿用隔离脚本 3/4/4b 口径）。

## 5. 测试矩阵（`Tests/Stage2/`，接入 `Stage2Tests` target）

| 测试文件 | 覆盖项 |
|---|---|
| `PermissionProbeStatusTests.swift` | 六态原始值；六态 Codable 往返；`notExecuted` ≠ `failed`；`unknown` 独立于 passed/failed |
| `PermissionProbeEvidenceTests.swift` | 全字段往返；可选字段 nil 省略键；JSON `null` 解码落 nil；错误域/码保留；分类缺失解码 |
| `PermissionProbeReportTests.swift` | 空证据统计全 0；多证据各状态计数；`notExecuted` 不计 failed；`unknown` 不计 passed/failed；`generatedAt` 不影响等义比较；证据数组顺序保持 |

验收：新增 XCTest 全部通过；既有 405 例回归无损伤；Codable 往返通过；隔离脚本通过；无冻结契约变更。

## 6. 架构约束映射（附件 A1～A8）

| 编号 | 约束 | D1 落地 |
|---|---|---|
| A1 | RootHide / Rootless Adapter 独立 | D1 模型不含路线分支；路线专属解析留待 D2/D3/D6 Adapter 接缝 |
| A2 | GUI 不直接访问 Adapter | 协议接缝在 Core；App 经服务协议组合根注入，隔离脚本 4/4b 口径不变 |
| A3 | Probe 只读 | D1 无文件/进程/API 访问实现；后续探针仅只读探测 |
| A4 | 复用 Stage 1 Core | D1 不重写 JBROOT 定位、扫描、配对、plist 解析 |
| A5 | 不修改冻结 Parser | 本批不触碰 `Core/PlistParser/` |
| A6 | `loaded` 恒 unknown | 探针模型不引入运行时加载结论；`loaded` 口径不变 |
| A7 | 每项探针独立记录 | 证据按探针逐条承载；服务协议单项失败不中断 |
| A8 | 未知 Profile 禁止写入 | D1 不做路径回退猜测；未知结论落 `unknown`/`unavailable` |

## 7. 边界与未决项

- 本批不产生真机/模拟器运行证据；CI/Simulator 通过不构成 RootHide 真机权限证据。
- 待后续批次：D2 JBROOT 访问、D3 TweakInject 目录、D4 dylib/plist/dpkg 读取、D5 entitlement/sandbox、D6 `jbroot()`、D7 Diagnostics 集成与真机完整验收。
- 既有未决项继续挂起：`OwnershipResolver` 未迁移、`loaded` 恒 `.unknown`、`permission.decision` 恒 undetermined、`pluginID` 规则 0.2.0 定稿、PARSE-009-B。
- 报告模型与 Stage-2 计划 §6.2 规划草图的差异：D1 采用六态 `ProbeStatus` + 分类 `ProbeCategory`；`processContext`、`jbroot` 子结构、`coldStartRetained`、`overall.limitations` 留待 D5/D6/D7 按真实探针结果补充，不在本批预写。

## 8. 0.1-D 链路落地修订（D2～D7 批次回填）

D2～D7 连续开发落地时，对 D1 冻结模型/协议做如下对齐修订（详见 `Stage-2.4-D2-D7-PermissionProbe-Chain-Spec.md`）：

- `ProbeEvidence` 增补 `id: String`（默认 UUID，证据稳定标识）与 `operation: ProbeOperation`（`resolve/stat/list/read/inspect/invoke`，默认 `.inspect`）；`id/probeID/status` 必填解码。
- 新增 `ProbeOperation` 枚举（`Models/PermissionProbe/ProbeOperation.swift`）。
- `PermissionProbing` 协议方法由 `probe() -> ProbeEvidence` 改为 `run() throws -> [ProbeEvidence]`：单探针可产出多条证据（如 stat + list）；探针可抛错，由编排服务捕获为保留原 probeID 的失败证据，不中断其他探针；常规错误仍以证据状态承载。
- 上述修订不改变六态/八分类语义，不引入综合授权判定；其余 D1 契约保持不变。
