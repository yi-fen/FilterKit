# C-F5 首轮 Runner 复核记录（run `44471548011` / job `ui-acceptance`）

- 时间：2026-11-19 06:26:22Z ～ 06:27:05Z；Runner `macos-26-arm64`，westus，MacCloud；Xcode 26.6。
- 检出 SHA：`b7286a2f22183cf327d8ce4000ee88add605134c`（远端 `main`；与本地 C-F5 树 `.swift`/`project.yml`/`Package.swift`/工作流无内容差异）。
- 本附件仅含 `ui-acceptance` 一个 job 的 Worker 日志；`build`/`test`/`isolation`/`app-build` 结论不在本包内，沿用 run `44426297905` 既有证据。

## 执行结果

| 步骤 | 结论 | 日志依据 |
|---|---|---|
| Checkout | ✅ 检出 `b7286a2` | `git rev-parse refs/remotes/origin/main` |
| XcodeGen | ✅ 2.46.0 生成工程成功 | `Created project at .../FilterKit.xcodeproj` |
| 模拟器选取 | ✅ iPhone 17 Pro `5AB3DACF-C352-49D1-BF9A-3C0104FA4ED3`，OS 26.2 | `Selected simulator: ...` |
| 包图解析 | ✅ 8 targets；`FilterKitUITests → FilterKit → Models/Adapters/Core` | `Target dependency graph (8 targets)` |
| `xcodebuild test -scheme FilterKitUITests` | ❌ 构建失败，用例未执行 | `error: Cannot code sign ... Info.plist ...`；`** TEST FAILED **`；exit 65 |

## 失败定性

- 错误（line 250/256）：`FilterKitUITests` target 无 Info.plist 且未自动生成，代码签名阶段中止：
  > Cannot code sign because the target does not have an Info.plist file and one is not being generated automatically. Apply an Info.plist file ... or set `GENERATE_INFOPLIST_FILE` to YES (recommended).
- 性质：**工程清单配置缺口**，非业务源码/契约问题；UI 用例、导出链路、Share Sheet 均未到达执行阶段。
- 未产出：导航/详情/诊断/设置截图、导出 JSON 样本、`roundtrip-result.json`、Share Sheet 截图；`ReportRoundtripValidator` 未被调用。

## 产物

- Artifact `filterkit-ui-acceptance`，ID `14504473558`，18 文件，13348 B；SHA256 `9c42041c571c7924e5ccfb576142e6ed6c8bc14bd6a1dab3d6e01f2e77eaf88c`；下载页 `https://github.com/yi-fen/FilterKit/actions/runs/44471548011/artifacts/14504473558`。
- 本地归档：`job-logs.txt`（27040 B，SHA256 `b10a202df33781c3dc3f3b4acab631b5d11f2c25599b61a63aceb3c070d2d173`）。

## 修复与待复核

- 修复：`project.yml` 的 `FilterKitUITests` target 补 `settings.GENERATE_INFOPLIST_FILE: YES`（UI 测试 bundle 由工程自动生成 Info.plist）。
- 下一轮待观察：测试 bundle 签名/标识是否通过；XCUITest 元素匹配；导出样本能否从容器 `tmp/` 拉出；校验工具 `swift run` 构建；Share Sheet 在无窗口 Runner 的渲染。
- 门禁影响：G8/G9/G10 仍**未取证**；G1～G7 既有判定不变；0.1-C 不予闭环。
