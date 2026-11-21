# R3-C Runner 全链路验收切片 — run `44867010916`（commit `9e61348`）

> 口径：本记录仅代表 Runner / Simulator / 合成 preview 桩口径；不构成真机权限、真实加载、`jbroot()` 真机可调用性或 Rootless 真机兼容证据。真机门禁 G10～G15 / R4-G 继续 pending/unknown。

## 1. 运行事实

| 项 | 值 |
|---|---|
| Workflow run | `44867010916` |
| Runner 检出 commit | `9e61348380752d4286c4487f3a2867bcd1d00652`（远端 main，提交信息「上传 源码」） |
| 元数据生成时间 | 2026-11-21T04:41:22Z |
| Runner | GitHub Actions `1000001344`，macOS；Xcode 26.6；SDK iphoneos26.5 / iPhoneSimulator 26.5 |
| Swift 测试目标 | `arm64e-apple-macos14.0`，Testing Library 1902 |
| 模拟器 | `98A0BFA3-CEC3-4FD6-9916-5A2149774DBF`，iPhone 17 Pro，OS 26.2，arm64 |
| App Bundle | `com.filterkit.manager`；App `0.1.0` build `1`；最小系统 17.0 |
| 代码对齐 | `App/ Core/ Models/ Adapters/ Tools/ Tests/ Package.swift/ project.yml/ Config/ .github` 与本地 HEAD 逐文件一致；唯一差异为 `scripts/validate-ldid-signature.sh` 权限位（远端 644 / 本地 755，内容零差异）。R3-C 五枚源码/测试件在 Runner 检出树内在位。 |

## 2. 验收结论（日志实测值）

### G1 非 UI Build — passed

- `non-ui/swift-build.log`：`Build complete! (13.58s)`；**0 `warning:` / 0 `error:`**。
- R3-C 件进入编译清单：`DiagnosticsExportModels.swift`、`CombinedReportEncoder.swift`（`DiagnosticsReportMapper` 经测试目标编译）。

### G2/G6 全量 Swift 测试 — passed

- `test/test-log.txt`：**Executed 598 tests, with 0 failures (0 unexpected)**，3.150s（3.248s wall）。
- 基线 590 + R3-C 桥接 8 = 598，既有回归无损伤。
- `DiagnosticsExportBridgeTests` 8 例全部 passed：
  - `testCombinedExportPreservesEnvelopeFields`
  - `testCombinedExportRoundTripsDiagnosticsSection`
  - `testCompletedSectionMapsCategoriesAndPreservesPayload`
  - `testEmptyReportMapsToCompletedEmptySection`
  - `testFailedSectionKeepsPreviousTimeWithoutCurrentItems`
  - `testLoadedUnknownSurvivesRoundTrip`
  - `testNeverRunSectionContainsNoSyntheticItems`
  - `testRepeatedMappingUsesLatestReport`

### G3 S1-05 配对映射 — passed

- `test/test-log-s105.txt`：**15 tests, 0 failures (0 unexpected)**。

### G5 隔离静态检查 — passed

- `isolation/isolation-summary.json`：1a / 1b / 2a / 2b / 3 / 4 / 4b 七项 `passed`，`failed: 0`。

### G7 App Build（模拟器）— passed

- `app-build/app-xcodebuild.log`：`** BUILD SUCCEEDED **`；唯一 1 条 warning 为 `appintentsmetadataprocessor`「No AppIntents.framework dependency found」元数据跳过系统噪声，非 Swift 编译告警。
- 模拟器启动：`sim-launch.log` pid `12216`，alive check 2026-11-21T04:44:47Z，bundle `com.filterkit.manager` 存活；模拟器 `EED6FB0A-E273-43C6-B5DE-3DF739543042`。
- 产物（DerivedData，不入库）：`FilterKit` 123,808B、`FilterKit.debug.dylib` 11,124,400B、`__preview.dylib` 83,952B、`Info.plist` 758B、`PkgInfo` 8B、`_CodeSignature/CodeResources` 2,321B；`dashboard.png` 1206×2622 RGBA，841,545B。

### G8 XCUITest — passed（8/0）

- `ui-acceptance/ui-test.log`：**Executed 8 tests, with 0 failures (0 unexpected)**，153.992s（154.003s wall）；无 Assertion Failure / XCUITestError / `##[error]`。

| 用例 | 结果 | 耗时(s) |
|---|---|---:|
| EmptyState `testExportDisabledWithoutEnvelope` | passed | 28.674 |
| ExportFlow `testExportProducesShareLinkWithoutError` | passed | 14.755 |
| NavigationFlow `testDashboardBaselineVisible` | passed | 14.677 |
| NavigationFlow `testDiagnosticsSectionsVisible` | passed | 22.911 |
| NavigationFlow `testPluginDetailOpensFromRow` | passed | 21.026 |
| NavigationFlow `testPluginsListSegmentsAndSearch` | passed | 21.881 |
| NavigationFlow `testSettingsVisible` | passed | 13.235 |
| ShareSheet `testShareSheetOpensAfterExport` | passed | 16.833 |

- 上一切片（run `44861183809` / cf741b）唯一失败的 EmptyState 本轮复跑通过；无失败时刻 xcresult 层级快照可复核，**H1 冷启动时序临界 / H2 空态渲染未切换仍不能在代码层定论**，本轮结果与 H1（时序抖动）相容，但未排除 H2。

### G9 导出 / 往返校验 — passed（模拟器合成 preview）

- 导出 `ui-acceptance/export/FilterKit-Report-0-1-0-preview.json`，5,463B，SHA256 `f0c9feb38f3a1dc7434b1bb26ca80d47b787746c7a241ece863252cd014f7bfc`；`SHA256SUMS` 落盘且复算一致。
- `roundtrip-result.json`：`decodable=true`、`equalIgnoringGeneratedAt=true`、`messages=[]`；counts plugins 3 / unknownItems 1 / warnings 1；`baselineGeneratorVersion 0.1.0-preview`。
- 信封字段与旧合成基线逐字段一致；唯一新增为 `diagnostics` 段：`scanState=neverRun`、`items=[]`、`environment={}`、`schemaVersion=1`、`evidenceScope=read-only`（未扫描空段，无合成插件数据）。
- 上一切片 G9「容器 tmp 未扫到样本」本轮未复现：样本落盘并通过往返校验。

### 设备构建 / 打包静态链路（R4-A～E 口径）

- **device-build**：d1～d6 全 passed，`failed: 0`；iphoneos26.5，Release，`CODE_SIGNING_ALLOWED=NO`，主二进制 Mach-O 64-bit **arm64**（Non-fat），Bundle ID `com.filterkit.manager`，MinimumOSVersion 17.0。
- **IPA**：p1～p3 全 passed；结构包 SHA256 `525f190337136e2ae3d37e4eb7140daf1e270ab911e44b2ac79653bc53b87b7a`；未签名结构包，不等于可安装 IPA。
- **DEB**：e1～e9 全 passed，`failed: 0`；`iphoneos-arm64e`，control `0.1.0-1`，`Depends: firmware (>= 15.0)`，root:root，rootfs 相对路径无 `var/jb` 前缀，e7 源/包 parity `equal=true`；`signatureState=ldid_signed_embedded`；**`installableCandidate=false` / `installability=device_acceptance_pending`**；e9 设备门禁 PENDING（Bootstrap/amfid 接受与启动属真机验证）。DEB SHA256 `4525b3c18072e9114244f69f48eba53beed6f81a37229fc76513dc2ccc335bc7`。
- **ldid 静态校验**：`ldid_signed_static_valid`，1 枚 Mach-O，`LC_CODE_SIGNATURE` present all macho，嵌入 entitlement 与源 plist `exact_match`；`deviceAcceptance=unknown`、`deviceInstallable=false`。
- **entitlements 静态准备**：t1～t3 passed；四枚候选键 `platform-application`、`no-sandbox`、`AppBundles`、`AppDataContainers` 齐全，无未批准私有键。
- **deviceInstall**：`Device Install Pending`（R4-G 真机门禁，本轮未授权、不取证）。

## 3. 第二份真机诊断载荷（伴随本批上传，隐私不入库）

- 单文件 JSON 7,460,339B，SHA256 `77e97befa3bbf1d12d10ec2afd9144ef2522d7ae5b0d47862b0423ccbdc9ce2f`；`diagnostics.scanState=completed`，14,029 条，13 类计数与首份基线（`d3d2408a…cfff484`）逐项一致：fileOwnership 9,255 / integrity 3,466 / packages 376 / applications 266 / helperRegistrations 534 / dynamicLibraries 16 / injectorEvidence 28 / associations 8 / finding 10 / roots 5 / plugins 8 / filters 8；integrity `mismatch 146 / no_checksum_record 3,312 / checksum_unavailable 8`；10 条 finding 状态逐项相同。
- 信封仍为合成 preview（plugins 3 / unknownItems 1 / warnings 1）；诊断段为独立真机来源。**Build provenance / Export bridge provenance 仍 unknown/unverified，A6 not passed**；两份载荷 jbrand 容器标识不同，对应两次安装容器，不能据此认定 R3-C 链路在真机运行。
- 按隐私边界：该 JSON 不复制进本证据目录、不进 DevDocs 包、不作 fixture；基线定位见 `../r3-c-real-device-payload-baseline/BASELINE-METADATA.md`。

## 4. 未闭环 / 不计 passed

- **A6 真机验收未发生**：模拟器信封为合成 preview；真机完整 JSON 须顶层环境来自真实设备、diagnostics 来自同一次扫描。
- EmptyState H1/H2 未在代码层定论（本轮复跑 green，无失败快照）。
- DEB 安装 / 首次启动 / 重启启动三项无设备证据；`device_acceptance_pending`；H4 切片/签名/弱链接/rpath、H5 uicache/JBROOT 映射未闭环。
- C1～C5 真机闪退假设无 `.ips` / 系统日志，不猜根因；G10～G15、R4-G 挂起 pending/unknown；D5 runtime entitlement、D6 `jbroot()` 真机调用仍占位 unknown。
- 16.5 SDK 对 iOS 17.0.2 向下兼容待实测；设备二进制 Non-fat arm64 与 control `iphoneos-arm64e` 档位差异沿用既有口径记录。
- 0.1-D 未闭环不签署、不进 0.1-E。

## 5. 边界复核

- 本轮归档仅日志、汇总 JSON、模拟器合成导出与截图；未归档 IPA/DEB/`.app` 二进制、dylib、tar.gz、xcresult Data 束与真机私密 JSON。
- 未改冻结 Models / 信封既有字段 / Adapter 七方法协议 / Plist Parser 语义 / Stage1 fixtures；未触真机写操作、插件启停、dylib/dpkg/软链改动、注入、Helper/IPC/daemon、entitlement/签名放行；未推送远端。
