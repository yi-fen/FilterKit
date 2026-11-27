# P2-37-R7 — APP 启停 IPC 完整调用链与状态回写

## 本阶段完成

- 新增 `HelperAppPluginActivationService`：从当前扫描项读取插件 `.plist` 与 Manifest 原始字节，计算 SHA-256，并构造单插件、单目标 App 的 R4 command。
- 新增 `HelperDeploymentCoordinator.prepareAppPluginActivation`：发送 Prepare IPC，严格检查协议版本、响应类型、requestID，并验证 Helper 返回的完整计划与原始 command 一致。
- 新增 `HelperDeploymentCoordinator.commitAppPluginActivation`：要求用户确认、计划绑定正确，使用独立 Commit envelope requestID，验证 Helper 提交证明。App 侧 `appPluginActivationCommitReleased` 保持 `false`，因此当前会在提交前拒绝，不会向 Helper 发送 Commit。
- 新增 `AppPluginActivationOperationStore`：管理 preparing/prepared/committing/committed/blocked/outcomeUnknown/failed 状态；计划绑定 `snapshotRevision`，扫描快照变化即失效。
- APP Detail 开关从本地预览改为请求 Helper Prepare；Helper 返回计划后展示明确确认界面。确认后进入 Commit 协调器，但当前因生产 Gate 关闭而显示锁定状态。
- UI 不乐观修改已配置启停状态。只有收到有效 proof 后才触发扫描刷新；任何传输错误/结果不确定均清除计划并要求重新扫描，不自动重放 Commit。
- 新增 coordinator XCTest：Prepare 消息/响应验证、目标篡改拒绝、Commit Gate 关闭、未确认拒绝。
- 更新中英文界面状态文案与 R3/R5 回归审计断言，使历史审计适配 R7 已接入的 APP 调用链。

## 安全边界

- APP Prepare 是只读授权预检，可经已配置的 Darwin Helper transport 发起。
- APP Commit Gate：`appPluginActivationCommitReleased = false`。
- Helper Dispatcher 测试执行注入点默认 `false`；生产 `HelperRuntime` 不启用。
- 生产环境仍不会修改 Filter.plist 或 Manifest。
- Commit 响应丢失/传输异常被视为 outcome unknown；不自动重试，先刷新扫描。此策略避免未知事务结果下重放操作。
- 仍未完成 Xcode/iOS SDK 编译、Apple XCTest Runner、签名 IPC、真实 Darwin peer identity 与 RootHide/ElleKit 设备验证。
