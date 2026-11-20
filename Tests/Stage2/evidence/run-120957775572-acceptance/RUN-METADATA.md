# RUN-METADATA.md — 0.1-D R1-A 接线恢复后 Runner 验收（G1～G9 通过；真机 G10～G15 挂起）

- Workflow run：`120957775572`；仓库 `yi-fen/FilterKit`，分支 `main`；工作流 `.github/workflows/filterkit-build.yml@refs/heads/main`。
- 检出 SHA：`4b08fe1a0c20bbd08dac40d0a58190d186e1a737`（origin/main，build job `git log -1 --format=%H` 复核；fetch-depth 1）。各 job 日志中 `Commit:` 行为 runner 镜像 provisioner 提交，非仓库 SHA。
- 本地基线：HEAD `d750247`（R1-A/B 接线恢复与 API 核实，未推送）。本轮核对：`metadata/Package.swift`、`Makefile`、`control`、`project.yml`、`metadata/.github/workflows/filterkit-build.yml` 与本地逐文件 diff 一致；Runner 检出 SHA 与本地 HEAD 不同名（历史远程经网页上传），归档结论以 Runner 实际日志为准，不声称本地 HEAD 已被本轮 Runner 逐行重新编译验证。
- 时间（UTC）：2026-11-20；environment 06:19:02 → 06:19:08；isolation 06:19:02 → 06:19:11；build 06:19:11 → 06:19:45；test 06:19:49 → 06:20:56；app-build 06:19:49 → 06:24:50；ui-acceptance 06:25:18 → 06:37:18；artifact 06:25:18 → 06:25:27。
- 环境：macOS 26.7.2（25G332）/ 镜像 `macos-26-arm64` 20261102.0473.1 / runner 2.338.2 / westus MacCloud；Xcode 26.6（17F113）；Apple Swift 6.3.3（swiftlang-6.3.3.1.3 clang-2100.1.1.101）；swift-driver 1.148.6；iOS / Simulator SDK 26.5；Swift 测试目标 `arm64e-apple-macos14.0`；XCUITest 目标 `arm64-apple-ios17.0-simulator`；Models/Adapters/Core 目标 `arm64-apple-ios12.0-simulator`。
- 本轮定位：R1-A 恢复 `app-build` / `ui-acceptance`(XCUITest) / `artifact` 依赖后，D7 之后第一次 XcodeGen + xcodebuild 全量 App target 构建与 Simulator 交互验证；G7 App Build、G8 Diagnostics 页面、G9 JSON 导出首次由 Runner/Simulator 实跑日志判定。

## 1. 门禁结论（G1～G9，Runner / Simulator 日志可判）

| 验收门 | 结论 | 证据 |
|---|---|---|
| G1 非 UI Build（Models / Adapters / AppPresentation / Core + ReportRoundtripValidator） | ✅ `Build complete! (13.28s)`，0 error / 0 warning；Models/Adapters/AppPresentation/Core emit，validator 编译并链接 | `build/swift-build.log`、`logs/4_build.txt` |
| G2 全量 Swift 测试 | ✅ Executed **448 tests，0 failures（0 unexpected）**；日志无 skipped 记录 | `test-log/test-log.txt`、`logs/3_test.txt` |
| G3 S1-05 配对映射独立过滤 | ✅ `PluginPairingS105FixtureTests` **15 tests，0 failures（0 unexpected）** | `test-log/test-log-s105.txt` |
| G4 探针专项套件（D1～D7） | ✅ 43 例 0 failure，见 §2 分列 | `test-log/test-log.txt` |
| G5 Adapter / 路线 / Core / App 隔离静态检查（Runner 实际执行） | ✅ 七项（1a/1b/2a/2b/3/4/4b）`passed`，`failed: 0`；本地脚本复跑 exit 0，结论一致 | `isolation/isolation-summary.json`、`isolation/isolation-output.log`、`logs/5_isolation.txt` |
| G6 既有回归无损伤（0.1-A / 0.1-B / 0.1-C 基线） | ✅ 含在 448 例内，0 failure；无损伤记录 | `test-log/test-log.txt` |
| G7 App Build（Runner，xcodebuild 全量 App target） | ✅ `** BUILD SUCCEEDED **`；0 error；1 条 warning 为 `appintentsmetadataprocessor`「No AppIntents.framework dependency found」元数据跳过系统噪声，非 Swift 编译告警；`FilterKit.app` 产物落 DerivedData（见 §3） | `app-build/app-xcodebuild.log`、`app-build/DerivedData/.../FilterKit.app/`、`logs/2_app-build.txt` |
| G7b 模拟器启动存活 | ✅ 设备 `EED6FB0A-E273-43C6-B5DE-3DF739543042`；`com.filterkit.manager` launch PID 4029；3 秒后存活 `4029 0 UIKitApplication:com.filterkit.manager[1de7][rb-legacy]`；`dashboard.png` 1206×2622 RGBA | `app-build/sim-launch.log`、`app-build/dashboard.png` |
| G8 Diagnostics / 导航页面（Simulator，XCUITest） | ✅ 8 例 0 failure（192.521s）；`testDiagnosticsSectionsVisible`、`testDashboardBaselineVisible`、`testPluginsListSegmentsAndSearch`、`testPluginDetailOpensFromRow`、`testSettingsVisible` 全 passed | `uitest/ui-test.log`、`uitest/FilterKitUITests.xcresult/`、`logs/1_ui-acceptance.txt` |
| G9 JSON 导出 + 往返校验 + Share Sheet（Simulator） | ✅ 导出 `FilterKit-Report-0-1-0-preview.json`；往返 `decodable=true`、`equalIgnoringGeneratedAt=true`、`messages=[]`；`SHA256SUMS` 落盘且复算一致；`testExportProducesShareLinkWithoutError`、`testShareSheetOpensAfterExport` passed；空态禁用导出用例 passed | `export/`、`uitest/ui-test.log` |
| 全量日志错误扫描 | ✅ 无 `##[error]`、无 `Process completed with exit code 1`、无 `FAILED`、无 `Assertion Failure` / `XCUITestError`；日志中 `::error::` 字符串均为脚本条件分支内 echo 源码行，未实际触发 | `logs/` 全量 job 文本 |

## 2. 探针专项用例分列（43 例，0 failure）

| 套件 | 覆盖项 | 用例 | fail |
|---|---|---:|---:|
| `PermissionProbeStatusTests` | 六态分类、notExecuted 不计 failed | 4 | 0 |
| `PermissionProbeEvidenceTests` | 证据 id/operation 往返、可选 nil/null、错误字段保留 | 5 | 0 |
| `PermissionProbeReportTests` | 归集统计、notExecuted 不计 failed、generatedAt | 6 | 0 |
| `PermissionProbeProbeTests` | D2 JBROOT / D3 ElleKit / D4 文件·plist·dpkg / D5 entitlement·sandbox / D6 jbroot() 接缝 / 服务抛错隔离与身份保留 | 24 | 0 |
| `PermissionProbePresentationTests` | nil 空态、八分类分组、六态分级映射、unknown 不升级、denied → failure | 4 | 0 |

- 三轮修复点（dpkg 11 bytes 断言、字典键兜底、errno `POSIXErrorCode.` 前缀）本轮随套件复核 passed；`Stage2Tests` 无 UITests unhandled 告警。

## 3. G7 App 产物（DerivedData 保留件）

路径：`app-build/DerivedData/Build/Products/Debug-iphonesimulator/FilterKit.app/`

| 条目 | 大小（B） |
|---|---:|
| `FilterKit` | 123808 |
| `FilterKit.debug.dylib` | 8944448 |
| `__preview.dylib` | 83952 |
| `Info.plist` | 756 |
| `PkgInfo` | 8 |
| `_CodeSignature/CodeResources` | 2321 |

- 代码签名：`FilterKit.debug.dylib`、`__preview.dylib`、`FilterKit.app` 均经 `codesign --force --sign -` 签名；`Validate` / `Touch` 通过。
- 导出信封（合成预览桩）：`schemaVersion 0.1.0`、`generatorVersion 0.1.0-preview`、`profile.id roothide-preview`、`profile.route roothide`；plugins 3 / unknownItems 1 / warnings 1；顶层键 `environment/generatorVersion/plugins/profile/schemaVersion/unknownItems/warnings`。
- **口径限制：** Dashboard 截图与导出 JSON 均为 `SyntheticReportFactory` 合成预览信封（RootHide·ellekit 1.0.0·3 插件·JBROOT `/private/var/jb` Confirmed·TweakInject Accessible·Permission Undetermined 2.4 probe），不构成真机权限、真实加载或真实扫描结果证据。

## 4. G8 / G9 XCUITest 用例明细（8 例，0 failure）

| # | 用例 | 耗时（s） | 门禁 |
|---:|---|---:|---|
| 1 | `EmptyStateTests testExportDisabledWithoutEnvelope` | 38.938 | G9 空态禁用导出 |
| 2 | `ExportFlowTests testExportProducesShareLinkWithoutError` | 23.749 | G9 导出无错误 |
| 3 | `NavigationFlowTests testDashboardBaselineVisible` | 12.500 | G8 Dashboard 基线 |
| 4 | `NavigationFlowTests testDiagnosticsSectionsVisible` | 22.158 | G8 Diagnostics 分区断言 |
| 5 | `NavigationFlowTests testPluginDetailOpensFromRow` | 34.190 | G8 详情页 |
| 6 | `NavigationFlowTests testPluginsListSegmentsAndSearch` | 25.240 | G8 列表分段/搜索 |
| 7 | `NavigationFlowTests testSettingsVisible` | 14.119 | G8 设置页 |
| 8 | `ShareSheetTests testShareSheetOpensAfterExport` | 21.628 | G9 Share Sheet |

## 5. 未通过 / 挂起项（不计 passed，不得以 CI / Simulator 替代）

### 5.1 真机门禁 G10～G15（pending / unknown）

| 编号 | 缺口 | 本轮状态 |
|---|---|---|
| G10 | GUI 进程内访问 JBROOT（`.jbroot-*`）权限 | ⬜ 未取证，pending/unknown |
| G11 | TweakInject 目录/文件可达 | ⬜ 未取证，pending/unknown |
| G12 | dylib / plist / dpkg status 真机读取 | ⬜ 未取证，pending/unknown |
| G13 | 进程 / 签名 entitlement、sandbox 放行 | ⬜ 未取证，pending/unknown；D5 仍占位实现 |
| G14 | `jbroot()` 函数声明 / 链接 / 调用安全性与返回路径一致性 | ⬜ 未取证，pending/unknown；D6 仍占位 resolver，禁止伪造 C 声明 / 弱链接 / dlsym |
| G15 | 冷启动后权限保持复验 | ⬜ 未取证，pending/unknown |

- 上述各项须 RootHide 真机真实 GUI 进程取证；模拟器 / CI / 合成桩不得替代；未取证项保持 pending/unknown，不判 passed。
- D5 进程/签名 entitlement 受支持读取接口、D6 `jbroot()` 签名与链接方式未在真机复核，当前为占位实现；接口核实后替换实现，协议快照与证据模型不变。

### 5.2 既有未决项（继续挂起）

- `OwnershipResolver` 未迁移；`loaded` 恒 `.unknown`；`permission.decision` 恒 undetermined；`pluginID` 稳定标识规则 0.2.0 定稿；PARSE-009-B 挂起；D6 一致性比较当前为原始字符串 `==`，路径规范化 / 软链解析细化列为未决。
- 0.1-C G10（Share Sheet / 空态复核）缺口作为已知限制带入，不豁免不签署；本轮 Simulator G9 通过不能替代 0.1-C 真机缺口证据。

## 6. 验收判定

- **Runner / Simulator 口径 G1～G9：通过。** 非 UI Build 0 error / 0 warning；全量 448 例 + S1-05 15 例 0 failure；探针 43 例全绿；隔离七项 passed；App Build `BUILD SUCCEEDED`、模拟器存活；XCUITest 8 例 0 failure；导出 JSON 往返校验通过、SHA256 一致；既有回归无损伤；工具链版本已录档。
- **0.1-D 里程碑：仍未闭环。** 真机门禁 G10～G15 未取证；不生成 0.1-D 签署结论，不进入 0.1-E。
- 本报告仅代表 Runner / Simulator / 合成桩口径，不构成真机权限、真实加载、`jbroot()` 真机可调用性或 Rootless 真机兼容证据。

## 7. 归档清单

- `logs/`：environment / build / test / isolation / app-build / ui-acceptance / artifact 七个 job 的分步文本日志（`0_artifact.txt`～`6_environment.txt`）与各 `system.txt`。
- `metadata/`：Runner 检出树的 `Package.swift`、`Makefile`、`control`、`project.yml`、`.github/workflows/filterkit-build.yml`。
- `build/swift-build.log`：非 UI 目标编译日志。
- `test-log/`：全量 `test-log.txt` 与 S1-05 `test-log-s105.txt`。
- `isolation/`：`isolation-summary.json`（机器可读）与 `isolation-output.log`。
- `app-build/`：`app-xcodebuild.log`、`sim-launch.log`、`dashboard.png`、`DerivedData/.../FilterKit.app/` 产物保留件。
- `uitest/`：`ui-test.log` 与 `FilterKitUITests.xcresult/`。
- `export/`：`FilterKit-Report-0-1-0-preview.json`、`roundtrip-result.json`、`SHA256SUMS`。

## 8. 上传产物（Runner artifact）

| Artifact | ID | 大小（B） | 上传 SHA256 digest |
|---|---:|---:|---|
| `filterkit-build-metadata` | 14606823120 | 9559 | `9c63647cabfefdaa8cf40c4ce00b389757b04a2c72193380816c77a87cd1cd45` |
| `filterkit-non-ui-build` | 14606687747 | 1645 | `5e8d38a2f9d4fa9c38712d98c913ea24d6c3f7aa814e29a17703ac3a81219456` |
| `filterkit-test-log` | 14607285914 | 12283 | `9baf60d3f8d6abc9d118941e6554d291f737c82b821526c699495d3a2b2958a5` |
| `filterkit-isolation` | 14606069404 | 891 | `3dd0f5ffd4a64313c01178897e39e5355da7ed4cfa17b4e3465a36def7dc6ee5` |
| `filterkit-app-build` | 14607141957 | 3,252,196 | `4b2656e3656b9851a4eaa7192d5ac8c5f27d721cfe0306376674e7953373788d` |
| `filterkit-ui-acceptance` | 14608270061 | 4,247,887（75 files） | `ba5222095a1fb6ea708371d1be84e0702e9ede462afb74baf1a11a7cd828f292` |

- 第七份为本轮 logs 压缩包（`logs_120957775572.zip`），已解压入 `logs/`。
