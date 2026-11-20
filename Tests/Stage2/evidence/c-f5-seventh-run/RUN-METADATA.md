# C-F5 七轮 Runner 复核记录（run `44555812135` / SHA `35674fec`，2026-11-19）

- 时间：2026-11-19 15:36:53Z ～ 15:59:25Z；Worker `{db40809f-69fa-47f0-afe4-ea9ff8d3b567}`；runner version 2.338.2；镜像 `macos-26-arm64`（image 20261112.0504）；Xcode 26.6（17F113），Swift 6.3.3，iPhoneSimulator26.5.sdk。
- 检出 SHA：**`35674fec7960292ff30edc551785c2b151db3b86`**（`git fetch --depth=1 origin +35674fec…:refs/remotes/origin/main`）。metadata 包内 `control` / `Makefile` / `Package.swift` / `project.yml` / `.github/workflows/filterkit-build.yml` 与本地工作树逐文件 `diff -q` 一致；六轮 `compare(_:_:)` 比较器修复与五轮搜索 `tap()` 聚焦修复已上 Runner（证据：非 UI `swift build` 0 error/warning；搜索用例通过；往返校验 `equalIgnoringGeneratedAt: true`）。
- 模拟器：UI 验收 `5AB3DACF-C352-49D1-BF9A-3C0104FA4ED3`（iPhone 17 Pro，iOS 26.2，arm64/x86_64）；app-build `98A0BFA3-CEC3-4FD6-9916-5A2149774DBF`，alive PID 7622，bundle `com.filterkit.manager`，alive check `2026-11-19T15:45:37Z`。
- 附件（artifact，retention 14 天）：

| Artifact | ID | 大小 |
|---|---|---|
| filterkit-isolation | 14546030840 | 891 B |
| filterkit-non-ui-build | 14545786554 | 1377 B |
| filterkit-test-log | 14545956693 | 11515 B |
| filterkit-app-build | 14545348466 | 3050574 B |
| filterkit-build-metadata | 14545718292 | 9126 B |
| filterkit-ui-acceptance | 14548602225 | 3987008 B |

## 用例执行结果（UI 自动化 8 tests，0 failure，0 unexpected，203.223s）

| 用例 | 结论 | 耗时 | 说明 |
|---|---|---|---|
| EmptyStateTests.testExportDisabledWithoutEnvelope | ✅ passed | 53.069s | 空信封导出入口禁用（ST-6） |
| ExportFlowTests.testExportProducesShareLinkWithoutError | ✅ passed | 19.290s | 导出链路与分享入口出现、无错误文案 |
| NavigationFlowTests.testDashboardBaselineVisible | ✅ passed | 10.045s | Dashboard 四计数与环境/系统行在位 |
| NavigationFlowTests.testDiagnosticsSectionsVisible | ✅ passed | 20.760s | 诊断分组卡片标识在位 |
| NavigationFlowTests.testPluginDetailOpensFromRow | ✅ passed | 21.491s | 行点按推入 Detail，`detail.plugin-id` 在位 |
| NavigationFlowTests.testPluginsListSegmentsAndSearch | ✅ passed | 45.154s | 五轮遗留搜索用例：先 `tap()` 聚焦再 `typeText("Preview")` 命中；`plugins.png` 归档 |
| NavigationFlowTests.testSettingsVisible | ✅ passed | 15.327s | Settings 导出入口在位 |
| ShareSheetTests.testShareSheetOpensAfterExport | ✅ passed | 18.088s | 点 ShareLink 后等待含 "Share" 元素；`share-sheet.png` 归档（G10 本体复核见门禁状态） |

## 其他门禁证据（七轮日志口径）

| 门禁 | 结果 | 证据 |
|---|---|---|
| Build（非 UI 目标） | ✅ | `swift-build.log`：110/110 `Build complete! (17.17s)`，0 `error:`、0 `warning:` |
| Test（全量 XCTest） | ✅ | `test-log.txt`：`Executed 405 tests, with 0 failures (0 unexpected)`（两行 0.296s） |
| S1-05 独立过滤 | ✅ | `test-log-s105.txt`：15 tests 0 failures；PAIR001～009 等 passed |
| GUI Presentation 单测 | ✅ | `GUIPresentationTests` GUI-01～08 八例全部 passed（15:39:29.625 套件 passed，含在 405 内） |
| Isolation | ✅ | `isolation-summary.json`：1a/1b/2a/2b/3/4/4b 全 passed，`failed: 0`；`isolation-output.log` 七项 OK 留存 |
| App Build | ✅ | `app-xcodebuild.log`：`** BUILD SUCCEEDED **`；FilterKit target deployment 17.0，bundle `com.filterkit.manager`；Models/Adapters/Core 12.0 |
| Simulator 启动 | ✅ | `sim-launch.log`：PID 7622 alive，bundle `com.filterkit.manager`；`dashboard-app-build.png` 基线 3/2/1/1 |
| Navigation（G8） | ✅ | 五面截图本体解包目视核验通过；搜索命中 `Preview Tweak`；分段 ALL/PAIRED/ISSUES 在位 |
| Export（G9） | ✅ | 样本落盘；`decodable: true`，`equalIgnoringGeneratedAt: true`，`messages: []`，计数 3/1/1；SHA256 与清单逐字一致；`set -euo pipefail` 下 `swift run` 后 `shasum` 步骤执行，validator exit 0 |
| Share（G10） | ⚠️ 部分，已搁置 | 用例 passed、附件归档解包；控制器调起有 `[ShareSheet]` 子系统日志旁证；但截图本体未呈现系统面板浮层，面板可见渲染未获像素/AX 级证据。2026-11-20 决定不再排程补证（详见 `C-F5-Gate-Status.md`） |

## 导出样本口径（`export/FilterKit-Report-0-1-0-preview.json`）

- schema `0.1.0`，generator `0.1.0-preview`；env roothide `/private/var/jb` iOS 17.0.2；plugins 3 / unknownItems 1 / warnings 1。
- 插件：`com.example.broken-plist` parse_failed / paired / manual；`com.example.orphan-plist` not_parsed / orphan_plist / unknown；`com.example.preview-tweak` valid / paired / dpkg_sileo。
- unknownItems：`Stray.plist` 孤立 plist（enumeration）；warnings：`PREVIEW-001` 合成预览信封（gui-preview）。字段未被 UI 裁剪。
- 样本仅写 App 临时目录（容器 `tmp/FilterKit-Report-0-1-0-preview.json`）；无信封样本导出入口禁用。

## 归档文件 SHA256

| 文件 | SHA256 |
|---|---|
| `job-logs-ui-acceptance.txt` | `3304b5be129dbfca56f3a5b431fdc748ce43ab67f7dbdb870d92bc762494a393` |
| `job-logs-test.txt` | `5a7fc357b809587311cf5561378dfa7c7bac04195637d393208f51e1ebf6374d` |
| `job-logs-app-build.txt` | `3605b7f3fe73ec3726115e0ab466a8522d06fb4d9db23bcb6d0ab317708b44fe` |
| `job-logs-build.txt` | `db605597a43946e39d0e022428c0dc1f80e8548f7657ba244f3167e5ca296a5e` |
| `job-logs-isolation.txt` | `f5683f2130d28ee85e9ee7a6a547e97907730dee2fc54320b76e1ea477b20345` |
| `ui-test.log` | `9bd55c8246d6f16ec011d0d8f2643262d486c62f80cddfe997e1626c263a0e12` |
| `test-log.txt` | `a0233e3f7bdb5c788d1356311b4ac1b18b04de1e4213179a44db0bc6afa17b8b` |
| `test-log-s105.txt` | `fcf420a348aaac18b33bf61ec56cf9fa2b78b21fef424d558b334e7ac511251f` |
| `isolation-output.log` | `bf3d31be4555e77dcb9246535c213324f70c2e04fcd967ebcd642b834f13e733` |
| `isolation-summary.json` | `1ebad9674d94971379b14be71aa63fd77873280d10ae32787eca070c5f7489c2` |
| `swift-build.log` | `a2fafc9a39f73937590c20f0431a5065d2783e7bd3ecddff186b0245dc3001ad` |
| `app-xcodebuild.log` | `9c0b78937f444210959d6912ae7185673cc898fa60e4a2f0ed84fe32783abb41` |
| `sim-launch.log` | `8b9cb8434d86d346dc424ca61c71ef07dfd93132a528acf2256643ca6b0a667e` |
| `export/FilterKit-Report-0-1-0-preview.json` | `cfbf36262da34aa089fa58afc03863e370b9a3b40f2a7ac58be813a5807c80d7` |
| `export/roundtrip-result.json` | `7b31c785d3f3f70dc615ef9d42e75dfb01cbb7e3cf3855d2c3b7a34efa49693f` |
| `export/SHA256SUMS` | `503606f1cfdc7accd5f6d1105592e644b514a419500144752e06659c136b810d` |
| `screenshots/dashboard.png` | `b82847832cf0e9516310c424940df6f9759dce988ff276c7201192764222773c` |
| `screenshots/diagnostics.png` | `489277dfb1bc5cdebd846145a99c949fe635d7170bdb56983e0dfb418b22aa3b` |
| `screenshots/plugin-detail.png` | `1d5cbf8da37ee90dbe724e0f649ab4452e93a0bdeb9c4f8d2f847c105b743800` |
| `screenshots/plugins.png` | `fa10d98366d6127436200581b58b8b3cd379ef10a1c616f8f328f640ef581814` |
| `screenshots/settings-exported.png` | `e17adba33ff3460f0e6d04622b6cb41890e6a2444a37c10a37dbde2c3ad4630d` |
| `screenshots/settings.png` | `fa4d528f9b1e558df8caeea7533922955baa134817339fad16130dcb05bd1c9b` |
| `screenshots/share-sheet.png` | `d191ac7d7ab085858ea8adf322f88c6d9b1d964c236a60026c97ad30cfce7e30` |
| `screenshots/dashboard-app-build.png` | `e6d35064304fb332a9d517b2155b2f7c5c0c06bcded89352b977d1beb3e3f771` |

## 截图附件 ↔ xcresult blob 映射（本机解包核验）

| 附件名 | payloadRef 哈希前缀 | 本体大小 | 目视内容 |
|---|---|---|---|
| `dashboard.png` | `0~GvfOk8rRBf3M…` | 704778 B | Dashboard：RootHide / ellekit 1.0.0 / roothide-preview；3 Total / 2 Paired / 1 Missing / 1 Parse Failed；JBROOT Confirmed；TweakInject Accessible；Permission Undetermined |
| `diagnostics.png` | `0~2cYcDPayVWIu…` | 826104 B | Diagnostics：Environment（类型/实现/版本/profile/iOS/架构/证据等级）、JBROOT、Dynamic Libraries 分组 |
| `plugin-detail.png` | `0~z9vlNLH6zjcf…` | 810795 B | Detail：Preview Tweak / `com.example.preview-tweak`；Status Installed/Configured/Loaded Unknown/Validation Valid/Permission Undetermined；Files dylib + plist 路径 |
| `plugins.png` | `0~V8eMF8Sphfbf…` | 265769 B | Plugins：搜索框 `Preview` 聚焦命中 Preview Tweak 行；ALL/PAIRED/ISSUES 分段；键盘在位 |
| `settings-exported.png` | `0~A0v0rg-jEu15…` | 192704 B | Settings（导出后）：Schema 0.1.0 / Generator 0.1.0-preview；Export JSON Report + Share Report 在位 |
| `settings.png` | `0~lJydLPdiygRx…` | 184531 B | Settings（导出前基线）：仅 Export JSON Report 入口 |
| `share-sheet.png` | `0~Kf3cRSh0SzgI…` | 193441 B | 截图本体为 Settings 底层视图（Share Report 行在位），**未见系统分享面板浮层/活动图标行** |

## 本轮无源码改动

- 七轮为纯复核运行；本地归档提交 `97ac6a8`（未推送），工作树未新增 `.swift` / 清单改动。
- 本机 Linux 无 Swift/Xcode，编译、渲染、测试结论以 Runner 日志与解包截图为准。
- **2026-11-20 决定**：G10 剩余验证搁置，不再排程；0.1-C 维持未闭环，缺口作为已知限制带入后续阶段。
