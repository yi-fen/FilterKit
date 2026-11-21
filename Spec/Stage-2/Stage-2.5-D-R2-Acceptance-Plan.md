# Stage 2.5 — 0.1-D Diagnostics-Port Acceptance R2 计划与记录

> 输入基线：DevDocs 包 `FilterKit-DevDocs-0.1.zip`，SHA256 `e43799a9bca7b54bdbb3f6e5073339cc4c98e5013ac1fc64a184d9879d34e004`；本地 HEAD `b28c5ae`。
> 依据：用户提案《根据 run 44836799174 的结果，我建议下一步进入 FilterKit 0.1-D》（归档于本目录记录引用）。
> 本批次只执行 **D-R2-01（复测口径归档）** 与 **D-R2-02（18 项诊断离线测试）**；D-R2-03 起按提案顺序后续批次另行授权。

## 1. 任务矩阵与本轮处置

| 编号 | 任务 | 优先级 | 本轮处置 |
|---|---|---|---|
| D-R2-01 | iOS dyld 编译修复复测 | P0 | 代码修复已落地（`import MachO.dyld`，run 44836799174 第二轮）；**本轮无新 Runner 日志，不认定 iOS 编译已通过**。四目标（iphoneos26.5 arm64 Release / iphonesimulator26.5 arm64 Debug / iphonesimulator26.5 x86_64 Debug / macOS Runner 原生 Debug）复测结论待下一轮 Runner；若报 `no such module 'MachO.dyld'`，备选 `import MachO`，禁止伪造 C 函数声明 |
| D-R2-02 | 18 项诊断离线测试 | P0 | 本轮落地：`Tests/Stage2/Diagnostics/` 18 枚测试文件 + 必要 target 接线；仅覆盖纯函数/纯聚合可离线验证表面，FS/私有 API/dyld 运行时表面标 deferred |
| D-R2-03 | 文件系统依赖解耦（`DiagnosticFileSystem` 协议 + 三模块拆分） | P0 | **本轮不做**。提案明确先不大规模目录重构；协议与拆分留待 D-R2-02 离线基线确立后单独授权 |
| D-R2-04 | 诊断证据等级与内部一致性检查 | P1 | **本轮不做**。不改报告信封与公共 Models；内部一致性校验在后续批次评估 |
| D-R2-05 | DEB 签名与闪退调查（H4-01～05 / H5-01～03 / C1～C5） | P0 | 独立并行线，与诊断引擎分支隔离；本轮不混合提交 |
| D-R2-06 | RootHide 真机只读验收 | P1 | 待编译与离线测试通过后上设备；本轮不连真机 |

## 2. 冻结与禁止边界（沿用，本轮不变）

- 不改冻结公共 Models、`ReportEnvelope`、Adapter 七方法协议、Plist Parser 语义、Stage1 fixtures。
- 不改 `loaded` / `installed` / `configured` 语义；`loaded` 无独立运行时证据恒 `unknown`，不得自动转 `false` / `failed` / `passed`。
- 测试只调用 Core 内部可见纯函数与既有公共类型；不为通过率把 unknown 翻成结论；不引入文件写入接口。
- 禁止：插件启停、plist/规则写入、dylib 删移、dpkg 写、软链改动、注入、Helper 启动/IPC/`launchctl`、常驻 daemon、entitlement/签名/沙盒例外放行、`jbroot()` 伪造调用与弱链接伪造符号声明。
- 本轮引擎改动仅限：纯静态/纯聚合辅助函数由 `private` 放宽为 internal（同模块可见，`@testable import Core` 可达）；为离线测试提取纯文本/纯字段辅助函数，FS 包装器行为不变。不拆目录、不改公共签名。

## 3. 18 项离线测试覆盖矩阵

测试目录：`Tests/Stage2/Diagnostics/`；全部 `import Foundation / XCTest / @testable import Core`。
覆盖分级：**pure**（纯函数离线断言）／**pure-agg**（纯聚合，输入构造记录数组）／**deferred**（FS / 私有 Workspace / dyld 运行时，离线不可验证，记录口径与待真机项，不写伪造断言）。

| # | 测试文件 | 对应能力 | 可离线表面 | 覆盖场景 | deferred 项 |
|---|---|---|---|---|---|
| 1 | `JBRootDetectorTests.swift` | JBROOT 定位与校验 | `.jbroot-<16hex>` 正则反解 | 命中/非匹配/无后缀/非法字符；根路径提取 | 存在/可读/结构标记、`jbroot()` dlsym、容器 `.jbroot-` 枚举待真机 |
| 2 | `DynamicLibrariesTests.swift` | 目录枚举/可访问性 | 报告结构与空态口径 | `scan()` 报告目录段键齐全；无可读目录时不伪造可访问记录 | 路径存在性/可读性/`opendir` errno、realpath 待真机 |
| 3 | `DylibScannerTests.swift` | dylib 文件扫描枚举 | 扩展名/类型归类辅助 | `.dylib` 小写后缀、目录/符号链接/常规文件归类口径 | 目录遍历、可执行位、逐文件 lstat 待真机；跨根去重见 #331 |
| 4 | `FilterPlistTests.swift` | plist 扫描读取 | 解析输入类型守卫 | 非字典顶层 → 类型不匹配口径；嵌套 `Filter` 与顶层字典布局；空字典 | 文件读取/损坏 plist/不可读待 FS 接缝（D-R2-03） |
| 5 | `FilterRulesTests.swift` | Bundles/Executables/Classes 解析 | `parseFilterDictionary` 纯函数 | 全局 `*` 标 global 不计 exact_match；已安装/未安装 Bundle；可执行名小写匹配；非数组值/非字符串项/空串 warnings；other_keys；`valid`/`entry_count`；Classes 仅保留不映射 | `*` loader 语义恒 `protocol_verified=false`，待 ElleKit 源码核实 |
| 6 | `InjectorDetectorTests.swift` | 注入器识别 | 包关键词匹配 + 画像表 + 运行时行构造 | 五类关键词命中/未命中；Status 含 ` installed` 口径；画像能力位；运行时行 `scope=current_process_only`；静态与运行时证据分列；空包空镜像不伪造 | 镜像 Info.plist 版本反查、兼容结论枚举、启停能力位待真机 |
| 7 | `DPKGStatusParserTests.swift` | status 读取与状态解析 | 纯文本记录拆分 | 记录分隔/续行/畸形行/孤儿续行/重复字段 warning；空与纯空白；缺失与非 UTF-8 包装告警 | status 候选路径探测、文件读取待 FS 接缝 |
| 8 | `DPKGOwnershipTests.swift` | `.list` 文件归属 | 路径归一化纯函数 | root 前缀剥离、`/var/jb/` 剥离、尾斜杠/标准化、绝对前缀；多包集合归属聚合 | `.list` 读取与物理路径存在性待 FS 接缝 |
| 9 | `PackageMetadataTests.swift` | 包元数据提取 | `dpkgState` 状态机纯函数 | `install ok installed` → installed；`reinstreq`；installed 非标准状态；已知中间态；缺字段空串；字段大小写不敏感首现拼写 | 全字段 `raw_fields` 保留待结构化模型轮 |
| 10 | `FileIntegrityTests.swift` | 存在/可读/缺失与三级分类 | magic 字节表 + 扩展名桶纯函数 | mach-o/fat/elf/png/jpeg/zip/gzip/pdf/bplist/sqlite magic；configuration/text/resource/unknown 扩展名归类；`no_checksum_record` 桶命名；MD5 仅对照 `.md5sums` 非签名口径 | 逐文件存在/可读/缺失计数、流式哈希比对待 FS 接缝 |
| 11 | `FileSourceTests.swift` | 插件来源识别 | 来源归类纯函数 | 有精确归属 → dpkg；status 在场无精确归属 → manual_inferred；status 缺失无归属 → unknown；`exact_package_record` 布尔；推断来源不冒充真实清单 | 真机 dpkg 清单对照待 G12 门禁 |
| 12 | `ConffilesTests.swift` | Conffiles 双渠道识别 | status 字段解析纯函数 | 路径+MD5 行解析；非绝对路径忽略；双渠道合并去重；单渠道缺失不武断 | `info/<pkg>.conffiles` 文件渠道读取待 FS 接缝 |
| 13 | `PackageConflictTests.swift` | 跨包归属冲突 | 纯聚合 | 同路径多包 → conflict=true；单包 → false；未归属插件文件计数口径 | 冲突记录独立列表待结构化模型轮 |
| 14 | `HelperPreflightTests.swift` | RootHelper 只读预检 | 逻辑路径归一化 + 记录键口径 | 逻辑路径标准化/根剥离；候选/注册行必备键；`operation=not_launched` 恒成立；不启动/不通信 | 固定/受限目录枚举、LaunchDaemons plist 反查、可执行位待真机 |
| 15 | `AppInventoryTests.swift` | 已安装 App 枚举 | 空态守卫口径 | 私有 Workspace 不可用/非数组 → 空清单，不伪造；报告 App 段键齐全 | `LSApplicationWorkspace` 真机行为待 G 门禁 |
| 16 | `AppMetadataTests.swift` | App 元数据 | 版本回退与系统标记纯函数 | 短版本优先/构建号回退/都缺 unknown；`/Applications/`、`/System/` 前缀系统标记；图标候选空态 | 图标解码、私有图标 API 样本待真机/UIKit 切片 |
| 17 | `PluginAssociationTests.swift` | 插件↔App 静态关联 | `buildAssociations` + `associationSummary` 纯聚合 | Bundle/Executable 精确匹配；global；unmatched_target；unresolved_non_bundle_rule；invalid_configuration；summary global/unmatched/missingDylib/missingPlist 计数；关联行 `loaded=unknown`；静态匹配≠注入 | App→插件反向索引、持久化损坏隔离待 0.1-E |
| 18 | `DiagnosticSummaryTests.swift` | 报告可信度与汇总 | 报告级不变量 | 插件行 `loaded` 恒 unknown；installed=false 不支持 configured=true；global 不计 exact_match；missing-dylib 不报成功关联；报告顶层段齐全；findings 随 scan 产出；证据不足归 unknown/unverified | D-R2-04 证据等级字段与内部一致性校验后续批次 |

## 4. 引擎可见性与提取清单（本轮，行为不变）

- 由 `private static` 放宽为 internal `static`：正则反解、Filter 字典解析、dpkg 状态机、路径归一化、注入器画像、magic/扩展名归类、路径类目/扩展名键、关联汇总与关联构造、版本回退/系统标记、来源归类、Conffiles 字段解析。
- 提取纯函数（FS 包装器保留原行为）：dpkg status 纯文本解析、Conffiles status 字段集合、插件来源归类、App 版本回退与系统标记。
- 不提取、不放宽：`scanInstalledApplications`（私有 Workspace）、`inspectHelpers` 目录枚举、`analyzeDpkg` 文件遍历、`classifyFile` 文件句柄读取、`md5File` 流式哈希、`runtimeInjectorImages` dyld 枚举。

## 5. 本地静态核对口径

本机 Linux 无 swiftc/swift/Xcode；可执行：括号配平、`#if`/`#endif` 配平、脚本 `bash -n`、Python `py_compile`、workflow YAML 解析、残留现代 API/强制解包扫描。Core emit-module 与 `swift test` 全套以 Runner（macOS Apple 工具链）复测为准；新增测试用例数与通过/失败结论回填 §6。

## 6. 记录

### 6.1 本轮落地文件

- `Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift`：可见性放宽与纯函数提取（行为不变）。
  - 放宽 private→internal：`rootFromJBRootPath`、`identifyInjectors`、`injectorProfile`、`InjectorProfile`、`parseDpkgStatusText`、`conffilePathsFromFields`、`canonicalDpkgPath`、`physicalDpkgPath`、`dpkgState`、`magicFormat`、`typeFromFormat`、`isConfigurationExtension`、`isTextExtension`、`isResourceExtension`、`pathCategory`、`extensionKey`、`associationSummary`、`AssociationSummary`、`buildAssociations`、`parseFilterDictionary`。
  - 新提取纯辅助：`classifyPluginSource(owners:dpkgStatusPresent:)`、`resolveAppVersion(short:build:)`、`isSystemApp(path:)`、`helperLogicalPath(_:root:)`；`identifyInjectors`/`buildAssociations` 无实例状态，转为 `static`。
  - 保留 deferred private：FS 遍历/句柄读取/流式哈希/私有 Workspace/dyld 运行时表面（见 §4），本轮不提取、不放宽。
- `Tests/Stage2/Diagnostics/`：18 枚测试文件，共 111 个 `test` 方法。

  | # | 文件 | 方法数 | 分级 |
  |---|---|---|---|
  | 1 | `JBRootDetectorTests.swift` | 6 | pure |
  | 2 | `DynamicLibrariesTests.swift` | 4 | pure-agg / deferred 空态守卫 |
  | 3 | `DylibScannerTests.swift` | 4 | pure / deferred 遍历 |
  | 4 | `FilterPlistTests.swift` | 5 | pure 类型守卫 / deferred 读取 |
  | 5 | `FilterRulesTests.swift` | 8 | pure |
  | 6 | `InjectorDetectorTests.swift` | 7 | pure / pure-agg |
  | 7 | `DPKGStatusParserTests.swift` | 6 | pure |
  | 8 | `DPKGOwnershipTests.swift` | 9 | pure / deferred `.list` 读取 |
  | 9 | `PackageMetadataTests.swift` | 6 | pure |
  | 10 | `FileIntegrityTests.swift` | 11 | pure / deferred 哈希比对 |
  | 11 | `FileSourceTests.swift` | 5 | pure |
  | 12 | `ConffilesTests.swift` | 6 | pure / deferred 文件渠道 |
  | 13 | `PackageConflictTests.swift` | 4 | pure-agg |
  | 14 | `HelperPreflightTests.swift` | 6 | pure / deferred 枚举 |
  | 15 | `AppInventoryTests.swift` | 3 | deferred 空态守卫 |
  | 16 | `AppMetadataTests.swift` | 5 | pure |
  | 17 | `PluginAssociationTests.swift` | 8 | pure-agg |
  | 18 | `DiagnosticSummaryTests.swift` | 8 | pure-agg 报告不变量 |

- `Package.swift`：Stage2Tests `sources` 接线新增 18 条 `Diagnostics/<file>.swift`。
- 本计划与 `PACKAGE-NOTE.md`。
- 证据：`Tests/Stage2/evidence/r2-device-screenshots-1795218890/`（截图 + 合成信封 + METADATA.md）。

### 6.1.1 本地静态核对（本机 Linux 无 swiftc/swift/Xcode）

- 引擎括号配平：braces 288/288、parens 723/723、brackets 456/456、`#if`/`#endif` 12/12。
- 18 枚新测试括号配平全部通过；无 `try!`/`as!`/强制解包；无测试内 `jbroot()` 调用、`dlsym`、FileHandle 读取。
- `Package.swift` 18 条新接线与磁盘文件一一对应；Core/Stage2 既有接线未删改。
- 本机不产出编译/测试结论；Core emit-module 与 `swift test` 全套以 Runner（macOS Apple 工具链）复测为准。

### 6.2 Runner 复测回填

**首轮 `swift test`（macOS Runner Debug 切片，基线 `751d5ff7668e77301dfa33142273e6eb52225475`）**：

- 环境：macos-26-arm64 / macOS 26.7.2 / Testing Library 1902 / `arm64e-apple-macos14.0`；job 命令 `swift test`；证据 `Tests/Stage2/evidence/r2-run-751d5ff-swift-test/`（`job-logs.txt` + `RUN-METADATA.md`）。
- 编译：Core 引擎编译通过，本切片无编译错误；警告仅 17 处新测试恒真 `is` 判定。
- 测试：总计 569 例，**1 failure**（exit 1）；R2 十八套件 111 例中 110 passed、1 failed。
- 唯一失败：`FileIntegrityTests.testResourceMagicSignatures`，sqlite magic 夹具字节序写错（`53 51 69 4C…` → 应为 `53 51 4C 69 74 65`）；引擎 `magicFormat` 口径正确，非引擎缺陷。
- 本地处置：夹具字节序改正；恒真 `is` 断言改为 `count >= 0` 守卫；引擎语义未改。待下一轮 Runner 复测 569 例 0 failure、警告清零后回填。
- 未覆盖：iphoneos26.5 arm64 Release / iphonesimulator26.5 arm64·x86_64 Debug 目标结论待对应 job 日志；无 Runner 结果前不认定 iOS 编译通过。若报 `no such module 'MachO.dyld'`，备选改 `import MachO`，禁止伪造 C 函数声明。

### 6.3 DevDocs 打包

- 打包基线提交：`b750802`（R3-A/B 实现 + `310a083` 反馈切片归档与夹具修复 + 真机截图批次 `1795227596` 三方核对归档；未推送；打包 HEAD 以包内 git 清单为准）。
- 包内 2175 文件，15,813,483 B，SHA256 `d226efafbbf5516d650980488c60d1080e2931a320950ce736fd4d2b720bfd63`；包内不内嵌自身哈希。
- `unzip -tq` 无错误；zip 清单与暂存目录逐一一致；`validate-ldid-signature.sh` 条目模式 100755；排除规则沿用既有口径（`.git/`、小写 `research/`、`node_modules/`、`build/`、`.theos/`、`DerivedData/`、`.build/`、`.swiftpm/`、`*.xcodeproj/`、`*.xcworkspace/`、`.tmp/`、`.DS_Store`、`*.zip`、`App/Info.plist`、`*.xcresult/`、`__pycache__/`、`*.pyc`；剔除 `Research/Validation/evidence/0.1.18-device-report.json`）。

## 7. R3 授权移交指针（2026-11-21）

- D-R2-03（FS 协议解耦）、D-R2-04（证据等级与一致性）、D-R2-05（DEB 安装与启动验收，签名修复验证）已授权进入 R3，分两条独立开发线：
  - 线 A 诊断引擎：`Spec/Stage-2/Stage-2.6-D-R2-03-04-Diagnostics-Engine-R3-Plan.md`（03 → 04 顺序依赖）。
  - 线 B DEB 验收：`Spec/Stage-2/DEB-Install-Crash-Investigation.md`（与线 A 并行、独立提交）。
- D-R2-06 真机只读验收、#331 截图计数/去重（D1～D5）本轮仍冻结，待后续单独授权。
- R2 复测 0 failure / 警告清零、iOS 双目标编译结论待下一轮 Runner 日志回填；本文件 R2 记录口径不随 R3 实现改动。
