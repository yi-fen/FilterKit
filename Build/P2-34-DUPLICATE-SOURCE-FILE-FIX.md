# P2-34 — 仓库根目录残留源文件同名冲突修复（离线修复轮）

## 证据

- Runner job `9a609b49-3f7b-51b3-ae1f-1680b6231a6a`（workflow `05905e0e-41af-45d8-bd7a-226e9d155ca1`，macOS 15 arm64，Xcode 16.4 / iOS 18.5 SDK，FilterKit app target Release-iphoneos）。
- 本机留存：`.tmp/ci-logs/p2-33/job-logs.txt`（52,089 B）。
- 错误（编译期，未进入 XCTest）：

```
error: filename "CachedAppDiscoveryProvider.swift" used twice:
  '…/Sources/CachedAppDiscoveryProvider.swift'
  '…/Sources/Environment/CachedAppDiscoveryProvider.swift'
```

## 根因

- CI 纯 `actions/checkout@v4` 签出 GitHub 仓库，不从上传 zip 解压。
- 仓库 `Sources/` 根目录残留一份早期骨架阶段的旧副本 `CachedAppDiscoveryProvider.swift`；现行版本已迁移到 `Sources/Environment/`。
- `Project.yml` 的 FilterKit target 原以 `- path: Sources` 递归扫描，把根目录旧副本与子目录现行副本同时纳入同一 target；Xcode 以文件名区分同名 private 声明，两份同名文件直接判 `used twice`。
- 本地工作树与交付 zip 基于上传包重建，不含该根目录残留，故本地无法直接看到或删除它。

## 修复口径

工程层兜底：FilterKit target 的 Sources 由单条递归路径改为显式一级子目录，根层散落的旧副本天然不被纳入：

- `Sources/Core`、`Sources/DesignSystem`、`Sources/Environment`、`Sources/Features`、`Sources/Localization`、`Sources/Persistence`、`Sources/Shared`。
- 本地 122 个 Swift 全部位于这 7 个子目录，显式列举覆盖无遗漏；`App/`、`Resources/` 路径不变。
- Helper target 与 Tests target 本就显式列举文件，不受本次改动影响。

## 改动文件与目录

- `Project.yml`（工程根）：FilterKit target `sources` 的 `- path: Sources` 替换为上述 7 个显式子目录。

## 必须在仓库侧完成的根治动作

工程配置只保证根层残留不参与编译；**仍需在 GitHub 仓库删除根目录旧文件**：

- `Sources/CachedAppDiscoveryProvider.swift`（根目录旧副本，勿删 `Sources/Environment/` 现行版）。
- 顺带核对仓库 `Sources/` 根目录是否还有其他早期骨架散落的 `.swift`；现行源码不应有任何直接位于 `Sources/` 根层的 Swift 文件。

## 静态核对（本机 Linux，无 Xcode/xcodegen）

- 122 个 Sources Swift 全部落在 7 个显式子目录内，无根层或其他一级目录文件。
- `Project.yml` 经 PyYAML 解析通过；9 条 source 路径（App + 7 子目录 + Resources）在本地均存在。
- Helper/Tests target sources 未改；既有 Provider/ViewModel/View 分层与本轮 P2-33 在飞合并逻辑不变。

## 未闭环 / 待 Runner 与真机复验

- 本机未跑 `xcodegen generate` 与 `xcodebuild`；子目录列举的 group/编译纳入以下次 Runner 为准。
- 若仓库根目录还存在其他同名或旧副本，删除后再跑 CI；显式子目录已使根层 `.swift` 不被 FilterKit target 纳入。
- DEB 安装/签名放行/jbroot API/真机注入验证仍 pending；0.1 未真机闭环不签署。
