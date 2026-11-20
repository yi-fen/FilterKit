# FilterKit 0.1-E Preflight

> 当前状态：**Preflight 准备中 / 不构成 0.1-E 发布验收**。本文件记录从 0.1-D-R4 签名候选进入 0.1-E 前必须具备的证据与门禁。`ldid-signed-candidate.deb` 不是已证明可安装的正式包。

## 1. 本轮签名修复范围

本轮只修复并增强 R4 的离线签名与 DEB 候选产物链：

1. 对设备构建产物副本执行 `ldid` 签名，不修改 Xcode 原始 unsigned build artifact。
2. App 内所有 Mach-O（主程序、Framework / PlugIns / 其他嵌套 Mach-O）必须具备 `LC_CODE_SIGNATURE`；嵌套 Mach-O 先签，主程序最后签。
3. 主程序签名时注入 `Config/Signing/FilterKit.entitlements`；签名后通过 `ldid -e` 提取实际嵌入内容，并与源 plist 结构化比较，必须完全相同。
4. `ldid -h` 对所有 Mach-O 提取 CodeDirectory hash，作为签名结构可读性证据。
5. DEB 产物必须命名为 `*.ldid-signed-candidate.deb`；不再产出看似正式可安装的普通 `.deb` 文件名。
6. CI 归档签名日志、签名摘要、DEB 验证日志、摘要与候选 DEB。

## 2. 工具链与脚本

| 项目 | 责任 |
|---|---|
| `scripts/sign-app-ldid.sh` | 对 App bundle 内 Mach-O 执行 ldid 签名，主程序注入候选 entitlements |
| `scripts/validate-ldid-signature.sh` | 检查每个 Mach-O 的 `LC_CODE_SIGNATURE`、`ldid -h` 结果，并比较主程序实际嵌入 entitlement |
| `scripts/package-deb.sh` | 仅接受已通过签名校验的 App，输出签名候选 DEB |
| `scripts/validate-deb.sh` | 解包后重新验证签名、entitlements、DEB 布局及文件 parity |
| `.github/workflows/filterkit-build.yml` | 安装 ldid / dpkg，执行签名、验证、打包与日志归档 |

CI 必需工具：`ldid`、`otool`、`file`、`python3`、`dpkg-deb`、`lipo`。缺少签名验证工具时不得将 DEB 标为静态签名通过。

## 3. 验收状态必须分层

| 状态 | 可证明内容 | 不可推导内容 |
|---|---|---|
| `ldid_signed_static_valid` | 所有扫描到的 Mach-O 有 `LC_CODE_SIGNATURE`；`ldid -h` 可提取 CodeDirectory hash；主程序嵌入 entitlement 与源文件完全一致 | RootHide / amfid 接受签名、sandbox 权限已放行 |
| `ldid-signed-candidate` | DEB 包含已静态验证的签名 App，且包结构校验通过 | dpkg 安装成功、uicache 注册成功、App 可启动 |
| `Device Install Passed` | 目标设备上实际安装、注册、冷启动与复测均通过且证据完整 | 不得仅凭 CI 结果、静态签名或模拟器结果得出 |

`deviceInstallable` 在候选阶段固定为 `false`，`deviceInstallStatus` 固定为 `not-tested`。只有独立授权并取得目标设备证据后，才可重新评估该状态。

## 4. 真机 DEB 闪退问题的剩余证据

本次签名链补齐主要针对“未签名 Mach-O / 缺失代码签名封印 / entitlement 未嵌入”这一类 C1 假设。即使静态签名通过，也不能单独证明 DEB 闪退已修复。真机验证仍需采集：

- 安装前后 DEB SHA-256、解包 App 与签名候选 App 的文件树/权限/符号链接对比；
- 设备型号、iOS 版本、RootHide / Bootstrap / ElleKit 版本及部署形态；
- dpkg 安装退出码、安装路径、`uicache` 结果；
- App 冷启动结果、进程退出状态、`.ips` / `JetsamEvent` / amfid 相关日志；
- 终止原因、崩溃线程、缺失动态库、dyld 错误与 `LC_LOAD_DYLIB` / rpath 证据；
- 同一 commit / build / bundle ID 下 IPA 与 DEB 的对照结果。

C2（Mach-O 切片、弱链接、rpath）、C3（RootHide 布局、权限、uicache / JBROOT 映射）、C4（App bundle 完整性）和 C5（应用自身异常）仍须按设备日志独立判断，不能以签名成功排除。

## 5. 进入 0.1-E 的门禁

- [ ] Source commit SHA 与构建 Runner 记录一致；
- [ ] 设备构建平台、架构、Deployment Target、Bundle ID、版本与 build number 证据完整；
- [ ] ldid 工具版本已归档；
- [ ] App 内所有 Mach-O 的 `LC_CODE_SIGNATURE` 与 `ldid -h` 均能提取 CodeDirectory hash；
- [ ] 主程序实际嵌入 entitlements 与源 plist 完全一致；
- [ ] DEB 解包后签名复验通过，source/package bundle parity 通过；
- [ ] 候选产物 SHA-256 与 CI 日志、metadata JSON 一致；
- [ ] 真机安装、注册、冷启动与复测有独立证据；
- [ ] 闪退 `.ips` / 系统日志已归档并完成 C1～C5 根因判断；
- [ ] 未完成门禁均保留 `pending` / `unknown`，不签署、不发布。

## 6. 安全边界

本批不执行真机安装，不调用 `uicache`，不写入越狱配置，不启停插件，不修改 dpkg 数据库，不移动或删除 dylib，不启动 Helper / daemon，不执行注入。`ldid` 仅修改 CI 工作目录中的 App 构建副本。Developer 证书签名路线与 ldid 路线仍然独立，不互相替代。
