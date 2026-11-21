# R3-B D-R2-05 既有签名修复验收准备记录

> 线 B 独立记录，对应 `Spec/Stage-2/DEB-Install-Crash-Investigation.md`。
> 本轮定位：验证既有签名链路是否在安装/启动链路成立；**不重新开发签名模块**，不放宽签名校验。
> 基线：本地 HEAD 以提交时 `git log` 为准；本机 Linux 无 ldid/otool/Xcode，脚本仅做 `bash -n` 静态语法核对，签名/安装/启动结论以 Runner 与真机复测为准。

## 1. 既有签名链路盘点（已实现，本轮未改）

| 环节 | 位置 | 本轮静态核对 |
|---|---|---|
| ldid 签名脚本（嵌套先签、主程序后签） | `scripts/sign-app-ldid.sh` | `bash -n` 通过 |
| 主程序候选 Entitlements 嵌入 | `scripts/sign-app-ldid.sh`、`Config/Signing/FilterKit.entitlements` | 候选键清单，未验证可用 |
| 签名后 Entitlements 精确比对 | `scripts/validate-ldid-signature.sh` | `bash -n` 通过 |
| 全 Mach-O `LC_CODE_SIGNATURE` / CDHash 检查 | `scripts/validate-ldid-signature.sh` | `bash -n` 通过 |
| DEB 静态结构与解包复验 | `scripts/validate-deb.sh` | `bash -n` 通过 |
| DEB 打包（RootHide rootfs 布局、候选包命名） | `scripts/package-deb.sh` | `bash -n` 通过 |
| IPA 结构校验 | `scripts/validate-ipa.sh`、`scripts/package-ipa.sh` | `bash -n` 通过 |
| CI 候选签名 DEB job | `.github/workflows/filterkit-build.yml`（ldid 安装 → 签名 → 候选 DEB → 解包复验 → 归档） | 步骤在位，最新 Runner 结果待下一轮日志 |
| CI Entitlements 静态准备 job | 同上 `signing-prep` 段 | 步骤在位 |

## 2. 验收表（条件与当前状态）

| 验收项 | 通过条件 | 当前状态 |
|---|---|---|
| macOS Runner 构建 | Swift 构建成功 | 待下一轮 Runner 日志 |
| iOS Device 构建 | iphoneos Release 构建成功 | 待下一轮 Runner 日志 |
| iOS Simulator 构建 | arm64、x86_64 均构建成功 | 待下一轮 Runner 日志 |
| 签名验证 | 所有目标 Mach-O 通过 `validate-ldid-signature.sh` | 待 Runner 签名 job 日志 |
| Entitlements | 主程序嵌入键与候选 plist 精确匹配 | 待 Runner 签名摘要 |
| DEB 解包复验 | 解包后逐 Mach-O 签名/CDHash 复验成功 | 待 Runner DEB 复验摘要 |
| 真机安装 | RootHide 环境实际安装成功 | **pending（无设备证据）** |
| 首次启动 | 安装后无闪退、界面可达 | **pending（无设备证据）** |
| 重启后启动 | 重启后仍能正常启动 | **pending（无设备证据）**

最后三项无真机证据前不得标记通过；CI 绿灯不等于安装/启动验收通过。

## 3. 闪退假设取证顺序（仅在真机仍闪退时启用）

1. 先收集 `.ips` / 系统日志；无日志不猜测 C1～C5 根因。
2. 按 H4（架构/弱链接/RPATH/依赖）→ H5（JBROOT 映射/Bundle 路径/uicache）→ C1（启动失败）→ C2（dylib 加载失败）→ C3（Entitlements 与签名）→ C4（权限与布局）→ C5（自身初始化）分类归档。
3. 不为消除错误而放宽签名校验、不绕过 entitlement 检查、不伪造弱链接符号。

## 4. 本轮边界

- 不重写 `sign-app-ldid.sh` / `validate-ldid-signature.sh` / DEB 打包路径；除非 Runner 暴露可复现的具体错误并单独授权。
- 不安装、不启动 App/Helper、不发起 IPC、不调用 `launchctl`、不注入、不启用常驻 daemon。
- 不把静态签名自洽记录为 amfid/Bootstrap 接受证据。
