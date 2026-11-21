# 真机截图证据归档（attachment_1795227596，2026-11-21 10:15–10:18）

## 来源与性质

- 4 张设备截图（WebP；三张 1290×2796，诊断长图 1290×8662）+ 合成预览信封 `FilterKit-Report-0-1-0-preview.json`。状态栏时间 10:15 / 10:17 / 10:18，电量 52–55。
- About 行显示 **`FilterKit 0.1-C GUI Foundation · 只读界面`**：设备运行的仍是 0.1-C GUI 桩构建，本轮 R3 Swift 引擎/协议层不在该设备包内。
- 本批次无 Runner 日志、无 `.ips`、无 dpkg 原始清单、无设备侧导出 JSON；计数与路径以截图文字为准，结论归设备观察线索，不替代真机取证门禁（G10～G15 / R4-G 仍 pending/unknown）。
- JSON 与归档 `r2-device-screenshots-1795218890/FilterKit-Report-0-1-0-preview.json` **字节相同**（SHA256 `cfbf3626…07c80d7`），为 `SyntheticReportFactory` 合成预览桩，不是设备扫描结果。

## 截图清单

| 文件 | 页面 | 截图可见事实 |
|---|---|---|
| `00-settings-report-export.png` | Settings | Schema `0.1.0`；Generator `0.1.0-preview`；Profile `roothide-preview · roothide`；Generated At `Unknown`；Export JSON Report / Share Report 按钮；About `0.1-C GUI Foundation · 只读界面` |
| `01-dashboard-environment-plugins.png` | Dashboard | Environment RootHide · ellekit 1.0.0 · roothide-preview；Plugins **3 Total / 2 Paired / 1 Missing / 1 Parse Failed**；System JBROOT `/private/var/jb` Confirmed；TweakInject `/private/var/jb/Library/TweakInject` Accessible；Permission Undetermined · 2.4 probe |
| `02-plugins-list.png` | Plugins | Preview Tweak 1.2.0（PreviewTweak.dylib，Yes/Yes/Unknown Runtime/Paired）；Broken Plist（Broken.dylib，Yes/No/Unknown Runtime/Paired）；Orphan Plist 0.9.0（Unknown dylib，Unknown/No/Unknown/Orphan Plist） |
| `03-diagnostics-environment-summary-long.png` | Diagnostics 长图 | 上半合成信封：Environment 六字段、JBROOT 候选、Frameworks/TweakInject、Enumeration 3/2/1、Parsing 1/1/1、PREVIEW-001、Stray.plist、Permission Probes 无证据；下半 0.1.18 汇总计数 + JBRoot Candidates 5 条 + Discovered Plugins 两条 |

## 三方核对

### A. JSON ↔ 合成信封 UI（一致）

| UI 位置 | 截图值 | JSON 字段 | 核对 |
|---|---|---|---|
| Settings Schema | `0.1.0` | `schemaVersion: 0.1.0` | 一致 |
| Settings Generator | `0.1.0-preview` | `generatorVersion: 0.1.0-preview` | 一致 |
| Settings Profile | `roothide-preview · roothide` | `profileId: roothide-preview` + route `roothide` | 一致 |
| Settings Generated At | `Unknown` | 信封无 `generatedAt` 字段 | 兜底 Unknown，一致 |
| Dashboard Total | 3 | `plugins` 长度 3 | 一致 |
| Dashboard Paired | 2 | `pairing=paired`：Preview Tweak、Broken Plist | 一致 |
| Dashboard Missing | 1 | Orphan Plist 无 dylib、`installed=null` | 一致 |
| Dashboard Parse Failed | 1 | Broken Plist `validation.status=parse_failed` | 一致 |
| Parsing Valid / Not Parsed | 1 / 1 | Preview `valid`；Orphan `not_parsed` | 一致 |
| Warnings | `PREVIEW-001 Synthetic preview report; not a device scan. · gui-preview` | `warnings[0]` code/message/sourceStage | 文本一致 |
| Unknown Items | `Stray.plist … orphan entry without paired dylib · enumeration · category: plist` | `unknownItems[0]` base/reason/sourceStage/detail.category | 文本一致 |
| Plugins 三行 | 版本/路径/已装/已配置/加载/配对 | 三条 plugin 字段逐项对照 | 一致 |

### B. 底部 0.1.18 汇总 ↔ R2 归档快照 `1795218890`（逐项相同，非新扫描）

| 计数项 | 本批次长图 | R2 归档 `06-diagnostic-summary-counts.png` | 核对 |
|---|---|---|---|
| JBROOT candidates | 5 | 5 | 相同 |
| DynamicLibraries directories | 16 | 16 | 相同 |
| dylib files | 8 | 8 | 相同 |
| Filter plists | 8 | 8 | 相同 |
| Injector evidence | 28 | 28 | 相同 |
| DPKG packages | 376 | 376 | 相同 |
| File ownership records | 9255 | 9255 | 相同 |
| Integrity records | 3466 | 3466 | 相同 |
| Helper candidates / registrations | 49 / 534 | 49 / 534 | 相同 |
| Installed Apps | 266 | 266 | 相同 |
| Static App associations | 8 | 8 | 相同 |
| Runtime loaded state | Unknown — no independent evidence | 同 | 相同 |
| JBRoot Candidates | 两 `.jbroot-8D3CAE7017A11CC5` 容器 validated；`/private/var/jb`、`/var/jb`、`/var/rootless` not_found | 与归档 `03` 相同 | 相同 |
| Discovered Plugins | PreferenceLoader.dylib、FilzaPatch.dylib，`source=manual_inferred`，`loaded=unknown` | 与归档 `02` 同容器路径口径 | 相同 |

### C. 矛盾点与保守口径

- **顶部合成信封与底部旧快照口径不同**：顶部 Dashboard/JBROOT 显示 `/private/var/jb` 绿色 Confirmed/valid；底部真实快照候选表 `/private/var/jb` 为 `status=not_found · readable=false · structure=false`。顶部 Confirmed 是合成演示状态，**不得当作真实根路径可达证据**。
- Broken Plist 列表标 `Paired`（按 `pairing` 字段）但 `configured=No`（橙色）；Dashboard Paired=2 含 Broken，Missing=1 仅 Orphan。配对 ≠ 已配置。
- 所有 `loaded=unknown` 与 `Unknown Runtime state` 口径正确：静态文件/匹配证据不能确认运行时加载；`source=manual_inferred` 不冒充 dpkg 精确清单。
- Permission Probes `No probe evidence · Unknown`；本轮无 entitlement/沙盒/GUI 进程权限结论。

## 判定与待办

- 本批次**不含新的真机扫描结果**：JSON 与旧归档字节相同；底部 13 项计数与旧快照逐项相同；设备运行 0.1-C GUI 桩，未接入 R3 引擎 live 快照。
- 真机缺口沿用 Stage1/R3 口径：全量目录列表、plist 原文、`.version-roothide`、dpkg 全量 list、进程内解析接入方式；无 `.ips`/系统日志前不猜 C1～C5 根因。
- #331 去重线索 D1～D5（候选根重复、dylib/plist/注入器/Helper 跨根重复）本批次未新增证据，继续冻结待单独授权。

## 文件指纹

| 文件 | SHA256（前 16 位） | 大小 B |
|---|---|---|
| `00-settings-report-export.png` | `510df1a670190fbb` | 84,042 |
| `01-dashboard-environment-plugins.png` | `0ca739273cf4e29c` | 99,650 |
| `02-plugins-list.png` | `188a46202367f756` | 80,744 |
| `03-diagnostics-environment-summary-long.png` | `9327d918ea1abe66` | 428,336 |
| `FilterKit-Report-0-1-0-preview.json` | `cfbf36262da34aa089f` | 5,295 |
