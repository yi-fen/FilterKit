# R3-C 真机诊断载荷基线（Real Device Diagnostics Payload Baseline）— 定位记录

> 性质：R3-C **中间验收证据**，不是 A6 最终验收报告。
> 本记录只保存结构核对结论与基线计数；设备报告本体（含真机标识、路径、已装 App 清单、dpkg 包清单）按隐私边界**不复制、不入库、不进 DevDocs 包、不作测试 fixture**。

## 1. 证据标签

| 项 | 记录值 |
|---|---|
| Artifact | Real Device Diagnostics Payload（单文件 JSON，打包于同名 zip） |
| 载荷 SHA256（JSON 本体） | `d3d2408a1404f1bbb246744923b72f40ffb649261c1afb5c0dcfcfe68cfff484` |
| JSON 大小 | 7,460,339 B |
| Schema | R3-C v1 compatible（静态结构核对，非 Codable 实跑） |
| 诊断段 scanState | `completed` |
| evidenceScope | `read-only` |
| Build provenance | **unknown**（构建来源待证据确认） |
| Export bridge provenance | **unverified**（不能证明 R3-C 代码链路在该次导出中运行） |
| A6 acceptance | **not passed** |

## 2. 为什么不能据此认定 R3-C 闭环

- 14,029 条诊断记录只能证明诊断引擎在真机环境产出了规模完整的只读诊断数据；**不能证明** R3-C 的 `DiagnosticsReportStore` / `CombinedReportEncoder` / Settings 导出链路在该次导出中实际运行。
- 该载荷可能来自旧 PoC 扫描结果，再由后续导出程序包装成当前 schema。在找到构建证据之前，按 §1 标签记录，不向上归因。
- 信封顶层仍是合成 preview：3 个合成插件、1 条 unknownItem、warning `PREVIEW-001 Synthetic preview report; not a device scan.`；诊断段与信封是两条独立来源（路线 A 既定结构）。

### 2.1 来源待确认清单（对应 C2-01 / C2-02，未授权执行）

1. App 版本号与 Build Number。
2. Bundle Identifier。
3. 导出时间与设备扫描时间。
4. App 内是否存在 R3-C `DiagnosticsReportStore`。
5. `SettingsViewModel.exportReport()` 是否已接入 Store。
6. CI 构建编号或安装包 SHA256。

## 3. 静态结构核对（本机 Linux，无 Swift 工具链；非 Codable 往返）

对照当前 `Core/Diagnostics/Export/DiagnosticsExportModels.swift`：

- 段级：`schemaVersion=1`、`evidenceScope=read-only`、`scanState=completed`、`generatedAt` iso8601、`environment` 值全为字符串；`previousCompletedAt` 缺失（可选，解码为 nil）；顶层信封 `generatedAt` 缺失（可选，解码为 nil）。
- 条目级：14,029 条全部 `id/category/title` 为字符串；`payload` 全 `[String:String]`，0 条非字符串值；`detail` 无缺失；0 条结构异常；无 `Unknown` 标题兜底。
- `status`：9,256 条**缺失 `status` 键**（非显式 null），Codable 解码为 nil；无显式 null 值。往返验收时不得把 nil 补成默认状态。
- 类别覆盖：13 类与 `DiagnosticsReportMapper.rowMappings` 一一对应；条目 id 沿用 `<category>:<index>`。
- 保守口径：诊断段插件 `loaded` 均为 `unknown`，未做运行时推断。

### 3.1 基线计数（对照值，非每次扫描必须相同的硬指标）

设备状态变化后数量自然可能变化；下一轮对照以“13 类是否齐全、嵌套字段/状态是否丢失、语义是否保留”为准，不以逐条等数为准。

| 类别 | 基线条数 | 类别 | 基线条数 |
|---|---:|---|---:|
| roots | 5 | fileOwnership | 9,255 |
| dynamicLibraries | 16 | integrity | 3,466 |
| plugins | 8 | helperCandidates | 49 |
| filters | 8 | helperRegistrations | 534 |
| injectorEvidence | 28 | applications | 266 |
| packages | 376 | associations | 8 |
| | | finding | 10 |
| **合计** | **14,029** | | |

信封侧基线：plugins 3 / unknownItems 1 / warnings 1（合成 preview，非真机清单）。

### 3.2 完整性与归属摘要（来自 findings，仅记计数口径）

- integrity：mismatch 146 / no_checksum_record 3,312 / checksum_unavailable 8；hard failure 1、warning 139。
- 归属冲突：185 条冲突路径、16 个未归属插件文件。
- associations：8 条，global 0、unmatched 0、missing dylib 0、missing plist 0。

## 4. 往返解码验收（R3-C-A6-Codable Round-Trip Verification，Runner 执行）

本机无 Swift 工具链，往返不在本机认定。下一轮 Runner 增加独立验收：

```
真机诊断 JSON → JSONDecoder → DiagnosticsExportSection → JSONEncoder → 重新 JSONDecoder → 字段与语义比较
```

验收条件：

- 14,029 条记录全部解码；13 个类别全部保留。
- 可选字段正确处理；9,256 条缺省 status 不被补成默认状态。
- payload 所有键值保持一致；`loaded=unknown` 保持不变；不生成 `Unknown` 标题或其他兜底伪数据。
- 比较解码后的模型字段与语义，**不直接比较 JSON 字符串**（键顺序、日期格式可能不同）。
- 另补空扫描 fixture 与失败扫描 fixture：`completed + empty` 与 `failed` 不得混淆（与既有 neverRun/running/completed/failed 状态机口径一致）。

## 5. 两段环境不一致（路线 A 边界，本轮保持原状）

```
ReportEnvelope.environment       ── Synthetic Preview
DiagnosticsExportSection.environment ── Real Device Scan
```

- 本轮不为消除不一致而修改顶层环境、插件归属或 Dashboard 数据来源。
- 环境统一与真实信封构建属路线 B，暂不全面启动。

### 5.1 关于建议字段 `environmentSource`

- 当前 `DiagnosticsExportSection` **不存在** `environmentSource` 字段；本载荷也未携带。
- 兼容性判断：后续若以可选 `String?` 新增，旧 JSON 缺键解码为 nil，解码方向向后兼容；但这是冻结导出模型的改动，须单独授权，本轮不加。

## 6. 隐私边界（当前不授权额外复制或持久化设备报告）

报告本体含：jbrand 哈希、JBROOT 路径、设备型号与系统版本、已安装 App 名称、dpkg 包清单、文件路径与完整性结果。

- 保留在会话临时目录，作为临时验收材料。
- 不写入公开 DevDocs；不提交 Git；不复制到普通测试 fixture。
- 如需长期保存，单独放入设备私有证据目录，并在归档清单中明确排除。

## 7. R3-C2 待授权 backlog（仅记录方向，本轮不编码）

目标链路：`ReadOnlyDiagnosticsEngine.scan() → DiagnosticsReportStore → DiagnosticsExportSection → ReportEnvelope + diagnostics → JSONExporter → 真实设备完整 JSON`。

| 编号 | 工作 |
|---|---|
| C2-01 | 核实本次报告来源及构建版本（§2.1 清单） |
| C2-02 | 核实 `DiagnosticsReportStore` 实际接线 |
| C2-03 | 修复合成 Preview 信封的数据来源：先建最小真实信封构建器，只填已有可靠设备环境信息；不足的插件、归属、注入状态继续标 unknown/unverified，不强行推断；不直接展开路线 B |
| C2-04 | 确保 Settings 导出使用真实扫描快照 |
| C2-05 | 加入 Codable 往返测试（§4 口径） |
| C2-06 | 空扫描、失败扫描、重复扫描测试 |
| C2-07 | Runner 构建与真机完整 JSON 验收 |

## 8. 冻结决策表

| 项目 | 决定 |
|---|---|
| 当前 14,029 条报告 | 接受为真机诊断数据基线（中间证据，非验收通过） |
| 构建来源 | 待证据确认 |
| Codable 往返 | 下一轮 Runner 验收 |
| 隐私报告持久化 | 暂不授权 |
| 路线 A | 进入真实信封闭环收尾 |
| 路线 B | 暂不全面启动 |
| D-R2-06 | 继续冻结 |
| #331（截图计数/去重） | 继续冻结 |

## 9. 未闭环沿用（本轮未动）

- R3-C 离线 8 例桥接用例与 590 例回归、iphoneos 编译结论待对应 Runner job 日志；`ui-acceptance` 切片 7 过 1 失败（EmptyState，H1/H2 未定论），G9 样本未落盘原因待查。
- 签名/DEB 闪退 H4/H5、C1～C5 无 `.ips` 证据、G10～G15 / R4-G 沿用 pending/unknown；0.1-D 未闭环不签署、不进 0.1-E。
- 最重要下一步不是再增加诊断项目，而是让下一次导出产生一份完整设备报告：顶层环境来自真实设备，diagnostics 来自同一次扫描，所有未知状态如实保留。
