# P2-35 — 预热 / 共享快照 / 行内进度（对齐 R16 首屏体验，不删加载态代码）

## 背景

真机录屏对比：新版冷启动后应用页 / 插件页出现整页"正在加载"过渡，旧版 R16 首屏几乎无过渡。对照 R16 源码核实，R16 并未删除加载态设计，而是靠三件事让加载态不遮挡首屏：

1. **启动即后台预热**：根 Tab `.task` 先预热 App 库存，完成回调链式预热插件；
2. **共享快照进页先上屏**：单例持有最近成功结果，进页读快照，后台补扫；
3. **壳形态为行内进度**：List 框架先行，扫描中仅在列表内放一行 `ProgressView`，已有数据时后台刷新不遮挡。

R16 保留了完整状态语义：`isScanning` 标志、加载 / 错误 / 空 / 失败分支齐全；插件五态 `neverLoaded / loading / loaded / empty / failed`。

## 本轮口径

**不删除任何加载态代码。** 状态标志、加载 / 错误 / 空 / 失败分支全部保留；只调整扫描调度时机、快照持有方式与壳的摆放位置。扫描算法仍用 NEW 自有通路，不移植 R16 的 LS / 目录遍历实现；不读 dylib 二进制、不查 dpkg 归属、不校验哈希、不写文件、不重签名、不改目标 App Bundle。

## 改动清单与目录

### A. App 库存预热 / 快照（复核保留既有实现）

- `Sources/Environment/CachedAppDiscoveryProvider.swift`：既有 `currentSnapshot()`、`prewarm()`、在飞复用保留；未改协议签名。
- `Sources/Features/Apps/AppsView.swift`：`load()` 开头先读快照上屏（既有）。
- `App/MainTabView.swift`：根 Tab `.task` 预热 App 库存。

### B. 插件共享 registry + 链式预热 + 快照（新增）

- **新建 `Sources/Environment/PluginScanRegistry.swift`**（`@MainActor ObservableObject` 单例）：
  - 持有最近成功 `PluginScanResult` 快照与 `isLoading`；
  - `prewarm()` / `loadIfNeeded()` 复用在飞扫描，已有快照在后台刷新期间保持可见；
  - 环境探测与插件枚举均在 `Task.detached(priority: .utility)` 内执行；
  - 扫描失败保留旧快照；目录未解析 / 不可访问由结果 `directoryState` 表达。
- `Sources/Features/Plugins/PluginsView.swift`：
  - `PluginsViewModel` 改读 `PluginScanRegistry.shared`，不再在页面内自建 scanner 同步探测；
  - 移除 ViewModel 内 `environment` 与现扫逻辑；App 名映射（`appNamesByBundleID/Executable`）后置到结果就绪后 enrich。
- `App/MainTabView.swift`：根 Tab `.task` 同时预热 App 与插件 registry（插件目录扫描不依赖 App 结果，并行预热以提前完成）。

### C. 壳降级：List 先行 + 行内进度

- `Sources/Features/Apps/AppsView.swift`：首次扫描的整页 `FKStateView(.loading)` 改为 `List` + 行内 `ProgressView` Section；错误 / 空 / 失败终态分支原样保留整页 `FKStateView`。
- `Sources/Features/Plugins/PluginsView.swift`：同上，加载中行内进度 Section；错误 / 目录不可用 / 空态终态分支保留。

### D. 环境探测挪离主线程首帧

- 插件页 `makeDiagnosticReport()` 同步探测由 registry 的 detached 后台任务执行，不在 `@MainActor` 首帧跑。
- 关联预览 `loadApps()` 的环境探测原本已在 `Task.detached` 内，复核保留。

## 未改动 / 边界

- 版本号不变：`MARKETING_VERSION` / `CFBundleShortVersionString` 仍为 `1.0.0`。
- 未改扫描算法、未接 dylib 二进制读取 / 属主 / CDHash 校验、未接 Helper 部署与签名放行。
- 错误 / 空 / 失败等终态界面未删除；加载态标志位未删除。
- 单次枚举重量优化（plist 批量 / 懒读、`resourceValues`、身份分析占比）留待真机剖面后再定。

## 静态核对（本机 Linux，无 Xcode / xcodegen）

- 改动文件括号配平通过；registry 在飞任务泛型为 `Task<PluginScanResult, Error>`。
- 视图对 `registry.result / registry.isLoading` 引用一致；无旧 `model.result / model.isLoading` 残留。
- 测试未引用新 registry 与改动后的 ViewModel 接口；既有 App 发现测试沿用 `CachedAppDiscoveryProvider` 既有 API。
- Runner `xcodegen generate` / `xcodebuild` / XCTest 结论以下次在线编译为准；首屏实际耗时、预热命中、在飞复用待真机复验。
