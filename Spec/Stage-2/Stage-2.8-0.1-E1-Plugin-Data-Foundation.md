# Stage 2.8 — 0.1-E1 Plugin Data Foundation（规格冻结）

状态：**规格冻结，进入 E1 实现**
授权：用户授权「0.1-E1：Plugin Data Foundation」八项范围（见 §1）；本轮不授权任何写操作。
基线：HEAD `c753e11`；DevDocs 包 SHA256 前缀 `79f3a8d2…1022e96`（2224 文件 / 16,699,699 B），开工前已核对本地源码与包一致、工作树干净。
上一阶段：0.1-D / R3-C 路线 A 在 Runner/Simulator 口径验收通过；**真机验收仍 pending**。0.1-E 与 0.1-D 并行，验收状态独立；E1 不得把未真机验证的数据标为已真机验收。

---

## §1 授权范围与排除清单

### §1.1 本轮授权（E1 八项，对应备忘录 §10）

1. 审计现有 `FKDiagnosticReport` 与所有插件相关 Models。
2. 检查现有 Mapper 能否完整提取插件数据。
3. 建立统一 Plugin Repository。
4. 建立共享 Diagnostic Snapshot。
5. 实现插件列表所需的领域模型。
6. 建立 installed / configured / loaded 三态展示模型。
7. 增加离线测试。
8. 保留现有报告与导出兼容性。

### §1.2 本轮不授权（冻结边界，沿用 0.1-D 只读口径）

- 插件启用 / 禁用；修改 Filter.plist；删除 / 移动 dylib；注入代码；Helper / IPC；dpkg 写入；软链改写；常驻 daemon。
- 放宽 entitlement / 沙盒；重写签名链路；GitHub 推送（仅本地提交）。
- E5 操作框架（enable / disable / restore service）本轮只留架构边界，**不实现、不注入生产 App**。
- E2 列表 / 搜索 / 筛选 UI、E3 详情与关联视图、E4 DI 接线与真实快照接入，均不在本轮。

### §1.3 批次拆分（备忘录 §8）

| 子批 | 名称 | 本轮落地 |
| --- | --- | --- |
| E1-01 | Plugin Models | Core 只读领域模型 |
| E1-02 | Plugin Status Model | 三态独立模型与口径 |
| E1-03 | Plugin Data Mapper | `FKDiagnosticReport` 行 → 领域模型 |
| E1-04 | Plugin Repository | 协议 + 诊断实现，一次扫描缓存 |
| E1-05 | Snapshot Sharing | 统一快照与双向索引 |

---

## §2 开工前审计结论（§1.1 第 1、2 项）

### §2.1 既有模型盘点（不重复定义）

| 既有类型 | 位置 | 职责 | E1 处置 |
| --- | --- | --- | --- |
| `Plugin` | `Models/PluginModels.swift` | 信封 Codable 插件记录（installed `Bool?` / configured `Bool` / loaded `LoadedState` / ownership / filter / validation / evidence） | **保留不动**；E1 不新增平行信封模型 |
| `FilterRule` / `Ownership` / `OwnershipDetails` / `ValidationReport` / `EvidenceBlock` / `UnknownItem` / `ReportWarning` | `Models/PluginModels.swift` | 信封归并模型 | 保留不动 |
| `SourceType` / `Pairing` / `LoadedState` / `Confidence` / `WritablePolicy` / `EvidenceLevel` 等 | `Models/ModelEnums.swift` | 冻结枚举 | 保留不动；E1 不增删枚举义 |
| `FKDiagnosticReport` | `Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift` | 扁平化 `[[String:String]]` 行报告：plugins / filters / applications / associations / packages / fileOwnership / integrity / findings 等 | E1 Mapper 的输入；结构不改 |
| `FKDiagnosticFinding` | 同上 | 独立 finding 模型 | 快照内直接复用 |
| `ReportBuilder` | `Core/Reporting/ReportBuilder.swift` | 由 Stage1/2 快照（inventory/pairing/parsing/ownership）归并信封 `Plugin` | 保留不动；其输入不是引擎扁平行，E1 不改造它 |
| `DiagnosticsReportMapper` | `Core/Diagnostics/Export/DiagnosticsReportMapper.swift` | 引擎行 → 导出条目（13 类 rowMappings） | 保留不动；E1 不复用其展示映射，另建 Core 只读映射 |
| `PluginRowSummary` / `PluginDetailModel` / `PluginListMapper` / `DisplayStatus` / `ReportLabels` | `App/Presentation/` | 信封 `Plugin` → 列表 / 详情展示摘要 | 保留不动；E2 再评估是否桥接新 Core 模型 |
| `PluginListViewModel` | `App/Features/Plugins/` | 现有 UI 视图模型，消费 `[Plugin]` | 本轮不改；E4 接线 |

### §2.2 现有 Mapper 缺口

- `ReportBuilder` 输入为分阶段快照，**不能**直接消费 `FKDiagnosticReport` 扁平行；`DiagnosticsReportMapper` 只产出导出条目，不含插件 / App / 关联的结构化领域视图。
- 引擎行可用键（以 `ReadOnlyDiagnosticsEngine.swift` 现状为准）：
  - **plugins**：`name` `path` `exists` `readable` `file_type` `size` `source` `loaded` `package_owners` `package_candidates` `exact_package_record` `source_evidence`。
  - **filters**：`plugin` `dylib_match` `plist_path` `read_status` `parse_status` `data_length` `top_level_keys` `has_filter_dictionary` `bundles` `executables` `classes` `other_keys` `global` `matched_bundle_ids` `unmatched_bundle_ids` `matched_executables` `unmatched_executables` `warnings` `valid` `entry_count` `protocol_verified` `global_semantics_verified`（失败行仅含 `plugin` `dylib_match` `plist_path` `read_status` `parse_status` `error`）。
  - **applications**：`bundle_id` `name` `bundle_path` `version` `version_source` `build_version` `executable` `is_system` `icon_source` `icon_path` `icon_decoded`。
  - **associations**：`plugin` `bundle_id` `match_type` `category` `is_global` `matched_app_count` `unmatched_target_count` `evidence` `loaded`。
- 结论：E1 需要在 Core 新增「引擎扁平行 → 只读领域模型」的映射层；既有信封模型与导出链路保持兼容。

### §2.3 引擎签名核对

- `ReadOnlyDiagnosticsEngine.scan()` 为**同步**方法，返回 `FKDiagnosticReport`，不抛错。备忘录 Repository 模板标注 `async throws` 为示意；E1 按真实同步签名落地，预留后续迁移异步的空间。

---

## §3 目录与产物

```
Core/Plugins/
├── Models/
│   ├── FKPluginStatus.swift          # E1-02 三态模型
│   ├── FKPluginSource.swift          # E1-01 来源模型
│   ├── FKPluginConfiguration.swift   # E1-01 Filter 配置模型
│   ├── FKPluginAssociation.swift     # E1-01 关联模型（含 FKAssociationType）
│   ├── FKApplication.swift           # E1-01 App 模型
│   ├── FKPlugin.swift                # E1-01 插件聚合根
│   └── PluginSnapshot.swift          # E1-05 统一快照
├── Mapping/
│   └── PluginDataMapper.swift        # E1-03 行 → 快照
└── Repository/
    ├── PluginRepository.swift        # E1-04 协议
    └── DiagnosticPluginRepository.swift # E1-04 诊断实现 + 缓存
```

测试：`Tests/Stage2/Plugins/PluginDataFoundationTests.swift`（纯内存夹具，不访问文件系统、不触发真实引擎扫描）。

> 备忘录建议的 `FKPluginSource` 等命名在不与 `Models` 既有类型重名的前提下沿用；`Models.Plugin` 信封模型不改名、不替换。

---

## §4 领域模型口径（E1-01）

### §4.1 `FKPluginStatus`（E1-02）

```swift
public enum FKPluginState: String, Codable, Equatable {
    case confirmed   // 有明确正向证据
    case absent      // 有明确缺失证据（对应行存在但标记不存在 / 无对应配置行）
    case unknown     // 证据整体缺失，不下结论
    case unverified  // 条目存在但证据未通过校验（如 plist 读取失败 / 类型不符）
}

public struct FKPluginStatus: Equatable, Codable {
    public var installed: FKPluginState
    public var configured: FKPluginState
    public var loaded: FKPluginState
}
```

**三态互相独立（强制口径）：**

- 文件存在 ≠ Filter 匹配 ≠ 运行时加载。
- `configured == .confirmed` 不得把 `loaded` 自动置为 `.confirmed`；`loaded` 无独立运行时证据时恒为 `.unknown`。
- `installed` 不由归属或配对结果反推；`configured` 不由 installed 反推。
- `.unknown` 与 `.unverified` 不等于失败；展示侧（E2）不得把两者统一降级为红色错误。

### §4.2 `FKPluginSource`

- `raw: String`：引擎 `source` 原值（`dpkg_sileo` / `filterkit` / `manual` / `unknown` 等），不做枚举收窄，保留原始证据。
- `packageIdentifier: String?`：首个 `package_owners`；`packageOwners: [String]` 全量归属包。
- `exactPackageRecord: Bool`：`exact_package_record` 解析；`evidence: String?`：`source_evidence`。
- 归属冲突保留全量 owners，不在此层合并为单一来源。

### §4.3 `FKPluginConfiguration`

- `filterPath: String?`（`plist_path`）；`bundles / executables / classes / otherKeys: [String]`（逗号分隔拆分，空串 → 空数组）。
- `isGlobalRule: Bool`（`global == "true"`）；`parseStatus: String?`（`parse_status` 原值）。
- `evidence: FKPluginState`：配置侧证据等级，与插件整体 `status.configured` 同口径。
- `isGlobalRule` 仅用于展示规则类型，**不计入**精确 App 关联数量。

### §4.4 `FKAssociationType` 与 `FKPluginAssociation`

沿用诊断引擎既有分类，不另造规则：

| 引擎 `category` | `FKAssociationType` |
| --- | --- |
| `exact_match` | `exactMatch` |
| `global` | `globalRule` |
| `unmatched_target` | `unmatchedTarget` |
| `invalid_configuration` | `invalidConfiguration` |
| `unresolved_non_bundle_rule` | `unresolved` |

关联记录字段：`pluginID`、`appBundleID: String?`（无匹配 App 时为空）、`matchType`（`bundle` / `executable` / `none`）、`type`、`isGlobal`、`matchedAppCount: Int`、`unmatchedTargetCount: Int`、`evidence`（原值 `static_filter_match_only`）、`loaded: String`（恒 `"unknown"`）。

口径：

- 只有 `exactMatch` 计入精确关联数量；`globalRule` 单独展示；`unmatchedTarget` 不冒充已关联；`invalidConfiguration` 不当有效注入规则。
- 静态匹配 ≠ 实际注入成功；关联证据等级不升级为 verified。

### §4.5 `FKApplication`

- `bundleID: String`（`bundle_id`，空串行以引擎原值保留并在快照内标注）；`name`；`version: String?`；`executable: String?`；`isSystem: Bool`。
- `associatedPluginIDs: [String]`：由关联行反向索引；关联类型不折叠，类型信息保留在 `FKPluginAssociation` 上供 E3 分流展示。

### §4.6 `FKPlugin`（聚合根）

- `id: String`：优先 `packageIdentifier:base`，回退 dylib 基名，再回退 plist 基名；与既有 `Plugin.pluginID` 构造口径一致。
- `name: String`；`dylibPath: String?`；`plistPath: String?`；`source: FKPluginSource`；`status: FKPluginStatus`。
- `configuration: FKPluginConfiguration?`；`associations: [FKPluginAssociation]`；`fileSize: Int64?`；`version: String?`；`packageIdentifier: String?`。
- `raw: [String: String]`：保留插件行原始键值，供 E3 详情与证据追溯；Mapper 不裁剪原始证据。

### §4.7 `PluginSnapshot`（E1-05）

一次扫描的统一只读视图：

- `generatedAt: Date`（报告 `generatedAt`）；`environment: [String: String]`。
- `plugins: [FKPlugin]`；`applications: [FKApplication]`；`associations: [FKPluginAssociation]`；`findings: [FKDiagnosticFinding]`。
- 索引：`pluginByID: [String: FKPlugin]`；`applicationByID: [String: FKApplication]`。
- 快照不可变：Mapper 产出后 Repository 缓存；列表 / 详情 / 关联页后续消费同一份，一个页面刷新不得触发多次独立扫描。

---

## §5 Mapper 口径（E1-03）

`PluginDataMapper.mapSnapshot(report: FKDiagnosticReport) -> PluginSnapshot`，纯函数，不访问文件系统、不触发扫描。

1. **配对键**：dylib / plist 均取路径末段去扩展名，大小写不敏感归并（与引擎 `buildAssociations` 口径一致）。
2. **installed 判定**：
   - 存在插件行且 `exists == "true"`（或 `readable == "true"`）→ `.confirmed`；
   - 存在插件行但 `exists == "false"` → `.absent`；
   - 无插件行（仅有 plist 侧条目）→ `.unknown`（文件侧证据缺失，不反推为 absent）。
3. **configured 判定**：
   - 命中 filter 行且 `valid == "true"` → `.confirmed`；
   - filter 行存在但 `parse_status ∈ {read_failed, type_mismatch, parse_failed}` → `.unverified`；
   - filter 行存在但 `parse_status == not_parsed` / 校验未过 → `.unverified`；
   - 无 filter 行 → `.absent`。
4. **loaded 判定**：恒 `.unknown`；引擎行 `loaded` 原值仅在 `raw` 中保留，不升级状态。
5. **关联装配**：associations 行按 `plugin` 标签回挂到插件（优先基名匹配，未命中保留原值作为 `pluginID`）；applications 行建反向索引。
6. **空报告**：各类目为空数组，不生成合成插件 / 合成 App；环境与 findings 原样保留。
7. **数值解析**：`size` / `matched_app_count` / `unmatched_target_count` 解析失败按 `nil` / `0` 保守处理，不在 Mapper 内补判。

---

## §6 Repository 与快照共享（E1-04 / E1-05）

```swift
public protocol PluginRepository {
    /// 当前缓存快照；尚未 refresh 时为 nil。
    func currentSnapshot() -> PluginSnapshot?
    /// 触发一次引擎扫描并重建快照；重复调用才会再次扫描。
    @discardableResult func refresh() -> PluginSnapshot
    func plugin(id: String) -> FKPlugin?
    func applications() -> [FKApplication]
}
```

`DiagnosticPluginRepository`：

- 持有 `ReadOnlyDiagnosticsEngine`；`refresh()` 调用一次 `scan()`，经 `PluginDataMapper` 产出快照并缓存。
- `currentSnapshot()` / `plugin(id:)` / `applications()` 全部读缓存，**不二次扫描**。
- 测试接缝：`refreshCount: Int`（公开，仅记录刷新次数，供离线测试断言「一次扫描」）。
- 本轮不接入 App DI；生产 App 仍沿用现有数据源，E4 再接线。

---

## §7 兼容性约束（§1.1 第 8 项）

- 不改 `ReportEnvelope`、`Plugin`、`FilterRule` 等 Models 冻结类型与 CodingKeys；不改 `CombinedReportEncoder` / `DiagnosticsExportModels` / `DiagnosticsReportMapper`。
- E1 新增类型全部位于 `Core/Plugins/`，不修改既有 Core 源文件行为。
- 既有 598 项 Swift 测试与 8 例桥接用例口径不变；新增测试独立成文件，不改动既有夹具。
- 导出 JSON schema 不变；E1 模型不进入合并导出。

## §8 离线测试清单（E1-07）

夹具为纯内存 `FKDiagnosticReport`，覆盖：

1. **配对有效插件**：dylib 在位 + filter valid + 精确关联 → installed `.confirmed` / configured `.confirmed` / loaded `.unknown`；关联类型 `exactMatch`；App 反向索引命中。
2. **孤立 plist**：仅有 filter 行无插件行 → installed `.unknown`，configured `.confirmed`；不得反推 installed `.absent`。
3. **损坏 plist**：插件在位、filter `read_failed` → installed `.confirmed` / configured `.unverified` / loaded `.unknown`。
4. **仅有 dylib**：无 filter 行 → configured `.absent`。
5. **全局规则**：`global == true` → `globalRule`，不计入精确关联。
6. **未匹配目标**：`unmatched_target` 类型映射；不冒充已关联。
7. **无效配置**：`invalid_configuration` 类型映射；不当有效规则。
8. **三态独立**：configured `.confirmed` 用例中 loaded 仍为 `.unknown`。
9. **空报告**：plugins / applications / associations 为空，无合成条目。
10. **快照共享**：Repository `refresh()` 一次；随后 `plugin(id:)` / `applications()` / `currentSnapshot()` 均返回缓存，`refreshCount == 1`。
11. **原始证据保留**：插件 `raw` 包含 `source` / `package_owners` 等原始键。

## §9 验收标准（E1）

1. 新增 Core 模型 / Mapper / Repository / 快照编译进 Core target，Package.swift 源清单同步。
2. §8 清单全部离线通过；既有测试与桥接用例不回归。
3. 三态独立口径在模型与测试中可验证；loaded 恒 unknown。
4. 关联五类映射齐全；精确 / 全局 / 未匹配 / 无效配置口径不串。
5. 既有信封、导出 JSON schema 与编码链路零改动。
6. 全程只读：无文件写入、无引擎写路径调用、无 Helper/IPC/注入。
7. 本地独立提交，不推送 GitHub。

### §9.1 本轮本地静态核对（2026-11-21，待 Runner 复验）

- 新增 10 枚 Core 源文件 + 1 枚测试文件，`Package.swift` Core / Stage2Tests 显式 sources 同步登记，与磁盘一一对应。
- 括号配平逐文件复核；新文件无 `FileManager` 写接口、无 `removeItem`/`createDirectory`、无 `dlsym`/`jbroot()`/注入/ dpkg 写调用。
- 本机 Linux 无 Swift/Xcode；Core emit-module、`swift test` 全套（既有 598 例回归 + 新增 9 例）与 iOS 两侧编译结论以 Runner 下一轮日志为准；无 Runner 日志前不认定编译通过、不标注真机验收。
- 既有 `Models.Plugin` / `ReportEnvelope` / `CombinedReportEncoder` / `DiagnosticsExportModels` / `DiagnosticsReportMapper` 零改动；E1 模型不进入合并导出。

## §10 本轮不做（留待后续批次）

- E2：列表视图、行视图、搜索、分段筛选。
- E3：详情视图、Filter 配置展示、App 详情与双向关联浏览。
- E4：App DI 接线、真实快照替换合成桩、空/错态视图、回归测试收口。
- E5：`PluginManagementService` 操作层仅在文档留边界，不定义可调用实现。
- 真机取证、A6 闭环、DEB 安装启动、EmptyState 根因：沿用 0.1-D pending 状态，不在 E1 内标注通过。
