# R2 Runner 复测记录 — `swift test`（macOS Runner Debug 切片）

## 基线与环境

- 仓库：`yi-fen/FilterKit`；checkout `origin/main` `751d5ff7668e77301dfa33142273e6eb52225475`（depth=1）。
- Runner：macos-26-arm64，macOS 26.7.2（25G332），runner 2.338.2；Testing Library 1902；目标平台 `arm64e-apple-macos14.0`。
- Job 命令：`swift test 2>&1 | tee .build/test-log.txt`；job-run UUID `1f48b41a-6ca3-5515-afc1-53b57ea6bc1f`。
- 日志：`job-logs.txt`（397,467 B，SHA256 `e8a779bcdd91c269431c598ddc9e0223a28ed9381fc43e205289ea5fae323a43`）。
- 产物：artifact `filterkit-test-log.zip`（ID `14682256827`，17,844 B，SHA256 `b88a3fc4569606ddc4c73a9ec39c5568b3c63b32759d1744a8e2f2f0818bb5f6`）。

## 编译结论

- Core 引擎 `ReadOnlyDiagnosticsEngine.swift` 编译通过（`[126/146] Compiling Core ReadOnlyDiagnosticsEngine.swift`）；本切片无编译错误。
- 警告仅为新测试内 17 处 `'is' test is always true`（类型已由 `FKDiagnosticReport` 冻结，`is` 判定恒真），分布：
  - `AppInventoryTests.swift:18`
  - `DynamicLibrariesTests.swift:47-51`
  - `DiagnosticSummaryTests.swift:89-99,107`
- 本日志未覆盖 iphoneos26.5 arm64 Release / iphonesimulator26.5 arm64·x86_64 Debug 目标；iOS 两侧编译结论待对应 Runner  job 日志回填。

## 测试结论

- 总计 **569 tests，1 failure（0 unexpected）**，进程 exit 1。
- 18 枚 R2 诊断套件共 111 例：17 套件 0 失败；`FileIntegrityTests` 11 例中 1 失败。

| 套件 | 例数 | 结果 |
|---|---|---|
| JBRootDetectorTests | 6 | passed |
| DynamicLibrariesTests | 4 | passed |
| DylibScannerTests | 4 | passed |
| FilterPlistTests | 5 | passed |
| FilterRulesTests | 8 | passed |
| InjectorDetectorTests | 7 | passed |
| DPKGStatusParserTests | 6 | passed |
| DPKGOwnershipTests | 9 | passed |
| PackageMetadataTests | 6 | passed |
| FileIntegrityTests | 11 | **failed（1）** |
| FileSourceTests | 5 | passed |
| ConffilesTests | 6 | passed |
| PackageConflictTests | 4 | passed |
| HelperPreflightTests | 6 | passed |
| AppInventoryTests | 3 | passed |
| AppMetadataTests | 5 | passed |
| PluginAssociationTests | 8 | passed |
| DiagnosticSummaryTests | 8 | passed |

## 失败诊断

- 用例：`FileIntegrityTests.testResourceMagicSignatures`（`FileIntegrityTests.swift:40`）。
- 断言：sqlite magic 期望 `"sqlite"`，实际 `nil`。
- 根因：**测试夹具字节序写错**，非引擎缺陷。引擎 `magicFormat` sqlite 签名为 `53 51 4C 69 74 65`（`SQLite`：S Q L i t e）；夹具误写成 `53 51 69 4C 69 74 65`（L 与 i 换位），不命中第 3/4 字节判定。
- 处置（本地）：夹具改正为 `[0x53, 0x51, 0x4C, 0x69, 0x74, 0x65]`；17 处恒真 `is` 断言改为 `count >= 0` 守卫；引擎语义与既有口径未改。
- 待下一轮 Runner 复测：569 例 0 failure、冗余警告清零后回填本记录。

## 边界与口径

- 本轮仅修测试夹具与测试断言；未改冻结 Models、Adapter 协议、Plist Parser 语义、Stage1 fixtures。
- `loaded`/`installed`/`configured` 语义不变；unknown 不翻 false/failed/passed；静态关联 ≠ 实际注入。
- 本记录为 macOS Runner Debug 切片证据，不替代 iOS 编译门禁与真机 G10～G15 / R4-G 验收。
