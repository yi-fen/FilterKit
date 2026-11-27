# P2-37-R5 — APP 启停协议 IPC 接入与 Helper 请求处理

## 本阶段目标

将 R4 单插件/单 App 启停协议接入 Helper 的认证 IPC 路由，补齐请求类型 allowlist、requestID 重放保护、请求时效、Helper 文件重读授权、状态前置条件校验和审计。生产写入继续关闭。

## 新增与调整

- 新增 `appPluginActivationPrepareRequest` / `appPluginActivationPrepared` 与 `appPluginActivationCommitRequest` / `appPluginActivationCommitted` 消息类型。
- 仅两个 Request 类型加入 Helper IPC server allowlist；Response 类型不能作为请求进入服务端。
- Dispatcher 对请求执行会话/nonce、requestID、时间戳、协议模型 freshness/shape 检查；复用全局 `HelperRequestReplayGuard`。
- Prepare 路由调用 Helper mutation authorizer，重新读取 ownership proof、Manifest 和 Filter.plist；将 Helper 结果映射成 R4 plan，不向 App 暴露路径或文件字节。
- Helper 从刚读取的 Manifest 中独立提取目标 App 当前启停状态，并与 command.expectedEnabled 比较；不信任 App 自报的前态。
- Prepare 结果必须通过 R4 `plan.validates(command:)`，并写入审计后才返回。
- Commit 路由重新执行 Helper authorizer 与前态检查，避免信任先前 prepare 结果；随后明确返回 `execution_disabled`，不调用事务执行器、不写文件。
- 新增 dispatcher 测试，覆盖 request allowlist、response 禁止入站、畸形请求拒绝和 requestID 重放拒绝。

## 安全边界

- `pluginAssociationCommitReleased` 保持 `false`。
- R5 的 commit IPC 目前是授权预检入口，不是生产写入入口；事务执行器没有在新路由中被调用。
- R4 `HelperAppPluginActivationProof` 暂未作为 commit response 返回，因为没有发生真实 commit。不能伪造 transactionID 或成功证明。
- APP UI 开关仍未连接真实 IPC 写入。
