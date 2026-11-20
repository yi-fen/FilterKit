# Stage 2.4-D1（0.1-D 首批次）：PermissionProbe Foundation 实现记录

- 日期：2026-11-20
- 授权依据：用户上传 0.1-D 规划 MD（Permission Probe & RootHide Real Device Validation），授权进入 0.1-D；按附件 §14 增量授权顺序，**本批仅授权 D1**（D2～D7 待单独授权）。冻结规格 `Stage-2.4-D1-PermissionProbe-Foundation-Spec.md`。
- 基线：本地归档提交 `5557f10`（未推送）。0.1-C 未正式签署，G10 缺口作为已知限制带入；D1 为纯离线模型/协议层，不依赖 G10 面板证据。
- 状态标记：**Implementation Landed / Local Static Review Passed / Runner Build & Test Pending**。本机 Linux 无 Swift/Xcode 工具链，本轮未编译、未执行 XCTest；编译与用例结论以在线 Runner 为准。

## 1. 本轮授权边界

### 允许
1. 新增 PermissionProbe 纯 Foundation 模型（状态、分类、证据、报告）到 `Models` target；
2. 新增探针协议接缝到 `Core` target（仅依赖 Models 类型）；
3. 新增对应 XCTest 并接入 `Stage2Tests` target；
4. 只读静态检查、接口核对与代码审查；隔离脚本口径复核。

### 禁止（本轮均未触碰）
1. 未访问真实 JBROOT / TweakInject / 插件文件；未读取真实 dylib、plist、dpkg 数据库；
2. 未调用 `jbroot()` 或任何 RootHide 私有 API；未写 C 桥接声明；
3. 未实现任何具体探针访问逻辑（目录枚举、元数据读取、签名/entitlement/sandbox 查询留待 D2～D6）；
4. 未修改冻结公共 Models 信封、七方法 `ElleKitAdapter` 协议、Plist Parser 语义、Stage1 fixtures；
5. 未在 App 内新增扫描/解析/路径解析私有逻辑；未开发启停、写入、归属迁移；`loaded` 继续恒 `.unknown`；
6. 未修改 entitlement、签名配置、安装位置或沙盒例外；未调度真机验证。

## 2. 文件清单

### 2.1 模型（`Models/PermissionProbe/`，`Models` target 隐式源集）

| 路径 | 说明 |
|---|---|
| `ProbeStatus.swift` | 六态枚举：`passed / failed / permissionDenied(permission_denied) / unavailable / notExecuted(not_executed) / unknown`；unavailable 与 permissionDenied 不合并 |
| `ProbeCategory.swift` | 八分类：`environment / jbroot / ellekit / pluginFiles(plugin_files) / packageDatabase(package_database) / entitlement / sandbox / jbrootAPI(jbroot_api)` |
| `ProbeEvidence.swift` | 单条证据：`probeID / category? / status / target? / observedValue? / errorDomain? / errorCode? / executedAt?`；可选字段 `encodeIfPresent` 省略键、`decodeIfPresent` 容错缺失键与 null；日期沿用仓库字符串惯例，不用 `Date` |
| `PermissionProbeReport.swift` | 汇总报告：`schemaVersion=1 / generatedAt? / evidence[]`；只读派生统计 passed/failed/denied/unavailable/notExecuted/unknown/total；模型层不排序证据数组 |

### 2.2 协议接缝（`Core/PermissionProbe/Protocols/`，Core target 显式源清单）

| 路径 | 说明 |
|---|---|
| `PermissionProbing.swift` | 单探针接缝：`probeID` + `run() throws -> [ProbeEvidence]`；探针可抛错由编排服务捕获为失败证据，常规错误以证据状态承载（throws 修订见 §6 与 D2-D7 记录 §5.3） |
| `PermissionProbeServiceProtocol.swift` | 编排接缝：`runProbes() -> PermissionProbeReport`；单项失败不中断其他探针；D1 无具体装配实现 |

### 2.3 测试（`Tests/Stage2/`，接入 `Stage2Tests`）

| 路径 | 覆盖 |
|---|---|
| `PermissionProbeStatusTests.swift` | 六态原始值、Codable 往返、notExecuted ≠ failed、unknown 独立于 passed/failed |
| `PermissionProbeEvidenceTests.swift` | 全字段往返、nil 省略键、JSON null 落 nil、错误域/码保留、分类缺失解码 nil |
| `PermissionProbeReportTests.swift` | 空证据全 0、混合状态计数、notExecuted 不计 failed、unknown 不计 passed/failed、证据顺序保持、报告往返 |

### 2.4 接线

- `Package.swift`：Core `sources` 增补两条协议文件；`Stage2Tests` `sources` 增补三条测试文件。Models target 为隐式源集，无需清单改动。

## 3. 规格对齐要点

- 状态分类口径对齐附件 D1 与 Stage-2 计划 §5.4/§6.2；报告综合判定（`overall.granted`、`processContext`、`jbroot` 子结构、`coldStartRetained`、`limitations`）不在 D1 预写，留待 D5/D6/D7 按真实探针结果补充。
- 隔离脚本 `scripts/check-adapter-isolation.sh` 本地复跑：1a/1b/2a/2b/3/4/4b 全 passed，`failed: 0`。PermissionProbe 协议只 import Foundation + Models，未引用具体 Adapter/Scanner/Parser。
- 日期字段为 ISO8601/RFC3339 字符串；`generatedAt` 不参与确定性比较（确定性归一化留待导出层，对齐 `ReportEnvelope` 惯例）。

## 4. 待 Runner 复核

1. Core `swift build` 0 error / 0 warning；`Stage2Tests` 既有 405 例回归无损伤，新增 3 文件用例全绿；
2. 新模型 Codable 往返、可选 nil/null、统计口径在 Runner 工具链下复核；
3. 隔离脚本在 CI 复跑通过。

## 5. 后续批次（未授权）

- D2 JBROOT 访问探针；D3 ElleKit/TweakInject 目录探针；D4 dylib/plist/dpkg 读取探针；D5 entitlement/sandbox 探针；D6 `jbroot()` API 探针；D7 Diagnostics GUI 集成与 RootHide 真机完整验收。
- 既有未决项继续挂起：`OwnershipResolver` 未迁移、`loaded` 恒 `.unknown`、`permission.decision` 恒 undetermined、`pluginID` 规则 0.2.0 定稿、PARSE-009-B。

## 6. D2～D7 批次回填修订

- `ProbeEvidence` 增补 `id: String`（默认 UUID）与 `operation: ProbeOperation`；新增 `ProbeOperation` 枚举；`PermissionProbing` 改为 `run() throws -> [ProbeEvidence]`（首轮 Runner 编译修复时由非抛出改为可抛错，编排服务捕获为失败证据；详见 D2-D7 记录 §5.3）。
- D1 测试同步：`makeEvidence` 传 `id/operation`；JSON fixture 补 `"id"` 键；全字段往返断言 `operation`。
- D2～D7 探针链路、接缝占位、展示映射与测试清单见 `Stage-2.4-D2-D7-PermissionProbe-Chain-Implementation-Record.md`。
