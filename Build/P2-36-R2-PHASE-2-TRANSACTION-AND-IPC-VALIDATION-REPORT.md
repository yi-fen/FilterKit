# P2-36-R2 Phase 2 — 双文件事务运行测试与 IPC 编码验证报告

## 结论

Phase 2 的 Host 级事务和 IPC 编码验证已执行通过。验证基于隔离的临时目录，实际运行 Helper 目标源文件集合编译出的 Host Smoke，不触碰越狱目录，不通过生产 IPC 请求开放写入。

- 静态审计：17/17 通过。
- Swift 源码与测试文件语法解析：通过。
- FilterKitHelper 目标源文件集合（Host Swift 6.2.1）语义类型检查：通过。
- 双文件事务 Host Smoke：通过。
- SIGKILL 子进程崩溃后由父进程恢复：通过。
- IPC Envelope 与完整软关联请求编码/解码：通过。
- 旧版逐 App 请求（不包含 `desiredSoftAssociations`）解码兼容：通过。
- App / Helper 两个生产 Release Gate：均保持 `false`。

## 覆盖范围

### Journal 阶段

针对以下六个持久化阶段逐一执行故障注入，并检查恢复结果：

1. `prepared`
2. `staged`
3. `backedUp`
4. `replacingPlist`
5. `replacingManifest`
6. `committed`

非 committed 阶段恢复为两份原始文件；`committed` 阶段保留两份新文件。所有恢复结束后 Journal 均清除。

### 双文件事务

- 正常提交后 Manifest 更新成功。
- 软关联集合修改保持 `Filter.plist` 原始字节不变。
- 收据中的 Plugin ID 和两个文件 SHA-256 与实际结果一致。
- 对目标文件注入外部/未知字节后，恢复返回 `manualIntervention`，保留未知字节，不覆盖未知修改。
- 重复调用恢复在 Journal 已清除后返回无待恢复事务，表现为幂等。

### 真实进程终止与恢复

Host Smoke 启动独立子进程，在 `replacingManifest` 阶段边界完成 Journal 持久化后向子进程发送 `SIGKILL`。父进程随后重新创建事务对象，读取遗留 Journal 并执行恢复，确认 `Filter.plist` 与 Manifest 均恢复到原始字节。

这证明了跨进程重启边界的阶段恢复路径；它不等同于设备掉电、文件系统缓存丢失或存储介质故障测试。

### IPC 编码

- `HelperIPCFrameCodec` UInt32 big-endian 长度前缀与 JSON Envelope 往返。
- `replaceSoftAssociations` 完整请求（包括 `desiredSoftAssociations`）往返。
- 旧版逐 App 请求省略可选 `desiredSoftAssociations` 后仍可解码。
- 多余尾随字节被拒绝。

本阶段没有启动真实 AF_UNIX socket，也没有执行 App 与已签名 Helper 进程之间的端到端认证/传输测试。

## Release Gate

以下值保持关闭：

```swift
HelperDeploymentCoordinator.pluginAssociationCommitReleased = false
HelperRequestDispatcher.pluginAssociationCommitReleased = false
```

Host Smoke 直接调用事务对象，只在 root-owned 临时目录和测试数据上运行；它没有经过生产 Dispatcher 的 Commit 分支。生产 Dispatcher 在调用事务前仍检查独立 Release Gate。

## 尚未完成的验收

当前运行环境为 Linux + Swift 6.2.1，不具备 Xcode、Apple iOS SDK、`xcodebuild` 或 XcodeGen。因此：

- 本报告不是 iOS SDK / Xcode 编译通过报告。
- 新增 XCTest 尚未由 Xcode XCTest Runner 执行。
- 未验证 iOS 设备上的文件系统语义、签名 Helper、RootHide/ElleKit 环境、真实 IPC peer identity、设备断电恢复或真实越狱目录权限。
- 未开放任何生产写入能力。

## 运行命令

跨平台 Host 验证：

```bash
Build/Host/run-p236r2-phase2-host-smoke.sh
```

macOS 上补充执行 Xcode XCTest：

```bash
Build/Host/run-p236r2-phase2-xcode-tests.sh
```

一体化入口：

```bash
Build/Host/run-p236r2-phase2-transaction-tests.sh
```
