# Stage 2.4-R1-A/B：App Runtime Readiness 接线恢复 与 D5/D6 API 可行性核实记录

- 日期：2026-11-20
- 授权依据：用户授权「FilterKit 0.1-D-R1-A/B」。R1-A 恢复 App Build / Simulator 验收 / XCUITest，验证 Diagnostics 页面与 JSON 导出，不改 Core、Models、Adapters 业务语义；R1-B 核实 RootHide `jbroot()` 真实声明与符号来源、调查 GUI 进程 entitlement 可用检查机制，把 D5/D6 占位整理为明确可行性结论；真实 API 确认前不实现对应调用；不改 Adapter 七方法协议、不改冻结公共 Models 与 ReportEnvelope。
- 状态标记：**R1-A 工作流接线已落盘 / 本地 YAML 解析通过 / Runner Build & Test Pending**；**R1-B 上游源码与官方文档核实完成 / 真机调用与权限结论 Pending/unknown**。本机 Linux 无 Swift/Xcode，App Build、Simulator、XCUITest 结论须以在线 Runner 日志为准，本轮不在本地声称编译通过。

## 1. 授权边界与禁止项

### 允许（本轮实际执行）

1. 恢复 `app-build`、`ui-acceptance`（XCUITest）CI Job 与 `artifact` 产物依赖；
2. 静态核对 App 源码、诊断映射、导出接缝与 UITest 标识一致性；
3. 联网核实 RootHide `jbroot()` 上游源码声明、所属库、符号导出、返回类型、链接方式与进程环境限制；
4. 调查 iOS GUI 进程 entitlement 的公开检查机制与平台可用性；
5. 将核实结论与占位现状整理为可行性记录；只读核对，不写真机调用代码。

### 禁止（本轮均未触碰）

1. 插件启停；修改 plist；删除或移动 dylib；dpkg 写操作；修改注入规则；自动修复；常驻 daemon；
2. 未链接 libroothide、未写 C 桥接声明、未弱链接、未 dlsym、未调用任何未验证私有 API；
3. 未修改 Adapter 七方法协议、冻结公共 Models、`ReportEnvelope`；未改动 Plist Parser 语义与 Stage1 fixtures；
4. 未访问真实 JBROOT / TweakInject / 插件文件 / dpkg 数据库；未加载 dylib、未执行插件代码；
5. 本授权不含 RootHide 真机写操作或插件管理功能。

## 2. R1-A：App Runtime Readiness 接线恢复

### 2.1 改动文件

| 路径 | 改动 |
|---|---|
| `.github/workflows/filterkit-build.yml` | ① `app-build` 移除摘出期间的 `if: false`，注释更新为「0.1-D-R1-A 恢复」；② `ui-acceptance` 移除 `if: false`，注释更新；③ `artifact` 的 `needs` 加回 `app-build`。工程定义、App 源码、UITests 源码、`Tools/ReportRoundtripValidator` 摘出期间一直保留，本轮未改其实现。 |

### 2.2 恢复后的 Job 依赖链（本地 YAML 解析校验通过）

```
environment → build → test
                     → isolation
build + isolation → app-build → ui-acceptance
build + test + isolation + app-build → artifact (if: always())
```

- `app-build`：Checkout → 安装 XcodeGen → `xcodegen generate` → `xcodebuild -project FilterKit.xcodeproj -scheme FilterKit -destination 'generic/platform=iOS Simulator' -configuration Debug -derivedDataPath build/DerivedData build` → 定位 `FilterKit.app` → 选首个可用 iPhone 模拟器 boot/install/launch `com.filterkit.manager` → sleep 3 后 `launchctl` 存活复查 + `simctl io screenshot build/dashboard.png` → 上传 `filterkit-app-build`（`app-xcodebuild.log`、`sim-launch.log`、`dashboard.png`、`Debug-iphonesimulator/FilterKit.app`）。
- `ui-acceptance`：Checkout → XcodeGen → 选模拟器 → `xcodebuild test -scheme FilterKitUITests -destination platform=iOS Simulator,id=...`（xcresult 落 `build/uitest`）→ boot 后 `get_app_container ... data` 拉取 `tmp/FilterKit-Report-*.json` → `swift run ReportRoundtripValidator` 往返校验 + `SHA256SUMS` → 上传 `filterkit-ui-acceptance`。
- `artifact` 不含 `ui-acceptance` 依赖，与摘出前一致。

### 2.3 静态一致性核对（不替代 Runner 结论）

- `project.yml`：工程名 FilterKit，`bundleIdPrefix com.filterkit`，deploymentTarget iOS 17.0；`FilterKit` application target 源目录 `App`，依赖 Models/Adapters/Core，Bundle ID `com.filterkit.manager`；`FilterKitUITests` 为 `bundle.ui-testing`，源 `Tests/Stage2/UITests`，依赖 FilterKit target。
- `Package.swift`：`Stage2Tests` 已排除 `evidence`、`UITests` 等；UITests 不进 SwiftPM 编译，仅由 XcodeGen 工程编译；`ReportRoundtripValidator` executable target 在位（`Tools/ReportRoundtripValidator`）。
- Diagnostics 页面：`DiagnosticsViewModel.sections = DiagnosticsMapper.sections(envelope)`（既有 7 信封分区）+ `ProbeDiagnosticsMapper.sections(probeReport)`（探针 8 分类分区）；`DiagnosticsView` 经 `SectionCardView(identifier: "diagnostics.section.\(section.id)")` 渲染。UITest `testDiagnosticsSectionsVisible` 断言既有 7 分区标识；探针分区为 D7 新增，不在该用例断言内。
- JSON 导出：`ReportExporter` 经 `Core/Reporting/ReportService.swift` 的 `ReportExporting` 协议回显；`SettingsViewModel.exportReport()` 写 App 临时目录，失败保留错误文案、不返回空文件；UITest 覆盖导出按钮、分享链接与错误标识。
- 旧占位 `App/PermissionProbe/PermissionProbe.swift` 仅注释，无符号、无引用，不构成编译阻碍。
- 启动装配：空态参数 `-FILTERKIT_PREVIEW_EMPTY` 注入空信封，否则 `SyntheticReportFactory.previewEnvelope()`；真机快照接入属 R1-C，本轮未接线。

### 2.4 G7/G8/G9 Runner 取证（run `120957775572` 已实跑判定）

| 门禁 | 环境 | 待核证据 | 本轮结论（2026-11-20，run `120957775572`） |
|---|---|---|---|
| G7 App Build | Runner | `** BUILD SUCCEEDED **`；`FilterKit.app` 产物存在；0 error / 0 warning 以日志为准 | ✅ `** BUILD SUCCEEDED **`，0 error；1 条 `appintentsmetadataprocessor` 元数据跳过系统噪声 warning；`FilterKit.app` 产物保留（FilterKit 123808B / debug.dylib 8944448B / `__preview.dylib` 83952B），签名 Validate 通过；模拟器 PID 4029 存活 |
| G8 Diagnostics 页面 | Simulator | App 安装启动存活；Dashboard 打开；Diagnostics 分区可见；探针运行期间 GUI 不冻结 | ✅ XCUITest 8 例 0 failure（192.521s）；Dashboard 基线、Diagnostics 分区、列表/详情/设置全 passed |
| G9 JSON 导出 | Simulator | 容器临时目录出现 `FilterKit-Report-*.json`；往返校验通过；`SHA256SUMS` 落盘；Share Sheet 流程可走 | ✅ 导出预览 JSON 5295B；往返 `decodable=true`、`equalIgnoringGeneratedAt=true`；`SHA256SUMS` 落盘复算一致；导出无错误 / Share Sheet / 空态禁用三例 passed |

注意：0.1-C 时期 app-build 成功早于 D2～D7 落盘；D7 之后 App 层改动（ProbeDiagnostics 映射、`AppDependencies.probeReport`）此前只被 SwiftPM 非 UI 编译覆盖。本轮 Runner（run `120957775572`）为 D7 后第一次 XcodeGen + xcodebuild 全量 App target 编译与 Simulator 交互验证，G7/G8/G9 已由日志判定通过；证据见 `Tests/Stage2/evidence/run-120957775572-acceptance/RUN-METADATA.md`。截图与导出信封为合成预览桩，不构成真机权限证据。

## 3. R1-B-D6：RootHide `jbroot()` 源码核实结论

### 3.1 上游来源（已抓取核对）

| 项 | 来源 |
|---|---|
| 头文件声明 | `roothide/libroothide` `roothide.h`（main 分支） |
| 实现 | `roothide/libroothide` `jbroot.c` |
| Theos 选头 | `roothide-theos.h`：`THEOS_PACKAGE_SCHEME_ROOTHIDE` 时 `#include <roothide/roothide.h>`，否则 `#include <roothide/stub.h>` |
| Swift 模块映射 | `module.modulemap`：`module roothide { header "roothide.h"; link "roothide"; export * }` |
| 接口文档 | Aubidu/Developer `interface.md`（roothide API 说明与示例） |

### 3.2 七项核实

1. **真实函数声明**
   - C：`const char* jbroot(const char* path);`
   - Objective-C：`NSString* _Nonnull __attribute__((overloadable)) jbroot(NSString* _Nonnull path);`
   - C++ 另有 `std::string` 重载；分配版 `jbroot_alloc(const char*)` / `jbrootat_alloc(int fd, const char*)`（调用方 free）；`jbroot` 走进程内静态缓存，返回缓存指针，不需 free。
2. **所属动态库**：libroothide；模块映射链接 `-lroothide`。
3. **符号是否导出**：实现以 `EXPORT`（`__attribute__((visibility("default")))`）标记；`jbroot`、`jbroot_alloc`、`jbrootat_alloc`、`jbrand`、`rootfs`、`rootfs_alloc` 均为默认可见导出符号。
4. **返回类型**：C 为 `const char*`；Obj-C 为 `NSString*`；路径为空/NULL 时 alloc 版返回 NULL；缓存版返回缓存路径指针。
5. **链接参数**：Theos scheme=roothide 自动按 roothide 头与库链接；Xcode 工程需配置 Theos 头/库路径或使用 roothide devkit 包；Swift 经 modulemap `import roothide`。rootful/rootless 编译走 `stub.h` 静态桩：`jbroot(path)` 原样返回 `path`，`rootfs(path)` 原样返回，`jbrand()` 返回 `0`——桩不提供真实 JBROOT 信息。
6. **FilterKit GUI App 是否可以调用**：**当前未知（pending）**。现状：FilterKit XcodeGen + SwiftPM 工程未链接 libroothide，无桥接头、无 roothide modulemap；普通未注入 GUI 进程不会自动加载 libroothide。能否解析到符号，取决于：App 是否按 roothide scheme 打包并链接 devkit、进程内是否存在由 roothide 初始化提供的 `__roothideinit_JBROOT` / `__roothideinit_JBRAND` 符号。该条件须在 RootHide 真机 GUI 进程内核实，本轮不假定可调用。
7. **进程环境限制**：
   - `jbroot(path)` 语义（据 `jbroot.c` 实现）：输入 jbroot 相对路径，返回挂载 JBROOT 前缀后的真实磁盘绝对路径（`jbrootat_alloc` 将 `JBROOT` 拼到解析结果之前）；`rootfs(path)` 为反向转换。**不存在零参「取 JBROOT 基目录」接口**；基目录由 extern 字符串符号 `__roothideinit_JBROOT` 承载，随机品牌值由 `jbrand()` 返回；`JB_ROOT_PARENT` 为 `/var/containers/Bundle/Application`。
   - 若要借助 API 取得基目录，`jbroot("/")` 的行为属待真机验证的推断，不能直接写成结论。
   - API-04 一致性检查要求路径规范化、软链处理并与 D2 已确认 JBROOT 比对；当前 `JBRootAPIProbe` 一致性为原始字符串比较，规范化/软链细化列为未决项（见 §6）。

### 3.3 可行性分级（D6）

| 结论位 | 状态 | 依据 |
|---|---|---|
| 声明 / 库 / 导出符号 / 返回类型 / 链接方式 / 桩行为 | 已核实 | 上游头文件、实现、modulemap、stub.h |
| GUI 进程内符号可解析 | 待真机 | 工程当前未链接；进程内初始化符号未验证 |
| 调用成功、返回有效路径 | 待真机 | 未在真实 RootHide 进程执行 |
| 与 D2 已确认 JBROOT 一致 | 待真机 | 需规范化 + 软链 + 证据比对 |
| API 返回路径正确 ≠ 该路径可访问 | 原则固化 | 内容可达性由 D2/D3/D4 文件探针独立取证 |

## 4. R1-B-D5：GUI 进程 Entitlement / Sandbox 检查机制调查

按附件口径拆为三类证据，互不替代。

### 4.1 Signed Entitlements（签名声明）

- 可在 macOS Runner 对构建产物执行 `codesign -d --entitlements :- FilterKit.app` 取证；是否可用、输出格式以 Runner 环境为准。备选：解析 `embedded.mobileprovision` 的 `Entitlements` 段（Apple TN3125：iOS 平台 profile 位于 App 包内 `embedded.mobileprovision`）。
- 边界：该证据**只能证明签名产物声明了哪些 entitlement，不能证明运行时一定获得这些权限**。建议归档 `signed-entitlements.txt` / `signed-entitlements.json` / `signature-inspection.log`（R1-C 真机阶段执行）。

### 4.2 Runtime Entitlements（进程实际持有）

- Security framework 的 `SecTaskCreateFromSelf`、`SecTaskCopyValueForEntitlement`、`SecTaskCopyValuesForEntitlements` 在 Apple 官方文档平台标注为 **Mac Catalyst 13.0+ / macOS 10.0+，不含 iOS**；iOS 上没有公开、稳定的进程内 entitlement 枚举/读取 API。
- 私有 amfi / sandbox 检查接口不在本授权范围：不调用、不弱链接、不 dlsym、不据函数名编造 C 声明。
- **结论**：Runtime entitlement 检查在 iOS GUI 进程上尚未获得可核实的公开机制；现有 `EntitlementInspecting` / `CodeSignInspecting` 接缝保持占位 unavailable/unknown。不允许根据 IPA/包签名内容推断运行时 entitlement。

### 4.3 Actual Resource Access（实际资源访问）

- 由 D2（JBROOT）、D3（ElleKit/TweakInject）、D4（插件 dylib/plist/dpkg）与 `SandboxAccessProbe` 的 POSIX 只读探针独立取证；每个目标独立记录可达 / 拒绝 / 不存在，错误按 ENOENT、EACCES、EPERM 分类，不合并为一个「拒绝」。
- 边界：单条路径可达不等于整个 Sandbox 已关闭；探针只做只读 inspect，不触发写入、不申请额外权限、不 dlopen 插件。

### 4.4 现状接缝对照（冻结面未改）

| 层 | 接缝（既有，未改名） | 占位实现（本轮未替换） |
|---|---|---|
| D5 进程 entitlement | `EntitlementInspecting` / `EntitlementSnapshot(available, observedKeys, reason)` | `UnavailableEntitlementInspector`：`available = false` + reason |
| D5 代码签名 entitlement | `CodeSignInspecting` | `UnavailableCodeSignInspector`：`available = false` + reason |
| D6 jbroot API | `JBRootResolving` / `JBRootAPISnapshot(symbolAvailable, invoked, resolvedPath, errorReason)` | `UnavailableJBRootResolver`：`symbolAvailable = false, invoked = false` |

- 附件草案 `RuntimeEntitlementResult` / `RuntimeEntitlementInspecting`、`RootHideJBRootResolving` / `RootHideJBRootResolver` / `JBRootAPIError` 属接口设计稿，不是最终实现；现有接缝命名与快照结构保持不动。未来落地真实实现时，新增实现类替换占位，协议与快照不变。
- 本轮**未实现任何真实 API 调用**；未新增外部符号声明、弱链接或 dlsym。

## 5. 本轮代码实现说明

- R1-A：仅工作流 YAML 接线恢复（§2.1），无业务代码改动。
- R1-B：无新增调用代码；仅产出本可行性记录。D5/D6 占位实现维持 0.1-D 现状。
- 未改动：Core 业务语义、Models 公共模型、`ReportEnvelope`、Adapter 七方法协议、Plist Parser 语义、Stage1 fixtures、既有探针分类与状态映射。

## 6. 未解决问题（含既有挂起项，不在 R1 范围擅自扩展）

1. ~~G7/G8/G9 待 Runner 实跑判定~~ **已闭环（run `120957775572`，2026-11-20）**：App Build `BUILD SUCCEEDED`、模拟器 PID 4029 存活、XCUITest 8 例 0 failure、导出 JSON 往返校验通过；详见 §2.4 与 `Tests/Stage2/evidence/run-120957775572-acceptance/RUN-METADATA.md`。该项仅 Runner/Simulator 口径通过，不替代真机 G10～G15 取证。
2. D6 真机条件未核实：GUI 进程内 libroothide 符号解析、`jbroot()` 调用、返回路径有效性、与 D2 证据一致性；`jbroot("/")` 取基目录行为待验证。
3. ~~D6 一致性比较细化：路径规范化、软链解析后再比对（当前为原始字符串 `==`）~~ **R2-B 代码层已落地（2026-11-20）**：`JBRootPathComparator` 四层 raw / normalized / symlink / accessible 比较替换探针内原始 `==`；词法规范化与软链解析属离线可测层，真实 inode/dev 身份验证与真机一致性仍待 RootHide 真机取证。详见 §8 与 D2-D7 记录 §5.9。
4. D5 Runtime entitlement：iOS 无公开机制的结论待真机环境复核；若 RootHide 提供经核实的进程内 helper/接口，再评估替换占位。
5. 既有挂起项（按原计划保留，部分属 0.2.0 评审范围）：`OwnershipResolver` 未迁移；`loaded` 恒 `.unknown`；`permission.decision` 恒 undetermined；`pluginID` 稳定标识规则 0.2.0 定稿；PARSE-009-B。
6. 0.1-C G10 缺口不豁免、不签署；不能把 0.1-D 真机权限结果当作 0.1-C Share Sheet 证据。
7. 真机部署形态（普通沙盒 App / 越狱文件访问 App / CLI 先行）仍待拍板；当前基线为方案 B（越狱文件访问 App）建议，未冻结。

## 7. R1-C 真机测试准备清单（前置条件，本轮不执行）

1. **设备与越狱**：RootHide 越狱真机，记录 iOS 版本、越狱版本/boot 方式、设备架构；确认是否 RootHide scheme 环境。
2. **签名与部署**：明确 App 签名方式（开发者证书 / ldid 授权）、安装位置与部署形态；准备产物 entitlement 取证命令与归档目录。
3. **libroothide 接入评估**：确认 devkit 头文件/库是否随包、链接参数与进程内 `__roothideinit_JBROOT/JBRAND` 存在性；未核实前 D6 不接真实调用。
4. **证据模型**：R1-C 新增独立真机证据模型（如 `DeviceValidationEvidence`，含 evidenceID/deviceProfile/processContext/probeID/operation/status/errorDomain/errorCode/executedAt），不修改冻结 Models；`processContext = FilterKit.GUI`，`deviceProfile = RootHide`，shell/CLI/Runner 证据不混入 GUI 结果。
5. **只读边界复核**：探针仅 lstat/stat/opendir/readdir/open/read；不 dlopen 插件、不执行插件代码、不写越狱目录、不执行 dpkg/apt 写操作。
6. **测试顺序**：JBROOT → TweakInject → 插件 dylib/plist → dpkg → D5/D6；基础文件访问未通过前，不把问题误判为 API 问题。
7. **冷启动复测**：退出并重启 FilterKit App 后重跑 D2～D6，比对 JBROOT 可达、TweakInject 可枚举、dylib 可读、plist 可解析、dpkg 可读、`jbroot()` 返回值一致性；不把目标 App 冷启动作为 D-G15 条件。
8. **归档**：真机日志、签名/entitlement 取证、导出 ProbeReport、截图与往返校验产物按 `Tests/Stage2/evidence/` 惯例归档；unavailable/unknown/pending 不得改写为 passed。

## 8. R2-A/B 复核与代码落地补充（2026-11-20）

- **授权范围**：「FilterKit 0.1-D-R2-A/B」。D5 三类证据（signed / runtime / resourceAccess）显式分离；D6 `jbroot()` 上游复核与路径一致性修复；补单测与错误态测试。不含 0.1-E 正式开发、发布打包与签署。
- **上游当前 main 复核（2026-11-20 重新抓取，与 §3 结论一致，无漂移）**：
  - `roothide.h`：C `const char* jbroot(const char* path);`；Obj-C `NSString* _Nonnull __attribute__((overloadable)) jbroot(NSString* _Nonnull path);`；alloc 变体与 `rootfs` / `jbrand` 声明同 §3.2。
  - `module.modulemap`：`module roothide { header "roothide.h"; link "roothide"; export * }`，链接 `-lroothide`。
  - `jbroot.c`：`jbroot(const char*)` 走静态 `cache_path` 缓存返回；alloc 版调用方释放；空 / NULL path 返回 NULL；`__private_jbrootat_alloc` 词法解析 `.` / `..`、去尾斜杠、inode/dev 比对与 `/rootfs` 前缀剥离。
  - `stub.h`：非 roothide 桩 `jbroot(path)` 原样返回 path、`jbrand()` 返回 0。
  - `common.h`：`EXPORT` 默认可见性；extern `__roothideinit_JBRAND` / `__roothideinit_JBROOT`；`JB_ROOT_PARENT "/var/containers/Bundle/Application"`；无零参取基目录接口。
  - Apple 文档复核：`SecTask*` entitlement 接口平台标注仍为 macOS / Mac Catalyst，不含 iOS。
- **代码落地（Core 层，冻结 Models 未改）**：
  - D5：新增 `EntitlementEvidenceSource`（signed / runtime / resourceAccess）与 `EntitlementEvidenceRecord`；`EntitlementProbe` 两条证据分别标注 `[runtime]` / `[signed]`；`SandboxAccessProbe` 标注 `[resourceAccess]`；runtime 占位原因注明 iOS 无公开稳定读取接口。协议、快照、占位实现替换路径未改。
  - D6：新增 `JBRootPathComparison` / `JBRootConsistencyVerdict` / `JBRootPathComparator`（raw / normalized / symlink / accessible 四层）；`JBRootAPIProbe` 一致性由原始 `==` 改为分层比较，初始化器加可选 `fileAccess`（默认 nil）；resolver 协议与快照未改。
  - 测试：`PermissionProbeProbeTests.swift` 更新受前缀影响断言，新增 10 例（D5 3 / D6 7）；Runner 编译与用例结论已由下一轮 CI 日志判定，见下条「Runner 复验」。
- **Runner 复验（run `121082423820`，2026-11-20，G1～G9 通过；真机 G10～G15 挂起）**：检出 SHA `59f3eb96a296c5ca8db908635275fc6f5b69c07f`，metadata 五文件与本地 `10d74a4` 基线逐文件 diff 一致。G1 非 UI Build `Build complete! (26.89s)` 0 error / 0 warning，两个新 Core 文件参与编译；G2 全量 **458 tests 0 failures**（基线 448 + 新增 10）；G3 S1-05 **15 tests 0 failure**；G4 探针 53 例 0 failure（Status 4 / Evidence 5 / Report 6 / Probe 34 / Presentation 4）；G5 隔离 7/7 passed；G7 `** BUILD SUCCEEDED **`，模拟器 `5AB3DACF-…` PID 6302 存活；G8 XCUITest **8 例 0 failure（238.195s）**；G9 导出 JSON 5295B 往返 `decodable=true` / `equalIgnoringGeneratedAt=true` / `messages=[]`，SHA256 复算一致。10 例新增用例在 test-log 逐一 passed。证据归档 `Tests/Stage2/evidence/run-121082423820-acceptance/`；本轮仅 Runner / Simulator / 合成桩口径，不替代真机取证。
- **仍挂起（不计 passed）**：GUI 进程符号解析 / 调用 / 返回路径有效性 / 真机一致性；`jbroot("/")` 基目录行为；词法规范化不等于 inode/dev 身份验证；runtime entitlement 真机读取机制；既有挂起项（OwnershipResolver、loaded 恒 unknown、permission.decision 恒 undetermined、pluginID 规则 0.2.0、PARSE-009-B）维持不变。
- 完整修改清单、verdict 规则、限制与真机准备清单见 `Stage-2.4-D2-D7-PermissionProbe-Chain-Implementation-Record.md` §5.9 / §5.10。
