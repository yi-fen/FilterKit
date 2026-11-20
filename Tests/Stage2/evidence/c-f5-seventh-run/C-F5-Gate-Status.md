# C-F4 门禁状态（run `44555812135` / SHA `35674fec`，2026-11-19 七轮复核）

> 对照冻结规格 `Spec/Stage-2/Stage-2.3-CF4-Final-Acceptance-Gates.md`。本轮为 C-F5 第七轮 CI 自动化运行；G1～G9 复核通过，**G10 Share 面板可见性证据不足（⚠️ 部分）**。按 C-F4 §5，**0.1-C 不予闭环**。
>
> **2026-11-20 决定**：G10 剩余验证不再排程（搁置），不豁免、不签署；0.1-C 维持未闭环，G10 缺口作为已知限制/观察项带入后续阶段。

## 1. 十项门禁逐项判定

| 门禁 | 通过条件 | 本轮证据 | 判定 |
|---|---|---|---|
| G1 Build（非 UI 目标） | Models/Adapters/Core `swift build` 0 error / 0 warning | `swift-build.log`：110/110 `Build complete! (17.17s)`；0 `error:`、0 `warning:` | ✅ 通过 |
| G2 Test（全量 XCTest） | 既有回归 + GUI-01～08 实际执行；Failure=0；Unexpected Skip=0 | `test-log.txt`：`Executed 405 tests, with 0 failures (0 unexpected)` | ✅ 通过 |
| G3 S1-05 独立过滤 | 15/15 passed，0 failure | `test-log-s105.txt`：15 tests 0 failures；PAIR001～009 等逐一 passed | ✅ 通过 |
| G4 GUI Tests | `GUIPresentationTests` 8/8 passed（GUI-01～08 逐一记录） | 套件段 testGUI01～08 全部 passed，套件 15:39:29.625 passed（含在 405 内） | ✅ 通过 |
| G5 Isolation | 1a/1b/2a/2b/3/4/4b 全 passed；摘要 `failed=0`；原始输出留存 | `isolation-summary.json` 7 passed / `failed: 0`；`isolation-output.log` 七项 OK 留存 | ✅ 通过 |
| G6 App Build | XcodeGen 生成后 `** BUILD SUCCEEDED **`，0 `error:` | `app-xcodebuild.log`：BUILD SUCCEEDED；Xcode 26.6，iPhoneSimulator26.5.sdk，FilterKit deployment 17.0，bundle `com.filterkit.manager` | ✅ 通过 |
| G7 Simulator 启动 | 模拟器 Booted，bundle 安装、启动、alive PID 存活 | `sim-launch.log`：PID 7622 alive，bundle `com.filterkit.manager`，device `98A0BFA3…`；`dashboard-app-build.png` 基线 3/2/1/1 目视一致 | ✅ 通过 |
| G8 Navigation | 五面可达，C-F3 §2～§4 观察项逐项通过 | UI 8/8 0 failure；`dashboard / diagnostics / plugin-detail / plugins / settings` 五张截图本体解包目视核验；搜索 `Preview` 命中 Preview Tweak；分段 ALL/PAIRED/ISSUES 在位；空态用例通过 | ✅ 通过 |
| G9 Export | 经 `ReportExporting` 生成合法 JSON；样本可回解析为等义信封；仅写临时目录 | `export/` 样本 5295 B；`roundtrip-result.json`：`decodable: true`、`equalIgnoringGeneratedAt: true`、`messages: []`，计数 plugins 3 / unknownItems 1 / warnings 1；SHA256 与 `SHA256SUMS` 逐字一致；`set -euo pipefail` 下 validator 后 `shasum` 步骤执行，exit 0；样本来自容器 `tmp/` | ✅ 通过 |
| G10 Share | 系统 Share Sheet 正常调起并归档 `share-sheet.png` | 用例 passed；`share-sheet.png` 已归档并从 xcresult blob 解包（193441 B，1206×2622）；App 日志 `[ShareSheet]` 子系统记录为临时目录 JSON 配置活动项；**但截图本体为 Settings 底层视图，未见系统面板浮层/活动图标行；AX 谓词宽松（identifier/label 含 "Share"），命中元素不能确证为系统面板；活动项 provider 拉取返回 null** | ⚠️ 部分，**2026-11-20 决定搁置，不再验证** |

## 2. 计数口径

- 405 = 基线 397 + GUI 8；S1-05 15 例独立口径，不与 XCTest 总数相加。
- UI 自动化 8 例：8 passed / 0 failure / 0 unexpected（203.223s）。
- 计数以真实日志 `Executed N tests` 为准，不预写死。

## 3. G10 证据细化与缺口判定

### 3.1 已有证据

- `ShareSheetTests.testShareSheetOpensAfterExport` passed（18.088s）：Settings → `settings.exportButton` 点按 → `settings.shareLink` 出现并点按 → 等待含 "Share" 元素 5s 超时内存在 → 归档 `share-sheet.png`。
- 附件链可追溯：xcresult 活动段记录 `filename: share-sheet_0_729DA9B9….png`、`name: share-sheet.png`、`payloadRef: 0~Kf3cRSh0…`、`payloadSize: 193441`；与解包 PNG 本体大小、哈希一一对应（映射见 `RUN-METADATA.md` §截图映射）。
- App 子系统日志（15:56:09～15:56:10，pid 10301）：
  - `[ShareSheet] Failed to request default share mode for fileURL:…/tmp/FilterKit-Report-0-1-0-preview.json : (null)`
  - `[ShareSheet] Only support loading options for CKShare and SWY types.`
  - `[ShareSheet] error fetching item for URL:…` ×2
  - `[ShareSheet] error fetching file provider domain for URL:… : (null)`
  - 上述日志表明 `ShareLink(item:)` 已创建分享控制器并尝试为临时 JSON 配置活动项；控制器调起链路在 App 侧已触发。

### 3.2 缺口（不判绿依据）

1. **像素本体未见面板**：`share-sheet.png` 解包目视为 Settings 页面底层视图（Export JSON Report / Share Report 行、About、底部 Tab 在位），无系统 UIActivityViewController 浮层、无活动图标行、无遮罩 Dim。
2. **AX 命中不可确证为系统面板**：断言谓词 `identifier CONTAINS[c] 'Share' OR label CONTAINS[c] 'Share'` 同时覆盖 App 内 `Share Report` 链接；查询快照命中根级子元素，树内未检出 `ActivityListView` / 系统活动面板类元素记录。
3. **活动项加载失败**：item / file provider domain 拉取返回 null；无窗口模拟器内面板活动项与渲染稳定性未获证据。
4. 对照 C-F3 ST-5「调起系统 Share Sheet；`share-sheet.png` 归档」与 C-F4 G10「系统 Share Sheet 正常调起」，本轮只能证明**分享入口触发与控制器配置尝试**，不能证明**面板正常可见呈现**。

### 3.3 处置方向（已搁置，2026-11-20 决定不再排程）

以下为若后续重启 G10 复核时的技术方向，**本轮及后续阶段不再据此安排 Runner 运行**：

- 测试断言收紧：区分 App 内 ShareLink 与系统面板元素（面板容器类型 / 活动列表标识 / 系统谓词），避免宽松谓词自匹配。
- 取证时机：面板呈现动画完成后再截图；必要时在有窗模拟器或真机复核面板可见性。
- 活动项 null：复核 `ShareLink(item:)` 对临时目录文件 URL 的活动项提供方式；属分享链路健壮性观察项，不影响 G9 导出往返结论。

## 4. §2 口径复核（本轮可观察部分）

- 合成信封：`loaded` 恒 `.unknown`（Detail 截图 Loaded = Unknown「Runtime state not verified」），`permission.decision` 恒 `undetermined`（2.4 probe）；未渲染为已加载 / Not Loaded。
- 导出仅写 `FileManager.default.temporaryDirectory`（容器 `tmp/FilterKit-Report-0-1-0-preview.json`）；无信封样本导出入口禁用（EmptyState 用例通过）。
- unknownItems（Stray.plist 孤立 plist）、warnings（PREVIEW-001）在导出 JSON 内完整保留，未被 UI 裁剪。
- 隔离摘要与文本输出一致：七项 OK 对应 `failed: 0`。

## 5. 状态与剩余事项

1. **G10 已搁置**：2026-11-20 决定不再排程补证；不视为通过，也不作豁免签署。
2. 0.1-C 维持未闭环：不生成统一 `ACCEPTANCE.md`，不回填 0.1-D 结论。G10 缺口以本文件 §3.2 记录为准，作为已知限制/观察项带入后续阶段；若未来重启复核，方向见 §3.3。

## 6. 未纳入本轮判定

真机目录扫描、真实插件加载、entitlement 放行、GUI 进程内 `jbroot()`、sandbox 放行、Rootless 真机兼容——属 0.1-D Permission Probe；`OwnershipResolver` 未迁移、`loaded` 恒 `.unknown`、`permission.decision` 恒 undetermined、`pluginID` 规则 0.2.0 定稿、PARSE-009-B 继续挂起，均不属本阶段闭环范围。模拟器合成信封通过不构成真机权限或可写入管理证据。
