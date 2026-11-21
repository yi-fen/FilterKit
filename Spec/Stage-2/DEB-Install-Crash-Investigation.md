# D-R2-05：DEB 安装与启动验收（Signing Fix Verification）调查记录与冻结规格

> 线 B 独立文档，与线 A 诊断引擎规格（`Stage-2.6-D-R2-03-04-Diagnostics-Engine-R3-Plan.md`）分别提交、分别回退。
> 输入基线：本地 HEAD `624ca8b`；DevDocs 包 2156 文件 / 15,121,424 B / SHA256 `a30ca00f3db6b8d0b4736af4e8d9f8088532eb501a23e0b1e869b8c56892e950`。
> 定位修正：本任务**不是**「重新开发签名模块」，而是**验证已完成的签名修复在安装/启动链路是否真正成立**；只有真机仍然闪退时，才进一步调查 Mach-O / RPATH / JBROOT / uicache / 应用自身初始化问题。

## 1. 状态区分：已完成的签名链路 ≠ 已证明闪退根因消除

### 1.1 已完成的签名流程代码修复（既有实现，本轮不重写）

| 环节 | 现状 | 位置 |
|---|---|---|
| ldid 签名脚本 | 已实现；嵌套 Mach-O 先签名，主程序最后签名 | `scripts/sign-app-ldid.sh` |
| Entitlements 嵌入 | 主程序嵌入候选 Entitlements；后续调整为嵌套 Mach-O **不带**主程序 Entitlements，仅主程序注入候选 plist | `scripts/sign-app-ldid.sh`、`Config/Signing/FilterKit.entitlements` |
| 签名后精确比对 | 签名后提取实际 Entitlements 与源 plist 精确比较 | `scripts/validate-ldid-signature.sh` |
| Mach-O 签名结构检查 | 检查所有 Mach-O 的 `LC_CODE_SIGNATURE` 与 CDHash 提取 | `scripts/validate-ldid-signature.sh` |
| DEB 解包后复验 | 解包后重新验证签名（确保签名不是只在打包前有效）；静态结构校验沿用 DEB 校验脚本 | `scripts/validate-deb.sh`、`scripts/validate-ldid-signature.sh` |
| 候选包机制 | `.ldid-signed-candidate.deb` 候选包；CI 增加 ldid 安装、签名、验证与日志归档 | CI 工作流 + 脚本 |
| 验证委托 | 签名与验证分离，委托独立脚本；脚本不安装、不启动、不通信 | 同上 |

### 1.2 尚未证明的事项（不得标记为真机验收通过）

| 待证项 | 状态 | 证据要求 |
|---|---|---|
| ldid 签名脚本 | 已实现 | 静态脚本存在且可执行 |
| Entitlements 精确比对 | 已实现 | 静态比对通过记录 |
| `LC_CODE_SIGNATURE` 检查 | 已实现 | 静态检查记录 |
| CDHash 检查 | 已实现 | 静态检查记录 |
| DEB 解包后复验 | 已实现 | 解包复验记录 |
| CI 真实签名结果 | **待确认最新 Runner** | 新一轮 Runner 签名/验证 job 日志 |
| RootHide 真机安装 DEB | **待验证** | 设备安装记录 / 包管理器日志 |
| 真机启动 App | **待验证** | 启动成功证据（进程存活 / 界面可达） |
| 重启后仍能启动 | **待验证** | 重启后再次启动证据 |

口径：签名流程修复完成，不等于 RootHide / amfid 接受该签名，不等于真机安装成功，不等于安装后可启动，不等于重启后可启动。`Config/Signing/FilterKit.entitlements` 为候选键清单，本身标注「未验证，不作可用签名方案」；entitlement 出现在签名中 ≠ 运行时获得权限。

## 2. 调查分组（H4 / H5 / C1 ～ C5）

现有设备现象：IPA 可启动，DEB 打开闪退；无 `.ips` / 系统日志。以下分组为待证假设，**无日志证据前不判定根因归属**。

| 分组 | 调查范围 | 本轮静态检查 | 待设备取证 |
|---|---|---|---|
| H4 | Mach-O 架构、弱链接、RPATH、动态库依赖 | 主程序与嵌套 dylib 的 arm64/arm64e 切片、文件类型、`LC_BUILD_VERSION`、`LC_LOAD_DYLIB`、`LC_LOAD_WEAK_DYLIB`、`LC_RPATH` | 真机加载期 dyld 报错 |
| H5 | JBROOT 映射、Bundle 路径、uicache | Bundle 内主程序路径、资源相对路径、RootHide 容器映射口径；uicache 注册状态无静态证据，挂起 | 设备 uicache / 路径解析日志 |
| C1 | 进程启动失败 | 主程序可执行位、`CFBundleExecutable` 指向、启动早期崩溃静态线索 | 进程退出码 / 启动期 `.ips` |
| C2 | 动态库加载失败 | 嵌套 dylib 清单、依赖链、弱链接缺失口径 | dyld 加载失败日志 |
| C3 | Entitlements 与签名 | 沿用既有签名/比对/CDHash 检查；候选 entitlement 键与实际嵌入键对照 | amfid / Bootstrap 接受证据 |
| C4 | 文件权限和目录布局 | DEB 解包后目录归属、权限位、可执行位、嵌套 Framework/dylib 摆放 | 设备文件系统实测 |
| C5 | 应用自身初始化异常 | 启动期初始化路径静态走查（不启动进程） | 初始化阶段崩溃 `.ips` |

## 3. 优先增加的自动静态检查

### 3.1 Mach-O 架构检查

对主程序与每枚嵌套动态库逐项记录：

- 架构切片：arm64 / arm64e（fat 包逐切片列出；缺失切片单独记录，不强制 arm64e）。
- 文件类型：可执行 / dylib / Framework / 其他。
- `LC_BUILD_VERSION`：最低系统版本与平台。
- `LC_LOAD_DYLIB`：强依赖链。
- `LC_LOAD_WEAK_DYLIB`：弱依赖与缺失风险。
- `LC_RPATH`：运行时搜索路径与 JBROOT 相对口径。

本机 Linux 无 `otool` / `lipo`；静态检查脚本在 Runner（macOS Apple 工具链）执行，本机仅做脚本 `bash -n` 与结构核对。

### 3.2 签名检查（沿用既有脚本，不重写）

- 继续使用 `scripts/sign-app-ldid.sh` 与 `scripts/validate-ldid-signature.sh`。
- 增加/复核 DEB 解包后的签名复验：解包产物内每枚 Mach-O 重新跑签名结构与 CDHash 检查，确认签名不是只在打包前有效。
- 复验结论只作静态证据；不据此推断 amfid / RootHide 接受。

### 3.3 Bundle 结构检查

- `Info.plist` 存在性；`CFBundleExecutable`、`CFBundleIdentifier` 字段。
- 主程序路径与 `CFBundleExecutable` 一致。
- 嵌套 Framework、嵌套 dylib 清单与摆放位置。
- 权限位与可执行位；目录布局与 RootHide rootfs 口径一致。

### 3.4 真机日志（取证优先，无日志不猜根因）

- 可获取设备 `.ips` 或崩溃日志时，优先按真实异常堆栈定位 C1 ～ C5。
- 没有日志时：假设保持 `pending/unknown`，禁止猜测根因、禁止把静态线索写成结论。
- 日志归档到 `Tests/Stage2/evidence/` 对应 run 目录，附 METADATA（设备 iOS 版本、架构、包版本、复现步骤、日志来源）。

## 4. 证据状态口径

每条假设记录状态：`pending`（未取证）/ `unknown`（证据不足）/ `confirmed`（有直接证据支持）/ `refuted`（有证据排除）。

- 静态检查通过 = 结构与签名自洽，不等于运行时接受。
- 静态检查异常 = 待证线索，不等于根因；需设备日志或复测闭环。
- 调查完成 ≠ 闪退修复完成；修复后仍需安装、启动、重启启动三轮真机证据闭环。
- 三原则沿用：已安装 ≠ 已配置；已配置 ≠ 已加载；静态关联 ≠ 实际注入成功。

## 5. 边界与禁止项

- 不重复实现已完成的签名功能；不改动既有签名脚本语义，除非 Runner 静态检查暴露明确缺陷并单独授权。
- 不在本线引入 entitlement 放行、沙盒例外、签名绕过；不伪造弱链接符号声明。
- 不安装、不启动 App/Helper、不发起 IPC、不调用 `launchctl`、不注入、不启用常驻 daemon。
- 不写 plist / 规则、不移删 dylib、不写 dpkg、不改软链。
- 线 B 提交不夹带线 A 引擎重构；两条线独立提交、独立回退。

## 6. 提交与完成标准

| 提交 | 内容 |
|---|---|
| `deb-crash-investigation` | 本调查记录、静态检查脚本/产物、Runner 日志归档（独立提交，不混线 A） |
| `r3-acceptance-report` | R3 验收归档：线 A 回归结论 + 线 B 静态报告与真机状态回填、打包基线 |

完成标准（本轮可离线部分）：

1. DEB 静态检查有完整报告：Mach-O 架构/依赖/RPATH、签名复验、Bundle 结构、权限布局逐项有记录。
2. RootHide 安装 / 启动 / 重启启动：有真机证据则回填结论；无证据则明确标记 `pending`，不签通过。
3. 既有基线测试无回归（随线 A Runner 复测一并确认）。
4. 本机 Linux 不产出编译/签名/启动结论；iOS 双目标编译与真机行为以 Runner / 设备复测为准。

## 7. 待真机缺口（沿用既有记录，不提前关闭）

- 全量设备目录列表、plist 原文、`.version-roothide`、dpkg 全量 list、pkgmirror 性质、进程内解析接入方式。
- H4 切片/弱链接/RPATH、H5 uicache/JBROOT 映射、C1 ～ C5 真机 `.ips` 与系统日志。
- 真机门禁 G10 ～ G15、R4-G 维持 `pending/unknown`；0.1-D 未闭环不签署、不进入 0.1-E-B。
