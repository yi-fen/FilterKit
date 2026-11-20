# C-F5 二轮 Runner 复核记录（重跑 run `44471548011` / job `ui-acceptance`）

- 时间：2026-11-19 06:39:29Z ～ 06:39:48Z；Worker `{81e4a215-e2de-48a4-b0ac-1e4214367560}`，westus，MacCloud；Xcode 26.6；模拟器 iPhone 17 Pro `5AB3DACF-C352-49D1-BF9A-3C0104FA4ED3`，OS 26.2。
- 检出 SHA：**`b7286a2f22183cf327d8ce4000ee88add605134c`**（日志 line 126 `commit = 'b7286a2…'`；fetch 与 `rev-parse` 一致）。
- 本附件仅含 `ui-acceptance` 单 job 日志。

## 与首轮对比

| 步骤 | 二轮结论 | 依据 |
|---|---|---|
| Checkout | 旧 SHA `b7286a2`（未取最新 main） | `commit = 'b7286a2…'`；`git rev-parse` |
| XcodeGen | ✅ 2.46.0 工程生成成功 | `Created project at .../FilterKit.xcodeproj` |
| 模拟器选取 | ✅ 同上 | `Selected simulator: 5AB3DACF…` |
| `xcodebuild test -scheme FilterKitUITests` | ❌ 同首轮构建失败，用例未执行 | line 501 同一 Info.plist 报错；`** TEST FAILED **`；exit 65 |

## 失败定性（与首轮同源，但触发原因不同）

- 报错与首轮完全相同：`FilterKitUITests` 无 Info.plist 且未自动生成，代码签名中止。
- **根因：本次是对旧 workflow run `44471548011` 的失败 job 重跑，GitHub Actions 重跑固定检出该 run 创建时的原始提交 `b7286a2`；修复提交之后才进入远端 main，未被本次重跑拾取。**
- 远端 `main` 现 SHA `5ddd489c01e90de563cc436268fd40e7ecd88ab7`；`project.yml` 的 `FilterKitUITests` 段已含 `GENERATE_INFOPLIST_FILE: YES`，与本地一致（本地 HEAD `43c780f`）。
- 即：**清单修复本身已在远端 main，但二轮 Runner 跑的是旧提交，没吃到修复；不是修复无效。**

## 产物

- Artifact `filterkit-ui-acceptance`，ID `14504924055`，18 文件，13357 B；SHA256 `70838b62a3e61687afc1751d12839f0db880c6933e1d65e2c9402ab8b6cb8909`；下载页 `https://github.com/yi-fen/FilterKit/actions/runs/44471548011/artifacts/14504924055`。
- 本地归档：`job-logs.txt`（60K，766 行，SHA256 `c7eafd09ba4a357bb598274d1ad2027593af36abc2aeb38d1d59c386edb6fc28`）。

## 下一步（调度口径）

- **不要**在 run `44471548011` 上再次 "Re-run failed jobs"——它会继续钉在 `b7286a2`。
- 需在 main `5ddd489` 上**新建一次** workflow 运行（`workflow_dispatch` 或推送触发），让 Runner 检出含修复的提交。
- 新运行待观察：测试 bundle 签名/标识、XCUITest 元素匹配、容器 `tmp/` 样本拉取、`ReportRoundtripValidator` 的 `swift run` 构建、Share Sheet 无窗口渲染。
- 门禁影响：G8/G9/G10 仍**未取证**；G1～G7 既有判定不变；0.1-C 不予闭环。
