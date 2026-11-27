# P2-37-R8 — Apple 平台编译、签名 IPC 与设备验收准备

## 本阶段目标

将 R7 的 APP → Helper 启停链路推进到可重复执行的 Apple 平台验收流程；本阶段建立 macOS/Xcode 构建、Darwin SDK 编译探针、已签名产物检查和设备验收记录规范。当前执行容器为 Linux，不能实际执行 Apple SDK 构建或设备测试，因此不把脚本准备描述为 Apple 平台验收通过。

## 新增内容

- `Build/Host/run-p237r8-apple-validation.sh`
  - 强制要求 macOS、Xcode、XcodeGen 和明确指定的 Simulator UDID。
  - 生成 Xcode 工程到 `Build/Artifacts/P2-37-R8/`，避免污染源码根目录。
  - 分别编译 Helper/App Simulator target，执行完整 XCTest，并分别执行 generic iPhoneOS Helper/App Release 编译。
  - 对 `LOCAL_PEERTOKEN`、`LOCAL_PEERPID`、`getpeereid` 和 `csops` 相关 Darwin SDK 声明执行 iPhoneOS 与 Simulator 编译期探针。
  - 不签名、不安装、不打开任何生产写入 Gate。
- `Build/Host/verify-p237r8-signed-artifacts.sh`
  - 对已签名 App 和 Helper 执行 `codesign --verify`。
  - 要求显式传入预期 TeamIdentifier，检查签名 Team ID 与 CDHash，并导出 entitlements 供人工审查。
  - 只检查产物，不执行签名或安装；明确提示 entitlement 静态内容不等于运行时权限。
- `Build/scripts/p237r8_apple_readiness_audit.py`
  - 检查 Project.yml target/test 配置、Darwin identity 实现、SDK probe、Apple runner、签名检查脚本和生产 Gate。
- `Build/DeviceAcceptance/P2-37-R8-DEVICE-ACCEPTANCE.md`
  - 记录真机签名、Helper peer identity、Helper 生命周期、IPC 故障注入、RootHide/ElleKit 只读验证和双文件事务设备验收步骤及证据要求。

## 安全边界

- APP `appPluginActivationCommitReleased` 继续为 `false`。
- Helper `activationCommitExecutionEnabled` 默认继续为 `false`，生产 `HelperRuntime` 不注入测试执行开关。
- 本阶段不修改签名 entitlement 候选，不声称候选 entitlement 已获系统授权。
- 本阶段不执行真实 Commit，不修改越狱文件，不在设备上安装或注入插件。
