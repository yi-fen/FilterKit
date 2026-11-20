# C-F4 门禁状态（run `44426297905` / SHA `2445ef1`，2026-11-19 复核）

> 对照冻结规格 `Spec/Stage-2/Stage-2.3-CF4-Final-Acceptance-Gates.md`。本轮为 HEAD 基线对应树（与本地 `bdd7c8a` 无 `.swift`/yml 内容差异）；仍非最终签署：G8/G9/G10 缺证。

## 1. 十项门禁逐项判定

| 门禁 | 通过条件 | 本轮证据 | 判定 |
|---|---|---|---|
| G1 Build（非 UI 目标） | Models/Adapters/Core `swift build` 0 error / 0 warning，build job 日志 `Build complete` 行 | `logs/non-ui-build/swift-build.log`：`Build complete! (11.99s)`；Models/Adapters/Core 全量编译；0 error、0 warning | ✅ 通过 |
| G2 Test（全量 XCTest） | 既有回归 + GUI-01～08 实际执行；Failure=0；Unexpected Skip=0；套件可追溯 | `test/test-log.txt`：405 tests，0 failures（0 unexpected），0 skipped，38 套件 | ✅ 通过 |
| G3 S1-05 独立过滤 | `PluginPairingS105FixtureTests` 15/15 passed，0 failure | `test/test-log-s105.txt`：15/15，0.015s | ✅ 通过 |
| G4 GUI Tests | `GUIPresentationTests` 8/8 passed（GUI-01～08 逐一执行记录） | 套件段 8 passed / 0 failed | ✅ 通过 |
| G5 Isolation | 1a/1b/2a/2b/3/4/4b 全 passed；摘要 `failed=0`；原始输出留存 | `iso/isolation-output.log` 7 项 OK；`iso/isolation-summary.json` 7 passed / failed=0，文本与摘要一致 | ✅ 通过 |
| G6 App Build | XcodeGen 生成后 `** BUILD SUCCEEDED **`，0 `error:` | `app-build/app-xcodebuild.log`：BUILD SUCCEEDED，0 error；1 条 AppIntents 良性 warning | ✅ 通过 |
| G7 Simulator 启动 | 模拟器 Booted，bundle 安装、启动、alive check PID 存活 | `app-build/sim-launch.log`：PID 7094 alive，device `5AB3DACF…` | ✅ 通过 |
| G8 Navigation | Dashboard/Plugins/Detail/Diagnostics/Settings 五面可达，C-F3 §2～§4 观察项逐项通过 | 仅 Dashboard 首屏截图；其余四页未点击 | ❌ 缺证 |
| G9 Export | 经 `ReportExporting` 生成合法 JSON；样本可回解析为等义信封；仅写临时目录 | 无 `export/` JSON 样本与 Settings 截图 | ❌ 缺证 |
| G10 Share | 系统 Share Sheet 正常调起并归档 `share-sheet.png` | 无 Share Sheet 取证 | ❌ 缺证 |

## 2. 计数口径

- 405 = 基线 397 + GUI 8；S1-05 15 例已计入基线，不与总数相加；Reporting 18 例（Builder 6 / Validator 4 / Exporter 5 / Service 3）含在基线内。
- 计数以真实日志 `Executed 405 tests` 为准；全日志无 XCTSkip / skipped 记录。

## 3. §2 口径复核（本轮可观察部分）

- Dashboard 合成信封：Permission `Undetermined`，未渲染为已加载/Not Loaded；本阶段无真实 `loaded` 证据，`loaded` 恒 `.unknown`。
- 其余四页的未知项 / warnings / skippedFields / otherKeys 不裁剪、空组空态展示等口径，本轮无模拟器交互证据，留待 G8 取证复核。
- 导出落盘边界（仅写 `temporaryDirectory`）与无信封入口禁用文案，留待 G9/G10 取证复核。

## 4. 闭环前剩余动作

1. ~~G1：工作流 `build` job 增补日志产物（或 Runner 回传原始 `swift build` 日志），留存 `Build complete` 与 0 error / 0 warning 明细~~ **已补证**：`logs/non-ui-build/swift-build.log`。
2. G8：模拟器逐页点击 Plugins / Detail / Diagnostics / Settings，按 C-F3 清单截图归档。
3. G9：生成并归档导出 JSON 样本，回解析校验等义，记录临时目录路径。
4. G10：调起 Share Sheet 归档截图。
5. 三项补齐后重跑完整 Runner 或补证归档，全部门禁 ✅ 后按 C-F4 §4 生成统一 `ACCEPTANCE.md` 签署关闭 0.1-C。

## 5. 未纳入本轮判定

真机目录扫描、真实插件加载、entitlement 放行、GUI 进程内 `jbroot()`、sandbox 放行、Rootless 真机兼容——属 0.1-D Permission Probe；本轮不取证、不闭环。
