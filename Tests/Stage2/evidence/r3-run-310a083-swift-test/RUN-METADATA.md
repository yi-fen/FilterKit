# R3 Runner 记录 — `swift test`（macOS Runner Debug 切片，编译中止）

## 基线与环境

- 仓库：`yi-fen/FilterKit`；checkout `origin/main` `310a08358378e4f6f7c2ac7fd025a55582438b42`（depth=1，该提交不在本地对象库；错误签名与本地修复前文件一致）。
- Runner：macos-26-arm64，macOS 26.7.2（25G332），runner 2.338.2；Hosted Compute Agent commit `b8a594ea`，image `20261117.0516.1`；目标 `arm64-apple-macosx/debug`。
- Job 命令：`swift test 2>&1 | tee .build/test-log.txt`；run UUID `d73d52a0-2f62-46c2-ab6a-580cb0a57335`；job-run UUID `5636574d-0196-5484-8fa0-9aa69352e2a8`。
- 日志：`job-logs.txt`（53,200 B，SHA256 `e63530e755a1c3300fe2602ae72d174a8174beb51254e31d2a292e6ce7059493`）。
- 日志时间窗：2026-11-21 01:50:20Z → 01:51:24Z；进程 exit 1。

## 编译结论

- **测试目标编译失败，测试用例未执行**（无 `Executed tests` 汇总；R2 残留的 1 failure 与 17 警告本轮未复测到）。
- Core 侧 R3 文件全部进入编译清单且无 Core 报错：`DiagnosticEvidence.swift` / `DiagnosticEvidenceLevel.swift` / `DiagnosticEvidenceValidator.swift` / `DiagnosticFileSystem.swift` / `DiagnosticFileSystemError.swift` / `LocalDiagnosticFileSystem.swift` / `ReadOnlyDiagnosticsEngine.swift`（`[131/152]`～`[137/152]`）。
- 本切片 `warning:` 计数 0；无 `no such module` / 缺符号 / 类型转换类错误。
- 唯一编译错误（成员查找诊断重复展开）：

| 位置 | 错误 |
|---|---|
| `Tests/Stage2/Diagnostics/DiagnosticFileSystemTests.swift:62:45` | `error: value of type 'Set<String>' has no member 'keys'` |

## 失败诊断

- 根因：内存替身 `directories` 声明为 `Set<String>`，`listDirectory` 误写 `directories.keys`；`.keys` 是字典成员，集合应直接取值。属**测试夹具缺陷**，生产代码与引擎语义未涉。
- 本地修复：`Set(files.keys + directories.keys)` → `Set(files.keys + Array(directories))`；`files` 仍为字典，`files.keys` 保留。
- 修复后本地静态核对：括号配平 0 残差；无残留 `.keys` 误用；本机 Linux 无 Swift 工具链，编译通过与否以下一轮 Runner 为准。

## 待下一轮 Runner 回填

- macOS Debug `swift test`：R3 新增 FS 夹具 8 例 + 证据校验 13 例通过；既有 111 例无回归；R2 残留 1 failure 与 17 处恒真 `is` 警告一并复测清零。
- iphoneos26.5 arm64 Release / iphonesimulator26.5 arm64·x86_64 Debug 编译结论，本日志未覆盖。
- 若报 `no such module 'MachO.dyld'`：备选改 `import MachO`，禁止伪造 C 函数声明。

## 边界与口径

- 本轮仅修测试夹具成员访问；未改冻结 Models、`ReportEnvelope`、引擎解析语义、签名/打包脚本。
- 本记录为 macOS Runner Debug 切片证据，不替代 iOS 编译门禁与真机 G10～G15 / R4-G 验收；CI 绿灯不等于安装/启动验收通过。
