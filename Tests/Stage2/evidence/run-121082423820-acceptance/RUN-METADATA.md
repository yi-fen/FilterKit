# RUN-METADATA.md — 0.1-D R2-A/B Runner 复验（G1～G9 通过；真机 G10～G15 挂起）

- Workflow run：`121082423820`；仓库 `yi-fen/FilterKit`，分支 `main`；工作流 `.github/workflows/filterkit-build.yml@refs/heads/main`。
- 检出 SHA：`59f3eb96a296c5ca8db908635275fc6f5b69c07f`（origin/main，各 job `git fetch` 复核；fetch-depth 1）。各 job 日志中 `Commit:` 行为 runner 镜像 provisioner 提交，非仓库 SHA。
- 本地基线：HEAD `10d74a4`（R2-A/B：D5 三类证据分离 + D6 路径一致性分层比较，未推送）。本轮核对：`metadata/Package.swift`、`Makefile`、`control`、`project.yml`、`metadata/.github/workflows/filterkit-build.yml` 与本地逐文件 diff 一致；Runner 检出 SHA 与本地 HEAD 不同名（历史远程经网页上传），归档结论以 Runner 实际日志为准，不声称本地 HEAD 已被本轮 Runner 逐行重新编译验证。
- 时间（UTC）：2026-11-20；environment 12:12:53 → 12:13:04；isolation 12:12:53 → 12:12:59；build 12:13:09 → 12:14:07；test 12:14:10 → 12:15:19；app-build 12:14:10 → 12:20:25；ui-acceptance 12:20:52 → 12:32:01；artifact 12:20:52 → 12:21:01。
- 环境：macOS 26.7.2（25G332）/ 标签 `macos-latest`；Xcode 26.6（17F113）；Apple Swift 6.3.3（swiftlang-6.3.3.1.3 clang-2100.1.1.101）；iOS / Simulator SDK 26.5；App target 部署目标 iOS 17.0，arm64 + x86_64 simulator 双架构。
- 本轮定位：R2-A/B 落地后第一次 Runner 复验。D5 将 entitlement 证据拆分为 signed / runtime / resourceAccess 三类（runtime 在 iOS 保持 unavailable/unknown，SecTask* 仅 macOS/Catalyst）；D6 以 raw / normalized / symlink / accessible 四层比较替换探针原始字符串 `==`；新增 10 例单测（D5 ×3、D6 ×7）。本轮仅 Runner / Simulator / 合成桩口径，真机门禁维持 pending/unknown。

## 1. 门禁结论（G1～G9，Runner / Simulator 日志可判）

| 验收门 | 结论 | 证据 |
|---|---|---|
| G1 非 UI Build（Models / Adapters / AppPresentation / Core + ReportRoundtripValidator） | ✅ `Build complete! (26.89s)`，0 error / 0 warning；新文件 `JBRootPathComparison.swift`（步骤 39/90）、`EntitlementEvidenceSource.swift`（步骤 86/114）参与编译 | `build/swift-build.log`、`logs/4_build.txt` |
| G2 全量 Swift 测试 | ✅ Executed **458 tests，0 failures（0 unexpected）**，0.212 (0.269) 秒；恰为 R1 基线 448 + R2 新增 10 | `test-log/test-log.txt`、`logs/3_test.txt` |
| G3 S1-05 配对映射独立过滤 | ✅ `PluginPairingS105FixtureTests` **15 tests，0 failures（0 unexpected）** | `test-log/test-log-s105.txt` |
| G4 探针专项套件（D1～D7） | ✅ 53 例 0 failure，见 §2 分列 | `test-log/test-log.txt` |
| G5 Adapter / 路线 / Core / App 隔离静态检查（Runner 实际执行） | ✅ 七项（1a/1b/2a/2b/3/4/4b）`passed`，`failed: 0` | `isolation/isolation-summary.json`、`isolation/isolation-output.log`、`logs/5_isolation.txt` |
| G6 既有回归无损伤（0.1-A / 0.1-B / 0.1-C / R1 基线） | ✅ 含在 458 例内，0 failure；无损伤记录 | `test-log/test-log.txt` |
| G7 App Build（Runner，xcodebuild 全量 App target） | ✅ `** BUILD SUCCEEDED **`；0 error；唯一 1 条 warning 为 `appintentsmetadataprocessor`「Metadata extraction skipped. No AppIntents.framework dependency found.」元数据跳过系统噪声，非 Swift 编译告警；`FilterKit.app` 产物落 DerivedData（见 §3） | `app-build/app-xcodebuild.log`、`logs/2_app-build.txt` |
| G7b 模拟器启动存活 | ✅ 设备 `5AB3DACF-C352-49D1-BF9A-3C0104FA4ED3`；`com.filterkit.manager` launch PID 6302；存活检查 `6302 0 UIKitApplication:com.filterkit.manager[c39f][rb-legacy]`；`dashboard.png` 1206×2622 RGBA，843,228 B | `app-build/sim-launch.log`、`app-build/dashboard.png` |
| G8 Diagnostics / 导航页面（Simulator，XCUITest） | ✅ 8 例 0 failure（238.195s）；EmptyState 1 / ExportFlow 1 / NavigationFlow 5 / ShareSheet 1 全 passed，明细见 §4 | `uitest/ui-test.log`、`logs/1_ui-acceptance.txt` |
| G9 JSON 导出 + 往返校验 + Share Sheet（Simulator） | ✅ 导出 `FilterKit-Report-0-1-0-preview.json`（5,295 B）；往返 `decodable=true`、`equalIgnoringGeneratedAt=true`、`messages=[]`；`SHA256SUMS` 落盘且本地复算一致；导出无错误 / Share Sheet / 空态禁用导出用例 passed | `export/`、`uitest/ui-test.log` |
| 全量日志错误扫描 | ✅ 无 `##[error]`、无 `Process completed with exit code 1`、无 `FAILED`、无 `Assertion Failure` / `XCUITestError`；日志中 `::error::` 字符串均为脚本条件分支内 echo 源码行，未实际触发 | `logs/` 全量 job 文本 |

## 2. 探针专项用例分列（53 例，0 failure）

| 套件 | 覆盖项 | 用例 | fail |
|---|---|---:|---:|
| `PermissionProbeStatusTests` | 六态分类、notExecuted 不计 failed | 4 | 0 |
| `PermissionProbeEvidenceTests` | 证据 id/operation 往返、可选 nil/null、错误字段保留 | 5 | 0 |
| `PermissionProbeReportTests` | 归集统计、notExecuted 不计 failed、generatedAt | 6 | 0 |
| `PermissionProbeProbeTests` | D2 JBROOT / D3 ElleKit / D4 文件·plist·dpkg / D5 entitlement·sandbox / D6 jbroot() 接缝 / 服务抛错隔离与身份保留；含 R2 新增 D5 ×3、D6 ×7 | 34 | 0 |
| `PermissionProbePresentationTests` | nil 空态、八分类分组、六态分级映射、unknown 不升级、denied → failure | 4 | 0 |

### 2.1 R2 新增 10 例（本轮全部 passed，test-log 已逐一核实）

**D5 三类证据分离（×3）**

- `testEntitlementEvidenceSourceCoversThreeSeparateClasses`
- `testEntitlementProbeRuntimeUnavailableRecordsPlatformReason`
- `testEntitlementProbeTagsRuntimeAndSignedSourcesSeparately`

**D6 四层路径一致性比较（×7）**

- `testJBRootComparatorNormalizesTrailingSlashDoubleSlashDotDot`
- `testJBRootAPIProbeNormalizedMatchDespiteRawDifferences`
- `testJBRootAPIProbeAccessibleLayerUnknownWithoutFileAccess`
- `testJBRootAPIProbeAccessibleMatchWithFileAccess`
- `testJBRootAPIProbeAccessibleFalseWhenUnreachable`
- `testJBRootAPIProbeUnknownWhenConfirmedPathMissing`
- `testJBRootComparatorVerdictRules`

## 3. G7 App 产物（DerivedData 保留件；二进制不入库、不进包）

路径：`app-build/DerivedData/Build/Products/Debug-iphonesimulator/FilterKit.app/`（Runner 产物，本轮未复制入 git 归档）

| 条目 | 大小（B） |
|---|---:|
| `FilterKit` | 123,808 |
| `FilterKit.debug.dylib` | 9,082,672 |
| `__preview.dylib` | 83,952 |
| `Info.plist` | 756 |
| `PkgInfo` | 8 |
| `_CodeSignature/CodeResources` | 2,321 |

- 代码签名：`FilterKit.debug.dylib`、`__preview.dylib`、`FilterKit.app` 均经 `codesign --force --sign -` 签名；`Validate` / `Touch` 通过。
- 导出信封（合成预览桩）：`baselineGeneratorVersion 0.1.0-preview`；plugins 3 / unknownItems 1 / warnings 1；环境字段 `jailbreakType roothide`、`ellekitImplementation ellekit`、`ellekitVersion 1.0.0`、`iosVersion 17.0.2`、`jbroot /private/var/jb`、`evidenceLevel partial`。
- **口径限制：** Dashboard 截图与导出 JSON 均为 `SyntheticReportFactory` 合成预览信封，不构成真机权限、真实加载或真实扫描结果证据。

## 4. G8 / G9 XCUITest 用例明细（8 例，0 failure）

| # | 用例 | 耗时（s） | 门禁 |
|---:|---|---:|---|
| 1 | `EmptyStateTests testExportDisabledWithoutEnvelope` | 82.670 | G9 空态禁用导出 |
| 2 | `ExportFlowTests testExportProducesShareLinkWithoutError` | 27.025 | G9 导出无错误 |
| 3 | `NavigationFlowTests testDashboardBaselineVisible` | 10.691 | G8 Dashboard 基线 |
| 4 | `NavigationFlowTests testDiagnosticsSectionsVisible` | 20.479 | G8 Diagnostics 分区断言 |
| 5 | `NavigationFlowTests testPluginDetailOpensFromRow` | 36.209 | G8 详情页 |
| 6 | `NavigationFlowTests testPluginsListSegmentsAndSearch` | 25.106 | G8 列表分段/搜索 |
| 7 | `NavigationFlowTests testSettingsVisible` | 18.491 | G8 设置页 |
| 8 | `ShareSheetTests testShareSheetOpensAfterExport` | 17.524 | G9 Share Sheet |

- 套件合计：NavigationFlow 5 例 110.977s；全量 8 例 238.195 (238.219) 秒。

## 5. 未通过 / 挂起项（不计 passed，不得以 CI / Simulator 替代）

### 5.1 真机门禁 G10～G15（pending / unknown）

| 编号 | 缺口 | 本轮状态 |
|---|---|---|
| G10 | GUI 进程内访问 JBROOT（`.jbroot-*`）权限 | ⬜ 未取证，pending/unknown |
| G11 | TweakInject 目录/文件可达 | ⬜ 未取证，pending/unknown |
| G12 | dylib / plist / dpkg status 真机读取 | ⬜ 未取证，pending/unknown |
| G13 | 进程 / 签名 entitlement、sandbox 放行 | ⬜ 未取证，pending/unknown；D5 runtime 证据在 iOS 仍为 unavailable/unknown |
| G14 | `jbroot()` 函数声明 / 链接 / 调用安全性与返回路径一致性 | ⬜ 未取证，pending/unknown；D6 分层比较器为接缝实现，禁止伪造 C 声明 / 弱链接 / dlsym |
| G15 | 冷启动后权限保持复验 | ⬜ 未取证，pending/unknown |

- 上述各项须 RootHide 真机真实 GUI 进程取证；模拟器 / CI / 合成桩不得替代；未取证项保持 pending/unknown，不判 passed。
- D5 进程/签名 entitlement 受支持读取接口、D6 `jbroot()` 签名与链接方式未在真机复核，当前为占位实现；接口核实后替换实现，协议快照与证据模型不变。

### 5.2 既有未决项（继续挂起）

- `OwnershipResolver` 未迁移；`loaded` 恒 `.unknown`；`permission.decision` 恒 undetermined；`pluginID` 稳定标识规则 0.2.0 定稿；PARSE-009-B 挂起。
- R1 记录中「D6 一致性比较当前为原始字符串 `==`，路径规范化 / 软链解析细化列为未决」一项，本轮已由四层比较器（raw / normalized / symlink / accessible）替换；symlink 层真机解析与 accessible 层真机文件访问仍待 G10/G14 取证。
- 0.1-C G10（Share Sheet / 空态复核）缺口作为已知限制带入，不豁免不签署；本轮 Simulator G9 通过不能替代 0.1-C 真机缺口证据。

## 6. 验收判定

- **Runner / Simulator 口径 G1～G9：通过。** 非 UI Build 0 error / 0 warning；全量 458 例 + S1-05 15 例 0 failure；探针 53 例全绿；隔离七项 passed；App Build `BUILD SUCCEEDED`、模拟器存活；XCUITest 8 例 0 failure；导出 JSON 往返校验通过、SHA256 一致；既有回归无损伤；工具链版本已录档。
- **0.1-D 里程碑：仍未闭环。** 真机门禁 G10～G15 未取证；不生成 0.1-D 签署结论，不进入 0.1-E。
- 本报告仅代表 Runner / Simulator / 合成桩口径，不构成真机权限、真实加载、`jbroot()` 真机可调用性或 Rootless 真机兼容证据。

## 7. 归档清单

- `logs/`：environment / isolation / build / test / app-build / ui-acceptance / artifact 七个 job 的分步文本日志（`0_artifact.txt`～`6_environment.txt`）与各 `system.txt`。
- `metadata/`：Runner 检出树的 `Package.swift`、`Makefile`、`control`、`project.yml`、`.github/workflows/filterkit-build.yml`。
- `build/swift-build.log`：非 UI 目标编译日志。
- `test-log/`：全量 `test-log.txt` 与 S1-05 `test-log-s105.txt`。
- `isolation/`：`isolation-summary.json`（机器可读）与 `isolation-output.log`。
- `app-build/`：`app-xcodebuild.log`、`sim-launch.log`、`dashboard.png`；DerivedData dylib/.app 二进制不入库。
- `uitest/`：`ui-test.log`；`FilterKitUITests.xcresult/` 数据束不入库、不进包。
- `export/`：`FilterKit-Report-0-1-0-preview.json`、`roundtrip-result.json`、`SHA256SUMS`。

## 8. 上传产物（Runner artifact）

| Artifact | ID | 大小（B） | 上传 SHA256 digest |
|---|---:|---:|---|
| `filterkit-app-build` | 14628406277 | 3,290,345（9 files） | `49ef3208cdb04284d7f2f27d3881dcf945577ea557ec2d180ad9ffe478bd6b40` |
| `filterkit-build-metadata` | 14627119636 | 9,581（5 files） | `d84e2b7516910de53b9f1aa55b51eb1b3445d30bbe53faa3bed62e4074d19d48` |
| `filterkit-non-ui-build` | 14626939307 | 1,659 | `64449e9cd1458f5c2bca9b00aec8595884840ace813c6310dace7abdfd4e9a89` |
| `filterkit-isolation` | 14627382680 | 891 | `df99ce1e8f47bdb082ef695af0a7d45ebcc56ea350e8084b8257c6815e5052a4` |
| `filterkit-test-log` | 14628330697 | 12,547（2 files） | `56fc9ea9ed451ee05c3b19cd0f6c6f50f68dc4770b598f69f439b3a1f73abd94` |
| `filterkit-ui-acceptance` | 14628522739 | 3,988,631（75 files） | `c26cf6aabd3114c69340f1d757278432512c96a7f4314075622ac0eab4aa0165` |

- 第七份为本轮 logs 压缩包（`logs_121082423820.zip`），已解压入 `logs/`。
- G9 导出件本地复算：JSON `cfbf36262da34aa089fa58afc03863e370b9a3b40f2a7ac58be813a5807c80d7`；roundtrip `7b31c785d3f3f70dc615ef9d42e75dfb01cbb7e3cf3855d2c3b7a34efa49693f`。
