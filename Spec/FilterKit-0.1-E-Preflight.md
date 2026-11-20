# FilterKit 0.1-E 发布验收设计前置准备（Preflight）

> 状态：PRE-E 资料准备稿；不是 0.1-E 正式验收规格冻结，不代表发布通过。
> 基线：`FilterKit-0.1-D-R4-Audit-Repair.zip`，R4-B2 修复包。

## 1. 目标与边界

0.1-E 的目标是在 0.1-D 的设备构建、签名候选、DEB 静态校验、真机部署/权限证据完整后，建立正式发布验收门禁。本文件只整理进入 0.1-E 设计前必须具备的输入、证据和阻塞项；不实施发布、不签署验收、不改变版本、不触发设备安装。

0.1.0 定义仍为 RootHide 只读插件管理器。插件启停、修改 plist、添加 Bundle ID、删除 dylib、dpkg 写入、自动修复、常驻 daemon、自研注入引擎均不属于本轮发布范围。

## 2. 必需输入资料

| ID | 输入 | 进入 0.1-E 前要求 | 当前状态 |
|---|---|---|---|
| PRE-01 | 当前源码基线 | 固定 commit SHA；源码、Workflow、归档 SHA256 一致 | 本修复包提供快照；GitHub HEAD 未连接复核 |
| PRE-02 | R4-B2 Runner | macOS Runner 实际 ldid 签名、Mach-O 检查、DEB 打包和摘要 | pending |
| PRE-03 | 签名证据 | ldid 版本、签名日志、LC_CODE_SIGNATURE、嵌入 entitlement 比对 | 仅 mock 测试通过；真实 Runner pending |
| PRE-04 | DEB 证据 | e1-e9 原始日志、摘要、DEB SHA256、control、payload tree | 旧 unsigned 产物仅历史证据；新 Runner pending |
| PRE-05 | RootHide 真机部署 | Bootstrap 安装、dpkg 状态、uicache 注册、App 启动结果 | pending，需单独授权 |
| PRE-06 | 崩溃诊断 | `.ips`、amfid、dyld、runningboardd 日志及安装包哈希对应关系 | 未提供；根因未定 |
| PRE-07 | GUI 权限探针 | FilterKit.GUI 进程上下文 G10-G15 完整证据 | pending |
| PRE-08 | 0.1-C G10 | 回到 C-F4 原始定义，独立补证并保留原门禁 | 未豁免、未签署 |
| PRE-09 | 0.1-D 最终验收 | R4-G、R3-B～R3-E、0.1-C G10 按原规格分别判定 | 未完成 |
| PRE-10 | 风险与范围 | 未决问题、限制、已知不支持功能和回滚策略 | 本文件初步汇总，待正式规格确认 |

## 3. 0.1-E 设计必须采用的证据层级

1. **Source Verified**：源码 SHA、工作区状态、构建输入和版本元数据可追溯。
2. **Build Verified**：真实 macOS Runner 的设备构建成功；Simulator 结果不得替代。
3. **Signature Payload Verified**：签名数据区和 entitlement 嵌入内容经过工具核验。`ldid_signed_embedded` 不是 RootHide 接受或可安装结论。
4. **Package Verified**：DEB 结构、控制字段、root:root、可执行权限、源/包完整性、架构、签名状态通过。
5. **Device Install Verified**：目标 RootHide Bootstrap 接受安装，dpkg/uicache 结果有设备证据。
6. **Device Launch Verified**：App 在目标设备冷启动成功，进程存活且无崩溃；启动失败必须判 failed。
7. **Permission Verified**：G10-G15 的探针在 `FilterKit.GUI` 进程中执行，记录实际操作、结果、errno/errorDomain/errorCode 和环境信息。
8. **Product Acceptance**：功能、只读边界、数据语义、限制、风险与发布文档全部符合冻结规格。

任一层级不得由前一层推断。`installed`、`configured`、`loaded` 不互推；没有独立运行时证据时 `loaded=unknown`。

## 4. 0.1-E 设计前阻塞项

- R4-B2 的真实 ldid/otool Runner 结果尚未取得；mock 不能替代。
- ldid 签名和四枚候选 entitlement 是否被目标 RootHide Bootstrap/amfid 接受未知。
- FilterKit GUI 进程是否能访问 `.jbroot-*`、TweakInject、插件 dylib/plist 和 dpkg 数据库未知。
- 当前 SwiftUI App 尚未实际调用 RootHide `jbroot()`；不因参考 0.1.18 自动添加未经核实的弱链接、rpath 或 C 声明。
- 用户报告的 DEB 闪退没有 `.ips` 或系统日志，不能断言唯一根因。
- 0.1-C G10 缺口仍然存在，不得以其他 Simulator/Runner 结果替代或豁免。
- Rootless 无真机，Rootless 真机兼容不纳入本轮 0.1.0 发布承诺。

## 5. 建议的 0.1-E 设计分组（待正式冻结）

- E1：源码与构建可追溯性。
- E2：设备构建与签名证据。
- E3：DEB/IPA 产物完整性和包元数据。
- E4：RootHide 安装、注册、冷启动与崩溃日志。
- E5：GUI 权限探针及只读访问边界。
- E6：UI/导出/分享/Diagnostics 验收，包括 0.1-C G10 独立补证。
- E7：产品语义、架构隔离、状态未知值和来源权限策略。
- E8：风险、限制、版本说明、安装/卸载/恢复文档。
- E9：最终发布判定、证据索引、SHA256 和归档。

## 6. 不可豁免的发布阻断规则

- 未签名或签名验证失败：阻断设备候选包。
- `ldid_signed_embedded` 但未取得 RootHide 设备接受证据：只允许称签名候选，不允许称可安装/可发布。
- App 真机启动失败：R4-G failed，后续权限探针结果无效。
- 关键权限探针缺失/unknown：不得宣称已获得对应目录访问能力。
- 0.1-C G10 缺证：不得签署完整 0.1-E 验收。
- loaded 无运行时证据：保持 unknown，不得作为发布成功指标。
- 任何结构检查、Simulator、离线 fixture 或 mock 均不得替代 RootHide 真机证据。

## 7. 进入正式 0.1-E 设计的准入条件

只有在 R4-B2 Runner 已产生可追溯结果、R4-G 与 R3 真机门禁完成或明确记录失败、0.1-C G10 独立补证完成后，才冻结 0.1-E 正式验收规格。若某项设备证据无法取得，应在正式规格中明确标为 blocker，不得降低门槛换取全绿。
