# P2-37-R8 验收清单

## 已在当前 Linux 环境完成

- [x] R8 Apple readiness static audit 17/17。
- [x] R7 APP activation flow audit 22/22。
- [x] R6 two-file transaction audit 22/22。
- [x] R5 Helper IPC audit 21/21。
- [x] R4 activation protocol audit 15/15。
- [x] R3 activation consistency audit 25/25。
- [x] R2 Helper identity audit 29/29。
- [x] P2-36-R2 transaction audit 17/17。
- [x] P2-36-R2 IPC integration audit 18/18。
- [x] P2-36-R2 Apple Gate audit 13/13。
- [x] R3 activation consistency Host Smoke 11/11。
- [x] P2-36-R2 transaction Host Smoke：Journal 六阶段恢复、双文件提交、外部篡改拒绝、SIGKILL 恢复、IPC 兼容性和 Gate 检查通过。
- [x] Helper source-set semantic typecheck（Linux Swift 6.2.1，补齐 Project.yml 中 Helper target 所需模型源文件后通过）。
- [x] Swift frontend parse：Sources/App/HelperRuntime/Tests；Build/Host Swift 文件逐个 parse。
- [x] 两个新增 shell 脚本 `bash -n` 通过。
- [x] Project.yml YAML parse 通过。
- [x] en / zh-Hans 各 422 个 localization keys，重复键 0。
- [x] R8 readiness audit 二次执行通过。

## 已知历史脚本问题

- 旧聚合脚本 `run-p236r2-phase2-host-smoke.sh` 会把多个含顶层表达式的历史 Host Smoke 文件一起传给 Swift 6.2 编译，触发 `expressions are not allowed at the top level`。这是旧聚合入口的编译组织问题；本轮独立运行 R3 Host Smoke 和 R6 transaction Host Smoke 均通过。未将旧聚合脚本标记为通过。
- R1/R2/R3 原始历史审计脚本中有少量断言仍要求早期“preview-only”界面行为；R7 已将这些检查更新到 `p237r7_activation_app_flow_audit.py`。因此 R1/R2 旧脚本的失败断言不作为当前 R7+状态的验收依据，使用 R7/R6/R5/R4/R3 对应回归审计。

## 必须在 macOS/Xcode 环境完成

- [ ] XcodeGen 工程生成。
- [ ] Darwin iPhoneOS 与 Simulator SDK probes。
- [ ] Helper Simulator build。
- [ ] App Simulator build。
- [ ] Apple XCTest Runner 全量执行并保存 `.xcresult`。
- [ ] generic iPhoneOS Helper/App Release build。
- [ ] 已签名 App/Helper `codesign --verify`、TeamIdentifier、CDHash、entitlements 检查。
- [ ] 真机 `LOCAL_PEERTOKEN` / `csops` / audit-token 运行时验证。
- [ ] Helper 重启、IPC 超时、重放、并发篡改与事务恢复设备测试。
- [ ] RootHide / ElleKit 只读预检。
- [ ] 隔离设备双文件事务验收与 proof 哈希核对。

## Release Gate

- [x] APP Commit Gate 保持关闭。
- [x] Helper activation commit execution 默认关闭。
- [ ] 不允许以本清单的静态/Host 检查结果批准生产写入。
