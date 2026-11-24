# P1-20 — Helper IPC Transport, Peer Verification & Lifecycle

## 1. 本阶段目标与边界

P1-20 从 P1-19 的 IPC/Policy/staging 骨架继续，完成 AF_UNIX 流传输、双端 nonce 握手、内核 peer credential 读取、CDHash 身份提供接口、连接并发限制、审计记录模型与 Helper 生命周期规格。

本阶段仍**不是可安装的 root Helper 产品包**：没有 launchd job、没有独立 Helper executable target、没有 root manifest 安装器，也没有实际 TweakInject 文件执行器。`HelperDeploymentCoordinator.executionReleased` 仍为 `false`；P1-19 的 Helper manifest 模板仍默认 `executionEnabled = false`。

## 2. 新增实现

### 2.1 AF_UNIX client/server

新增 `Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift`：

- POSIX `AF_UNIX` / `SOCK_STREAM` client 与 server。
- UInt32 big-endian length-prefix + JSON frame；复用 96 KiB 帧上限。
- 处理 partial send/recv 与 EINTR。
- 每次 client exchange 建立独立连接，连接内只执行一次握手和一次请求/响应。
- socket path 必须为绝对路径，不允许 `..`，长度受 sockaddr_un 限制。
- 连接读写超时；服务端 accepted socket 同样设置 5 秒读写超时。
- server 最大并发连接数默认 8；超额连接直接关闭。
- 已存在的 socket 路径不会自动 unlink；安装/恢复工具必须先判断路径类型和服务存活状态，避免误删普通文件或活跃 socket。
- server 的 `stop()` 只关闭 listener；本阶段没有做 inode 绑定的 socket path unlink。

Transport 不把 socket mode 当作身份认证。client 和 server 均必须注入身份提供器及 trust evaluator；默认 identity provider 是拒绝型，未配置平台身份读取时连接失败关闭。

### 2.2 nonce 握手状态机

新增 `HelperHandshake.swift`：

- client 每次连接生成新的 UUID v4 派生 128-bit nonce。
- hello 与 helloAck 的 protocolVersion、requestID、nonce 必须匹配。
- nonce 长度限制 32–128 字符。
- 握手消息时间偏差限制 120 秒。
- 错误消息会将客户端状态置为 failed。
- 服务端将 nonce 与本连接的 `HelperAuthenticatedPeerContext` 绑定；不会跨连接复用。

该 nonce 是连接新鲜度/会话绑定机制，不替代 peer credential 或 CDHash 身份验证。

### 2.3 内核 peer credentials 与 CDHash

- Darwin：通过 `getpeereid` 读取 peer uid/gid；通过 `getsockopt(SOL_LOCAL=0, LOCAL_PEERPID=2)` 读取 peer pid。
- Linux 仅用于本地可执行 smoke test：通过 `SO_PEERCRED` 读取 uid/gid/pid。
- 新增 `DarwinPeerIdentityProvider`：调用 XNU `csops(pid, CS_OPS_CDHASH=5, ..., 20)` 获取 20-byte CDHash，转换为 40 位 hex。
- `HelperPeerTrustPolicy` 对 uid、pid、CDHash 格式及 CDHash 白名单进行 fail-closed 检查。
- `HelperStartupIdentityGate` 提供 Helper 自身 CDHash 与 manifest 白名单比对入口。

**尚未解决的身份原子性问题：** AF_UNIX peer PID 与随后 `csops(pid)` 查询不是同一个 audit-token 原子快照；pid 复用/exec 竞态仍需真机评估。Unix socket 不直接提供 Mach audit token，因此 `pidVersion` / `auditSessionID` 目前仍为 nil/预留，不得宣称已获得 audit-token 级别鉴权。

### 2.4 并发与审计模型

- Server 使用有界 `DispatchSemaphore`，默认最多 8 个并发连接。
- 服务端集成进程内同步 replay guard，默认 10 分钟/4096 项；重复 requestID 会被拒绝。进程重启后的持久化重放记录仍未实现。
- 新增 `HelperAuditRecord` / `HelperAuditSink`：记录 eventID、时间、requestID、操作、peer uid/pid/CDHash、结果、reason code、相对路径、可选 SHA-256 和截断输出。
- 记录字段有长度和数量上限；不记录 dylib/plist 原始内容。
- 新增 `HelperLifecycleProfile.conservativePersistent` 规格：RunAtLoad=true、KeepAlive=true、ThrottleInterval=10s、连接上限 8、连接读写超时 5s、socket mode 0666、审计文件 0600、单文件 1 MiB、保留 3 份。
- 以上 lifecycle profile 是规格模型，不是已安装的 launchd plist 或已运行的审计 writer。

### 2.5 指纹失效恢复策略

`HelperFingerprintRecoveryPolicy.failClosed` 明确：不允许 App 自动重钉；必须由受信任的 root 安装/修复流程重新计算 App 与 Helper CDHash 并更新 root-owned manifest；App 不得修改 manifest。

## 3. 生命周期与安装决策

当前候选为常驻 launchd daemon：AF_UNIX listener 由 Helper 自己创建，故暂定 RunAtLoad + KeepAlive；ThrottleInterval 10 秒用于崩溃重启节流。连接 idle timeout 5 秒只限制单连接，不会让 daemon 自动退出。

安装/卸载建议流程：

1. 由 root 安装/修复脚本或可信越狱包安装阶段部署 Helper 二进制、launchd plist 和 manifest。
2. manifest root:wheel 0600；launchd plist root:wheel，权限按设备 launchd 规则验证。
3. 包 postinst 不直接假设可成功 bootstrap；首次启动/启用由明确的 root 安装步骤处理。
4. 卸载时先停止/bootout 服务，再验证 socket 路径确为 FilterKit socket 后删除；只清理 FilterKit 自己的 Helper/manifest/log/staging，不扫描或删除其他越狱目录。
5. CDHash 变化时停止服务并进入带外修复/重新钉指纹流程；不能由 App 请求“信任当前新 hash”。

这些步骤尚未在 Dopamine RootHide / Rootless 真机执行。

## 4. 官方资料核对

- Apple XNU `sys/un.h` 将 `SOL_LOCAL` 定义为 0、`LOCAL_PEERPID` 定义为 0x002；P1-20 Darwin socket 代码按此实现。参考：<https://www.newosxbook.com/src.php?file=%2Fbsd%2Fsys%2Fun.h&tree=xnu>
- Apple XNU `kern_proc.c` 的 `CS_OPS_CDHASH` 分支读取代码目录 hash，并要求输出长度匹配 CDHash 长度；`codesign.h` 定义 `CS_OPS_CDHASH = 5`。参考：<https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_proc.c>、<https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/codesign.h>
- Apple launchd plist man page 将 KeepAlive 定义为持续运行/条件运行策略，并说明 ThrottleInterval 默认通常为 10 秒。参考：<https://github.com/apple-oss-distributions/launchd/blob/main/man/launchd.plist.5>

这些是 XNU/launchd 上游定义，不等于 Dopamine RootHide / Rootless 的设备权限、csops 可用性或进程签名行为已经验证。

## 5. 对照缺口

| 项目 | P1-20 状态 |
|---|---|
| AF_UNIX client | 已实现 POSIX transport |
| AF_UNIX server | 已实现通用 listener/connection handler；尚未编入 root Helper target |
| length-prefix framing | 已实现并复用 P1-19 codec |
| nonce handshake | 已实现双端状态机，每连接新 nonce |
| getpeereid | Darwin 分支已接入，未在 iOS SDK/设备编译验证 |
| LOCAL_PEERPID | Darwin 分支已接入，常量依据 XNU 源码，未真机验证 |
| Linux SO_PEERCRED | 已用于本地 socket smoke test |
| csops CDHash | Darwin provider 已写，未在 iOS 越狱设备验证 |
| 双端 CDHash pinning | client/server trust evaluator 接口已接入；真实 manifest 供给和启动注册未完成 |
| Helper self-CDHash gate | 校验入口已实现；尚无 Helper main 启动流程调用它 |
| audit token / pidversion | 未实现；Unix socket 不直接提供 audit token |
| replay guard | server 已接入进程内 10 分钟/4096 项同步守卫；跨进程重启持久化未实现 |
| 并发限制 | server 连接数上限已实现 |
| 设备审计持久化 | 仅结构与 sink protocol；未实现 root-owned writer/rotation |
| launchd KeepAlive/Throttle | 已形成规格模型；无 plist |
| stale socket cleanup | 明确拒绝自动 unlink；需要安装器做安全清理 |
| install/uninstall/re-pin | 规格已写；未实现脚本/设备流程 |
| 实际 root copy/remove | 未实现，执行仍关闭 |

## 6. 安全限制

- 不能因 AF_UNIX socket 可连接就信任调用者。
- 默认 identity provider 会拒绝所有连接；必须提供经设备验证的 peer identity provider 与 pinned CDHash policy。
- `csops` 的可用性、权限和结果必须在 RootHide 与 Rootless 分别测试。
- peer PID + csops CDHash 不是 audit-token 原子身份；未补齐 pidversion/audit token 前，特权执行不得开放。
- `HelperAuditSink` 目前只是协议，不能称为已持久化审计日志。
- server 是可复用的 POSIX listener 类，不是已经安装的 root daemon。
- `executionReleased` 与 manifest `executionEnabled` 均保持关闭。
