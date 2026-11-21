# FilterKit DevDocs 0.1 — 打包说明

- 打包时间：2026-11-21（Asia/Shanghai）
- 本地基线提交：`b750802`（R3-A/B 实现 + `310a083` 反馈切片归档与夹具修复 + 真机截图批次 `1795227596` 三方核对归档；未推送；Runner 结论以在线日志为准，本机 Linux 无 Swift/Xcode、无 RootHide 真机）
- 当前 DevDocs 包：`FilterKit-DevDocs-0.1.zip`，包内 2175 文件，15,813,483 B，SHA256 `d226efafbbf5516d650980488c60d1080e2931a320950ce736fd4d2b720bfd63`；`unzip -tq` 无错误，清单与暂存目录一致；包内不内嵌自身哈希。
- 范围：规格文档（Spec/）、App/Core/Models/Adapters/Tools 源码、CI 工作流、Stage1~Stage2 测试与历史 Runner 证据归档、隔离/校验/打包/元数据脚本。
- 边界：0.1-C 维持未闭环（G10 搁置、不豁免不签署，缺口作为已知限制带入）；0.1-D Runner/Simulator 切片 G1～G9 通过（R2-A/B 复验 run `121082423820`）；R3-A/A2/F 与 R4 规格已冻结；R4-A～E 第五轮 TAR 权限保真链路生效、DEB 在打包前置版本校验中止（App `1.0` vs control 基线 `0.0.1`），已本地统一版本源至 App `0.1.0`/build `1` ↔ control `0.1.0-1`，待下一轮 Runner 复验出包；真机侧 IPA 可启动、DEB 打开闪退，无 `.ips`/系统日志，C1 签名封印 / C2 切片链接 / C3 布局注册 / C4 完整性 / C5 自身异常五类假设待设备取证；H4 切片/签名/弱链接、H5 uicache/JBROOT 映射未闭环，R3-B～F 真机取证待设备/GUI 上下文，真机门禁 G10～G15、R4-G 挂起 pending/unknown，里程碑未闭环、不进入 0.1-E。

## 0.1-D-R2 Diagnostics 离线测试落地（2026-11-21，待 Runner 复验）

规格：`Spec/Stage-2/Stage-2.5-D-R2-Acceptance-Plan.md`（§3 十八项覆盖矩阵、§4 可见性与提取清单、§5 静态核对口径、§6 记录）。本轮仅 D-R2-01 复测口径归档 + D-R2-02 离线测试；D-R2-03 FS 协议解耦、D-R2-04 证据等级、D-R2-05 DEB 闪退调查、D-R2-06 真机验收均未授权，留待后续批次。

- **引擎可见性与纯函数提取（行为不变）**：`ReadOnlyDiagnosticsEngine.swift` 将可离线纯表面由 private 放宽为 internal；`parseDpkgStatusText`/`conffilePathsFromFields` 从 FS 读取中提取为纯文本解析；新增 `classifyPluginSource`/`resolveAppVersion`/`isSystemApp`/`helperLogicalPath` 纯辅助；`identifyInjectors`/`buildAssociations` 无实例状态转 `static`。FS 遍历、句柄读取、流式哈希、私有 Workspace、dyld 运行时表面保留 deferred private，不提取不放宽。
- **离线测试**：`Tests/Stage2/Diagnostics/` 18 枚测试文件、111 个 `test` 方法；`Package.swift` Stage2Tests `sources` 同步接线。覆盖纯函数/纯聚合可离线表面；FS/私有 API/dyld 运行时项在文件头与规格矩阵标注 deferred，不写伪造断言。口径不变：`loaded`/`installed`/`configured` 语义不改；unknown 不自动翻 false/failed/passed；静态关联 ≠ 实际注入；MD5 仅对照 `.md5sums` 非签名；Mach-O 差异不判成因。
- **本地静态核对**：引擎 braces 288/288、parens 723/723、brackets 456/456、`#if`/`#endif` 12/12；18 枚新测试括号配平；无 `try!`/`as!`/强制解包/测试内 `jbroot()`/`dlsym`/FileHandle 读取；18 条 Package 接线与磁盘文件一一对应。本机 Linux 无 Swift/Xcode，Core emit-module 与 `swift test` 全套以 Runner 复测为准；无新一轮 Runner 日志前不认定 iOS 编译通过。
- **证据**：`Tests/Stage2/evidence/r2-device-screenshots-1795218890/`（7 张真机截图 + 合成预览信封 JSON + `METADATA.md`，D1～D5 计数/去重线索挂起 #331，本轮不修聚合语义）。
- **边界不变**：不改冻结公共 Models/ReportEnvelope/Adapter 七方法协议/Plist Parser 语义/Stage1 fixtures；不启停插件、不写 plist/规则、不动 dylib/dpkg/软链、不注入、不启 Helper/IPC/daemon、不放行 entitlement/签名；0.1-D 未闭环不签署、不进 0.1-E-B。
- **DevDocs 重打**：基线 `7428441`；包内 2154 文件；`unzip -tq` 无错误，清单与暂存目录一致；排除规则沿用既有口径；大小/SHA256 以交付附件复算为准；R2 Runner 四目标编译与 111 例测试结论待下一轮日志回填。

### R2 首轮 `swift test` 反馈（macOS Runner Debug 切片，基线 `751d5ff`，2026-11-21）

- Runner：macos-26-arm64 / macOS 26.7.2 / Testing Library 1902 / `arm64e-apple-macos14.0`；Core 引擎编译通过，本切片无编译错误；总计 **569 例，1 failure（0 unexpected）**，exit 1。证据 `Tests/Stage2/evidence/r2-run-751d5ff-swift-test/`（`job-logs.txt` 397,467 B + `RUN-METADATA.md`；artifact `filterkit-test-log.zip` ID `14682256827`，17,844 B，SHA256 `b88a3fc4…bb5f6`）。
- 唯一失败：`FileIntegrityTests.testResourceMagicSignatures` sqlite magic 夹具字节序写错（应为 `53 51 4C 69 74 65`），属测试夹具 bug；引擎 `magicFormat` 口径正确。警告：17 处新测试恒真 `is` 判定（`AppInventoryTests:18`、`DynamicLibrariesTests:47-51`、`DiagnosticSummaryTests:89-99,107`）。
- 本地修复（引擎未改）：夹具字节序改正；恒真 `is` 断言改为 `count >= 0` 守卫。待下一轮 Runner 复测 569 例 0 failure、警告清零回填；iphoneos/iphonesimulator 目标结论未在本日志覆盖。

## 0.1-D Acceptance R3 规格冻结（2026-11-21，仅规格，实现待下一批授权）

- 授权范围：D-R2-03（只读 FS 协议解耦）、D-R2-04（诊断证据等级与一致性）、D-R2-05（DEB 安装与启动验收，签名修复验证）；D-R2-06 真机验收、#331 截图计数/去重本轮仍冻结。
- 两条独立开发线、分别提交：线 A 诊断引擎 `Spec/Stage-2/Stage-2.6-D-R2-03-04-Diagnostics-Engine-R3-Plan.md`（03 → 04 顺序依赖；`Core/Diagnostics/Infrastructure/` 协议/本地实现/错误类型；内部证据模型 + E-01～E-09；不改公共 Models/信封/报告 JSON）；线 B DEB 验收 `Spec/Stage-2/DEB-Install-Crash-Investigation.md`（H4/H5/C1～C5 分组、Mach-O/签名/Bundle 静态检查、无 `.ips` 不猜根因；调查完成 ≠ 闪退修复完成）。
- 边界不变：只读访问；不新增写入接口；不把访问失败当不存在；不重写既有签名链路；不放开 entitlement/沙盒；不安装/启动/注入/daemon。本机 Linux 无 Swift/Xcode，R3 编译与测试结论待 Runner 复测。

## 0.1-D Acceptance R3-A/B 实现落地（2026-11-21，待 Runner 复测）

- **R3-A D-R2-03**：`Core/Diagnostics/Infrastructure/` 三枚只读协议件（`DiagnosticFileSystem` 五接口 / `DiagnosticFileSystemError` 五类 POSIX 映射 / `LocalDiagnosticFileSystem`）；引擎 JBROOT、Filter plist、dpkg status 与 info 目录（`.list`/`.md5sums`/`.conffiles`）三模块迁移至协议；动态库枚举、注入器指纹、Helper、Workspace App、流式句柄与静态文件类型触点保留 deferred `FileManager` 直连。
- **R3-A D-R2-04**：`Core/Diagnostics/Evidence/` 内部四等级 + 证据记录 + `DiagnosticEvidenceValidator`（E-01～E-09）；违规走既有 finding 通道，合规基线零新增 finding；公共 Models、`ReportEnvelope`、报告 JSON 字段零改动。
- **测试**：新增 `DiagnosticFileSystemTests`（内存替身，8 例）与 `DiagnosticEvidenceValidatorTests`（13 例）；Diagnostics 套件累计 132 个 `test` 方法。本地静态核对：括号/`#if` 配平零残差、无 `try!`/`as!`/强制解包/写入型 FS 接口、Package 接线与磁盘一一对应；Swift 编译与 `swift test` 全套以 Runner 复测为准。
- **R3-B D-R2-05**：仅验收准备记录 `Tests/Stage2/evidence/r3-b-deb-signing-prep/PREP-METADATA.md`；既有签名/打包脚本 `bash -n` 通过、CI job 在位；真机安装/首次启动/重启启动三项无设备证据，记 pending/unknown；未重写签名模块、未放宽校验。
- **本地提交（未推送）**：`951899c`（A1/A2 协议层）→ `133e12e`（A3/A4/A5 迁移）→ `adb9d32`（A6 FS 测试）→ `b422510`（A7/A8/A9 证据层与用例）→ `9fbe709`（B1 准备记录）；R3 实现基线 SHA 以包内 git 清单为准。
- **首轮 Runner 反馈切片**（`310a083`，macOS Debug）：测试目标编译中止，唯一错误为 FS 夹具 `Set<String>.keys` 误用（夹具缺陷，Core R3 文件编译无报错）；本地修复 `8edb06a`，全套用例与 iOS 两侧编译待下一轮 Runner 复测；证据 `Tests/Stage2/evidence/r3-run-310a083-swift-test/`。
- **真机截图批次 `1795227596`**：JSON 与合成信封 UI 逐项一致；底部 0.1.18 汇总 13 项计数与旧快照 `1795218890` 逐项相同，非新扫描；设备运行 0.1-C GUI 桩，未接入 R3 live 快照；证据 `Tests/Stage2/evidence/r2-device-screenshots-1795227596/`。

## 0.1-D Diagnostics-Port（2026-11-21，待 Runner 复验）

对照附件 `FilterKit-0.1.19-source.zip` 18 项只读诊断接口与两份 MD 口径，以 LDID-Signing-Fix 快照为签名基线做增量移植，未删除既有文件。

- **引擎增补**：`Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift` 在既有扁平化报告形态内补证据字段——JBROOT 置信度/标记/软链、目录软链、plist 顶层数据长度/类型/键/嵌套 `Filter` 字典、`*` 全局与命中/未命中 Bundles·Executables、注入器静态包证据 + 固定指纹库、包元数据与 dpkg 状态机拆解、文件存在/不可读/未校验分桶、MD5 三级类型分类与无校验记录桶、来源精确包记录、Helper 文件/注册明细、关联类别与汇总计数。顶层报告结构与公共类型不变；P1 六项同轮落地但缺证据项保持 unknown/unverified。
- **签名基线对齐**：新增独立校验脚本 `scripts/validate-ldid-signature.sh`（逐 Mach-O `LC_CODE_SIGNATURE`/CDHash + 主程序嵌入 entitlement 精确比对）；`sign-app-ldid.sh` 改为嵌套 Mach-O 临时签名不带主 entitlement、仅主程序注入候选 plist、签后委托独立校验；`verify` 同路径委托校验。`package-deb.sh`/`validate-deb.sh` 三态门禁与既有调用点不变。
- **记录**：`Spec/Stage-2/Stage-2.5-0.1-D-Diagnostics-Port-Plan.md`（18 项缺口矩阵、P0/P1 处置、保守口径、Acceptance 延迟项）。
- **本地静态核对**：十枚脚本 `bash -n`、workflow YAML 解析、Python 编译通过；引擎括号配平、残留现代 API/`RTLD_`/强制解包扫描通过；本机无 Swift 工具链，Core emit-module 与 `swift test` 全套待 Runner 复验。
- **边界不变**：全程只读，不启停插件、不写 plist/规则、不动 dylib/dpkg/软链、不注入、不启 Helper/IPC/daemon、不放行 entitlement/沙盒；签名/DEB 闪退仍是独立阻塞项，本轮不视为 amfid/Bootstrap 接受或启动验证；H4/H5、真机闪退 C1～C5、G10～G15、R4-G 沿用 pending/unknown；0.1-D 未闭环不签署、不进 0.1-E-B。

## 0.1-D Diagnostics-Port 首轮 Runner 编译反馈修复（run `44835136866`，待 Runner 复验）

诊断归档：`Tests/Stage2/evidence/0.1-d-run-44835136866-build-failure/`（`job-logs.txt` + `RUN-METADATA.md`）；Runner 基线 `828e69f9fcd90c4ea99c7e5cf73471ffd5eb00ab`。

- **Runner 事实**：`build` job（macos-26-arm64 / macOS 26.7.2）`swift build` 在 Core emit-module 阶段 exit 1（2026-11-20 23:14:08Z）；Models / Adapters / AppPresentation / ReportRoundtripValidator 均 emit/link 通过；错误与 1 条 warning 全部集中在 `Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift`；build 失败后未跑 `swift test`。artifact `filterkit-non-ui-build`（ID `14676389058`，2757B，SHA256 `71400283…b3fe2905`）。
- **三类诊断**：E1/E2（84 条）magicFormat 4 元组 switch 内 jpeg 3 元素 / gzip 2 元素模式长度错配；E3（42 条）内嵌 `logicalPath` 闭包 `String` 误用 `NSString.standardizingPath`；W1 非 UIKit 单元 `iconDecoded` 恒 false，返回字典三元 `bundle_file` 分支不可达。
- **修复（唯一源码文件 `Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift`，+14/-4）**：短缓冲签名在 switch 前按字节位置单独 `if` 判定，switch 内改通配 4 元组；`standardizingPath` 补 `as NSString` 桥接；`#if canImport(UIKit)` 两侧分别计算 `iconSource`，非 UIKit 侧直走候选/未解析口径。字段名、保守口径、公共类型与报告结构不变。
- **本地静态核对**：括号配平 279/279、703/703、450/450；`#if`/`#endif` 12/12；全仓无未桥接 `.standardizingPath`；其余 2 元组 switch 模式长度匹配。本机 Linux 无 Swift 工具链，编译结论待下一轮 Runner 复测 emit-module 与 `swift test`。
- **DevDocs 重打**：打包基线 `9760e69`（源码修复提交 `9b0c6c3`）；包内 2055 文件；`unzip -tq` 无错误，zip 清单与暂存目录一致，`validate-ldid-signature.sh` 条目模式 100755；大小/SHA256 以交付附件复算为准，包内不内嵌自身哈希。

## 0.1-D Diagnostics-Port 第二轮 Runner iOS 构建反馈修复（run `44836799174`，待 Runner 复验）

诊断归档：`Tests/Stage2/evidence/run-44836799174-ios-build-failure/`（77 文件解包结构 + `RUN-METADATA.md`）；Runner 基线 `fb8a6932bfe7d9f1f21bfe8b9cf68f167dd08790`。

- **Runner 事实**：9 个 job 中 environment / isolation（七项 passed，failed 0）/ signing-prep（entitlements t1～t3 passed）/ test（全量 458 + S1-05 15 例，0 failures）/ artifact 通过；非 UI macOS `swift build` `Build complete! (27.62s)`，首轮三类修复在 macOS 编译单元复测通过；device-build（iphoneos26.5 arm64 Release）与 app-build（iphonesimulator26.5 Debug，arm64 + x86_64 两切片）`BUILD FAILED` exit 65；package-validation 因无产物 Build/IPA/DEB 三态 Pending，Entitlements Static Passed、metadata JSON decodable。
- **诊断**：E1/E2（6 条，device 1 切片 + app 2 切片）`cannot find '_dyld_image_count' / '_dyld_get_image_name' in scope`，位于 `ReadOnlyDiagnosticsEngine.swift:454/455` `runtimeInjectorImages()`。两符号声明于 `<mach-o/dyld.h>`，属 `MachO.dyld` 子模块；macOS SwiftPM Darwin 伞头透出，iOS SDK 不经 Darwin 重导出，Xcode 显式模块编译单元下符号不在作用域。
- **修复（唯一源码文件 `Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift`，+4/-0）**：既有 `#if canImport(Darwin)` 块内追加 `import MachO.dyld`；调用点、函数签名、证据字段与保守口径不变；非 Darwin 平台整块排除。未改走 dlsym 动态解析，未写伪造 C 声明/弱链接。
- **本地静态核对**：括号配平 279/279、704/704、450/450；`#if`/`#endif` 12/12；全仓（排除 `research/`）无其他待导入 MachO 子模块符号；脚本 `bash -n`、Python 编译、YAML 解析通过。本机 Linux 无 Swift 工具链，device/app 编译结论待下一轮 Runner 复测。
- **DevDocs 重打**：打包基线 `3c8e6f8`（打包 HEAD 以包内清单为准）（源码修复提交 `d53a475`）；包内 2126 文件；`unzip -tq` 无错误，zip 清单与暂存目录一致，`validate-ldid-signature.sh` 条目模式 100755；大小/SHA256 以交付附件复算为准，包内不内嵌自身哈希。
- **边界不变**：未改 Adapter 七方法协议、冻结 Models、`ReportEnvelope`、Plist Parser 语义、Stage1 fixtures；当前进程 dyld 镜像证据仅限当前进程；未触插件启停、plist/规则写入、dylib/dpkg/软链改动、注入、Helper/IPC/daemon、entitlement/签名/沙盒例外；H4/H5、真机闪退 C1～C5、G10～G15、R4-G 沿用 pending/unknown；0.1-D 未闭环不签署、不进 0.1-E-B。

## 0.1-D-R4-B2 非界面层 `swift build` 编译失败修复（run `44820826563`，待 Runner 复验）

诊断归档：`Tests/Stage2/evidence/run-44820826563-non-ui-build/run-44820826563-b2-non-ui-swift-build-compile-diagnosis.md`。

- **Runner 事实**：`build` job（macos-26-arm64 / macOS 26.7.2 / Xcode 26.6 / MacOSX26.5.sdk）检出 `origin/main` `f13989a0846aa82c4dda6f813b16a9a08bdab93c`；Models / Adapters / AppPresentation emit-module 通过，Core emit-module exit 1，`Process completed with exit code 1`；artifact `filterkit-non-ui-build.zip`（4106B，ID `14671841990`，SHA256 `e30629f8…cc4cd8`）。报错仅集中在 `Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift`，四类诊断：L275/L288 `RTLD_DEFAULT` 宏在 Swift 作用域不可见（dlfcn.h:97 指针转换宏不被导入）；L554 `close()` 需 macOS 10.15+；L555 `read(upToCount:)` 需 macOS 10.15.4+。
- **修复（唯一源码文件 `Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift`，+16/-6）**：新增私有静态 `rtldDefaultHandle = UnsafeMutableRawPointer(bitPattern: -2)`，两处 `dlsym` 句柄由 `RTLD_DEFAULT` 改走该位模式常量（与 `((void *) -2)` 宏值一致，不依赖宏导入）；FileHandle 读取/关闭改旧式兼容接口 `closeFile()` / `readData(ofLength:)`，`sample` 去可选包装；未抬高 Deployment Target、未在 `Package.swift` 声明 `platforms:`、未加 `@available`/`if #available`，符号名与 `@convention(c)` 类型别名不变。
- **边界与待复验**：未改 Models/Adapters/AppPresentation/Core 其余子目录/Tests/Tools/CI 脚本；未弱链接、未伪造 C 声明、未放行 entitlement、未触真机写操作。本机 Linux 无 Swift/Xcode，仅做括号配平、残留现代 API 全树扫描与 `dlsym`/`RTLD_` 引用复核；待下一轮 Runner `swift build` 复验 Core emit-module 通过、`test` job 到达并跑全套 `swift test`。H4/H5、真机闪退 C1～C5、G10～G15、R4-G 沿用 pending/unknown；0.1-D 未闭环不签署、不进 0.1-E-B。

## 0.1-D-R4 第五轮（run `44797390321`）App/DEB 版本不一致中止诊断与版本单一源修复（待 Runner 复验）

诊断归档：`Tests/Stage2/evidence/r4-device-build/run-44797390321-round5-version-mismatch-diagnosis.md`。

- **第五轮离线事实**：第四轮权限保真 TAR 链路在 Runner 生效——artifact 下载、TAR 解包通过，主程序执行位保留（`-rwxr-xr-x 755 build/device-restored/FilterKit.app/FilterKit`）。唯一失败在 `package-deb` 前置一致性校验：`App version=1.0 does not match control Version base=0.0.1`，exit 1；e1～e9 未到达，DEB artifact 约 209B 为失败日志，非可安装包。原始 job-logs 签名链接过期未取回，事实按用户笔记与 R4-D2 快照源码转录。
- **根因分级**：R1 版本校验 fail-closed 拦截漂移（行为正确，未删除/未放宽）；R2 `project.yml` 文件型 `info.properties` 未显式携带 `CFBundleShortVersionString`/`CFBundleVersion`，`MARKETING_VERSION` 构建设置不回填文件型 plist，缺键被 Xcode 回退默认 `1.0`/`1`；R3 control 基线沿用旧工程占位 `0.0.1`，活跃 Models/Envelope/Factory/测试口径已是 `0.1.0`。
- **版本单一源修复**：`project.yml` 注入 `CFBundleShortVersionString=$(MARKETING_VERSION)`、`CFBundleVersion=$(CURRENT_PROJECT_VERSION)`，营销版本 `0.1.0`、构建号 `1`；control `Version: 0.1.0-1`（基线 `0.1.0` + 修订号 `-1`）；`Config/DEB/README.md` 写明版本单一源口径。预检可见性：device-build 打印 App 版本/构建号，package-deb 打印 control Version/基线，打包脚本预检输出两侧实际值，validate-deb e2 带 `AppVersion`/`ControlVersion`。
- **快照回填**：R4-D2 快照打包实现同步本地——`roothide.env` 档案元数据单一源、`compare-app-bundles.py` 全树 parity、package-deb 档案/可执行位/Bundle ID/版本基线校验与 ditto 暂存、validate-deb e1～e9 链、metadata profile 归集、workflow TAR 往返与同源 parity、R4-D2 实现记录归档。
- **本地演练**：正向桩包（`0.1.0`/build `1`）打包 exit 0，e1～e7 passed、e8/e9 Linux unavailable、parity `equal=true`；反向 App `1.0`、App `0.0.1`、Bundle ID 错误三种样例均在打包前置校验 exit 1 并打印两侧值；八脚本 `bash -n`、Python 编译、YAML 解析、元数据空输入 JSON 解码全过。
- **待复验与未闭环不变**：下一轮 Runner 须确认生成 plist 实测 `0.1.0`/`1`、DEB 正常出包且 e1～e7 passed；H4 切片一致性、H5 uicache/JBROOT 映射、真机闪退 C1～C5 仍待设备取证；G10～G15、R4-G 仍 pending/unknown，0.1-D 未闭环不签署、不进 0.1-E-B。

## 0.1-D-R4 第四轮（run `44783839130`）e5 bsdtar 误判修复 + DEB 闪退待证（待 Runner 复验）

诊断归档：`Tests/Stage2/evidence/r4-device-build/run-44783839130-round4-deb-crash-ownership-falsepositive.md`。

- **第四轮离线事实**：H1/H2 修复在 Runner 生效，DEB 命名 `iphoneos-arm64e`、e2 解出 arm64e + `firmware (>= 15.0)`；设备 Build Passed（iphoneos / Non-fat arm64 / MinOS 17.0 / Bundle ID `com.filterkit.manager`）；IPA Package Passed（内包 sha256 `68b96cf7…f6e8b5`）；DEB Package Failed——e1/e2/e3/e4 passed，e5 failed。全量 Swift 测试 0 failures、隔离七项 passed、XCUITest All tests passed；dpkg 1.23.12。
- **e5 误判定性**：Runner macOS bsdtar 列表为 `perms links owner group` 分列（`0 root root`），原 awk 按 GNU tar `owner/group` 单字段取 `$2`，拿到链接数 `0` 误判非 root；日志条目属主/属组实为 root:root。修复为双格式解析：`$2` 含 `/` 按 GNU 拆分，否则取 `$3`/`$4`；owner/group 归一化接受 `root`/`0`。本地 awk 单测混合格式正向 exit 0，三类非 root 反向 exit 1；桩包正向 e1～e5 passed、非 root 反向 e5 仍 FAIL。
- **真机闪退待证**：IPA/DEB 包装同一未签名 `.app`，CI `CODE_SIGNING_ALLOWED=NO`，entitlement 仅静态 plist 校验未嵌入签名页；DEB data tar 仅 5 条目，未见 Frameworks/PlugIns/`_CodeSignature`。五类假设（C1 签名/entitlement 封印缺失、C2 切片/弱链接/rpath、C3 布局/uicache/权限、C4 Bundle 完整性、C5 应用自身异常）须 `.ips` 终止原因与解包对比复核；本轮不碰运气追加 entitlement、不改 GUI/Core 代码。

## 0.1-D-R4 第三轮（run `44772873717`）DEB RootHide 隐根口径修复（待 Runner 复验）

诊断归档：`Tests/Stage2/evidence/r4-device-build/run-44772873717-round3-deb-roothide-diagnosis.md`。

- **第三轮离线事实**：第二轮归档层级修复生效，设备 `.app` Build Passed（iphoneos / Non-fat arm64 / MinOS 17.0 / Bundle ID `com.filterkit.manager`）；IPA Package Passed（sha256 `a198e927…00b5b`）；DEB 旧 arm64 命名包静态 Package Passed（e1～e4，sha256 `2c059442…e1d0`）。用户陈述：IPA 真机安装成功；DEB 经 RootHide 隐根转换后安装失败；日志包内无真机转换/dpkg 报错原文；5 张截图为 `gui-preview` 合成信封，不作扫描/权限证据。
- **同机对照取证**（0.1.18 设备报告，只读归档）：366 包中二进制档 83 个全部 `iphoneos-arm64e`、`iphoneos-arm64` 为 0；五个已装 App 包 control 均为 arm64e + `Depends: firmware (>= 15.0)`，数据归档为 rootfs 相对 `/Applications/*.app` 布局（无 `var/jb/` 前缀）。
- **离线修复（H1 架构档 / H2 firmware 依赖 / H3 属主 root:root）**：`Config/DEB/control` Architecture 改 `iphoneos-arm64e`、补 `Depends: firmware (>= 15.0)`；`package-deb.sh` 默认产物名改 arm64e 档，`dpkg-deb --build --root-owner-group` 强制 root:root（标量 flag 兼容 bash 3.2 `set -u`，旧版降级告警）；`validate-deb.sh` e2 锁定 arm64e + firmware，e4 拦截 rootless `var/jb/` 前缀泄漏，新增 e5 root:root 属主校验；workflow 三处产物名同步。
- **未闭环（H4/H5）**：设备二进制 Non-fat `arm64` 与 control 目标 arm64e 的切片一致性、arm64e 切片/弱链接 libroothide/roothide rpath、签名与 entitlement 放行、postinst uicache 行为与 JBROOT 映射，均属 R4-A/R4-G 真机门禁；打包层不伪造切片/签名。本地正向桩 e1～e5 全 passed，反向样例（旧 control / rootless 布局 / 非 root 属主）对应检查 FAIL；真机失败报错原文待设备侧补采后复核 H1～H5 排序。

## 0.1-D-R3-A2/F：部署包规格冻结与 R3 总方案补全（待真机，未编码未打包）

规格：`Spec/Stage-2/Stage-2.4-R3-Device-Validation-Plan.md`（§2/§3/§5/§6/§8 修订）、`Spec/Stage-2/Stage-2.4-R3-A2-Deployment-Package-Spec.md`（新建）；两份建议稿归档 `Tests/Stage2/evidence/r3-device-validation/R3-proposal-batch-sequencing.md`、`R3-proposal-deployment-deb.md`。

- **批次补全**：R3-A 方案冻结 → **R3-A2 部署包规格** → R3-B JBROOT/TweakInject → R3-C 文件与 dpkg 只读 → R3-D Entitlement/`jbroot()` → R3-E 冷启动复验与留证 → **R3-F 总体验收**（Runner 切片 + 真机门禁统一复核，门禁状态由证据重算）；其后才是 0.1-C G10 独立补证、0.1-D Final、0.1-E。R3-B～E 不做批次间正式 Runner 验收，但各自完成执行记录与证据归档。
- **内部检查点**：A（R3-B 后：路径正确、目录可达、确为 FilterKit GUI 进程、未拿 shell 结果充当 GUI 结果）；B（R3-C/D 后：读取与解析分离、Entitlement 三类分离、`jbroot()` 用真实 API、四层比较可追溯、无新增私有扫描器）；C（R3-E 后：冷启动前后设备/形态/代码版本一致、复测独立留证、证据 SHA256 一致、门禁状态可由证据重算）。
- **环境五冻结**：设备环境、部署形态、代码版本基线（commit SHA/Build Number/Bundle ID/部署 profile，中途变更须记新 SHA 并重判受影响门禁）、测试样本基线、证据环境；全程只读。
- **部署形态**：A 普通 IPA / B 特殊权限 App / C Bootstrap 通道 / **B+C 组合**（优先验证，最终真机证据决定）。DEB 为正式真机测试主载体，IPA 仅辅助对照；安装成功≠权限放行，安装位置/签名/entitlement/sandbox 四项分别验证。
- **R3-A2 规格范围**：DEB 建议结构（`Applications/FilterKit.app` + `DEBIAN/control`/`postinst`）；Bundle ID/版本/架构/Deployment Target 草案口径（B2/B3 仍未冻结）；control 最小字段口径；postinst 仅允许 uicache 注册、禁止改插件/注入规则/系统配置/起 daemon；entitlement 候选四枚（`platform-application`、`no-sandbox`、`AppBundles`、`AppDataContainers`）为参考清单，签名出现≠运行时放行；CI 静态检查与构建元数据（commitSHA/buildNumber/bundleID/scheme/ARCHS/SDK/builtAt/artifactSHA256）口径先行。
- **证据字段扩列**：DeviceValidationEvidence 补 deviceID/deviceModel/iOSVersion/RootHideVersion/ElleKitVersion/filterKitCommitSHA/filterKitBuildNumber/deploymentProfile；Swift 类型仍待 R3-B 落地。
- **边界**：本轮不改写现有 `control`/`Makefile`/`project.yml` 占位；不写落盘安装脚本、不打包、不签名、不真机安装；G10～G15 继续 pending/unknown；0.1-D 未闭环不签署、不进 0.1-E。

## 0.1-D-R4-A0：Device Build & Deployment 规格冻结与离线脚手架（待 Runner 离线复验）

规格：`Spec/Stage-2/Stage-2.4-R4-Device-Build-Deployment-Plan.md`；建议稿归档 `Tests/Stage2/evidence/r4-device-build/R4-proposal-device-build-deployment.md`。

- **两条并行路线**：产品开发路线推进 R4 设备构建/部署；发布验收路线保留 0.1-D 真机门禁，证据不足不签署、不发布；R4 不把未完成的真机问题带进 0.1-E。
- **批次**：R4-A 设备构建（`Release-iphoneos`，arm64 主目标，平台 iPhoneOS 校验）→ R4-B 签名与 entitlement（Developer 证书 / ldid 两路线区分，候选四枚键仅清单）→ R4-C IPA 结构打包（对照，未签名只称结构包）→ R4-D DEB 打包（优先方向，`Applications/FilterKit.app` + `DEBIAN/`）→ R4-E 包静态校验 → R4-F 部署文档；R4-G 真机启动冒烟门禁（8 项，启动失败如实记 failed，后续探针证据无效）。R4 先于 R3-B～E。
- **0.1-E 拆分**：0.1-E-A 验收引擎可提前开发（门禁注册/证据索引/SHA256/RunnerID/CommitSHA/环境检查/状态传播/验收 JSON，不访问真实 JBROOT，不产生发布通过结论）；0.1-E-B 最终验收必须等 0.1-C/0.1-D 闭环。
- **离线脚手架草案**：`Config/Signing/FilterKit.entitlements`（四枚候选键）、`FilterKit.Debug.xcconfig` / `FilterKit.Release.xcconfig`（离线 `CODE_SIGNING_ALLOWED=NO` 占位）；`Config/DEB/control`、`Config/DEB/postinst`（仅 uicache 注册）；`scripts/validate-device-build.sh`、`validate-ipa.sh`、`validate-deb.sh`、`validate-entitlements.sh` 静态校验；`scripts/package-ipa.sh`、`package-deb.sh` 打包草稿。`bash -n` 与 plist 良构通过；未编译设备包、未签名、未产出可安装包、未连真机。
- **边界**：不改冻结 Models/Adapter 七方法协议/Core 语义/既有模拟器 CI；脚手架接入 CI 与 Runner 复验前不视为可构建/可打包/可安装；G10～G15 与 R4-G 继续 pending/unknown。

## 0.1-D-R4-A～E：CI 设备构建 / IPA·DEB 打包 / 静态校验链路接线（待 Runner 离线复验）

授权稿归档 `Tests/Stage2/evidence/r4-device-build/R4-A-to-E-authorization.md`；验收报告 `R4-A-to-E-acceptance-report.md`。范围限定 R4-A～E，不授权 R4-G 真机冒烟、不授权 0.1-E-B 最终验收。

- **CI 五 job（`filterkit-build.yml`，macos-latest，复用既有 checkout/xcodegen/artifact 惯例）**：`device-build`（R4-A：Release `-sdk iphoneos -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO`，`validate-device-build.sh` 校平台/架构/Bundle ID/最低系统版本）；`signing-prep`（R4-B：`validate-entitlements.sh` 静态格式与候选清单校验）；`package-ipa`（R4-C：`package-ipa.sh` 未签名 Payload 结构包 + `validate-ipa.sh`）；`package-deb`（R4-D：`package-deb.sh` 测试 DEB + `validate-deb.sh`）；`package-validation`（R4-E：`collect-package-metadata.sh` 归集 SHA256 与三态标签）。R4 链路与既有模拟器链路并行独立，模拟器产物不作设备构建证据。
- **三态口径**：Build Passed = 生成 iPhoneOS 设备产物且静态校验 failed=0；Package Passed = IPA/DEB 结构符合静态检查；Device Install Passed 属 R4-G 真机门禁。本轮 Build/Package 均 Pending（待 Runner 实跑），Device Install Pending（未授权）。
- **脚本/配置**：新增 `scripts/collect-package-metadata.sh`；`Config/Signing/README.md` 区分 Developer 证书与 ldid 两路线、四条独立验证结论；`Config/DEB/README.md` 记录 control 字段口径与待实测项；`control` 去除 dpkg-deb 不接受的 `#` 注释与空 `Depends:`；`package-deb.sh` 校验 `dpkg-deb --build` 退出码；`validate-entitlements.sh` 无 plutil 时记 unavailable 不计 failed。
- **本地静态演练（占位桩，非设备证据）**：`bash -n` 八脚本全过；YAML 解析 12 jobs；entitlements plist 良构；元数据 JSON 可解码；占位假 App 演练 IPA 结构 passed（二进制非 Mach-O 如实 failed）、DEB e1～e4 passed。本机无 xcodebuild/swift/plutil/lipo，设备产物/实测值/Runner 日志待 `workflow_dispatch` 回填。
- **边界**：未编译设备包、未签名、无可安装 IPA/DEB、未连真机；未改冻结 Models/ReportEnvelope/Adapter 七方法协议/Core 语义与 loaded/installed/configured 语义；RootHide/Rootless Adapter 独立；未真机安装/Bootstrap 部署/签名放行验证/`jbroot()` 真机调用/插件写操作/dpkg 写。


## 0.1-D-R4 Runner 首轮失败诊断与修复（run `44758871580`，待二次复验）

诊断归档：`Tests/Stage2/evidence/r4-device-build/run-44758871580-round1-failure-diagnosis.md`；Runner 基线 commit `460a9906ffa51d4b317169e285c3c846290d1baf`。

- **device-build（非编译失败）**：macos-26-arm64 / macOS 26.7.2 / Xcode 26.6 / SDK iphoneos26.5；`xcodebuild ... CODE_SIGNING_ALLOWED=NO build` **BUILD SUCCEEDED**，产物 `Release-iphoneos/FilterKit.app`（Mach-O 64-bit arm64，3,294,752B）。中断于 `validate-device-build.sh` d3：`line 86: supported�: unbound variable`——裸变量 `$supported` 后直接紧跟全角右括号 `）`，Runner shell/区域设置下多字节字符被并入变量名，`set -u` 引用未绑定变量退出；`CFBundleSupportedPlatforms` 系数组，标量读取不适用。
- **package-validation（下游 + 归集无容错）**：`package-ipa`/`package-deb` 因 `needs: [device-build]` 被跳过，无 IPA/DEB 产物；归集步骤 `find build/r4-artifacts/filterkit-ipa: No such file or directory`，`pipefail` + `bash -e` 下 step exit 1，元数据 JSON 未产出。
- **本地修复（未编译未签名未装机）**：`validate-device-build.sh` d3 去掉数组取值、OK 行只报 `DTPlatformName=iphoneos`，d6 `$min_os` 改 `${min_os}`；`package-ipa.sh`/`package-deb.sh` 三处同类 `$STAGE` 改 `${STAGE}`；workflow `package-validation` 新增 `find_first()`（目录缺失返回空、stderr 丢弃），七个产物定位改走该函数，缺产物由归集脚本记 Pending 不中断归档。
- **本地静态演练**：八脚本 `bash -n` 全过；裸变量紧邻非 ASCII 扫描脚本与 YAML 无命中；YAML 12 jobs 良构；entitlements plist 良构；元数据脚本空输入 JSON 可解码、三态 Pending、exit 0；`find_first` 缺失/存在两路径模拟 exit 0。设备产物、IPA/DEB 结构包与 SHA256 实测值待二次 Runner 复验。
- **边界不变**：未改冻结 Models/`ReportEnvelope`/Adapter 七方法协议/Core 语义/Plist Parser 语义/Stage1 fixtures；未触真机写操作、插件启停、dylib 删移、dpkg 写、注入规则、entitlement/签名放行、常驻 daemon；未进 R4-G、未进 0.1-E-B。

## 0.1-D-R4 Runner 第二轮失败诊断与归档层级修复（run `44766814111`，待复验）

诊断归档：`Tests/Stage2/evidence/r4-device-build/run-44766814111-round2-failure-diagnosis.md`；Runner 基线 commit `211365cbf039f525a0bbc4f8608f44ca3c5e84e3`。

- **失败现象**：`package-ipa`（job run `614a21ed-12d8-59f5-9f6e-abe3021a8644`）与 `package-deb`（job run `67d8538d-43e0-5221-9e6e-3fd7812f6e54`）均成功下载 `filterkit-device-build`（ID `14645672385`，901,844B，digest `ae0b5ef2…02fb7`），但 `find build/device-artifact -name 'FilterKit.app' -maxdepth 4` 返回空，`device app missing` exit 1；IPA/DEB 上传 No files found。`package-deb` 侧 `brew install dpkg` 1.23.11 成功。
- **根因（CI 归档层级，非编译/链接失败）**：`device-build` 上传路径中日志在 `build/device/`、`.app` 在 `build/DerivedData-device/Build/Products/Release-iphoneos/FilterKit.app`；`upload-artifact@v7` 多路径取最小公共祖先 `build/` 为 artifact 根，下载后 `.app` 在第 5 层，`maxdepth 4` 命不中。
- **本地修复**：`device-build` 新增 Stage 步骤，上传前 `cp -R` 暂存 `.app` 到 `build/device/FilterKit.app`；上传路径改暂存副本，LCA 收窄到 `build/device/`，artifact 内 `.app` 位于根层（下载后第 1 层）。下游定位步骤与 `find_first()` 不改；打包 job 对缺 `.app` 保持硬失败，缺产物容错仍归 `package-validation` 归集层。
- **产物版本口径**：当前 CI 不区分 RootHide/Rootless 版本——单份未签名 `.app`/IPA/DEB，包名与 control 无路线维度，无双 scheme 矩阵；双路线仅体现在 `Adapters/RootHide`、`Adapters/Rootless` 两套独立适配器。前期默认只对 RootHide 路线负责（R4 规格即 RootHide Deployment Plan，唯一真机为 RootHide；Rootless 无设备，仅离线/合成验证，不得以 RootHide 结果覆盖）。Rootless 版本包待 Theos rootless scheme 接线与真机/样本到位后再分叉。
- **本地静态演练**：八脚本 `bash -n` 全过；YAML 12 jobs 良构；`/tmp` 层级模拟证实旧嵌套布局 `maxdepth 4` 落空、新 staged 布局第 1 层命中；`postinst` 越界扫描无命中。设备产物/IPA/DEB 实测值待下一轮 Runner；G10～G15、R4-G、0.1-E-B 状态不变，**0.1-D 未闭环不签署**。

## 0.1-D-R3-A：RootHide 真机验证方案冻结（待真机，未编码）

规格：`Spec/Stage-2/Stage-2.4-R3-Device-Validation-Plan.md`；用户建议稿归档 `Tests/Stage2/evidence/r3-device-validation/R3-proposal-user-conclusion.md`。

- **批次拆分**：R3-A 方案冻结 → R3-B JBROOT/TweakInject 访问 → R3-C 插件文件与 dpkg 只读 → R3-D Entitlement/`jbroot()` 真机验证 → R3-E 冷启动复验、Diagnostics 接入与归档；0.1-C G10 独立补证（独立门禁/独立证据，不并入 0.1-D 判定）；其后才是 0.1-D Final 签署与 0.1-E。R3-B～D 复用 R2 已落地探针，不另造扫描器。
- **执行矩阵**：G10 `jbroot.directory.access`、G11 `ellekit.directory.access`、G12 `plugin.file.metadata`/`plugin.plist.read`/`package.database.read`、G13 `entitlement.inspect`/`sandbox.resource.access`、G14 `jbroot-api.inspect`、G15 冷启动复测。stat/list/read/parse/inspect/invoke 各成独立证据，不跨操作推断成功；读取≠解析≠加载，`loaded` 继续恒 unknown。
- **证据模型**：复用冻结 `ProbeStatus` 六态/`ProbeOperation`/`ProbeCategory`/`ProbeEvidence`/`PermissionProbeReport`；R3 局部包装层（DeviceValidationEvidence/Gate/Report）R3-B 才落地 Swift 类型，不扩冻结信封；证据可追溯门禁/探针/操作/commit/runID/环境/文件 SHA256/时刻/设备与进程上下文（`processContext = FilterKit.GUI`）。
- **Preflight 与门禁**：设备档案、部署形态 A/B/C 冻结、commit 对齐、目标版本 libroothide 头文件/符号/链接核实、只读边界、样本基线、GUI 进程上下文、环境纯净、证据通道、工具链兼容性逐项确认后才进 R3-B。验收分 Runner 离线切片（458 基线不回退、模型往返、状态传播、映射、导出、隔离、App Build、Simulator 回归）与 RootHide 真机 G10～G15 两类；CI/Simulator 不替代真机，未完成项保持 pending/unknown。
- **边界**：本轮不编译、不建工程、不写真机调用；不调用真实 `jbroot()`、不写桥接声明/弱链接/dlsym；不做插件启停、plist 写入、dylib 删移、dpkg 写、注入规则修改、自动修复、常驻 daemon；0.1-E 仅预冻结设计不实现。

## 排除项

`.git/`、小写 `research/`（第三方上游克隆）、`node_modules/`、`build/`、`.theos/`、
`DerivedData/`、`.build/`、`.swiftpm/`、`*.xcodeproj/`、`*.xcworkspace/`、`.tmp/`、`.DS_Store`、
`*.zip`、`App/Info.plist`、`*.xcresult/`、`__pycache__/`、`*.pyc`；
大写 `Research/` 保留，仅排除 `Research/Validation/evidence/0.1.18-device-report.json`（设备私有数据）。
`.github/workflows/` 实时工作流纳入本包（CI 源码，非设备私有数据）。
编译产物（dylib / `.app` 二进制 / xcresult 数据束）不进交付包；G7 产物大小与签名结论以 `RUN-METADATA.md` 与构建日志为准。

## 0.1-D R2-A/B Runner 复验（run `121082423820`，SHA `59f3eb96`，G1～G9 通过；真机 G10～G15 挂起）

证据归档：`Tests/Stage2/evidence/run-121082423820-acceptance/`（分步日志、metadata、test-log、隔离产物、app-build 日志与截图、导出信封、`RUN-METADATA.md`；xcresult 数据束与 DerivedData 二进制按惯例不入库、不进包）。检出 SHA `59f3eb96a296c5ca8db908635275fc6f5b69c07f`（origin/main）；metadata 五文件（`Package.swift`、`Makefile`、`control`、`project.yml`、`.github/workflows/filterkit-build.yml`）与本地 `10d74a4` 代码基线逐文件 diff 一致。环境：macOS 26.7.2（25G332）/ Xcode 26.6（17F113）/ Swift 6.3.3（swiftlang-6.3.3.1.3 clang-2100.1.1.101）/ SDK 26.5。

**Runner / Simulator 口径 G1～G9：通过（日志实测值）。**

- G1 非 UI Build：`Build complete! (26.89s)`，0 error / 0 warning；新文件 `JBRootPathComparison.swift`（步骤 39/90）、`EntitlementEvidenceSource.swift`（步骤 86/114）参与编译。
- G2/G6 全量 Swift 测试：**458 tests，0 failures（0 unexpected）**，0.212 (0.269) 秒；恰为 R1 基线 448 + R2 新增 10；既有 0.1-A / 0.1-B / 0.1-C / R1 基线含在 458 例内，0 failure、无损伤。
- G3 S1-05 配对映射：`PluginPairingS105FixtureTests` **15 tests，0 failures（0 unexpected）**。
- G4 探针专项 53 例全绿：Status 4 / Evidence 5 / Report 6 / Probe 34（基线 24 + R2 新增 10）/ Presentation 4。
- G5 隔离静态检查：1a/1b/2a/2b/3/4/4b 七项 `passed`，`failed: 0`。
- G7 App Build：`** BUILD SUCCEEDED **`，0 error；唯一 1 条 warning 为 `appintentsmetadataprocessor`「No AppIntents.framework dependency found」元数据跳过系统噪声，非 Swift 编译告警。`FilterKit.app` 产物保留于 DerivedData：`FilterKit` 123,808B、`FilterKit.debug.dylib` 9,082,672B、`__preview.dylib` 83,952B、`Info.plist` 756B、`PkgInfo` 8B、`_CodeSignature/CodeResources` 2,321B；dylib 与 bundle 均签名并 Validate/Touch 通过。模拟器设备 `5AB3DACF-C352-49D1-BF9A-3C0104FA4ED3`，`com.filterkit.manager` launch PID 6302 存活；`dashboard.png` 1206×2622 RGBA，843,228B。
- G8 Diagnostics / 导航页面：XCUITest **8 例 0 failure（238.195s）**；EmptyState 1 / ExportFlow 1 / NavigationFlow 5 / ShareSheet 1 全 passed。
- G9 JSON 导出 / 往返校验 / Share Sheet：导出 `FilterKit-Report-0-1-0-preview.json`（5,295B，plugins 3 / unknownItems 1 / warnings 1，`baselineGeneratorVersion 0.1.0-preview`）；往返 `decodable=true`、`equalIgnoringGeneratedAt=true`、`messages=[]`；`SHA256SUMS` 落盘且本地复算一致；导出无错误、Share Sheet、空态禁用导出三例 passed。
- R2 新增 10 例（D5 ×3：三类来源覆盖、runtime 不可用平台原因、runtime/signed 来源分标；D6 ×7：规范化、raw 失配 normalized 匹配、无访问器 accessible=unknown、有访问器可达匹配、不可达 accessible:false、确认路径缺失 unknown、verdict 规则四分支）在 test-log 中逐一 passed。
- 全量日志无 `##[error]`、无 exit code 1、无 `FAILED`、无 `Assertion Failure` / `XCUITestError`；六份 Runner artifact 全部上传并 finalized。

**未闭环项（不计 passed，不得以 CI / Simulator 替代）：**

- 真机门禁 **G10～G15 全部 pending/unknown**：JBROOT GUI 进程访问、TweakInject 可达、dylib/plist/dpkg 真机读取、entitlement/sandbox 放行、`jbroot()` 声明/链接/调用与路径一致性、冷启动权限保持；须 RootHide 真机真实 GUI 进程取证。D5 runtime 证据在 iOS 仍为 unavailable/unknown；D6 symlink 层真机解析与 accessible 层真机文件访问仍待 G10/G14 取证。
- Dashboard 截图与导出 JSON 均为 `SyntheticReportFactory` 合成预览桩，不构成真机权限、真实加载或真实扫描证据；本轮 Simulator G9 通过不能替代 0.1-C G10 真机缺口。
- 既有挂起项维持不变：`OwnershipResolver` 未迁移、`loaded` 恒 unknown、`permission.decision` 恒 undetermined、`pluginID` 规则 0.2.0、PARSE-009-B；0.1-C G10 缺口不豁免不签署。

## 0.1-D-R2-A/B 代码落地（2026-11-20，授权分批）

授权范围：D5 Entitlement 技术实现准备（Signed / Runtime / Resource Access 三类证据显式分离）与 D6 RootHide `jbroot()` 真实 API 复核及路径一致性修复；补 D5/D6 单测与错误态测试。不含 0.1-E 正式开发、发布打包与签署。

### 上游复核（libroothide 当前 main，2026-11-20 重新抓取，与 R1-B 记录一致，无漂移）

- `roothide.h`：C `const char* jbroot(const char* path);`；Obj-C `NSString* _Nonnull __attribute__((overloadable)) jbroot(NSString* _Nonnull path);`；alloc 变体 `jbroot_alloc` / `jbrootat_alloc`、`rootfs` / `rootfs_alloc`、`jbrand`。
- `module.modulemap`：`module roothide { header "roothide.h"; link "roothide"; export * }`，链接 `-lroothide`。
- `jbroot.c`：`jbroot(const char*)` 经 `jbroot_alloc` 走进程内静态 `cache_path` 缓存返回；alloc 变体由调用方释放；空 / NULL path 返回 NULL；`__private_jbrootat_alloc` 词法解析 `.` / `..`、去尾斜杠、inode/dev 比对与 `/rootfs` 前缀剥离。
- `stub.h`：非 roothide 构建静态桩，`jbroot(path)` 原样返回 path、`jbrand()` 返回 0。
- `common.h`：`EXPORT` 默认可见性；extern `__roothideinit_JBRAND` / `__roothideinit_JBROOT`；`JB_ROOT_PARENT "/var/containers/Bundle/Application"`；无零参取基目录接口。
- Apple 文档复核：`SecTaskCreateFromSelf` / `SecTaskCopyValueForEntitlement` / `SecTaskCopyValuesForEntitlements` 官方平台仅 macOS / Mac Catalyst，不含 iOS。

### 代码落地（Core 层，冻结 Models 未改）

- **D5**：新增 `EntitlementEvidenceSource`（signed / runtime / resourceAccess）与 `EntitlementEvidenceRecord`；`EntitlementProbe` 两条证据分别标注 `[runtime]` / `[signed]`；`SandboxAccessProbe` 标注 `[resourceAccess]`；runtime 占位原因注明 iOS GUI 进程公开稳定读取接口未核实。协议、快照、占位实现替换路径未改。
- **D6**：新增 `JBRootPathComparison` / `JBRootConsistencyVerdict` / `JBRootPathComparator`，raw / normalized / symlink / accessible 四层取证；`JBRootAPIProbe` 一致性由原始字符串 `==` 改为分层比较，初始化器加可选 `fileAccess`（默认 nil 兼容既有调用）；verdict：normalized 失配 → failed；normalized 匹配且 symlink 失配 → failed；normalized 匹配且 symlink 未知或匹配 → passed；路径缺失 → unknown。accessible 为独立证据层，不可达不反向改写一致性 verdict。
- **测试**：`PermissionProbeProbeTests.swift` 更新受来源前缀影响的既有断言，新增 10 例（D5 3 / D6 7）；编译与用例结论已由 run `121082423820` Runner 日志判定通过（见上节）。

### 冻结与未触碰边界

Adapter 七方法协议未改；RootHide / Rootless Adapter 独立；冻结公共 Models、`ReportEnvelope`、Core 业务语义、Plist Parser 语义、Stage1 fixtures 未改；`loaded` / `installed` / `configured` 既有语义未改；未链接 libroothide、未写 C 桥接声明、未弱链接、未 dlsym、未调用未验证私有 API；未做插件启停、plist 写入、dylib 删除 / 移动、dpkg 写操作、注入规则修改、自动修复、常驻 daemon；未触真机。

### 未解决技术限制

1. GUI 进程内 libroothide 符号可解析性、调用成功、返回路径有效性、与 D2 一致性均待 RootHide 真机；`jbroot("/")` 取基目录行为属待真机验证推断。
2. 词法规范化不等于真实 inode / dev 文件身份验证；`resolvingSymlinksInPath()` 对不存在路径仅作词法解析；真实身份比对须真机 stat 取证。
3. D5 Runtime entitlement iOS 无公开稳定读取接口；真机 entitlement / sandbox 结论须 RootHide 真机 GUI 进程取证。
4. 既有挂起项维持不变：`OwnershipResolver` 未迁移、`loaded` 恒 unknown、`permission.decision` 恒 undetermined、`pluginID` 规则 0.2.0、PARSE-009-B；0.1-C G10 缺口不豁免不签署。

记录：`Spec/Stage-2/Stage-2.4-D2-D7-PermissionProbe-Chain-Implementation-Record.md` §5.9 / §5.10 / §5.11；`Spec/Stage-2/Stage-2.4-R1B-APIPermission-Feasibility-Record.md` §8。

## 0.1-D R1-A 接线恢复后 Runner 验收（run `120957775572`，SHA `4b08fe1a`，历史轮次）

证据归档：`Tests/Stage2/evidence/run-120957775572-acceptance/`（分步日志、metadata、test-log、隔离产物、app-build 日志与截图、导出信封、`RUN-METADATA.md`）。环境：macOS 26.7.2（25G332）/ Xcode 26.6（17F113）/ Swift 6.3.3（swiftlang-6.3.3.1.3 clang-2100.1.1.101）/ swift-driver 1.148.6 / SDK 26.5 / Swift 测试目标 arm64e-apple-macos14.0 / XCUITest 目标 arm64-apple-ios17.0-simulator。

**Runner / Simulator 口径 G1～G9：通过（日志实测值）。**

- G1 非 UI Build：`Build complete! (13.28s)`，0 error / 0 warning；Models / Adapters / AppPresentation / Core emit，ReportRoundtripValidator 编译并链接。
- G2/G6 全量 Swift 测试：**448 tests，0 failures（0 unexpected）**；既有 0.1-A / 0.1-B / 0.1-C 基线含在 448 例内，0 failure、无损伤。
- G3 S1-05 配对映射：独立过滤 **15 tests，0 failures（0 unexpected）**。
- G4 探针专项 43 例全绿：Status 4 / Evidence 5 / Report 6 / Probe 24 / Presentation 4；三轮修复点复核 passed；无 UITests unhandled 告警。
- G5 隔离静态检查：1a/1b/2a/2b/3/4/4b 七项 `passed`，`failed: 0`；Runner isolation job 实际执行，本地脚本复跑 exit 0 结论一致。
- G7 App Build：`** BUILD SUCCEEDED **`，0 error；唯一 1 条 warning 为 `appintentsmetadataprocessor`「No AppIntents.framework dependency found」元数据跳过系统噪声，非 Swift 编译告警。`FilterKit.app` 产物保留于 DerivedData：`FilterKit` 123808B、`FilterKit.debug.dylib` 8944448B、`__preview.dylib` 83952B、`Info.plist` 756B、`PkgInfo` 8B、`_CodeSignature/CodeResources` 2321B；dylib 与 bundle 均 `codesign --sign -` 签名并 Validate/Touch 通过。模拟器设备 `EED6FB0A-…`，`com.filterkit.manager` launch PID 4029，3 秒后存活；`dashboard.png` 1206×2622 RGBA。
- G8 Diagnostics / 导航页面：XCUITest **8 例 0 failure（192.521s）**；Dashboard 基线、Diagnostics 分区、列表分段/搜索、详情页、设置页全 passed。
- G9 JSON 导出 / 往返校验 / Share Sheet：导出 `FilterKit-Report-0-1-0-preview.json`（5295B，`schemaVersion 0.1.0` / `generatorVersion 0.1.0-preview` / `profile roothide-preview·roothide`，plugins 3 / unknownItems 1 / warnings 1）；往返 `decodable=true`、`equalIgnoringGeneratedAt=true`、`messages=[]`；`SHA256SUMS` 落盘且复算一致；导出无错误、Share Sheet、空态禁用导出三例 passed。
- 全量日志无 `##[error]`、无 exit code 1、无 `FAILED`、无 `Assertion Failure` / `XCUITestError`；六份 Runner artifact 全部上传并 finalized。

**未闭环项（不计 passed，不得以 CI / Simulator 替代）：**

- 真机门禁 **G10～G15 全部 pending/unknown**：JBROOT GUI 进程访问、TweakInject 可达、dylib/plist/dpkg 真机读取、entitlement/sandbox 放行、`jbroot()` 声明/链接/调用与路径一致性、冷启动权限保持；须 RootHide 真机真实 GUI 进程取证。D5/D6 仍占位 unavailable/unknown。
- Dashboard 截图与导出 JSON 均为 `SyntheticReportFactory` 合成预览桩，不构成真机权限、真实加载或真实扫描证据；本轮 Simulator G9 通过不能替代 0.1-C G10 真机缺口。
- 本验收仅代表 Runner / Simulator / 合成桩口径，不构成真机权限、真实加载、`jbroot()` 真机可调用性或 Rootless 真机兼容证据。

## 0.1-D 离线/CI 统一 Runner 验收（run `120942979030`，SHA `cb130c36`，历史轮次）

证据归档：`Tests/Stage2/evidence/run-120942979030-acceptance/`（分步日志、metadata、test-log、build/isolation 产物、`RUN-METADATA.md`）。该轮 App Build / 模拟器 / XCUITest 按摘出口径置 `if: false` 未执行；离线/CI 口径 L2 切片通过：非 UI Build `Build complete! (15.69s)` 0 error / 0 warning；全量 448 例 + S1-05 15 例 0 failure；探针 43 例全绿；隔离七项 passed；既有回归无损伤。

## 0.1-D-R1-A/B（2026-11-20，分批收口）

### R1-A：App Runtime Readiness 接线恢复

- `.github/workflows/filterkit-build.yml` 恢复 `app-build`（needs `[build, isolation]`）、`ui-acceptance`（needs `[app-build]`，XCUITest）与 `artifact` 对 `app-build` 的依赖；移除摘出期间两处 `if: false`。Job 链 `environment→build→test / isolation→app-build→ui-acceptance→artifact`。
- 验证代码一直保留：`Tests/Stage2/UITests/` 五个 XCUITest 源文件、`project.yml` 的 `FilterKitUITests` target、`Tools/ReportRoundtripValidator` 往返校验器、App target 工程定义。
- `Package.swift` 的 `Stage2Tests` 已 `exclude: "UITests"`：五个 XCUITest 源文件不纳入 SwiftPM 测试目标编译；Xcode target 引用保留。
- G7/G8/G9 已由 run `120957775572` 实跑判定通过（见上节）；仅 Runner/Simulator 口径，不替代真机 G10～G15。

### R1-B：D5/D6 API 可行性核实（未实现真实调用）

- **D6 `jbroot()`**（上游 `roothide/libroothide` 源码核实）：所属库 libroothide，链接 `-lroothide`，Swift 经 modulemap `import roothide`；C 声明 `const char* jbroot(const char* path)`，Obj-C `NSString*` 重载；符号 `EXPORT`（visibility default）默认导出；rootful/rootless 编译走 `stub.h` 静态桩（原样返回 path、`jbrand()` 返回 0）；无零参取基目录接口，基目录由 extern `__roothideinit_JBROOT` 承载。GUI 进程内符号解析/调用/返回路径有效性/一致性均待 RootHide 真机验证。
- **D5 Entitlement**：`SecTaskCreateFromSelf` / `SecTaskCopyValueForEntitlement` / `SecTaskCopyValuesForEntitlements` 官方平台仅 macOS/Catalyst，不含 iOS；iOS GUI 进程无公开稳定的运行时 entitlement 读取接口。Runtime entitlement 保持 unavailable/unknown；签名声明（Signed Entitlements）与实际资源访问（Actual Resource Access）由独立证据承载，互不替代。
- D5/D6 占位实现未替换；未写真实 API 调用、弱链接、dlsym 或伪造 C 声明；未改 Adapter 七方法协议、冻结公共 Models、`ReportEnvelope`、Core 业务语义。
- 核实记录：`Spec/Stage-2/Stage-2.4-R1B-APIPermission-Feasibility-Record.md`（含七项核实、三分拆证据口径、未决项与真机准备清单）。

## 0.1-D 三轮 Runner 修复历程（本地提交，未推送）

- 首轮 build（run `5a0ac726`，SHA `967d8152`，提交 `df3f2dd`）：PlistReadProbe `observed` 改 `String?`；协议 `run()` 改 `throws`；服务 `try` 调用保留失败证据；抛错桩补 `throws`；隔离用例对照桩计数修正。
- 二轮 test（run `92462907`，SHA `92127cd1`，提交 `1af6ae9`）：EvidenceTests 字典键兜底改 `Set<String>` map 写法；ProbeTests errno 补 `POSIXErrorCode.` 前缀；`Package.swift` 排除 UITests。
- 三轮 test（run `d2b6f5e1`，SHA `c657da5d`，提交 `021abd2`）：dpkg 用例期望 `12 bytes` 偏移，夹具实为 11 字节、探针 `data.count` 口径正确，断言改 `11 bytes`。
- 证据：`Tests/Stage2/evidence/0.1-d-run-logs/`、`0.1-d-run-2-logs/`、`0.1-d-run-3-logs/`。

## 0.1-D D2～D7 链路（本地落盘）

- 规格：`Spec/Stage-2/Stage-2.4-D2-D7-PermissionProbe-Chain-Spec.md`（冻结）与 `Stage-2.4-D2-D7-PermissionProbe-Chain-Implementation-Record.md`（§5.3～§5.19 三轮修复、验收、R1-A/B、R2-A/B、R3-A、R3-A2/F、R4-A0、R4-A～E 记录）；D1 规格/记录回填 `ProbeOperation`、证据 `id/operation`、`run() throws -> [ProbeEvidence]` 协议口径。
- 模型补齐（`Models/PermissionProbe/`）：`ProbeOperation` 六类操作；`ProbeEvidence` 增补 `id`/`operation`。
- 文件访问抽象（`Core/PermissionProbe/FileAccess/`）：`FileAccessChecking` 接缝、`FoundationFileAccessChecker` 只读实现、`ProbeStatusClassifier` 错误分类。
- 探针（`Core/PermissionProbe/Probes/`）：D2 `JBRootProbe`；D3 `ElleKitDirectoryProbe`；D4 `PluginFileProbe` / `PlistReadProbe` / `DpkgDatabaseProbe`；D5 `EntitlementProbe` / `SandboxAccessProbe`；D6 `JBRootAPIProbe`。
- 接缝占位：`EntitlementInspecting`/`CodeSignInspecting` + 占位检查器；`JBRootResolving` + 占位 resolver。接口未核实前不写伪造 C 声明/弱链接/dlsym，结果落 unavailable/unknown。
- 服务装配：`PermissionProbeService` 逐条编排、单项失败保留原 probeID 不中断；`PermissionProbeReportBuilder` 归集证据。
- 展示层：`App/Presentation/ProbeDiagnostics.swift` 纯 Foundation 映射；`AppDependencies` 增补 `probeReport` 接缝；旧 `ProbeItem` 占位退役。
- 纯离线只读：未触真机文件、未调 `jbroot()`、未改 entitlement/签名；`loaded` 恒 unknown。

## 历史归档

- 0.1-C 七轮复核证据与 G10 搁置决定：`Tests/Stage2/evidence/c-f5-seventh-run/`；记录 §12.7/§12.8。
- 0.1-B 报告/导出、0.1-C GUI Foundation 源码与历史 Runner 证据随包保留；校验器 `Tools/ReportRoundtripValidator/`。
