# P2-37-R7 验收清单

- [x] APP 从扫描项读取当前 Filter 与 Manifest 字节并计算哈希。
- [x] Command 绑定唯一插件、目标 Bundle ID、期望状态和快照版本。
- [x] APP Prepare IPC 请求及 Helper 响应类型/requestID 校验。
- [x] Helper plan 与原始 command 完整绑定。
- [x] Commit 使用独立 envelope requestID。
- [x] Commit 要求用户显式确认。
- [x] Prepare plan 与 `snapshotRevision` 绑定。
- [x] 扫描快照变化清除待提交计划。
- [x] 不乐观修改 UI 已配置状态。
- [x] 有效 proof 后刷新只读扫描。
- [x] Commit 传输结果不确定时不自动重试。
- [x] APP Commit Release Gate 保持关闭。
- [ ] XcodeGen / iOS SDK 完整构建。
- [ ] Apple XCTest Runner 执行新增测试。
- [ ] 签名 App/Helper IPC 与 Darwin peer identity 设备验收。
- [ ] RootHide / ElleKit 设备级启停验收。
- [ ] 单独评审并开放生产写入 Gate。
