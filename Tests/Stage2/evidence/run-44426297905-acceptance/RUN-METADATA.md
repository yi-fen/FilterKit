# RUN-METADATA.md — 0.1-C Stage 2.3 GUI Foundation 第四轮统一验收（run 44426297905 / SHA 2445ef1，2026-11-19）

- Workflow run：`44426297905`；branch `main`；检出 SHA `2445ef1f11d1b71ffbff68fd8f9209ed6ffb76f3`；conclusion `success`；duration 3m 40s；repo `yi-fen/FilterKit`；手动触发。
- 本地基线：HEAD `e6845aadfe2239aa119c5d3410a3234ca0051801`。`git diff e6845aa origin/main`：无 `.swift` 源码与 `.github/workflows/filterkit-build.yml` 内容差异；`scripts/check-adapter-isolation.sh` 仅远端执行位 100755→100644（CI 以 `bash scripts/...` 调用，不影响执行）；`Research/` 与设备私有 JSON 未随远端上传；远端另含 `PACKAGE-NOTE.md`。`metadata/` 内 `Package.swift`、`project.yml`、`Makefile`、`control`、工作流 yml 与本地逐文件 diff 一致。
- 时间：test 日志 `2026-11-19 00:08:34.633`（UTC）；alive check `2026-11-19T00:09:17Z`。
- 环境：macOS 26.7.2（25G332）；Xcode 26.6（build 17F113，`/Applications/Xcode_26.6.app`）；Apple Swift 6.3.3（swiftlang-6.3.3.1.3 clang-2100.1.1.101）；iPhoneSimulator26.5.sdk；测试目标平台 `arm64e-apple-macos14.0`；Testing Library 1902；模拟器设备 `5AB3DACF-C352-49D1-BF9A-3C0104FA4ED3`。工具链版本记录见 `logs/environment/3_Record toolchain versions.txt`。
- 同窗口另有失败 run `44359919722`（30m 6s，runner 等待/失败），其产物未随本批回传，不在本目录归档范围。

## 1. 门禁结论（对照 `Spec/Stage-2/Stage-2.3-CF4-Final-Acceptance-Gates.md`）

| 门禁 | 结论 | 证据口径 |
|---|---|---|
| G1 Build（Models / Adapters / Core 非 UI 目标） | ✅ 通过 | `logs/non-ui-build/swift-build.log`（`logs/non-ui-build/3_Build non-UI targets...txt`）：`Build complete! (11.99s)`；Models / Adapters / Core 全量编译；0 条 `error:`、0 条 `warning:` |
| G2 Test（全量 XCTest） | ✅ 通过 | `test/test-log.txt`：**Executed 405 tests，0 failures（0 unexpected），0 skipped**，38 套件全 passed；明细见 `test/test-summary.json` |
| G3 S1-05 独立过滤 | ✅ 通过 | `test/test-log-s105.txt`：15/15 passed，0 failure；摘要 `test/s1-05-summary.txt` |
| G4 GUI Tests | ✅ 通过 | `GUIPresentationTests` 8/8 passed（GUI-01～08） |
| G5 Isolation | ✅ 通过 | `iso/isolation-output.log` 7 项 OK；`iso/isolation-summary.json` 7 项 `passed`、`failed=0`；文本与摘要一一对应 |
| G6 App Build | ✅ 通过 | `app-build/app-xcodebuild.log`：`** BUILD SUCCEEDED **`，0 条 `error:`；1 条 `warning:` 为 appintentsmetadataprocessor 元数据跳过（未链接 AppIntents.framework，良性） |
| G7 Simulator 启动 | ✅ 通过 | `app-build/sim-launch.log`：bundle `com.filterkit.manager`，PID `7094`，alive check 进程行在位 |
| G8 Navigation（五页面） | ❌ 缺证 | 仅 `app-build/dashboard.png` Dashboard 首屏；Plugins / Detail / Diagnostics / Settings 未点击切换取证 |
| G9 Export（JSON 样本） | ❌ 缺证 | 无 `export/` JSON 样本与 Settings 导出截图；仅有 GUI-08 单测接缝往返 |
| G10 Share（Share Sheet） | ❌ 缺证 | 无 `share-sheet.png` 或 Share Sheet 调起取证 |

## 2. app-build 取证明细

- 编译：Models / Adapters / Core / FilterKit 四目标，arm64 + x86_64 双架构；日志全文 0 条 `error:`。
- 启动：bundle `com.filterkit.manager`，launch PID `7094`；alive check 行 `7094 0 UIKitApplication:com.filterkit.manager[6756][rb-legacy]`。
- 截图：`app-build/dashboard.png`（PNG 1206×2622 RGBA；MD5 `c17185ce753cfdb9abd73fdbe5b485e7`；SHA256 `3cba67182a0dae9b244976794ecd62da85fd6e07e04513795b87f0f02bba3edb`）。

### 截图内容（Dashboard 合成信封渲染）

- 标题 `FilterKit`；Environment：Jailbreak `RootHide`（绿标 RootHide）、ElleKit `ellekit 1.0.0`、Profile `roothide-preview`。
- Plugins：Total 3 / Paired 2 / Missing 1 / Parse Failed 1。
- System：JBROOT `/private/var/jb`（绿标 Confirmed）；TweakInject `/private/var/jb/Library/TweakInject`（绿标 Accessible）；Permission `Undetermined`（灰标 2.4 probe）。
- 底部 Tab：Dashboard（选中）/ Plugins / Diagnostics / Settings；脚注「只读界面：展示信封由 Core/Models 生成；本阶段不含扫描、启停或写入功能」。

## 3. 本轮取证缺口（闭环前补齐）

1. ~~**G1**：`build` job 未归档 `swift build` 日志~~ **已补证**（2026-11-19，Worker 日志包 `logs_120262177442.zip`）：`logs/non-ui-build/swift-build.log` 留存 `Build complete! (11.99s)`，0 error / 0 warning；Models / Adapters / Core 全量编译记录在案。
2. **G8**：模拟器内点击 Plugins / Detail / Diagnostics / Settings，按 C-F3 §2～§4 清单逐页截图归档。
3. **G9**：经 `ReportExporting` 接缝生成合法 JSON 样本，归档 `export/` 并回解析为等义信封；记录仅写 App 临时目录。
4. **G10**：调起系统 Share Sheet 并归档 `share-sheet.png`。
5. ~~environment job 工具链版本步骤日志未随包回传~~ **已补证**：`logs/environment/3_Record toolchain versions.txt`（macOS 26.7.2 / Xcode 26.6 / Swift 6.3.3 / SDK 26.5）。

## 4. 产物与归档

| 附件 | 大小 | SHA256 |
|---|---:|---|
| `filterkit-build-metadata 3.zip` | 7849 B | `4e2bbddbfaa1c9f81e8d23c39c6264e6a5f9d2a034bc944414fa906562159598` |
| `filterkit-app-build 2.zip` | 2740242 B | `09ff346869adfbf72e78c09e8aef5e4b96cfdf34e4aec4aee9ed94576cf257ee` |
| `filterkit-isolation.zip` | 891 B | `6573f5c14cd58f276ef101c3fd8722de982615e2b08d68fce57bdc26ef13da17` |
| `filterkit-test-log 2.zip` | 11102 B | `ab5800635028f653fae4f7051689cd6947e46175c6a48c4671bafbce04cc396c` |
| `logs_120262177442.zip`（Worker 全量步骤日志） | 180575 B | `d91bcd4667a73587061bc69c4aa327bb4cf6569428af033ac17cb4fd8976b104` |

- Artifact ID：`filterkit-app-build` 14483279990；`filterkit-isolation` 14484926020；`filterkit-test-log` 14485215351；`filterkit-build-metadata` 14484452808。
- Worker 日志包归档于 `logs/`（environment / build / test / isolation / app-build / artifact 六 job 步骤与 system 记录）；G1 编译步骤提取为 `logs/non-ui-build/swift-build.log`（SHA256 `7d7db4a542c1de1ecd942ec5132763a9c3c1cc059c58a748afa368aa0bbb68a0`）。
- 归档目录：`Tests/Stage2/evidence/run-44426297905-acceptance/`（`app-build/`、`iso/`、`test/`、`metadata/`、`build/`、`logs/`）。

## 5. 边界与未决观察项

- 本轮为 CI/Simulator 口径；合成信封不代表真实 RootHide 文件权限、真实加载或扫描结果。未修改 plist / 插件文件，未做启停 / 注入 / dpkg / 软链改动 / 配置写入；Parser 不推断 `loaded`。
- 归属识别（`Core/OwnershipResolver/`）仍未迁移；`loaded` 恒 `.unknown`；`permission.decision` 恒 `undetermined`；`pluginID` 稳定标识规则 0.2.0 定稿；PARSE-009-B 继续挂起。
- 真机目录扫描、真实插件加载、entitlement 放行、GUI 进程内 `jbroot()`、sandbox 放行、Rootless 真机兼容属 0.1-D，本轮不取证、不闭环。
