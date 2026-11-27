# P2-37-R8 验证报告

## 当前执行环境

- Host: Linux x86_64
- Swift: 6.2.1 (`x86_64-unknown-linux-gnu`)
- Xcode / xcodebuild: 不可用
- XcodeGen: 不可用
- Apple iOS SDK / Simulator: 不可用
- 已连接 RootHide / ElleKit 设备: 未测试

## 本地可执行验证

| 项目 | 结果 |
|---|---:|
| R8 Apple readiness audit | **17/17** |
| R7 APP activation flow audit | **22/22** |
| R6 two-file transaction audit | **22/22** |
| R5 Helper IPC audit | **21/21** |
| R4 activation protocol audit | **15/15** |
| R3 activation consistency audit | **25/25** |
| R2 Helper identity audit | **29/29** |
| P2-36-R2 transaction audit | **17/17** |
| P2-36-R2 IPC integration audit | **18/18** |
| P2-36-R2 Apple Gate audit | **13/13** |
| R3 Activation Consistency Host Smoke | **11/11** |
| P2-36-R2 Transaction Host Smoke | **PASS**：Journal 六阶段恢复、双文件提交、外部篡改拒绝、SIGKILL 进程死亡恢复、IPC 兼容性、生产 Gate |
| Helper source-set semantic typecheck | **PASS**（Linux Swift 6.2.1，按 Project.yml 补齐 Helper target 源文件） |
| Swift frontend parse | **PASS**（Sources/App/HelperRuntime/Tests；Build/Host 文件逐个 parse） |
| Shell syntax | **PASS**（R8 新增两个脚本） |
| Project.yml YAML parse | **PASS** |
| Localization | en 422 keys / zh-Hans 422 keys；重复键均 0 |

## 历史脚本注意事项

旧聚合入口 `run-p236r2-phase2-host-smoke.sh` 在 Swift 6.2 下会把多个含顶层表达式的历史 Host Smoke 文件合并编译，触发 `expressions are not allowed at the top level`。本轮分别运行 R3 Activation Consistency Host Smoke 和 R6 Transaction Host Smoke 均通过，但未将旧聚合脚本标记为通过。

部分 R1/R2 原始静态审计仍保留早期 preview-only UI 断言，与 R7 已接入的 Prepare/Commit UI 流程不一致。当前回归采用 R7 维护后的 APP flow audit，以及 R6/R5/R4/R3 对应审计；旧断言失败不被隐藏，也不作为当前阶段通过依据。

## Apple 平台验证状态

| 项目 | 状态 |
|---|---|
| XcodeGen project generation | NOT RUN — Linux host |
| Darwin iPhoneOS SDK probe | NOT RUN — no Apple SDK |
| Darwin Simulator SDK probe | NOT RUN — no Apple SDK |
| Helper Simulator build | NOT RUN — no Xcode |
| App Simulator build | NOT RUN — no Xcode |
| Apple XCTest Runner | NOT RUN — no Xcode |
| Generic iPhoneOS Helper/App build | NOT RUN — no Xcode |
| Signed App/Helper signature inspection | NOT RUN — no codesign / signed artifacts |
| LOCAL_PEERTOKEN + csops runtime | NOT RUN — requires signed device deployment |
| RootHide / ElleKit device validation | NOT RUN |
| Device-level transaction/recovery | NOT RUN |

## 交付内容

- `Build/Host/run-p237r8-apple-validation.sh`：macOS Apple SDK 构建与 XCTest 执行入口。
- `Build/Host/verify-p237r8-signed-artifacts.sh`：已签名 App/Helper 静态签名检查。
- `Build/scripts/p237r8_apple_readiness_audit.py`：Apple 验收准备静态审计。
- `Build/DeviceAcceptance/P2-37-R8-DEVICE-ACCEPTANCE.md`：设备验收步骤与证据要求。

## 安全结论

R8 完成了 Apple 平台验收准备和可重复执行脚本，但不是 Apple 平台验收完成。Linux 静态审计/Host smoke 不能替代 Xcode 编译、Apple XCTest、真实签名 IPC 或越狱设备验收。

APP `appPluginActivationCommitReleased` 仍为 `false`；Helper `activationCommitExecutionEnabled` 默认仍为 `false`。没有执行生产 Commit，也没有修改越狱文件。生产写入 Gate 必须继续关闭。
