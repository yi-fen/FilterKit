# P2-37-R6 — APP 启停双文件事务接入与提交证明

## 本阶段交付

- Commit IPC payload 从单独 command 改为 `HelperAppPluginActivationCommitRequest`，必须携带 Prepare 返回的完整 `HelperAppPluginActivationPlan`。Commit 使用独立的新 envelope requestID（不同于 Prepare command requestID），避免全局 Replay Guard 将合法 Commit 误判为 Prepare 重放；原 command ID 仍用于绑定 Prepare plan 与最终 proof。
- Commit 时 Helper 重新读取并授权插件 ownership、Filter.plist 与 Manifest；独立读取 Manifest 中目标 App 的当前启停状态。
- Helper 重新计算当前 plan，并要求其与 APP 携带的 Prepare plan 完全相等；任一前置状态、目标、文件哈希或 after-hash 改变均拒绝。
- 授权通过后先写入持久审计授权事件，再调用既有 `HelperPluginFilterConfigurationTransaction`。
- 复用该双文件 Journal 事务，只修改 Filter.plist 与 `.fk.json` Manifest，不修改 dylib；事务内部执行原始哈希/字节复核、staging、备份、逐文件替换、提交标记与回滚/恢复。
- 仅在事务成功后从事务 Receipt 构造 `HelperAppPluginActivationProof`；无变化请求返回无 transactionID 的 no-op proof。
- 新增 commit payload plan-tampering 测试和 dispatcher malformed commit 测试。

## 安全边界

- `pluginAssociationCommitReleased` 仍为 `false`。
- 新增 `activationCommitExecutionEnabled` 仅为内部测试注入点，默认 `false`；生产 `HelperRuntime` 不传入、不启用。
- 因此生产 IPC 在重新授权和计划比对后仍返回 `execution_disabled`，不会写入越狱文件。
- 不开放 APP UI 真实开关，不生成生产提交证明。
- 事务原语已有 crash-phase XCTest；本环境只进行源码级检查，未声称已在 Apple XCTest Runner 或 RootHide 设备执行。
