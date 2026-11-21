# Stage 2.6 — 0.1-D Acceptance R3 线 A：诊断引擎（FS 协议解耦 → 证据一致性）计划与冻结规格

> 输入基线：本地 HEAD `624ca8b`（链 `7428441` → `472f130` → `0a24e1e` → `624ca8b`，未推送）；DevDocs 包 `FilterKit-DevDocs-0.1.zip` 2156 文件 / 15,121,424 B / SHA256 `a30ca00f3db6b8d0b4736af4e8d9f8088532eb501a23e0b1e869b8c56892e950`。
> 授权范围：用户提案《D-R2-03、D-R2-04、D-R2-05 同一轮推进、拆两条独立开发线》；本轮授权 **D-R2-03、D-R2-04、D-R2-05**。本文件仅覆盖**线 A（诊断引擎）**；线 B（DEB 安装与启动验收）见独立文档 `Spec/Stage-2/DEB-Install-Crash-Investigation.md`，两条线分别提交、分别回退，不混合修改集。
> R2 复测现状：Runner `751d5ff` macOS Debug 切片 569 例 / 1 failure / 17 处恒真 `is` 警告；本地已修 4 枚测试文件，**0 failure 与警告清零待下一轮 Runner 复测回填**；本机 Linux 无 Swift/Xcode，不认定编译通过。

## 1. 任务矩阵与依赖

| 编号 | 任务 | 优先级 | 依赖 | 是否改源码 | 本轮处置 |
|---|---|---|---|---|---|
| D-R2-03 | 只读文件系统协议解耦（`DiagnosticFileSystem` 协议 + 本地实现 + 错误类型） | P0 | 无 | 是 | 本文件冻结规格；实现与离线夹具待下一批授权 |
| D-R2-04 | 诊断证据等级与内部一致性校验 | P1 | D-R2-03 完成后实施 | 是 | 本文件冻结规格；实现待 D-R2-03 落地并回归后授权 |
| D-R2-05 | DEB 安装与启动验收（签名修复验证，非重开发签名） | P0 | 与线 A 并行 | 视调查结果 | 见线 B 独立文档 |
| D-R2-06 | RootHide 真机只读诊断验收 | P1 | 编译与离线测试通过后上设备 | — | **本轮不授权**，不连真机 |
| #331 | 真机截图计数/去重（D1～D5） | — | 等 FS 抽象完成后单独处理 | — | **本轮冻结**，不改聚合语义 |

线 A 顺序：D-R2-03 协议解耦 → D-R2-04 证据一致性 → 18 项诊断测试回归；不得先做 D-R2-04 再补 FS 接缝。

## 2. 冻结与禁止边界（沿用 R2，本轮不变）

- 不改冻结公共 Models、`FKDiagnosticReport` / `FKDiagnosticFinding` 报告信封、Adapter 七方法协议、Plist Parser 语义、Stage1 fixtures。
- 不改报告 JSON 结构与既有字段键名；不改变原有诊断分类语义（来源归类、版本回退、关联类别、dpkg 状态机、注入器画像、magic/扩展名桶口径沿用 R2 已冻结结论）。
- 不改 `loaded` / `installed` / `configured` 语义；`loaded` 无独立运行时证据恒 `unknown`，不得自动转 `false` / `failed` / `passed`。
- 协议只暴露**只读**访问；不新增写入、删除、移动、重命名、链接变更接口。
- 不把文件访问失败（拒绝/不可达/异常）自动转换成「文件不存在」；异常必须保留类别。
- 禁止：插件启停、plist/规则写入、dylib 删移、dpkg 写、软链改动、注入、Helper 启动/IPC/`launchctl`、常驻 daemon、entitlement/签名/沙盒例外放行、`jbroot()` 伪造调用与弱链接伪造符号声明。
- 不一次性重构 18 项诊断：D-R2-03 只迁移提案指定的三个模块，其余模块暂留原 `FileManager` 直连。

## 3. D-R2-03：只读文件系统协议解耦

### 3.1 目标

把诊断引擎对文件系统的直接 `FileManager` 调用收敛到一个可注入的只读协议；生产实现包装现有 Foundation/Darwin 能力，测试实现使用临时目录或内存替身，使 JBROOT / Filter plist / dpkg 三类 FS 触点可离线构造夹具验证。引擎路径识别、根反解、解析与归类逻辑行为不变。

### 3.2 新增文件（规格冻结，路径与类型名）

```
Core/Diagnostics/Infrastructure/
├── DiagnosticFileSystem.swift        // 只读协议
├── LocalDiagnosticFileSystem.swift    // 生产实现（包装 FileManager）
└── DiagnosticFileSystemError.swift   // 错误枚举与映射口径
```

`Package.swift` Core target `sources` 显式数组同步接线三条新文件；既有 Core 接线不删改。

### 3.3 协议接口（冻结签名）

```swift
import Foundation

protocol DiagnosticFileSystem {
    /// 路径是否存在（不区分目录/文件；目录判定走 attributes 或调用方既有口径）。
    func fileExists(atPath path: String) -> Bool
    /// 路径存在且当前进程可读。
    func isReadableFile(atPath path: String) -> Bool
    /// 读取整个文件内容；失败抛 DiagnosticFileSystemError。
    func readData(atPath path: String) throws -> Data
    /// 读取文件属性（类型/大小/权限位等）；失败抛 DiagnosticFileSystemError。
    func attributes(atPath path: String) throws -> [FileAttributeKey: Any]
    /// 列出目录直接子项名称（不递归、不跟随符号链接做二次解析）。
    func listDirectory(atPath path: String) throws -> [String]
}
```

### 3.4 错误类型与映射口径

`DiagnosticFileSystemError` 至少区分：

| 案例 | 错误类别 | 报告/测试口径（沿用 R2 异常分类） |
|---|---|---|
| 路径不存在 | `notFound` | 未发现；不得与拒绝访问混写 |
| 存在但不可读/权限拒绝 | `permissionDenied` | 访问受限；**不得**回落为 notFound |
| 路径是目录却按文件读 / 是文件却按目录列 | `typeMismatch` | 解析/类型异常单独记录 |
| 系统调用异常、中断、非预期 IO | `unavailable` | 访问受限或未知，保留原始描述 |
| 其他未归类 | `unknown` | 只读 unknown，不伪造结论 |

- 生产实现把 `FileManager` / `Data(contentsOf:)` / `attributesOfItem` 抛出的 `CocoaError` / `POSIX` 错误按上表归类；`try?` 吞错路径必须带上类别，禁止 `try?` 后空列表当「不存在」。
- 测试替身可按用例注入 `permissionDenied` / `notFound` / 空目录 / 损坏字节，验证引擎按类别记录而非合并。

### 3.5 首批迁移范围（仅三模块）

| 模块 | 现引擎触点（R2 现状，行号以实现轮复核为准） | 迁移后口径 |
|---|---|---|
| JBROOT 诊断 | 候选容器父目录 `contentsOfDirectory`；根路径 `fileExists` / `isReadableFile`；`.jbroot-<16hex>` 标记子项（Library/usr 等）存在性检查 | 经协议枚举与判存在；正则反解、根路径提取纯函数不变 |
| Filter plist 读取 | plist 路径 `isReadableFile`；`Data(contentsOf:)` 映射读取；非字典/损坏 plist 守卫 | 经 `readData` 取字节后交既有 Plist Parser 解析；解析失败类别不变 |
| dpkg 状态解析 | status 候选路径 `fileExists` / `isReadableFile` / 物理路径判定；status 文本读取 | 经协议读取后交既有 `parseDpkgStatusText` 纯文本解析；`.list` / conffiles / `.md5sums` 读取**本轮一并收敛到协议接口调用**，解析纯函数不变 |

暂不迁移（保留原实现，避免一次性大重构）：动态库目录枚举之外的 dyld 运行时镜像、私有 Workspace App 枚举、Helper 目录枚举、流式 MD5 哈希、符号链接私有解析；这些 deferred 表面在规格矩阵继续标注 deferred。

### 3.6 输入 / 输出 / 异常 / 样本（实现轮夹具口径）

- **输入**：绝对或 JBROOT 相对路径字符串；协议不做路径规范化（规范化沿用 `canonicalDpkgPath` / `physicalDpkgPath` / `helperLogicalPath` 既有纯函数）。
- **输出**：布尔存在/可读、`Data`、属性字典、子项名数组；协议不返回报告段、不做归类。
- **异常**：见 §3.4；调用方按既有六类场景（正常 / 空 / 错误 / 文件不存在 / 无权限 / 证据不足）落测试。
- **样本**：临时目录构造正常 plist、损坏 plist、空目录、缺失文件、无权限位目录、嵌套符号链接；双路线（RootHide/Rootless）夹具沿用 Stage1 口径，不复制真机私有数据。

### 3.7 验收标准（D-R2-03）

1. 三类模块的引擎代码不再直接持有 `FileManager` 做上述读写；生产实现只在 `LocalDiagnosticFileSystem` 内包装 `FileManager`。
2. 协议可被测试替身注入；新增 FS 离线测试覆盖存在/可读/拒绝/类型不符/空目录/损坏字节六类场景。
3. 既有 458 例基线 + R2 111 例无回归；新增 FS 测试 Runner 通过（本机仅静态核对）。
4. 报告 JSON 段键、字段值口径与 R2 冻结信封逐段一致；异常类别不被合并为 notFound。
5. 公共 Models / Adapter 协议 / Plist Parser / Stage1 fixtures 零改动。

## 4. D-R2-04：诊断证据等级与内部一致性校验

### 4.1 目标

在引擎内部引入证据等级与一致性校验，把 R2 已冻结的「已安装≠已配置、已配置≠已加载、静态关联≠实际注入」等口径落成可执行规则；校验结论通过**既有**报告 `findings` 通道输出，不新增公共字段、不改信封。

### 4.2 内部证据模型（不进公共 Models）

```swift
// 引擎内部，fileprivate/internal 可见；不加入 FKDiagnosticReport Codable 结构
enum DiagnosticEvidenceLevel: String {
    case confirmed    // 有当前进程/运行时或直接记录证据
    case inferred      // 由静态文件/路径/清单推断，无运行时确认
    case unverified    // 存在记录但未完成校验
    case unknown       // 证据不足，保持未知
}

struct DiagnosticEvidence {
    let level: DiagnosticEvidenceLevel
    let source: String      // 证据来源：静态文件/dpkg 清单/运行时镜像/预览合成等
    let detail: String?     // 补充说明，可空
}
```

- 该模型为引擎内部聚合辅助；对外报告仍输出既有 `[[String:String]]` 段与 `FKDiagnosticFinding`（id/title/state/detail/payload）。
- 不为引入等级而改 `FKDiagnosticReport` / `FKDiagnosticFinding` 的 Codable 形状；等级映射进既有 `state` / `payload` 键时，键名沿用 R2 既有命名，不新造顶层 JSON 段。

### 4.3 一致性校验规则（E-01 ～ E-09，冻结）

| 规则 | 要求 | 违反时处置 |
|---|---|---|
| E-01 | `installed` 与 `configured` 分离：有包/文件记录不等于规则已配置 | 不得由 installed 推 configured；冲突进 findings |
| E-02 | `configured` 与 `loaded` 分离：规则解析通过不等于已加载 | 不得由 configured 推 loaded；冲突进 findings |
| E-03 | 静态匹配不能证明 `loaded` | 无运行时镜像证据时关联/插件行 `loaded=unknown` |
| E-04 | 没有 MD5 记录不能证明文件损坏 | 无 `.md5sums` 记录入 `no_checksum_record` 桶，不判损坏 |
| E-05 | 不可访问不能等同不存在 | 拒绝/不可达按访问受限记录，不合并为缺失 |
| E-06 | 未知注入器不能直接判定不兼容 | 未命中画像表标 unknown/inferred，不下不兼容结论 |
| E-07 | global 不能计入 `exact_match` | `*` 全局规则归 global 桶，不计精确匹配计数 |
| E-08 | 缺失 dylib 不能报告成功关联 | 缺 dylib / 缺 plist 关联归对应缺失桶，不报成功 |
| E-09 | 缺少运行时证据时 `loaded` 保持 `unknown` | 禁止自动翻 false/failed/passed；evidence 标 static_filesystem_only 或 current_process_only |

### 4.4 证据映射口径（沿用 R2 结论，不放宽）

- 来源归类：owners 空 + status 空 → unknown/insufficient；owners 空 + status 在场 → manual_inferred/no_exact_dpkg_list_owner；owners 非空 → dpkg/dpkg_list_exact_path；`exact_package_record = !ownerList.isEmpty`。
- 版本回退：短版本优先，回退构建号，都缺 unknown；只判 nil 不判空串。
- 关联类别：`not_parsed` / `read_failed` → invalid_configuration；global=true → global；有匹配 → exact_match；有未命中目标 → unmatched_target；否则 unresolved_non_bundle_rule；关联行 `loaded=unknown`、`evidence=static_filter_match_only`。
- MD5 仅对照 `.md5sums`，非安全签名；Mach-O 差异不判成因；Conffiles 允许本地差异；私有 Workspace 须 `responds(to:)` 守卫；dyld 镜像证据仅限当前进程。

### 4.5 校验执行位置与输出

- 校验在报告段聚合完成后、`scan()` 返回前于引擎内部执行；输入为既有各段记录，不回写文件、不触发二次扫描。
- 发现的不一致以既有 `FKDiagnosticFinding` 输出：`state` 取 R2 既有状态词表，`detail` 写规则编号（如 `E-03`）与证据类别，`payload` 带来源与计数；不新增 finding 类型枚举。
- 内部 `DiagnosticEvidence` 可在单元测试中断言等级映射；对外快照比对仍以 R2 信封为准。

### 4.6 验收标准（D-R2-04）

1. E-01 ～ E-09 每条规则有对应离线用例：正常 / 空 / 证据不足 / 冲突各至少一例。
2. 校验不改动报告 JSON 顶层段与字段；既有 569 例（R2 复测通过后基线）无回归。
3. 未知/证据不足场景不被翻成确定结论；global、缺 dylib、缺 plist 计数口径与 R2 `associationSummary` 一致。
4. 内部证据模型不泄露为公共 API；`@testable import Core` 可达仅限引擎内部可见性。

## 5. 提交拆分（两条线各自独立）

| 提交 | 线 | 内容 | 回退粒度 |
|---|---|---|---|
| `filesystem-abstraction` | A | D-R2-03：协议/本地实现/错误类型 + 三模块迁移 + FS 夹具测试 + Package 接线 | 可独立回退 FS 接缝 |
| `diagnostic-evidence-validation` | A | D-R2-04：内部证据模型 + E-01～E-09 校验 + 一致性用例 | 可独立回退校验层，不动协议 |
| `deb-crash-investigation` | B | 线 B 独立调查记录与静态检查产物（见线 B 文档） | 与线 A 互不影响 |
| `r3-acceptance-report` | 共用 | R3 验收归档、Runner 复测结论回填、打包基线 | 最后单独提交 |

禁止把四项合成一个提交；线 A 引擎重构不得夹带签名/打包流程改动。

## 6. 本地静态核对口径与待 Runner 项

- 本机 Linux 无 swiftc/swift/Xcode/plutil/lipo/ldid/codesign/otool；可执行：括号配平、`#if`/`#endif` 配平、`bash -n`、`py_compile`、workflow YAML 解析、禁用 API / 强制解包 / `try!` / `as!` / 测试内 `jbroot()` / `dlsym` / FileHandle 残留扫描、Package 接线与磁盘文件一一对应。
- 待 Runner 实测：macOS Debug `swift test` 全套 0 failure / 警告清零；iphoneos26.5 arm64 Release、iphonesimulator26.5 arm64·x86_64 Debug 编译结论。无新日志前不认定 iOS 编译通过。
- 若 Runner 报 `no such module 'MachO.dyld'`：备选改 `import MachO`，禁止伪造 C 函数声明。

## 7. 本轮明确不做

- 不做 D-R2-06 真机只读验收；不连 RootHide 真机、不安装/启动 DEB/IPA。
- 不做 #331 截图计数/去重（D1～D5）：目录枚举、跨根指纹、候选重叠、聚合语义改动等 FS 抽象落地后单独授权。
- 不重写签名/打包链路；线 A 不触碰 `scripts/sign-app-ldid.sh` / `validate-ldid-signature.sh` / DEB/IPA 打包脚本。
- 不放开 entitlement、签名、沙盒例外；不引入常驻 daemon 或 Helper IPC。

## 8. R3-A 实现落地记录（2026-11-21，待 Runner 复测）

### 8.1 落地文件

**D-R2-03 FS 协议层**（`Core/Diagnostics/Infrastructure/`）

- `DiagnosticFileSystem.swift`：只读协议五接口（`fileExists` / `isReadableFile` / `readData` / `attributes` / `listDirectory`）；无写入/删除/移动/复制/改属性接口。
- `DiagnosticFileSystemError.swift`：`notFound` / `permissionDenied` / `typeMismatch` / `unavailable` / `unknown`；POSIX 错误码映射（ENOENT / EACCES·EPERM / ENOTDIR·EISDIR / EIO·ENODEV·ESTALE），非 POSIX 域进 unknown；权限拒绝不回落 notFound。
- `LocalDiagnosticFileSystem.swift`：包装注入的 `FileManager`；协议扩展 `isDirectory(atPath:)` 经 `.type` 判定。

**引擎迁移**（`Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift`）

- 新增内部注入构造器 `init(fileSystem:appBundlePath:)`；公共 `init(fileManager:appBundlePath:)` 内部包装 `LocalDiagnosticFileSystem`。
- 已迁移：JBROOT 候选容器枚举/存在性/可读性/marker 检查；Filter plist 目录枚举与字节读取；dpkg status 候选定位/读取、`.list`/`.md5sums`/`.conffiles` 读取与物理路径存在/可读/目录判定。
- 保留 deferred 原 `FileManager` 直连：动态库目录枚举与 dylib 清单、注入器指纹、Helper 预检与 LaunchDaemons 反查、私有 Workspace App 枚举、流式 MD5/句柄读取、静态 `fileType`/`symlinkFlag`。

**D-R2-04 证据层**（`Core/Diagnostics/Evidence/`）

- `DiagnosticEvidenceLevel.swift`：`confirmed` / `inferred` / `unverified` / `unknown`，内部可见，不进公共 Models。
- `DiagnosticEvidence.swift`：内部证据记录（level/source/observedValue/reason/timestamp）。
- `DiagnosticEvidenceValidator.swift`：E-01～E-09 纯校验；报告级聚合 `validate(report:)`，违规经既有 `FKDiagnosticFinding` 通道输出；合规基线不产生新 finding。

**离线测试**（`Tests/Stage2/Diagnostics/`）

- `DiagnosticFileSystemTests.swift`：内存替身 `InMemoryDiagnosticFileSystem` + 8 例（存在可读 / notFound / 拒绝 / 类型不符 / unavailable / unknown / 目录列举 / status 缺失不伪装空包）。
- `DiagnosticEvidenceValidatorTests.swift`：13 例，E-01～E-09 各独立用例 + 合规三元组/合规段记录反向用例。
- `Package.swift`：Core 接线 6 条新文件；Stage2Tests 接线 2 枚新测试。Diagnostics 套件累计 132 个 `test` 方法（R2 基线 111 + 本轮 21）。

### 8.2 本地静态核对

- 新增/改动 Swift 文件括号配平全部为 0 残差；`#if`/`#endif` 12/12；无 `try!` / `as!` / 强制解包 / 测试内 `jbroot()` / `dlsym` / FileHandle；无写入型 FS 接口；Package 接线与磁盘文件一一对应。
- 既有签名/打包脚本 `bash -n` 通过；本轮未改脚本语义。
- 本机 Linux 无 Swift/Xcode：Core emit-module、`swift test` 全套与四目标编译以 Runner 复测为准；无新日志前不认定编译通过、不认定 0 failure。

### 8.3 提交链（本地，未推送）

`951899c`（A1/A2 协议层）→ `133e12e`（A3/A4/A5 三模块迁移）→ `adb9d32`（A6 FS 夹具测试）→ `b422510`（A7/A8/A9 证据层与用例）。线 B 准备记录见 `9fbe709`。

### 8.4 待 Runner 项

- macOS Debug `swift test`：132 例诊断套件 + 既有基线无回归；新增 21 例通过；无恒真 `is` 类新警告。
- iphoneos26.5 arm64 Release / iphonesimulator26.5 arm64·x86_64 Debug 编译结论。
- R2 残留：`751d5ff` 切片 1 失败 + 17 警告的修复仍待本轮 Runner 一并复测。

### 8.5 首轮 Runner 反馈切片（`310a083`，2026-11-21，编译中止）

- 基线：`origin/main` `310a08358378e4f6f7c2ac7fd025a55582438b42`；macos-26-arm64 / macOS 26.7.2 / `arm64-apple-macosx/debug`；命令 `swift test`；日志归档 `Tests/Stage2/evidence/r3-run-310a083-swift-test/`（53,200 B，SHA256 `e63530e7…059493`）。
- 结论：**测试目标编译失败，用例未执行**，exit 1；本切片警告 0；Core 侧 R3 七枚文件（Evidence/Level/Validator/FileSystem/Error/Local/Engine）编译清单内无 Core 报错。
- 唯一错误：`DiagnosticFileSystemTests.swift:62:45` `Set<String>` 无成员 `keys`——内存替身 `directories` 为集合，误用字典 `.keys`；夹具缺陷，非引擎语义。
- 本地修复：`Set(files.keys + directories.keys)` → `Set(files.keys + Array(directories))`（提交 `8edb06a`）；待下一轮 Runner 复测编译与全套用例。
