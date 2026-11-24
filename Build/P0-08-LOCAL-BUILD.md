# P0-08 — macOS 本地手动构建

## 目标

本地 Mac 构建入口与 GitHub Actions 共用 `Build/Scripts/ci-build.sh`，避免两套构建规则逐渐分叉。

## 环境要求

- macOS
- Xcode（含命令行工具）
- XcodeGen：`brew install xcodegen`
- Python 3

## 使用方式

在仓库根目录执行：

```bash
bash Build/Scripts/build-local.sh
```

脚本交互选择：

- Environment：RootHide / Rootless
- Profile：Auto / 已登记 Profile
- Configuration：Debug / Release
- Architecture：arm64e / arm64 / Both
- Tests：Yes / No
- Package：DEB / IPA / Both / None
- Clean Build：Yes / No

也支持环境变量模式（适合本地自动化）：

```bash
ENVIRONMENT=RootHide PROFILE=Auto CONFIGURATION=Release \
ARCHITECTURE=arm64 RUN_TESTS=false PACKAGE=None CLEAN_BUILD=true \
bash Build/Scripts/ci-build.sh
```

## 输出

每次构建输出至 `Build/Output/<Environment>/`，包括：

- `profile.json`：本次使用的 Profile 记录
- `xcodebuild.log`：Xcode 构建日志
- `FilterKit.app`：构建产物
- 可选 `FilterKit-unsigned.ipa`
- `build-report.json`：构建环境、参数、Git commit、工具版本和产物清单
- `SHA256SUMS.txt`：产物 SHA-256

## 当前限制

- 必须在 macOS/Xcode 环境实际运行；Linux 环境只能做静态检查。
- RootHide 记录的是项目参考基线，不代表已完成设备兼容认证。
- Rootless 尚无冻结的已验证 Profile，选择后会被 Profile resolver 拒绝。
- DEB / Both 暂时由共享构建脚本阻断，等待 RootHide/Rootless 包结构、路径及控制文件完成核验。
- IPA 当前为未签名 IPA；安装和越狱环境部署能力仍需后续验证。
- `Both` 架构会传递 `arm64 arm64e` 给 Xcode，实际是否能由当前 SDK/toolchain 产出，必须在目标 Xcode 版本验证。

## GitHub 与本地一致性

GitHub workflow 与本地入口均调用 `Build/Scripts/ci-build.sh`。两者仅负责收集参数和提供运行环境；Profile 解析、构建、打包保护、报告与哈希生成均在共享脚本中执行。
