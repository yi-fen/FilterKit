# P1-19 — Helper / IPC 安全边界与部署计划

## 1. 本阶段输入与 NEW 源码事实

本阶段从 `FilterKit-NEW-P1-18.zip` 开始。检查 P1-18 源码时，`Sources` 中尚无 Helper、IPC、staging writer 或部署协调器实现；已有恢复审查和备份校验，但没有可调用的特权部署通道。因此本阶段新增的是**协议/模型/策略骨架和 App 沙盒 staging**，不是可运行的 root daemon。

用户提供的 NEW 架构参考定义了目标形态：App(mobile) → app-container staging → HelperDeploymentWriter/Coordinator → IPC → root Helper → HelperPolicy → 固定执行计划。计划中的三项操作是 `installDylib`、`removeUnmanagedDylib`、`replaceFilterPlist`；执行计划仅允许 `copyFile` / `removeFile`，不允许 shell、任意 argv、环境变量或任意可执行路径。

## 2. 本阶段代码落点

- `Sources/Core/Models/Helper/HelperIPCModels.swift`
  - v1 JSON envelope、UInt32 big-endian length-prefix frame codec。
  - 96 KiB 单帧上限。
  - hello/helloAck、operationRequest/operationReceipt、healthRequest/healthResponse、rejected 消息类型。
  - peer identity 记录 uid/gid/pid/CDHash，并为 pidVersion/auditSessionID 预留字段。
  - 三项操作枚举、固定动作枚举、请求与回执模型。
  - 回执验证 requestID/operation、结果码一致性、changedPaths 精确集合、output 32 KiB 上限、时间偏差。
- `Sources/Core/Models/Helper/HelperDeploymentModels.swift`
  - 部署 manifest 模型，包含 route、jbroot、TweakInject、staging、socket、App/Helper CDHash 白名单、允许客户端 UID、executionEnabled。
  - 安全模板强制 `executionEnabled = false`。
  - HelperPolicy 只将请求转换为封闭 `copyFile` / `removeFile` 计划，不执行文件操作。
  - 检查代码身份白名单、请求时间、路径/文件名、扩展名、目标存在状态、源文件常规文件证据、SHA-256 和 plist 可解析性。
- `Sources/Environment/Helper/HelperDeploymentPlanBuilder.swift`
  - 将已通过恢复审查的选择转换为固定操作请求；硬冲突项目不能进入计划。
- `Sources/Environment/Helper/HelperDeploymentWriter.swift`
  - 只把恢复文件写入 App 自己容器下的 task-scoped staging；返回相对路径与 SHA-256 请求。
- `Sources/Environment/Helper/HelperReplayGuard.swift`
  - actor 内存重放守卫，默认 10 分钟、4096 项。
- `Sources/Environment/Helper/HelperDeploymentCoordinator.swift`
  - transport protocol、健康检查、回执解码/验证。
  - `executionReleased = false`，submit 直接拒绝；没有生产 socket transport。
- `Tests/UnitTests/HelperIPCAndPolicyTests.swift`
  - 帧、默认关闭、路径、回执和重放守卫测试。

## 3. 安全决策

1. Unix-domain socket 是当前候选传输，不在本阶段切换 Mach/XPC。
2. socket 文件权限只决定连接可达性，不作为身份认证。
3. 身份证据模型包含 uid/gid/pid 与 CDHash；pidVersion/auditSessionID 仅预留，不能声称已经读取内核 audit token。
4. App CDHash 与 Helper 自身 CDHash 分别核对；manifest 模板默认没有指纹，因而默认不可认证。
5. `executionEnabled` 缺失/false 的 manifest 必须 fail closed；当前模板固定 false，协调器也固定禁止提交。
6. staging 仅位于 App 容器；权限目录 0700、文件 0600；路径使用 task UUID + leaf filename。
7. HelperPolicy 只生成闭合计划，不执行复制/删除。当前没有 root 文件写入代码。
8. `removeUnmanagedDylib` 语义仍需产品明确：名字可能与“只允许管理 FilterKit 自有插件”的产品规则冲突。策略骨架要求目标是常规非符号链接 dylib，但真正上线前还必须增加所有权/manifest 授权证据；本阶段不提供调用入口。
9. 文件回执 changedPaths 必须与预期路径集合完全相等；但路径集合的最终 canonical 形式需在真机 Helper 实现时绑定 manifest 固定目录。

## 4. 官方模型与成熟参照核对

### Apple 官方文档支持的事实

- Apple 将 XPC 描述为轻量 IPC；launchd 管理服务生命周期，可按需启动、空闲关闭和崩溃重启；LaunchDaemon 以 root 运行并响应用户进程请求。见 Apple XPC 文档。
- Apple `SMAppService` 面向 macOS 13+ 的 LoginItems、LaunchAgents、LaunchDaemons 注册管理；不能把它当作 iOS 越狱环境的现成注册接口。
- Apple `SMJobBless` 已标记 deprecated，官方建议使用 `SMAppService`；SMJobBless 文档描述 App `SMPrivilegedExecutables` 与 Helper `SMAuthorizedClients` 的双向签名要求，并说明参数应通过 IPC 传递。

### 用户提供的成熟参照（本阶段按参考资料记录，不将其当作已验证本地代码）

- 用户提供的 Dopamine jbserver broker 参照：集中危险能力、窄类型请求、以 audit token/domain 做调用方鉴权；此处作为用户调研结论记录。
- 本次可直接核对到的 Dopamine 3.x `systemhook` 源码包含 `libjailbreak/jbclient_xpc.h`、`libjailbreak/codesign.h`，并实现 `csops_audittoken` hook；它支持“Dopamine 内部存在 XPC 客户端与代码签名相关组件”的判断，但不能单凭该文件证明 jbserver 的完整授权细节或 FilterKit 可复用其内部协议。
- NEW 当前候选：Unix socket + `getpeereid` + `LOCAL_PEERPID` + `csops(CS_OPS_CDHASH)`；需要真机确认 RootHide/Rootless 的可用性与稳定性。

## 5. 已完成 vs 未完成

| 项目 | P1-19 状态 |
|---|---|
| IPC envelope / frame codec | 已实现模型与编码解码；未接真实 socket |
| 帧长度上限 | 已实现 96 KiB |
| 三项窄操作模型 | 已实现枚举和请求模型 |
| 固定执行计划 | 已实现策略生成；没有执行器 |
| manifest executionEnabled | 安全模板默认 false；当前协调器硬关闭 |
| CDHash 白名单模型 | 已实现字段与策略比较；未接 csops |
| getpeereid / LOCAL_PEERPID | 未实现，待 iOS 越狱 SDK/真机 |
| audit token / pidversion | 仅模型预留，未实现读取 |
| AF_UNIX listener/client | 未实现 |
| nonce 握手完整状态机 | 仅消息类型/envelope；未实现会话握手 |
| 重放守卫 | 进程内 actor 已实现；daemon 重启持久化/会话 nonce 绑定未实现 |
| 设备侧审计日志 | 未实现 |
| launchd plist / root:wheel 0600 manifest 安装 | 未实现 |
| Helper 自身 CDHash 启动自检 | 策略模型要求白名单，但无 Helper executable 启动入口 |
| 崩溃重启/KeepAlive/ThrottleInterval | 未实现，待生命周期决策 |
| 指纹重钉与卸载清理 | 规格待补，未实现 |
| 真机路径 canonicalization / symlink race 防护 | 未实现；需使用 lstat/openat/O_NOFOLLOW 等 fd-relative 实现验证 |
| 实际 root copy/remove | 明确未实现、未开放 |

## 6. 风险与后续门槛

- 不应把 macOS 的 SMJobBless/SMAppService/XPC 生命周期能力直接宣称为 iOS 越狱可用。
- Unix socket 的 0666 不等于信任；正式实现必须每连接、关键消息复核 peer 身份，并在支持时增加 audit token/pidversion。
- CDHash 会因 App/Helper 重签、uicache 或构建变化而变化；必须有受控的带外重钉流程。
- 路径安全必须基于已打开目录 fd 做相对操作，避免先检查路径后被 symlink 替换的 TOCTOU。
- manifest 必须由可信安装流程创建，root:wheel 0600；App 不能自行修改执行开关。
- 先明确 Helper 生命周期、日志、安装/卸载和重钉流程，再实现实际 socket daemon。
- RootHide 与 Rootless 的 jbroot/TweakInject 路径必须独立 profile，不能从一台设备推导所有布局。

## 7. 上游资料

- Apple XPC: https://developer.apple.com/documentation/xpc
- Apple SMAppService: https://developer.apple.com/documentation/servicemanagement/smappservice
- Apple SMJobBless: https://developer.apple.com/documentation/servicemanagement/smjobbless(_:_:_:_:)?language=objc
- Dopamine upstream: https://github.com/opa334/Dopamine
- Dopamine 3.x systemhook source: https://github.com/opa334/Dopamine/blob/3.x/BaseBin/systemhook/src/main.c
