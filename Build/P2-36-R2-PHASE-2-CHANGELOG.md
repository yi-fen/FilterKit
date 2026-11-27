# P2-36-R2 Phase 2 Changelog

- 扩展 `HelperPluginFilterConfigurationTransactionTests`：覆盖六个 Journal 阶段、正常提交、Filter.plist 字节保持、未知文件修改 fail-closed、恢复幂等性。
- 扩展 `HelperIPCAndPolicyTests`：覆盖完整软关联集合请求 IPC 往返、旧版逐 App 请求兼容解码、尾随字节拒绝。
- 新增 `Build/Host/P2-36-R2-Transaction-Smoke.swift`：独立 Host 可执行测试，包含 SIGKILL 子进程终止与父进程跨进程恢复。
- 新增 `Build/scripts/p236r2_phase2_transaction_audit.py`：17 项静态审计。
- 新增 `Build/Host/run-p236r2-phase2-host-smoke.sh`：执行审计、Swift 语法解析、Helper 目标源文件语义类型检查和事务 Host Smoke。
- 新增 `Build/Host/run-p236r2-phase2-xcode-tests.sh`：macOS/Xcode XCTest 执行入口。
- 新增 `Build/Host/run-p236r2-phase2-transaction-tests.sh`：统一入口；无 Apple 工具时明确标记 XCTest 跳过。
- 修正 Helper 授权逻辑中的 trailing-closure 编译警告。
- App 与 Helper 生产 Release Gate 维持关闭。
