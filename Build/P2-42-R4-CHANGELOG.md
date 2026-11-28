# P2-42-R4 — Helper 卸载授权与 IPC 集成

## 本轮目标

把 R3 的三文件卸载事务接入 Helper 的身份认证 IPC 分发链路，同时保持生产卸载 Gate 关闭。

## 变更

1. 新增 `HelperPluginUninstallRequest` / `HelperPluginUninstallResponse` 与 IPC 消息类型。
2. 新增 `HelperPluginUninstallAuthorizer`：
   - 只接受 Plugin ID、文件叶名称和三文件 SHA-256 期望值，不接受客户端路径或文件内容。
   - Helper 侧重新读取 dpkg `.list` 所有权证据；任何一个目标文件被 dpkg 管理即拒绝。
   - Helper 侧重新验证 Root 所有的 Manifest、dylib、Filter.plist、Mach-O 身份和哈希。
   - 根据 Manifest Schema 4 BindingTopology 或 Schema 3 兼容数据与实际 Filter.plist 检查启用目标；任何关联 App 仍启用则拒绝。
3. `HelperRequestDispatcher` 增加卸载 IPC 路由：
   - 使用现有认证 peer context、nonce、时效与 replay guard。
   - 需要 operator confirmation，并调用 `HelperRecoveryAuthorization` 验证非 Root 客户端及内核 peer 身份证据。
   - 写入前要求 audit 成功。
   - 生产 Gate 关闭时只返回 `executionNotReleased`，不执行文件操作。
4. `FilterKitHelper` 运行时注册卸载 Authorizer 和 R3 三文件事务。
5. 三文件事务增加最后写入边界回调，重新验证 dpkg 所有权、插件身份、哈希和启用状态，降低 Prepare 与实际文件隔离之间的 TOCTOU 风险。
6. 启动恢复检查识别卸载 Journal；卸载 Journal 与其他事务 Journal 同时存在时按 `invalidJournal` 处理。
7. `HelperOwnershipProofVerifier` 支持已定义的 Manifest Schema 3/4 结构；Schema 4 必须验证 BindingTopology 与兼容镜像字段一致，允许无 Fixed Owner 的拓扑。

## 明确未开放

- `HelperRequestDispatcher.pluginUninstallExecutionReleased = false`。
- `PluginToggleReleaseGate.productionMutationReleased` 保持 false。
- 未开放真实注入、启停、卸载或备份恢复写入。
- Plugin 页面卸载按钮仍应保持禁用，直到后续 App IPC 客户端接入、签名产物验证和 RootHide/ElleKit 真机验收完成。

## 已知边界

- 当前外部包管理器所有权识别仍基于配置的 dpkg info 目录；Sileo/dpkg 可识别，其他包管理器未适配时必须按未知来源拒绝自动卸载。
- Schema 3 的 Fixed Owner 启用状态从实际 Filter.plist 的 Bundle 规则核验；Schema 4 使用 Manifest BindingTopology 并要求与 Filter.plist 一致。
