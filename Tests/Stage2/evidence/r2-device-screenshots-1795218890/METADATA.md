# R2 真机截图证据归档（attachment_1795218890，2026-11-21 07:53–07:54）

## 来源与性质

- 7 张设备截图（1290×2796 WebP，已转 `.png` 语义命名）+ 合成预览信封 `FilterKit-Report-0-1-0-preview.json`。
- 截图为用户设备屏幕拍摄/录制导出，**无对应 Runner 日志、无 `.ips`、无 dpkg 原始清单**；计数与路径以截图文字为准，结论归设备观察线索，不替代真机取证门禁（G10～G15 / R4-G 仍 pending/unknown）。
- `FilterKit-Report-0-1-0-preview.json` 为 `SyntheticReportFactory` 合成预览桩（warning `PREVIEW-001`，3 条合成插件），**不是设备扫描结果**，仅作信封格式参照。
- 本目录问题清单对应挂起任务 #331（引擎计数/去重），**本批次 D-R2-02 离线测试不修复这些去重问题**；修复须另行授权。

## 截图清单

| 文件 | 页面区段 | 截图可见事实 |
|---|---|---|
| `00-injector-evidence.png` | Injector Evidence | ellekit 静态包行 ×4；substrate 指纹行 ×6；substitute 指纹行 ×4；行内 `image=—`，静态/运行时证据分列 |
| `01-filter-rules.png` | Filter Rules | FilzaPatch / PreferenceLoader / filzacrack / weifengqad 四条规则各出现两次；`parse=parsed`，Bundles 命中 |
| `02-discovered-plugins-paths.png` | Discovered Plugins | 四条 dylib 路径各出现一次以上；路径位于 `.jbroot-8D3CAE7017A11CC5` 容器内 `Library/MobileSubstrate/DynamicLibraries/`；`source=manual_inferred`，`loaded=unknown` |
| `03-jbroot-candidates-plugins.png` | JBROOT Candidates + Plugins | `.jbroot-8D3CAE7017A11CC5` 经 `/private/var/containers/...` 与 `/var/containers/...` 两条路径各列一次；`/private/var/jb`、`/var/jb`、`/var/rootless` `not_found` |
| `04-environment-jbroot-libraries.png` | Environment / JBROOT / Dynamic Libraries / Enumeration | RootHide · ellekit 1.0.0 · roothide-preview · iOS 17.0.2 · arm64e · Partial；DynamicLibraries `/private/var/jb/Library/Frameworks`，TweakInject `/private/var/jb/Library/TweakInject`；Enumeration 3 Found / 2 Paired / 1 Orphan（合成桩口径） |
| `05-parsing-warnings-probes-summary.png` | Parsing / Warnings / Unknown Items / Permission Probes / Summary 头 | Valid 1 / Parse Failed 1 / Not Parsed 1；`PREVIEW-001 Synthetic preview report; not a device scan`；Stray.plist orphan；Permission Probes `No probe evidence · Unknown`；JBROOT candidates 5 |
| `06-diagnostic-summary-counts.png` | 0.1.18 Diagnostic Summary 全量计数 | JBROOT candidates 5；DynamicLibraries directories 16；dylib files 8；Filter plists 8；Injector evidence 28；DPKG packages 376；File ownership records 9255；Integrity records 3466；Helper candidates 49；Helper registrations 534；Installed Apps 266；Static App associations 8；Runtime loaded state `Unknown — no independent evidence` |

## 待核去重线索（#331，未授权修复）

| 编号 | 现象 | 截图对照 | 初判方向（待核） |
|---|---|---|---|
| D1 | 同一 `.jbroot-8D3CAE7017A11CC5` 容器经 `/private/var/containers/...` 与 `/var/containers/...` 重复列为候选 | `03`、`06`（candidates 5，含 1 对同物理路径重复） | 候选路径未按 standardized 物理路径归一化去重 |
| D2 | 4 条唯一 dylib 枚举为 8 条 | `02`、`06`（dylib files 8） | 选定根候选目录与固定回退根目录指向同一容器，枚举结果未按规范路径去重 |
| D3 | 4 条唯一 plist 枚举为 8 条 | `01`、`06`（Filter plists 8） | 同 D2，plist 遍历跨重叠目录根重复 |
| D4 | 注入器指纹行跨 `root`、`/var/jb`、`/private/var/jb` 三根重复；包行亦重复 | `00`、`06`（Injector evidence 28） | `fingerprintInjectors` 根列表未去重/未跳过不存在根；包证据与指纹证据未按 type+path 合并 |
| D5 | Helper registrations 534，疑跨多个重叠 LaunchDaemons 根重复 | `06` | 待核 LaunchDaemons 候选根重叠度与 plist 路径去重；本轮不下结论 |

## 保守口径（沿用冻结边界）

- `loaded` 无独立运行时证据恒 `unknown`；截图 `loaded=unknown` 口径正确，不得据此推断未加载。
- 静态 Filter 匹配 ≠ 运行时注入成功；`source=manual_inferred` 仅为无 dpkg 精确清单时的推断来源，不冒充设备真实清单。
- 去重修复属引擎计数/聚合行为变更，须在 D-R2-02 离线测试基线确立后、经单独授权再做；本批次不改动枚举/聚合结果语义。
