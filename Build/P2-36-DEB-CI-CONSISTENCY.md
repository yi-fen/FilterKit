# P2-36 — DEB 打包 / CI 一致性修复（B1：表单选项与实际能力对齐）

## 背景

沿用 P1-47.3 / P2-29 打包链路复核：DEB 打包当前只闭环 **RootHide rootfs 布局**；Rootless 整条路线（含 profile 注册、DEB 布局、IPA/None 产物）未闭环。早期对照分析指出 B1：workflow 表单允许选择 Rootless / Both 环境与 DEB / Both 包型，但打包链路对非 RootHide 拒绝，组合要跑到 CI 中段才失败。

本轮在 P2-35 最新工作树基础上，只修 **CI 入口与脚本的一致性口径**；不改打包布局、不造 Rootless 路线、不接签名闭环、不动 App / Helper 源码。

## 现状核对（修复前）

| 维度 | 现行实现 | 一致性问题 |
| --- | --- | --- |
| 环境选项 | `environment: [RootHide, Rootless, Both]` | 仅 RootHide 有注册 profile 与可验证打包布局；Rootless/Both 未闭环 |
| 包型选项 | `package: [DEB, IPA, Both, None]` | DEB/Both 仅 RootHide；Rootless 下 IPA/None 也会被 profile 解析 fail-closed 阻断 |
| 兼容校验位置 | build job 在安装 dpkg/ldid、跑管线自测**之后**才校验环境/包型 | 矛盾组合先消耗前置步骤再退出；`Both` 展开的 Rootless 节点注定失败 |
| 拒绝文案 | 提示 "Use IPA/None for Rootless" | 与实现不符：Rootless IPA/None 同样无注册 profile，不可走 |
| profile 解析 | `ci-build.sh` 无条件先跑 `resolve-profile.py`；Rootless Auto 无注册画像 → exit 20 | 与 `verify-local-build.sh` 既有断言一致（Rootless 必须被拒），属有意 fail-closed，本轮不放宽 |

## 本轮落地

### 1. 输入级前置校验（`select-environments` job）

- 生成 matrix 之前先判：`package ∈ {DEB, Both}` 且 `environment ≠ RootHide` → 直接 `exit 30`，给出明确提示。
- 拦截两类矛盾组合：`Rootless + DEB/Both`、`Both + DEB/Both`（避免放出注定失败的 Rootless matrix 节点）。

### 2. 节点级兜底校验前移（`build` job）

- 兼容校验步骤从"安装依赖 / 管线自测之后"前移到 `checkout` 之后、安装 dpkg/ldid 之前。
- 作为 matrix 展开后的第二道防线，口径与输入级校验一致；`fail-fast: false` 下非 RootHide 节点提前退出，不浪费工具安装与自测步骤。

### 3. 表单描述与拒绝文案对齐实现口径

- `environment` / `profile` / `package` 描述如实标注：仅 RootHide 闭环；Rootless/Both profile 未注册、路线未验证。
- 拒绝文案统一为：DEB/Both 仅 RootHide；Rootless 路线（任意包型）pending；不再暗示 Rootless 可走 IPA/None。
- `ci-build.sh` DEB 门禁文案与 workflow 统一，退出码保持 `30`。

## 刻意未改（pending，待授权 / 真机闭环）

- **Rootless DEB 布局**：不新增 `rootless.env` / `control.rootless` / `postinst.rootless`；`/var/jb` 前缀在 RootHide 包内仍是禁前缀断言，不是受支持布局。
- **Helper target 进 CI 编译**：`FilterKitHelper` 为独立 `tool` target，未挂入 FilterKit scheme；CI `xcodebuild -scheme FilterKit` 不编译它。属独立工程接线工作，待单独评审授权。
- **IPA 签名**：IPA 产物仍为 `FilterKit-unsigned.ipa` 未签名结构包；签名闭环 pending。
- **arm64e 真切片**：包管理架构标签 `iphoneos-arm64e` 与 App Mach-O 切片分别校验；App 二进制仍固定 arm64，真 arm64e 切片需 ABI 复核后再启用。
- **Rootless profile 容错**：不放宽 `resolve-profile.py` 对未注册 Rootless 画像的拒绝（`verify-local-build.sh` 既有断言要求 Rootless 必须被拒）。

## 静态校验（Linux 主机，无 Xcode / iOS SDK）

- `bash -n` 通过：`ci-build.sh`、`package-deb.sh`、`test-deb-packaging.sh`。
- `build.yml` 经 PyYAML 解析通过；jobs 为 `select-environments`、`build`。
- 本机不执行 `xcodegen generate` / `xcodebuild` / XCTest / ldid 校验；CI 结论以 macOS Runner 实际日志为准。

## 改动文件

| 目录 | 文件 | 改动 |
| --- | --- | --- |
| `.github/workflows/` | `build.yml` | 输入级兼容校验；节点级校验前移；表单描述与拒绝文案对齐 |
| `Build/Scripts/` | `ci-build.sh` | DEB 门禁拒绝文案与 workflow 统一（退出码 30 不变） |

## 边界

未改 App / Helper / 测试源码；未改 DEB 布局、entitlements、签名脚本与 profile 注册表；未装卸、未注入、未改目标 App Bundle；0.1 未真机闭环不签署。
