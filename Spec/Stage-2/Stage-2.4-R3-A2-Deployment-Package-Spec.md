# Stage 2.4 R3-A2 — RootHide 测试部署包规格（冻结）

> 授权依据：用户两份 R3 建议稿（批次连续推进 / DEB 部署口径）。本规格为 **R3-A2 部署包批次** 的离线规格冻结，承接 `Stage-2.4-R3-Device-Validation-Plan.md` §2。
>
> **本轮边界**：只冻结包结构、命名/路径策略、签名与 entitlement 方案、control/postinst 口径、静态检查与元数据口径；**不编写落盘安装脚本、不在本机或 Runner 产出可安装 DEB/IPA、不签名、不真机安装**。真实安装、uicache 注册、App 启动与权限验证属于 R3-B 及以后真机批次。

## 1. 定位与交付物

### 1.1 两种安装载体

| 载体 | 定位 | 是否 R3 完成条件 |
|---|---|---|
| `FilterKit.deb` | RootHide 正式真机测试载体（Bootstrap / dpkg 通道），优先验证 | R3-B～E 真机门禁的主载体 |
| `FilterKit.ipa` | 普通安装方式对照测试，可选辅助对象 | 不要求 IPA 路径通过才完成 R3 |

- DEB 安装成功 **不等于** App 获得 JBROOT 访问权限；安装位置、代码签名、entitlement、sandbox 是四个分别验证的问题（沿用 Dev-Preparation §6.1 边界）。
- 真机权限结论只能来自 FilterKit GUI 进程内取证；SSH / 越狱终端 / CLI / Runner / Simulator 结果不得写入 GUI 门禁。

### 1.2 部署形态（通道与权限解耦，承接 R3 计划 §3.1）

| 形态 | 说明 | R3 口径 |
|---|---|---|
| A 普通 IPA | 默认沙盒，不假设可读 JBROOT | 对照基准，不作为权限通过前提 |
| B 特殊权限 App | 携带额外 entitlement / 平台能力的权限形态 | 最终方向之一，可行性待真机证据 |
| C Bootstrap 安装通道 | 经越狱包管理通道装入 JBROOT 的安装通道 | 与 B 互补，不代表权限放行 |
| **B+C** | 经 Bootstrap（DEB）安装的特殊权限 App | **优先验证**，但未取证前不认定为最终方案 |

最终形态由真机证据决定；不得因 DEB 装上、uicache 注册成功、App 能启动，推断 B 形态权限已放行。

## 2. DEB 包结构（建议结构，最终路径/脚本结合实际 RootHide 环境确定）

```
FilterKit.deb
├── Applications/
│   └── FilterKit.app/
│       ├── FilterKit                 # 主二进制（Swift）
│       ├── Info.plist
│       ├── Frameworks/               # 内嵌动态库/资源（若有）
│       └── embedded resources
└── DEBIAN/
    ├── control                       # 最小化包元数据（§4）
    └── postinst                      # 安装后注册（§5，本轮不落地）
```

- 安装位置优先评估 `<JBROOT>/Applications/FilterKit.app`；**不得未经验证硬编码某个 JBROOT 绝对路径**。
- Theos 侧 `INSTALL_PATH := /Applications` 为包内相对根，不写死设备 JBROOT 前缀；现有 `Makefile` 草稿口径见 §7 现状。
- App 内部资源、Frameworks 与 rpath 方案待 R3-B 构建批次按目标 SDK/链接方式核实，本规格不预设。

## 3. 命名、版本与架构（草案口径，R3-B 前定值）

| 项 | 现有草案 | 状态 | 冻结口径 |
|---|---|---|---|
| Bundle ID（Package 字段） | `com.filterkit.manager`（`project.yml` / `control` 占位） | 未冻结，承接 Stage-2.1 B3 | R3-B 前命名确认；包内 `CFBundleIdentifier` 与 `control` Package 字段一致 |
| 版本 | `0.0.1` / Build 1 | 占位 | 遵循 0.0.x 递增；R3 真机基线单独记录 `filterKitCommitSHA` + `filterKitBuildNumber` |
| 架构 | RootHide `arm64e arm64`；Rootless `arm64` | 基线口径（Dev-Preparation §4） | 按路线矩阵分别构建；control `Architecture` 与二进制实际架构一致 |
| Deployment Target / MinimumOSVersion | 草案 iOS 17.0；官方 Manager 参照 15.0 | 未冻结，承接 Stage-2.1 B2 | 取设备/框架/SDK 兼容交集；既有缺口：无 17.x SDK，16.5 SDK 对 iOS 17.0.2 向下兼容待实测，不为 CI 绿抬高/压低 |

## 4. DEBIAN/control 最小口径

本轮仅冻结字段口径；现有仓库根 `control` 为草稿占位，**本轮不改写落盘**。

| 字段 | 口径 |
|---|---|
| `Package` | 与 App `CFBundleIdentifier` 一致（§3 草案 `com.filterkit.manager`） |
| `Name` | `FilterKit` |
| `Version` | 语义版本，与 `MARKETING_VERSION` 一致；构建号另入元数据，不写入 control Version |
| `Architecture` | 与实际二进制架构一致；双路线分别打包 |
| `Maintainer` | 维护者摘要 |
| `Description` | 只读插件管理器；不含写入/启停/注入功能（与现状描述一致） |
| `Section` | `Applications`（沿用现有草案） |
| `Depends` | 占位；RootHide / ElleKit / bootstrap 依赖版本须经目标环境核实后再填，**不凭猜测写死依赖** |

- control 不携带权限声明；entitlement 属于二进制签名层（§6），不在 control 表达。
- 不新增 postrm / preinst 等脚本；卸载流程仅在 §8 说明口径内评估。

## 5. postinst 安全设计（本轮不落地脚本）

- **允许的唯一动作**：安装后注册 App 到系统 LaunchServices，参照官方 Manager 口径 `uicache -p <App 相对路径>`；具体命令与路径以真机 bootstrap 环境核实为准。
- **禁止动作**（贯穿 R3 只读边界）：
  - 不安装/卸载/启停插件；不修改 plist、dylib、注入规则；
  - 不写越狱目录、不改软链、不执行 dpkg/apt 写操作；
  - 不修改系统配置、不创建常驻 daemon、不注册后台服务；
  - 不在脚本内做权限放行或 entitlement 补签。
- 脚本失败须可追溯：注册命令退出码与输出入证据；注册失败不掩盖为安装成功。
- 真实脚本落地属于后续部署实现批次，须在部署形态冻结、签名方案核实后单独授权。

## 6. 签名与 entitlement 方案（候选清单，不推定放行）

### 6.1 候选 entitlement（来源：官方 RootHide Manager 解包 / 旧 0.1.18 PoC 参考，Dev-Preparation §6.2）

| 候选键 | 用途假设 | 证据状态 |
|---|---|---|
| `platform-application` | 平台应用标识 | 候选；运行时是否被 amfid/签名链放行待真机核实 |
| `com.apple.private.security.no-sandbox` | 关闭沙盒 | 候选；出现于签名 ≠ 系统放行 |
| `com.apple.private.security.storage.AppBundles` | 访问 App Bundles 存储域 | 候选 |
| `com.apple.private.security.storage.AppDataContainers` | 访问 App 数据容器域 | 候选 |

- 旧 PoC 结论不作新基线；BaseBin 守护进程更强 entitlement（`no-container`、`task_for_pid-allow`、`system-task-ports` 等）仅供参照，不等同 App 可用。
- 签名方式（开发者证书 / ldid 授权）待真机环境核实；私有 entitlement 是否被签名工具保留、是否被 bootstrap 签名链认可，均为独立待验证项。
- **边界沿用 R1-B 结论**：iOS GUI 进程无公开稳定的运行时 entitlement 枚举 API；现有 `EntitlementInspecting` / `CodeSignInspecting` 接缝保持占位 unavailable/unknown。签名产物中存在某键，不能推断运行时获得对应权限。

### 6.2 签名取证口径（真机/Runner 后续批次）

- 可对构建产物执行 `codesign -d --entitlements :- FilterKit.app` 取证（可用性以 Runner 环境为准）；备选解析 `embedded.mobileprovision` 的 `Entitlements` 段。
- 证据仅证明签名产物声明了哪些 entitlement；runtime 放行与资源访问结果另立独立证据（G13）。

## 7. 仓库现状核对（本轮不改）

| 文件 | 现状 | 本轮动作 |
|---|---|---|
| `control` | 草稿占位：Package `com.filterkit.manager`，Version `0.0.1`，Architecture `arm64e`，Depends 空 | 保持占位，不改写 |
| `Makefile` | Theos application 模板草稿；`TARGET := iphone:clang:latest:15.0`，`INSTALL_PATH := /Applications`，`ARCHS := arm64e arm64`；Swift 工具链/rpath/Bundle ID 待确认 | 保持草稿；双路线 scheme/SDK 口径沿用 Dev-Preparation §4 |
| `project.yml` | Bundle ID 草案 `com.filterkit.manager`，deploymentTarget iOS 17.0，Swift 5.0 | 保持草案；B2/B3 未冻结 |
| `reference/0.1.18-src/entitlements.plist` | 旧 PoC 四枚 entitlement 参考 | 仅参考，不复制为新基线 |

## 8. 设备安装 / 卸载说明口径（R3-B 真机批次执行，本轮不执行）

### 8.1 安装与启动顺序

1. RootHide 越狱环境正常启动；冻结设备与系统版本、ElleKit 版本；
2. 冻结 FilterKit 部署形态（§1.2）与代码基线（commit SHA / Build Number / Bundle ID）；
3. 传输并经 Bootstrap / dpkg 安装 DEB；
4. postinst 完成 uicache 注册；
5. **从 iOS 主屏幕真正启动 FilterKit**，确认 GUI 进程运行正常；SSH 启动 CLI 不算 GUI 进程验证；
6. 在 GUI 进程上下文执行 PermissionProbe，按 R3 计划 §4 矩阵取证。

### 8.2 卸载口径

- 经 dpkg 通道移除包；记录移除后 App 容器、注册项与残留状态（只读记录，不手工清理）。
- 卸载不影响既取证证据归档；不把卸载操作作为探针能力的一部分。

## 9. CI 静态检查口径（后续部署构建批次，不在本机执行）

R3-A2 规格冻结后，后续可在 macOS Runner 做 **离线静态检查**（不连真机）：

1. 包目录结构符合 §2；`DEBIAN/control` 字段齐全且与 §3 一致；
2. 二进制架构、`CFBundleIdentifier`、`CFBundleVersion` 与元数据一致；
3. 签名/entitlement 清单可被解析并归档（声明层，不判 runtime 放行）；
4. 生成构建元数据：`commitSHA`、`buildNumber`、`bundleID`、`scheme`（roothide/rootless）、`ARCHS`、`SDK`、`builtAt`、`artifactSHA256`；
5. DEB 归档完整性（`dpkg-deb --info` / 解包结构核对）与 SHA256 记录。

静态检查通过 **不构成** 真机安装成功或权限放行证据；真机安装/uicache/启动/访问能力仍归 G10～G15 门禁。

## 10. 未决与禁止事项

### 10.1 待真机/目标版本核实

- 部署形态最终选择（A / B / C / B+C）；B+C 组合中 entitlement 是否真正生效；
- 实际签名工具链与签名链对私有 entitlement 的放行情况；
- DEB 内 App 安装绝对路径与 uicache 命令在目标 bootstrap 上的实际行为；
- 是否还需要 `no-container` 或额外 sandbox exception 才能访问隐藏容器；
- 16.5 SDK 对 iOS 17.0.2 向下兼容；Swift 在 Theos 下的工具链链接与 rpath。

### 10.2 本轮禁止

- 不写落盘 `postinst` / `control` 最终版；不产出可安装 DEB/IPA；不签名、不重签；
- 不在本机 Linux 云主机继续开发真机探针；不把离线静态检查结论写成真机权限结论；
- 不改冻结公共 Models、Adapter 协议、Core 业务语义；不放宽只读边界；
- 0.1-C G10 不随本批次重启复核（见 R3 计划 §7）。

## 11. R3-A2 交付与不交付

**交付**：本规格（载体定位、形态决策、包结构、命名/架构口径、control 字段口径、postinst 安全边界、entitlement 候选与取证口径、CI 静态检查与元数据口径、安装卸载说明口径）。

**不交付**：可安装包；安装脚本；签名产物；真机安装/注册/启动/权限结论；部署形态最终拍板。相关结论在部署形态冻结与真机取证后，按 R3-B～F 批次独立留证。
