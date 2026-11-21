# Stage 2.5 — 0.1-D Diagnostics Port（0.1.19 只读诊断 18 项对齐）计划与记录

## 1. 基线与范围

- 基线仓库 HEAD：`4b91254`（0.1-D-R4-B2 非界面层编译修复）。
- 对照源码：附件 `FilterKit-0.1.19-source.zip`（纯 ObjC，`Sources/`）；接口口径以附件 `FilterKit-0.1.19-18项诊断检测代码清单.md` 为准；批次/边界/两提交拆分以附件《我的建议是：先移植…有边界的.md》为准。
- 签名/打包基线：附件 `FilterKit-DevDocs-0.1-LDID-Signing-Fix.zip` 快照。本轮只做**增量增补/对齐**，不删除仓库既有文件，不覆盖 R4-D2 之后已演进的打包/校验链路。
- 本记录对应建议 MD 的第一个提交 `0.1-D-Diagnostics-Port`：移植诊断引擎、数据证据字段与检测能力；测试补齐、Runner 编译复测、真机取证归入后续 `0.1-D-Acceptance` 提交。
- 不移植范围（0.1-E / 信任链，清单与建议 MD 均排除）：`Helper/`、`HelperDaemon/`、`Operation/`、`Security/`、`Views/`、`Backup/FKBackupManager*` 备份恢复工作流；`FKFileHasher` 仅参考其 MD5/SHA-256 流式摘要口径。

## 2. 与既有工程的关系

- 既有 Swift 端口位于 `Core/Diagnostics/`：`ReadOnlyDiagnosticsEngine.swift`、`ReadOnlyFileHasher.swift`、`AssociationSnapshotStore.swift`，由 `DiagnosticsViewModel.runReadOnlyDiagnostics()` 显式触发，不在启动时自动扫描。
- 本轮沿用既有「扁平化 `[[String:String]]` 行 + findings」报告形态，**不新增顶层报告数组、不改公共 `Models`/`ReportEnvelope`/Adapter 七方法协议/Plist Parser 语义/Stage1 fixtures**。建议 MD 的 Environment/Injector/Package/Integrity/Association 目录拆分作为 0.1-E 重构候选记录在案，本轮不做目录级搬迁以压缩编译面。
- ObjC 源码不复制进 Swift target；所有行为以 Swift 重写，纯数据对照，不调用注入器私有 API、不 dlopen 插件、不伪造运行时符号。

## 3. 签名基线对齐（LDID-Signing-Fix 快照增量）

快照相对仓库的独有签名链路，本轮按以下方式对齐：

1. **新增** `scripts/validate-ldid-signature.sh`（快照原文）：遍历 App 内全部 Mach-O，逐个校验 `LC_CODE_SIGNATURE` 与 `ldid -h` CodeDirectory hash 可提取；主程序 `ldid -e` 提取嵌入 entitlements 与 `Config/Signing/FilterKit.entitlements` **精确比较**；输出摘要 JSON（`signatureState=ldid_signed_static_valid`、`machoCount`、`lcCodeSignature=present_all_macho`、`codeDirectoryHash=extractable_all_macho`、`embeddedEntitlements=exact_match`、`deviceAcceptance=unknown`、`deviceInstallable=false`），支持 `LDID_SIGNATURE_SUMMARY_PATH` 落盘。
2. **改写** `scripts/sign-app-ldid.sh`：
   - `sign`：嵌套 Mach-O 一律 `ldid -S` **不带主程序 entitlement**；仅主 `CFBundleExecutable` 用 `ldid -S<entitlements>` 签名；签完立即调用独立校验脚本。
   - `verify`：委托同一独立校验脚本，保留原有 `sign|verify` CLI 契约与 `SIGNING_SUMMARY_PATH` 环境变量映射。
   - 旧版「每个 Mach-O 都套用主 entitlement 并逐个比对嵌入 entitlement」的做法废弃：嵌套镜像按基线语义不携带主 App entitlement，逐镜像 entitlement 比对不再适用。
3. 仓库 `scripts/package-deb.sh` / `scripts/validate-deb.sh` / workflow 已演进为 unsigned-structure / ldid-signed-embedded / apple-signed-candidate 三态门禁，本轮**保留**；其 `sign-app-ldid.sh verify` 调用点不变，现由独立校验脚本承接。
4. 快照 `validate-entitlements.sh` 的 t4（与 `reference/0.1.18-src/entitlements.plist` 逐字节一致）检查、`collect-package-metadata.sh` 的候选包标签字段为快照口径；仓库后续已演进，本轮不回退，留待 Acceptance 轮评估是否补回 t4 静态门禁。

> 签名/DEB 闪退仍是独立阻塞项：本轮静态签名语义对齐不代表 amfid/Bootstrap 接受、安装或启动已验证；真机 `.ips`/系统日志、H4 切片/弱链接/rpath、H5 uicache/JBROOT 映射仍待设备侧取证。

## 4. 18 项缺口矩阵

状态口径：**present**（既有 Swift 已覆盖核心路径）／**enriched**（本轮补证据字段）／**deferred**（Acceptance 轮或 0.1-E，标未确认）。

| # | 能力 | 优先级 | 既有 Swift 覆盖 | 本轮处置 | 延迟项 |
|---|---|---|---|---|---|
| 1 | JBROOT 定位与校验 | P0 | `discoverJBRoots`/`roothideJBRoot`/`roothideJBrand`：候选收集、存在/可读/结构标记、API 符号可选解析 | enriched：根行补 `confidence`（confirmed/candidate/path_hint_only）、`markers` 命中清单、`is_symlink`；findings 记录候选来源顺序 | POSIX `realpath`/errno 细分、容器 `.jbroot-` 条目独立列表；`jbroot()` 符号与私有 Workspace 行为待真机 |
| 2 | DynamicLibraries 目录枚举/可访问性 | P0 | `discoverDynamicLibraryDirectories`：候选路径、exists/directory/readable/enumerable/entry_count | enriched：目录行补 `is_symlink` | `lstat`/`access(X_OK)`/`opendir` errno 细分、`realpath` 证据 |
| 3 | dylib 文件扫描枚举 | P0 | 目录内 `.dylib` 枚举、去重、存在/可读/大小 | enriched：插件行补 `file_type`；findings 记录 `enumeration_completed`（零 dylib 也算枚举成功） | 逐文件 POSIX 类型/可执行位判定 |
| 4 | Filter plist 扫描读取 | P0 | 目录 `.plist` 读取、PropertyList 解析、失败不中断 | enriched：行补 `data_length`、`top_level_type`、`top_level_keys`、`has_filter_dictionary`；支持顶层字典与嵌套 `Filter` 字典两种 Theos 布局 | 图标/二进制 magic 诊断（属 16） |
| 5 | Filter 规则解析（Bundles/Executables/Classes） | P0 | 三键字符串数组提取、other_keys | enriched：识别嵌套 `Filter`；补 `global`（Bundles 含 `*`）、`matched/unmatched_bundle_ids`、`matched/unmatched_executables`、`warnings`、`valid`、`entry_count`、`protocol_verified=false`、`global_semantics_verified=false`；非数组值/非字符串项/空串/非字符串键入 warnings | `*` 通配语义未经 ElleKit loader 源码确认，恒标未验证；Classes 仅保留规则，不映射 Bundle ID |
| 6 | 注入器识别（静态包+运行时镜像+兼容画像） | P0 | `identifyInjectors`/`runtimeInjectorImages`/`injectorProfile`：包 ID 关键词、当前进程 dyld 镜像、能力位表 | enriched：静态行补 `version_source=dpkg_status`、`evidence_level=partial`、`installed`、`architecture`；补固定指纹库（`usr/lib/libellekit.dylib` 等 dylib/framework）存在性/可读性静态探测行 | 镜像 Info.plist 版本反查、兼容结论枚举（compatible/partial/incompatible/reasons）、启停能力位恒未验证 |
| 7 | dpkg status 读取与状态解析 | P0 | `parseDpkgStatus`：记录拆分、续行/畸形行/重复字段 warnings | present（warnings 已入 findings） | status 候选路径探测列表、`want/error_flag/current` 三态拆解并入第 9 项 |
| 8 | dpkg `.list` 文件归属 | P0 | `analyzeDpkg`：info/<pkg>.list 读取、路径归一化、多包集合反查 | present | 归属反查同时覆盖 dylib+plist 的清单对照细节 |
| 9 | 软件包元数据提取 | P0 | Version/Architecture/Status/Maintainer/Description/Depends/Pre-Depends/Section/Source | enriched：补 Recommends/Suggests/Provides/Conflicts/Replaces/Essential/Homepage；补 `want`/`error_flag`/`current_state`/`state` 状态机拆解 | `raw_fields` 全字典保留（扁平化行形态受限，Acceptance 评估结构化模型） |
| 10 | 安装文件完整性（存在/可读/缺失） | P0 | listed/missing/unreadable 计数；目录不并入普通文件校验 | enriched：补 `existing_files`、`unreadable_files`、`not_checked_files`（目录）计数 | 逐文件 regular/symlink/directory 类型与可执行位清单 |
| 11 | MD5 校验与三级差异分类（SHA-256 备份一致性） | P0 | `.md5sums` 流式 MD5、match/mismatch、Mach-O/conffile/text/resource 粗分类；`ReadOnlyFileHasher` 一遍流式 MD5+SHA-256 | enriched：补 `no_checksum_record` 桶行；mismatch 行补 `format`/`detection_method`/`confidence`/`path_category`/`extension`/`reason`；magic>内容>扩展名三级分类；findings 汇总 checked/mismatch/hard/warning/not-confirmed | 按文件类型/路径类目/扩展名/包的不匹配分布统计；SHA-256 备份前后对照由调用方显式触发，引擎不自动备份 |
| 12 | 插件来源识别（dpkg/manual/unknown） | P0 | 归属包反查 → dpkg/manual_inferred/unknown；`source_evidence` | enriched：补 `exact_package_record`、`package_candidates` | 推断来源与 FilterKit 自身关联记录不冒充设备真实清单 |
| 13 | 跨包归属冲突检测 | P1 | 归属行 `conflict` 布尔 | enriched：findings 汇总冲突路径数与未归属插件文件数 | 冲突记录独立列表（结构化模型轮） |
| 14 | RootHelper 只读预检（正向+反向） | P1 | 固定/受限目录关键词候选；LaunchDaemons plist 的 Program/ProgramArguments 反查 | enriched：候选补 `file_type`/`size`/`logical_path`/`package_ids`；注册行补 `readable`/`valid_plist`/`user_name`/`group_name`；补固定 RootHelper 相对路径候选表 | `access(X_OK)`/`lstat` 类型判定、MachServices/RunAtLoad 结构化收集；永不启动/信号/通信/launchctl |
| 15 | 已安装 App 枚举 | P1 | 守卫 `LSApplicationWorkspace`：`allInstalledApplications`→`allApplications` 回退，非数组返回空 | present | 私有接口不可用时的空态证据细化 |
| 16 | App 元数据（版本/可执行名/图标/系统标记） | P1 | 短版本优先/构建号回退、CFBundleExecutable、图标文件候选、图标解码诊断、系统路径前缀 | present（图标 magic/format 样本诊断 deferred） | 私有图标 API 样本统计、magic 识别明细 |
| 17 | 插件↔App 静态关联（匹配+反查+持久化） | P1 | Bundles/Executables 静态匹配；`AssociationSnapshotStore` 沙盒原子写 | enriched：关联行补 `category`/`is_global`/`matched_app_count`/`unmatched_target_count`；findings 汇总 global/unmatched/missing-dylib/missing-plist/abnormal 计数 | App→插件反向索引、重复/冲突标记、配对缺失（missing_dylib/missing_plist）独立分桶；持久化仅沙盒、损坏文件隔离 |
| 18 | Conffiles 双渠道识别 | P0 | status `Conffiles` 字段 + `info/<pkg>.conffiles` 合并去重 | present | 渠道读取失败的逐渠道告警记录 |

## 5. 保守口径（本轮继续冻结）

- 三原则：已安装≠已配置；已配置≠已加载；静态关联≠实际注入成功。`loaded` 无独立运行时证据恒 `unknown`。
- 静态 Filter 匹配不宣称 loader 语义已验证；`*` 全局规则标 `protocol_verified=false`。
- MD5 仅对照 dpkg `.md5sums`，不是安全签名；Mach-O 摘要差异不判定成因（重签名/补丁/重定位）；Conffiles 允许本地配置差异；非 Conffiles plist 差异列复核，不直接判损坏或篡改。
- 私有 Workspace 调用前 `responds(to:)` 守卫；当前进程 dyld 镜像证据仅限当前进程。
- 禁止项不变：插件启停、plist/规则写入、dylib 删移、dpkg 写、软链改动、注入、Helper 启动/IPC/`launchctl`、常驻 daemon、entitlement/签名/沙盒例外放行、`jbroot()` 伪造调用与弱链接伪造符号声明。

## 6. 本地静态核对（本轮环境限制与已执行项）

本机 Linux 无 swiftc/swift/Xcode/ldid/otool/plutil/lipo；可执行：`bash -n` 脚本、python 语法/JSON 解码、YAML 解析、括号配平、残留现代 API/`RTLD_` 扫描。Core emit-module 与 `swift test` 全套以 Runner（macOS Apple 工具链）复测为准。

本轮已执行静态核对（2026-11-21）：

- 十枚 `scripts/*.sh` 全部 `bash -n` 通过；workflow YAML 解析通过；`compare-app-bundles.py` `py_compile` 通过。
- 引擎文件括号配平：花括号 277/277、圆括号 702/702、方括号 445/445；无 `RTLD_DEFAULT` 符号引用（仅注释说明位模式来源）；无 `close()`/`read(upToCount:)` 现代 FileHandle 调用（仅注释提及可用性门槛）；无强制解包；下标访问均有 count 守卫。
- 未在本机执行 Swift 编译/测试；编译结论待 Runner。

## 6.1 本轮落地文件清单（增量，未删除既有文件）

- `Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift`：18 项证据字段增补（见 §4 enriched 行），报告顶层结构与公共类型不变。
- `scripts/validate-ldid-signature.sh`：快照独立签名校验脚本新增。
- `scripts/sign-app-ldid.sh`：嵌套 Mach-O 临时签名不带 entitlement、主程序 entitlement 签名、签后委托独立校验；保留 `sign|verify` CLI 与 `SIGNING_SUMMARY_PATH` 映射。
- `Config/Signing/README.md`：§6 流程说明同步为新基线口径。
- 本记录 `Spec/Stage-2/Stage-2.5-0.1-D-Diagnostics-Port-Plan.md`。

## 6.2 DevDocs 打包

- 打包代码基线提交：`9760e69`（源码修复提交 `9b0c6c3`，另含记录回填提交，打包 HEAD 以交付附件内 git 清单为准）；包内文件 2055；`unzip -tq` 无错误、清单与暂存目录一致；大小/SHA256 以交付附件复算为准，包内不内嵌自身哈希。
- 暂存 `git archive HEAD` 后剔除 `Research/Validation/evidence/0.1.18-device-report.json`；排除规则沿用既有口径（`.git/`、小写 `research/`、`build/`、`.theos/`、`.build/`、`DerivedData/`、`*.xcodeproj/`、`*.xcworkspace/`、`.tmp/`、`.DS_Store`、`*.zip`、`*.xcresult/`、`__pycache__/`、`*.pyc`）；`reference/`、`.github/workflows/`、大写 `Research/` 保留。
- 本论包内文件计数与大小以交付附件复算为准；包内不内嵌自身哈希。

## 6.3 Runner 首轮编译反馈与修复（run 44835136866，基线 `828e69f9`）

Runner `swift build` 在 Core emit-module 阶段失败（2026-11-20 23:14:08Z exit 1）；Models / Adapters / AppPresentation / ReportRoundtripValidator 均通过，错误与 1 条 warning 全部集中在 `Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift`；build 失败后未跑 `swift test`。证据落盘 `Tests/Stage2/evidence/0.1-d-run-44835136866-build-failure/`（日志 + RUN-METADATA.md）。

| 编号 | Runner 位置 | 报错 | 根因 | 修复 |
|---|---|---|---|---|
| E1/E2 | 802:14 / 804:14 | 84 条 `tuple pattern has the wrong length for tuple type '(UInt8, UInt8, UInt8, UInt8)'` | magicFormat switch 对象为 4 元组，jpeg(3 元素)/gzip(2 元素) 分支模式长度不符；短缓冲签名在 `guard count>=4` 后本不可达 | 短缓冲签名在 switch 前按字节位置单独 `if` 判定；switch 内改通配 4 元组 `(0xFF,0xD8,0xFF,_)` / `(0x1F,0x8B,_,_)`；其余分支与 bplist/sqlite 判定不变 |
| E3 | 933:22 | 42 条 `value of type 'String' has no member 'standardizingPath'` | 内嵌 `logicalPath` 闭包末尾漏 `as NSString` 桥接 | `return (p as NSString).standardizingPath`（对齐同文件 339/718/930 行既有写法） |
| W1 | 1071:50 | `will never be executed` / `condition always evaluates to false` | 非 UIKit 单元 `iconDecoded` 恒 `false`，返回字典三元首分支不可达 | `#if canImport(UIKit)` 两侧分别计算 `iconSource`；非 UIKit 侧直走 `iconPath.isEmpty ? "unresolved" : "bundle_file_candidate"`；字段名与保守口径不变 |

本地静态复核（2026-11-21，Linux 无 Swift 工具链）：引擎括号配平 279/279、703/703、450/450；`#if`/`#endif` 12/12；全仓无未桥接 `.standardizingPath`；其余 2 元组 switch 模式长度匹配。编译结论以下一轮 Runner 复测为准；本轮未改 Adapter 协议、冻结 Models、报告信封、Plist Parser 语义与 Stage1 fixtures，未触任何写操作/签名放行/沙盒例外。

## 6.4 Runner 第二轮 iOS 构建反馈与修复（run 44836799174，基线 `fb8a6932`）

本轮 9 个 job：environment / isolation / signing-prep / test / artifact 通过；非 UI macOS `swift build` `Build complete! (27.62s)`，458 + S1-05 15 例 0 失败（§6.3 修复在 macOS 编译单元复测通过）；device-build（iphoneos26.5 arm64 Release）与 app-build（iphonesimulator26.5 Debug，arm64 + x86_64 两切片）`BUILD FAILED` exit 65；package-validation 因无产物 Build/IPA/DEB 三态 Pending，Entitlements Static Passed、metadata JSON decodable。证据落盘 `Tests/Stage2/evidence/run-44836799174-ios-build-failure/`（77 文件解包结构 + RUN-METADATA.md）。

| 编号 | Runner 位置 | 报错 | 根因 | 修复 |
|---|---|---|---|---|
| E1/E2 | `ReadOnlyDiagnosticsEngine.swift:454:26` / `:455:33` | 6 条 `cannot find '_dyld_image_count' / '_dyld_get_image_name' in scope`（device 1 切片 + app 2 切片） | 两符号声明于 `<mach-o/dyld.h>`，属 `MachO.dyld` 子模块；macOS SwiftPM Darwin 伞头透出，iOS SDK 不经 Darwin 重导出，Xcode 显式模块编译单元下 `import Darwin` 后符号不在作用域 | 既有 `#if canImport(Darwin)` 块内追加 `import MachO.dyld`；调用点、函数签名、证据字段与保守口径不变；非 Darwin 平台整块排除 |

本地静态复核（2026-11-21，Linux 无 Swift 工具链）：括号配平 279/279、704/704、450/450；`#if`/`#endif` 12/12；全仓（排除 `research/`）无其他待导入 MachO 子模块符号；脚本 `bash -n`、Python 编译、YAML 解析通过。device/app 编译结论待下一轮 Runner 复测；未改 Adapter 协议、冻结 Models、报告信封、Plist Parser 语义与 Stage1 fixtures，未触写操作/签名放行/沙盒例外/dlsym 伪造符号。

DevDocs 重打（2026-11-21）：打包基线 `3c8e6f8`（打包 HEAD 以包内清单为准）（源码修复提交 `d53a475`）；包内 2126 文件；`unzip -tq` 无错误、清单与暂存目录一致、`validate-ldid-signature.sh` 条目模式 100755；大小/SHA256 以交付附件复算为准，包内不内嵌自身哈希。

## 7. 待 Acceptance 轮闭环

1. Runner 同 R4-B2 基线编译 Core/Models/Adapters/AppPresentation，回填编译反馈。首轮 run 44835136866 反馈已按 §6.3 修复（macOS 单元复测通过）；第二轮 run 44836799174 iOS 构建 dyld 子模块导入问题已按 §6.4 修复，待下一轮 Runner 复测 device-build / app-build 与 `swift test`。
2. 为纯函数（Filter 解析、status 状态机、Conffiles 合并、路径归一化）补离线夹具单测。
3. 真机 RootHide arm64e / Rootless arm64 路径可达性、私有 Workspace、`jbroot()` 符号取证。
4. 评估补回 entitlements t4 参考一致性静态门禁；评估结构化诊断模型（替代扁平化行）。
5. DEB 签名/闪退独立阻塞项不随本轮关闭：`.ips`/系统日志、H4、H5 继续挂起。
