# P2-37-R7 验证报告

## 验证结果

| 项目 | 结果 |
|---|---:|
| R7 APP activation flow static audit | 22/22 |
| R3 activation consistency regression audit | 25/25 |
| R4 activation protocol audit | 15/15 |
| R5 Helper IPC audit | 21/21 |
| R6 two-file transaction audit | 22/22 |
| Swift frontend parse（Sources、App、Tests） | PASS |
| Project.yml YAML parse | PASS |
| English localization keys | 422，重复 0 |
| Simplified Chinese localization keys | 422，重复 0 |
| ZIP integrity | 待打包后执行 |

## 本轮新增 XCTest

新增 `HelperAppPluginActivationCoordinatorTests.swift`，包含 4 个测试方法：

1. Prepare 使用正确消息类型及 command requestID，并验证 Helper plan。
2. Helper plan 目标 App 被篡改时拒绝。
3. APP Commit Gate 关闭时不触达 transport。
4. 未显式确认时不触达 transport。

这些测试已纳入源码语法解析，但当前执行环境没有 Xcode/Apple XCTest Runner，因此**没有声称 XCTest 已运行通过**。

## 未完成 / 不可声称的验证

- 未执行 XcodeGen 与 Xcode iOS 构建。
- 未执行 Apple XCTest Runner。
- 未验证签名 App 与签名 Helper 的真实 IPC。
- 未验证 Darwin `LOCAL_PEERTOKEN`、`csops` 和真实 peer identity。
- 未在 RootHide / ElleKit 越狱设备验证启停结果。
- 未开放生产 Commit Gate。

## 安全结论

R7 完成 APP 侧 Prepare → 用户确认 → Commit 请求协调 → Proof 验证 → 只读扫描刷新 的调用结构。当前 Commit 在 APP 侧 Gate 即被阻断；Helper 生产执行开关也保持关闭，因此不会执行生产文件写入。

## 追加 Host 验证

- P2-37-R3 Activation Consistency Host Smoke：11/11 通过。
- P2-36-R2 Transaction Smoke：逐项独立编译并运行，Journal 六阶段恢复、双文件提交、外部篡改拒绝、SIGKILL 崩溃恢复、IPC 兼容性及生产 Gate 检查均通过。
- 旧的聚合脚本 `run-p236r2-phase2-host-smoke.sh` 在执行到历史 `P2-37-Activation-Model-Smoke.swift` 时，因 Swift 6.2 将多个顶层表达式源文件一起编译而报错；因此未将聚合脚本标记为通过。对应 R3 smoke 和 R6 transaction smoke 已分别独立运行通过。
- Helper 源码集使用 Linux Swift 6.2.1 进行语义类型检查：通过（包含 `PluginFilterConfiguration.swift`）。这不等同于 iOS App target 的完整类型检查或 Apple SDK 构建。
