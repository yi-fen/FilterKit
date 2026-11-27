# P2-37-R8 Apple / RootHide / ElleKit 设备验收规程

本文件是执行清单，不代表相关测试已经执行或通过。所有测试必须先在隔离测试设备和可恢复配置上进行。生产 Commit Gate 在完整证据评审前保持关闭。

## A. Apple SDK 与 XCTest

1. 使用受支持的 macOS/Xcode，安装 XcodeGen。
2. 选择可用 iOS Simulator，并设置 `FILTERKIT_SIMULATOR_UDID`。
3. 在仓库根目录运行 `Build/Host/run-p237r8-apple-validation.sh`。
4. 保存 `Build/Artifacts/P2-37-R8/` 下全部日志和 `.xcresult`。
5. 必须确认 Helper/App Simulator build、完整 XCTest、generic iPhoneOS Helper/App build 均成功；任何失败均阻止后续设备验收。

## B. 已签名产物静态检查

1. 使用项目认可的签名流程生成 App 与 Helper，不得直接把候选 entitlement 当成已获系统授权。
2. 设置 `FILTERKIT_SIGNED_APP`、`FILTERKIT_SIGNED_HELPER`、`FILTERKIT_EXPECTED_TEAM_ID`。
3. 运行 `Build/Host/verify-p237r8-signed-artifacts.sh`。
4. 人工审查 App/Helper TeamIdentifier、CDHash、entitlements 与发布信任清单的一致性。
5. 将实际安装二进制的 CDHash 与 Helper Release Trust Manifest 中预期值逐项核对。

## C. 真实 Darwin Peer Identity

必须在已签名 App 与已签名 Helper 的真实设备 IPC 会话上验证：

- 服务端通过 `getpeereid` / `LOCAL_PEERPID` 取得 socket peer credentials。
- `LOCAL_PEERTOKEN` 长度为 8 个 UInt32，且 euid/egid/pid 与 socket credentials 一致。
- `csops(CS_OPS_CDHASH)` 返回 20-byte 非零 CDHash，并与已安装客户端的签名 CDHash 匹配。
- 在 CDHash 读取前后重新读取 audit token，证明 token 未变化。
- 拒绝错误 Team/错误 CDHash/无效 token/peer PID 与凭据不一致的请求。
- 记录设备型号、iOS 版本、App/Helper build、TeamIdentifier、CDHash、诊断码和完整日志；不得记录敏感用户数据。

注意：SDK 编译探针只证明 API 声明可编译，不证明设备运行时 syscall 成功，也不证明 entitlement 生效。

## D. Helper 生命周期与 IPC 故障注入

在只读或隔离测试模式下验证：

1. Helper 正常启动、监听、健康检查和关闭。
2. Prepare 在 Helper 重启后重新建立 Session，不复用旧 nonce。
3. Commit 响应丢失时 APP 标记 outcomeUnknown，不自动重放。
4. 相同 envelope requestID 重放被拒绝；Prepare 与 Commit 使用不同 envelope requestID，但仍绑定同一 command/plan。
5. 并发修改 Filter.plist 或 Manifest 后，Commit 因原始哈希变化被拒绝。
6. Helper 在事务各 Journal 阶段被终止后，重启恢复结果与磁盘状态一致。
7. 验证日志记录授权失败、恢复失败和恢复成功，不泄漏文件内容。

## E. RootHide / ElleKit 只读预检

- 验证 JBROOT 定位、RootHide 路径和 ElleKit DynamicLibraries 可访问性。
- 对目标插件验证 dylib、plist、Manifest 身份及哈希证据。
- 验证 hard-bound 与 soft association 的完整集合及 Filter.Bundles 对应关系。
- 不修改任何注入规则，不启停插件，不重签插件。

## F. 双文件事务隔离验收

仅当前述 A-E 完成并经评审后，才允许在可恢复的测试设备上进行独立授权的事务试验；不得通过修改生产 Gate 绕过评审。需要证明：

- Filter.plist 与 Manifest 同一 Journal 事务提交。
- 两文件任一替换失败均按恢复协议回滚或进入可诊断的 recovery-required 状态。
- Helper 崩溃/强制终止后恢复不会留下混合版本。
- proof 的两个最终哈希与磁盘实测哈希一致。
- no-op 不产生伪造 transaction ID。

## 证据归档

每台设备单独归档：设备型号、iOS build、越狱类型/版本、ElleKit 版本、App/Helper 版本、TeamIdentifier、CDHash、签名验证日志、XCTest `.xcresult`、IPC 日志、事务 Journal 摘要、恢复结果和验收人结论。
