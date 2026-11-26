# P2-32 — 扫描动作 R16 对齐审计与规格评审（未落地）

- 状态：**规格评审中，未改动任何 `Sources/` 扫描代码**。按瀑布流程：规格冻结 → 离线夹具核对 → 授权下一阶段落地。
- 基线：NEW 工作树 P2-31 交付态（`FilterKit-NEW-0.1.0-source.zip`，SHA256 `230abbfd…475d923`）。
- 对照基准：R16 只读快照 `FilterKit-R16/`。历史 R16.1 副本在 `.tmp/compare/old/`，不作基准。
- 范围：App（已装应用）扫描动作、插件（目录枚举/分类/配对/关联）扫描动作与 R16 设计的口径对齐。
- 边界原则：**移植 R16 底层适配口径，不照搬结构；UI 与新增能力保持 NEW 自有设计**。

## 1. 两侧范式（先对齐认知）

| 层 | R16 | NEW |
|---|---|---|
| 离线纯规则管道 | `Core/PluginScanner/Enumeration/*`（FixtureSignal → Evidence → Inventory，不碰真实 FS） | 无对应离线管道；扫描直接跑真机只读 FS |
| 真机适配 | `Repository/FastPluginInventoryEngine.swift`（243 行） | `Environment/ReadOnlyPluginScanner.swift` + `PluginDirectoryLocator.swift` + `ReadOnlyPluginAssociationReader.swift` |
| 查询/筛选 | `Core/Plugins/Query/*`（纯内存无状态，三维筛选 + 名称排序） | `Features/Plugins/PluginListScope.swift`（单一所有权开关） |
| 新增增强 | 无 manifest、无 Mach-O 身份指纹、无 dpkg 所有权、无 Helper IPC | manifest 绑定、Mach-O 指纹/冲突、所有权证据、Helper 通道均为 0.1 新增 |

对齐口径理解为：**扫描规则/分类/证据口径一致**；结构上保留 NEW 的 Environment + 模型分层，不回退成 R16 的离线 FixtureSignal 管道。

## 2. App 扫描差异矩阵

### 2.1 已一致（不改）

| 口径 | R16 | NEW 现状（已核对文件） |
|---|---|---|
| LS 私有类枚举 | `LSApplicationWorkspace`，先 `allInstalledApplications` 空回退 `allApplications` | `LaunchServicesAppDiscoveryProvider.scanLaunchServices()` 相同回退 |
| 逐条读取 | `applicationIdentifier` / `localizedName` / `bundleURL`，Info.plist 单次读 | 相同；`infoPlistValues` 单次解码，名称/版本/可执行/图标共用 |
| 系统判定 | 路径前缀 `/System/`、`/Applications/` | `LaunchServicesAppDiscoveryProvider.classify` 相同路径优先规则 |
| 图标候选 | plist IconFiles 末项，懒解码，不在主循环重探测 | `proxyIconDescriptor` + `ContainerDirectoryAppScannerIconBuilder`，asset 解码延后到 `ApplicationIconView` |
| 去重合并 | bundleID 首条胜 | `CachedAppDiscoveryProvider.deduplicatedAndSorted` 用 `uniquingKeysWith: { first, _ in first }` 首条胜 |
| 排序 | 服务层 `localizedCaseInsensitiveCompare` | 缓存层 `localizedStandardCompare`，同名按 bundleID 次序；显示层不再二次排序（P2-30 A7 已收敛） |

### 2.2 待对齐（规则口径）

| 编号 | 口径 | R16 基准 | NEW 现状 | 建议动作 |
|---|---|---|---|---|
| A1 | 工作区实例获取健壮性 | `class_getClassMethod` 校验 `defaultWorkspace` 存在，`method_getImplementation` 取实现并强转 `@convention(c)` 取实例 | 直接 `workspaceClass.perform(defaultWorkspace)`，无方法存在性校验 | 补方法存在性校验；校验失败按 unavailable 降级，避免 `responds:`/`perform` 误判 |
| A2 | 兜底容器 bundleID 校验 | R16/LS 侧宽松：非空且 ≤255 即接受 | `ContainerDirectoryAppScanner.isValidBundleIdentifier` 过严：必须两段点分、首字符字母数字、每段仅字母数字 `-` | 放宽到与 LS provider 同一宽松口径（非空 ≤255），避免漏掉合法但格式松散的容器 App |
| A3 | 关联侧 bundleID 校验（同口径问题） | R16 静态匹配按原始 bundleID/executable 比对，不做段级语法强校验 | `ReadOnlyPluginAssociationReader.isValidBundleIdentifier` 两段 + 首字符字母数字 + 段字符集 | 对齐宽松口径；语法强校验只保留给写路径（部署事务），只读匹配不据此丢证据 |
| A4 | 在飞请求合并 | NSLock + `isLoading` + `completionWaiters`，在飞请求合并，后台 userInitiated 回主线程 | actor 缓存 + TTL 60s + prewarm；并发进入无在飞合并，可能重复 LS 枚举 | **待授权**：补在飞合并（共享同一在飞扫描结果），还是维持 actor TTL 模型 |
| A5 | 部分失败状态 | 结果三态 `success / partial(String) / unavailable(String)`；缺 ID、plist 空记 `partial`，不可用显式报错不当空库存 | throw 错误枚举 + 容器兜底；库存模型无 `partial` 概念 | **待授权**：是否在库存模型带回 `partial` 标记（最小扩展），还是维持 throw/兜底口径 |

### 2.3 NEW 增强（建议保留，不回退）

- 名称两级 plist 兜底：`CFBundleDisplayName ?? CFBundleName ?? bundleID`（R16 仅 `localizedName ?? bundleID`）。
- actor TTL 短缓存 + 后台 prewarm 预热（P2-29 已落地）。
- LS 受限/空时的容器目录兜底扫描（R16 无；作为受限环境回退保留）。

## 3. 插件扫描差异矩阵

### 3.1 已一致（不改）

| 口径 | R16 基准 | NEW 现状 |
|---|---|---|
| 目录候选 | 单 jbroot 下四相对目录：`Library/ElleKit/DynamicLibraries`、`Library/MobileSubstrate/DynamicLibraries`、`library/MobileSubstrate/DynamicLibraries`、`usr/lib/TweakInject` | `PluginDirectoryLocator.inspect` 同四路径；另把 `Library/TweakInject` 标记为 ElleKit 自身组件目录，不入第三方 |
| 枚举规则 | 单层非递归；软链目录/软链条目跳过；后缀 lowercased；配对键去扩展名小写 base 名 | `ReadOnlyPluginScanner.scan` 相同：`isSymbolicLink` 跳过、`isRegularFile` 判定、stem 小写 |
| 库存层克制 | 不哈希、不解析 Mach-O、不查 dpkg 所有权（留给 Diagnostics/detail） | 相同；`ownership` 库存恒 `.unknown`，Mach-O/哈希/身份延后 detail 路径 |
| plist 解析 | `Filter` 字典 ?? 顶层字典；`Bundles/Executables/Classes` 字符串数组；其余 keys 归集 | `PluginFilterConfiguration.parse` 相同，另解析 `Mode`、归集 unknownKeys、记录 warnings |
| 配对键与冲突 | base 名小写配对；重复大小写不敏感 basename 不随意取一 | stem 分组；组内多条置 `.invalid` + `duplicate_case_insensitive_basename` 警告 |
| 只读 | 不写/不改权限/不装卸/不碰 dpkg | 相同；`isReadOnly: true` |

### 3.2 待对齐（核心缺口）

| 编号 | 口径 | R16 基准（FastPluginInventoryEngine） | NEW 现状 | 建议动作 |
|---|---|---|---|---|
| P1 | **静态关联匹配（全量）** | 对所有已解析 plist，用 `Bundles/Executables` 对已装 App 集合做双维匹配：`matchedBundles` = 含 `*` 或命中 bundleIDs；`unmatchedBundles` = 非 `*` 且未命中；`matchedExecs` = executable 小写命中；`unmatchedExecs` 反之。`entryCount = bundles+execs+classes`；`valid = 字典非空且 entryCount>0` | `PluginFilterConfiguration` 已解析出 bundles/executables/classes，但**未参与任何 App 匹配**；关联仅来自 manifest hard/soft，且只处理 `ownership == .filterKit` | **补全量静态匹配**：对全部 plist 产出 matched/unmatched bundle 与 executable 列表，作为只读展示证据；manifest hard/soft 绑定优先，静态结果不覆盖绑定 |
| P2 | 关联分类五态 | `exact_match / global / unmatched_target / invalid_configuration / unresolved`；`invalid`（parse_status not_parsed 等）→ invalid_configuration；含 `*` 或 `global=="true"` → global；matches 空 → unmatched_target；否则 exact_match；未识别词表归 unresolved | `PluginAssociationSnapshot` 只有 `hardBoundAppInstalled / hardBoundAppMissing / hardBoundIdentityUnavailable`，无规则分类维度 | 新增只读静态关联分类投影（五态 + match_type bundle/executable/none + matched/unmatched 计数），与 manifest 绑定投影并列 |
| P3 | 关联证据口径 | `evidence = static_filter_match_only`；`loaded = unknown`；静态匹配 ≠ 注入成功，证据不升级 verified | 无静态证据位；loaded 无独立运行时证据 | 静态匹配条目标注 `static_filter_match_only` / `loaded=unknown`，与 R16 同保守口径 |
| P4 | 列表筛选三维 | 配置（configured/notConfigured/unverified/unknown）× 关联（associated/unassociated/global/unmatched/invalid/unresolved）× 证据（confirmed/absent/unverified/unknown）AND 组合；loaded 不入筛选 | `PluginListScope.includes` 仅 `filterKitOnly` 所有权开关 | **待授权**：是否本轮把三维筛选接入模型/引擎；UI 控件可下一轮，模型与纯内存查询先对齐 |
| P5 | 条目文件事实位 | dylib 行记录 exists/readable/regular/file_type/size；目录行记录 exists/directory/symlink/readable/enumerable/entry_count | 库存项记录路径与符号链接跳过事实；缺 size/regular/readable 文件事实位（Mach-O kind 库存恒 nil 属延后，可保留） | 补文件事实位（size/regular/readable）；Mach-O 解析仍延后 detail，不在库存层开启 |
| P6 | 枚举状态机 | `EnumerationStatus`：enumerated / partial / enumerationFailed / unresolved；单条目异常不中断 | `directoryState` + `issues`；条目级 partial 口径与 R16 不同 | **待授权**：是否对齐 R16 四态枚举与单条目 partial 归集口径 |

### 3.3 复核项（不改，仅确认）

- **跨根聚合**：R16 注释 `Never mix roots`，但 FastEngine 实际在单根下遍历四目录。NEW locator 入参为单 jbroot，候选均为该根下相对路径，天然同根；`ambiguous` 同根多目录聚合与 R16 不冲突。落地前复核 locator 不引入跨根候选混入。

### 3.4 NEW 增强（建议保留，不回退）

- `.fk.json` manifest 配对层 + hard/soft 绑定 + `PluginManifestIdentityBinding` 状态。
- Mach-O UUID/CDHash/installName/架构指纹与 `PluginIdentityAnalyzer` 冲突归集（duplicateIdentity / installNameCollision / uuidCDHashMismatch / unresolvedBasenameCollision）。
- dpkg 所有权证据层（detail 路径）。
- locator `ambiguous / inaccessible / unresolved` 状态与 canonical 别名合并。
- 配对状态机 `orphanDylib / orphanPlist / invalid / 重复 basename`。

## 4. 建议改动清单草案（授权后再落地，文件级）

> 仅草案；落地时逐文件核对，标注改动文件名与所在目录。

### App 线
- `Sources/Environment/LaunchServicesAppDiscoveryProvider.swift`：A1 工作区方法存在性校验。
- `Sources/Environment/ContainerDirectoryAppScanner.swift`：A2 放宽 bundleID 校验口径。
- `Sources/Environment/ReadOnlyPluginAssociationReader.swift`：A3 只读匹配放宽 bundleID 校验（写路径校验不动）。
- （待授权 A4/A5）`Sources/Environment/CachedAppDiscoveryProvider.swift`：在飞合并；`Core/Models/InstalledApp.swift` 或新增发现结果模型：partial 标记。

### 插件线
- `Sources/Environment/ReadOnlyPluginScanner.swift`：P1 全量静态匹配所需的 App 集合注入；P5 文件事实位采集。
- 新增/扩展关联只读模型（`Core/Models/PluginAssociationReadModels.swift` 或新文件）：P2 五态分类投影、P3 证据/loaded 口径。
- `Sources/Environment/ReadOnlyPluginAssociationReader.swift`：P1 静态匹配遍历全量 plist，manifest 绑定优先。
- （待授权 P4）`Features/Plugins/PluginListScope.swift` 与查询层：三维 AND 筛选。
- （待授权 P6）扫描结果状态机对齐 R16 四态。

## 5. 红线（落地轮必须遵守）

- 不改目标 App Bundle、不重签名、不自研注入引擎。
- 库存层仍不调用 dpkg、不哈希、不解析 Mach-O；这些保留在 detail/diagnostics 路径。
- 不回退 Helper IPC、备份恢复、授权（`PluginManagementPermission`）模型。
- 只读扫描：不写 plist、不增删移文件、不改规则、不装卸、不改软链、不注入、无常驻 Daemon。
- 本机 Linux 无 Xcode/iOS SDK/SwiftPM/ldid/lipo/otool；改动后仅做静态核对（花括号配平、引用一致性、脚本校验），编译结论以下次 Runner `xcodebuild` 为准。

## 6. 待授权开放项

1. **对齐边界**：是否确认保留 NEW 新增层（manifest / Mach-O 身份 / 所有权 / Helper），仅对齐扫描规则口径？（默认：保留）
2. **静态匹配**：是否按 R16 补全量 plist 静态关联匹配与五态分类，manifest 绑定优先？（默认：补）
3. **App 缓存与状态**：在飞请求合并、partial 部分失败态是否本轮补？（默认：在飞合并补；partial 最小模型扩展补标记）
4. **筛选接入**：三维筛选本轮落到模型/引擎，还是 UI 控件一并接入？（默认：模型/引擎先对齐，UI 下一轮）
5. **枚举状态机**：是否对齐 R16 四态与单条目 partial 归集？（默认：视 P6 与 A5 一并定）

## 7. 未闭环 / 待 Runner 与真机复验

- LS 单数组枚举对各 rootless / RootHide 组合的覆盖度；预热冷启动命中。
- 静态匹配在真实 App 清单上的 matched/unmatched 分布；`*` 全局规则归类。
- Xcode 编译、XCTest Apple SDK、ldid 签名、`lipo`/`otool` 校验、Sileo 安装、冷启动与重启启动。
- DEB 安装/签名放行/jbroot API/真机注入验证仍 pending；0.1 未真机闭环不签署。
