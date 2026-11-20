# C-F4 门禁状态（run `44543099338` / SHA `71bc6b0`，2026-11-19 五轮复核）

> 对照冻结规格 `Spec/Stage-2/Stage-2.3-CF4-Final-Acceptance-Gates.md`。本轮为 C-F5 第五轮 CI 自动化运行；G1～G7 复跑通过，G8/G9 各剩一项待六轮复核，G10 日志口径通过、截图本体未解包。**0.1-C 不予闭环。**

## 1. 十项门禁逐项判定

| 门禁 | 通过条件 | 本轮证据 | 判定 |
|---|---|---|---|
| G1 Build（非 UI 目标） | Models/Adapters/Core `swift build` 0 error / 0 warning | `swift-build.log`：110/110 `Build complete! (13.87s)`；0 `error:`、0 `warning:` | ✅ 通过 |
| G2 Test（全量 XCTest） | 既有回归 + GUI-01～08 实际执行；Failure=0；Unexpected Skip=0 | `test-log.txt`：`Executed 405 tests, with 0 failures (0 unexpected)` | ✅ 通过 |
| G3 S1-05 独立过滤 | 15/15 passed，0 failure | `test-log-s105.txt`：15 tests 0 failures | ✅ 通过 |
| G4 GUI Tests | `GUIPresentationTests` 8/8 passed（GUI-01～08 逐一记录） | 套件段 testGUI01～08 全部 passed（含在 405 内） | ✅ 通过 |
| G5 Isolation | 1a/1b/2a/2b/3/4/4b 全 passed；摘要 `failed=0`；原始输出留存 | `isolation-summary.json` 7 passed / `failed: 0`；`isolation-output.log` 留存 | ✅ 通过 |
| G6 App Build | XcodeGen 生成后 `** BUILD SUCCEEDED **`，0 `error:` | `app-xcodebuild.log`：BUILD SUCCEEDED | ✅ 通过 |
| G7 Simulator 启动 | 模拟器 Booted，bundle 安装、启动、alive PID 存活 | `sim-launch.log`：PID 4390 alive，bundle `com.filterkit.manager`，device `EED6FB0A…` | ✅ 通过 |
| G8 Navigation | 五面可达，C-F3 §2～§4 观察项逐项通过 | Dashboard / Detail / Diagnostics / Settings 通过；分段计数 ALL/PAIRED/ISSUES 通过；**搜索输入未取证**（搜索框无键盘焦点失败），`plugins.png` 未归档 | ⚠️ 部分，待六轮 |
| G9 Export | 经 `ReportExporting` 生成合法 JSON；样本可回解析为等义信封；仅写临时目录 | 样本已落盘 `export/FilterKit-Report-0-1-0-preview.json`，`decodable: true`，计数 3/1/1 一致；**往返不等义**（数组顺序未归一化，validator exit 1） | ⚠️ 部分，待六轮 |
| G10 Share | 系统 Share Sheet 正常调起并归档 `share-sheet.png` | `ShareSheetTests.testShareSheetOpensAfterExport` passed，附件名 `share-sheet.png` 记入 xcresult；截图本体封在 Data blob，本机 Linux 无 xcresulttool，像素本体未解包核验 | ✅ 日志口径（本体待解包） |

## 2. 计数口径

- 405 = 基线 397 + GUI 8；S1-05 15 例独立口径，不与 XCTest 总数相加。
- UI 自动化 8 例：7 passed / 1 failure / 0 unexpected（196.324s）；失败仅 `testPluginsListSegmentsAndSearch` 搜索输入步骤。
- 计数以真实日志 `Executed N tests` 为准，不预写死。

## 3. §2 口径复核（本轮可观察部分）

- 合成信封：`loaded` 恒 `.unknown`，`permission.decision` 恒 `undetermined`；未渲染为已加载/Not Loaded。
- 导出仅写 `FileManager.default.temporaryDirectory`；无信封样本导出入口禁用（EmptyState 用例通过）。
- 未知项 / warnings / skippedFields / otherKeys 字段在导出 JSON 内完整保留，未被 UI 裁剪。

## 4. 闭环前剩余动作（六轮 Runner）

1. G8：搜索框先聚焦再输入，命中「Preview」≥1 行并归档 `plugins.png`。
2. G9：校验器两侧数组排序归一化后判等，`equalIgnoringGeneratedAt: true`、validator exit 0。
3. G10：从 xcresult blob 解包 `share-sheet.png` 等六张截图本体，逐项目视核验。
4. 三项闭环后按 C-F4 §4 归集证据、生成统一 `ACCEPTANCE.md` 签署 0.1-C；在此之前不回填 0.1-D 结论。

## 5. 未纳入本轮判定

真机目录扫描、真实插件加载、entitlement 放行、GUI 进程内 `jbroot()`、sandbox 放行、Rootless 真机兼容——属 0.1-D Permission Probe；`OwnershipResolver` 未迁移、`loaded` 恒 `.unknown`、`pluginID` 规则 0.2.0 定稿、PARSE-009-B 继续挂起，均不属本阶段闭环范围。
