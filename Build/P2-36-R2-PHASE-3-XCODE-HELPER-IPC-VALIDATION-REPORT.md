# P2-36-R2 Phase 3 — Xcode / XCTest / Helper IPC 集成验收报告

## 结论

本阶段完成了可在当前 Linux Host 执行的工程集成审查和真实 AF_UNIX socket 端到端 Host 测试，并准备了 macOS/Xcode 一键验证入口。**Apple 平台的 Xcode 编译和 XCTest 尚未执行**：当前运行环境是 Linux + Swift 6.2.1，没有 `xcodebuild`、`xcodegen` 或 Apple iOS SDK。

因此本阶段不是 Xcode build pass，也不是 Apple 平台 Helper 身份认证验收通过。

## 本阶段实际完成与验证

- `Project.yml` YAML 解析通过，确认 `FilterKit`、`FilterKitHelper`、`FilterKitTests` 三个 target 存在。
- 工程配置静态审计：**18/18 通过**。
- `Sources`、`App`、`HelperRuntime`、`Tests` 和 Host Swift 文件语法解析通过。
- 新增 live AF_UNIX Host 集成 Smoke：实际启动 `UnixDomainSocketServer` 和 `UnixDomainSocketTransport`，由 Linux 内核 `SO_PEERCRED` 提供 UID/GID/PID；完成双向连接、nonce handshake、请求/响应 ID 与 nonce 绑定。
- 认证后的 `.healthRequest` 真实进入 `HelperRequestDispatcher.dispatch`，返回 `.healthResponse`，并由测试 Audit Sink 观察到一条审计记录。
- Phase 2 回归 Host Smoke 已重新执行通过：六个 Journal 阶段、正常双文件提交、未知字节 fail-closed、SIGKILL 跨进程恢复、IPC framing/兼容性均通过。
- App 和 Helper 两个生产软关联提交 Release Gate 仍为 `false`。

## Live IPC 测试的边界

本次 AF_UNIX Host 集成使用 `FixturePeerIdentityProvider` 和 Host 测试用 CDHash 值，以验证 transport 的连接、内核 socket credentials、握手、请求分发和响应通路。它**没有**验证 Darwin 的 `LOCAL_PEERTOKEN`、`csops` 真实 CDHash、Apple code-signature 身份、签名 Helper 与 iOS App 的真实互认证。

本次经真实 socket 发送的是只读 `.healthRequest`，没有经生产 IPC 提交软关联写入。生产提交仍被两道 Release Gate 拦截。

## XCTest 状态

工程已有以下相关 XCTest 源文件，且已通过 Swift parser 语法解析：

- `HelperPluginFilterMutationRequestTests.swift`
- `HelperPluginAssociationMutationPolicyTests.swift`
- `HelperPluginFilterConfigurationTransactionTests.swift`
- `HelperPluginFilterMutationCommitTests.swift`
- `HelperRequestDispatcherTests.swift`
- `HelperIPCAndPolicyTests.swift`
- `HelperPeerIdentityBindingTests.swift`
- `PluginAssociationCommitIntegrationTests.swift`

但 XCTest Runner 依赖 Xcode/iOS Simulator，本环境没有运行这些测试。

## Xcode 执行入口

在 macOS 安装 Xcode、XcodeGen，并启动一个可用 iOS Simulator 后执行：

```bash
FILTERKIT_SIMULATOR_UDID="<可用模拟器 UDID>" \
  Build/Host/run-p236r2-phase3-xcode-validation.sh
```

脚本依次生成 Xcode 工程、编译 `FilterKitHelper`、编译 `FilterKit`，并运行 `FilterKitTests`，保存日志与 `.xcresult` 到 `Build/Artifacts/`。

当前环境的执行结果：`run-p236r2-phase3-xcode-validation.sh` 在工具预检阶段退出，原因是缺少 `xcodegen`；`xcodebuild` 同样不可用。

## Release Gate

以下生产开关保持关闭：

```swift
HelperDeploymentCoordinator.pluginAssociationCommitReleased = false
HelperRequestDispatcher.pluginAssociationCommitReleased = false
```

没有开放真实写入，没有修改越狱文件，没有启用注入。

## 后续验收条件

1. 在 macOS/Xcode 执行 Helper、App 的 iOS Simulator 编译。
2. 运行完整 `FilterKitTests` XCTest 套件并处理真实 SDK 编译错误。
3. 在目标 RootHide/ElleKit 设备上验证 Darwin `LOCAL_PEERTOKEN`、`csops`、签名 CDHash pinning 和真实 App↔Helper socket 身份绑定。
4. 验证签名、部署、Helper 启动与重启恢复。
5. 继续保持软关联提交 Release Gate 关闭，直到设备证据完整审查。
