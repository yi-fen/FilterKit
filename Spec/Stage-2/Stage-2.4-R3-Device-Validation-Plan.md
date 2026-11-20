# Stage 2.4-R3 — RootHide Device Validation & Release Readiness 方案冻结（R3-A，待真机）

> 阶段：0.1-D 收尾批次 R3（RootHide 真机权限验证与 0.1-C G10 独立补证）。
> 基线：本地归档提交 `204ef12`（未推送）；R2 Runner 复验 run `121082423820` G1～G9 Runner/Simulator 口径通过；真机门禁 G10～G15 全部 pending/unknown。
> 授权口径：本轮授权 **0.1-D-R3-A（真机验证准备：测试对象、执行矩阵、证据字段契约、执行前检查、验收标准）**；R3-B～E 真机只读探针执行、冷启动复验与归档须在具备 RootHide 真机的环境分批授权执行；0.1-E 仅允许预冻结设计设想，不进入正式实现。
> 工具链：本机 Linux 云主机无 Swift/Xcode、无 RootHide 真机；本规格不编译、不建工程、不写真机调用代码，代码与真机结论以在线 Runner 与真机日志为准。
> 依据：用户 R3 建议稿《现在仍然不建议正式进入 0.1-E。建议先完成 0.1-D-R3：RootHide 真机权限验证与 0.1-C G10 缺口补证》（2026-11-20 上传归档）；建议稿内代码结构为示意，落地前必须对照本仓库真实文件与冻结模型。

## 1. 定位与边界

### 1.1 三个层次的现状（不得互相替代）

| 层次 | 当前状态 | 判断口径 |
|---|---|---|
| 代码实现 | R2 D5/D6 已落地（三类证据分离、四层路径比较） | 已参与 Runner 编译 |
| CI / Simulator | G1～G9 通过（run `121082423820`，458 例 + S1-05 15 + 探针 53 + 隔离 7/7 + XCUITest 8） | 离线/模拟器验收通过 |
| RootHide 真机 GUI 进程 | G10～G15 全部 pending/unknown | 尚未验证，不得由 Simulator 合成桩代替 |

### 1.2 R3-A 目标

- 冻结 R3 批次拆分、真机测试对象与探针执行矩阵；
- 冻结真机证据模型字段契约（R3 局部包装层，复用冻结公共 Models，不扩展冻结信封）；
- 冻结执行前检查（Preflight）清单与双类验收门禁（Runner 离线切片 / RootHide 真机）；
- 明确 0.1-C G10 独立补证的门禁隔离口径与 0.1-E 预冻结边界。

### 1.3 非目标（R3-A 及未授权批次禁止）

- 不访问真实 JBROOT / TweakInject / 插件文件；不在本机或 Runner 执行真机只读探测。
- 不调用 `jbroot()` 或任何 RootHide 私有 API；不写 C 桥接声明、不弱链接、不 dlsym、不伪造符号声明。
- 不新增第二套插件扫描器 / 枚举器 / 配对器；R3-B～D 优先复用 R2 已落地探针与既有 Reader/Parser。
- 不修改冻结公共 Models、`ReportEnvelope`、Adapter 七方法协议、Plist Parser 语义、Stage1 fixtures；不改 `loaded` / `installed` / `configured` 既有语义。
- 不做插件启停、plist 写入、dylib 删除/移动、dpkg 写操作、注入规则修改、自动修复、常驻 daemon；不改 entitlement/签名/沙盒例外。
- 不生成 0.1-D 签署结论，不进入 0.1-E 正式开发，不做发布打包与签署。
- 不把 shell / CLI / Runner / Simulator 证据混入 FilterKit GUI 进程结果。

## 2. 批次拆分（R3-A / A2 / B～F + 独立补证）

| 批次 | 开发/验证内容 | 主要交付 | 前置 |
|---|---|---|---|
| **R3-A** | 真机测试准备：环境清单、探针执行矩阵、证据字段契约、Preflight、验收标准 | 本规格；离线可测的模型/映射契约（R3-B 落地 Swift 类型） | R2 归档 `204ef12` |
| **R3-A2** | RootHide 测试部署包：DEB 结构、Bundle ID/安装路径策略、签名与 entitlement 方案、最小 control 口径、安全 postinst 设计、静态完整性与元数据口径（规格冻结，见 `Stage-2.4-R3-A2-Deployment-Package-Spec.md`） | 部署规格；CI 可做 DEB 构建/静态检查的口径（本轮不写安装脚本、不真机安装） | R3-A 方案冻结 |
| **R3-B** | JBROOT / TweakInject 访问验证（真机只读） | G10/G11 真实目录访问独立证据 | 部署形态冻结；真机与进程上下文就位；Preflight 通过；R3-A2 部署包口径就绪 |
| **R3-C** | 插件文件与 dpkg 读取验证（dylib metadata/read、plist read/parse、dpkg metadata/read） | G12 只读证据；复用现有 Reader/Parser | R3-B 环境就位；样本基线录档 |
| **R3-D** | Entitlement / `jbroot()` 验证（D5 三类真机表现、D6 四层一致性真机取证） | G13/G14 真实运行证据；runtime 不可用保持 unknown | 目标版本 libroothide 头文件/符号/链接方式核实 |
| **R3-E** | 冷启动复验、Diagnostics 真机报告接入、证据归档 | G15 复验记录；真机报告；批次内证据归档 | R3-B～D 证据齐备且可追溯 |
| **R3-F** | R3 总体验收：Runner 离线切片 + RootHide 真机门禁统一复核，门禁状态由证据重算 | R3 统一验收结论与归档 | R3-B～E 全部留证；检查点 A/B/C 通过；证据 SHA256 与版本一致 |
| **0.1-C G10 补证** | 独立 GUI 门禁：系统 Share Sheet 面板可见性复核（既有搁置项，见 §7） | 独立门禁证据，不并入 0.1-D / R3 判定 | 须先明确授权推翻 2026-11-20 搁置决定 |
| **0.1-D Final** | 真机门禁全绿后的正式签署归档 | 0.1-D 闭环结论 | G10～G15 + 0.1-C G10 独立闭环 |
| **0.1-E Specification** | 发布验收引擎规格预冻结（见 §9，不实现） | 规格草案 | 0.1-D 闭环前仅作设计记录 |

批次顺序：R3-A 冻结方案 → R3-A2 部署规格 → R3-B～D 真机探针 → R3-E 冷启动复验与留证 → R3-F 总体验收 → 0.1-C G10 独立补证 → 0.1-D Final → 0.1-E 规格 → 0.1-E 实现 → 0.1-E Final。R3-B～D 复用 R2 代码，不另造扫描器。R3-B～E 不做批次间正式 Runner 验收，但必须各自完成执行记录与证据归档（见 §6 检查点），不得堆到 R3-F 才补前置检查。

## 3. 执行环境与进程上下文要求

### 3.1 设备档案（每次真机取证必须录档，摘要入证据）

- 越狱方案与版本（RootHide profile）、iOS 版本、设备架构（arm64e/arm64）、ElleKit 版本；
- 设备标识仅记录必要摘要，不录入完整私有序列号 / UDID；
- 部署形态须在 R3-B 前冻结，未冻结前不得安排真机探测。形态重新定义为四类（通道与权限解耦）：
  - **A 普通 IPA**：默认沙盒，不假设可访问 JBROOT；
  - **B 特殊权限 App**：携带额外 entitlement / 平台能力，权限形态；
  - **C Bootstrap 安装通道**：经越狱包管理通道装入 JBROOT，安装通道；
  - **B+C**：经 Bootstrap（DEB）安装的特殊权限 App。优先验证 B+C，但最终形态由真机证据决定，不得预设通过；
- 安装成功 ≠ 权限放行：安装位置、代码签名、entitlement、sandbox 是四个分别验证的问题，uicache 注册成功、App 能启动均不能推断 JBROOT 可读或 `jbroot()` 可调用；
- App 构建产物对应的 commit SHA、Runner/构建标识、签名与安装位置摘要。

### 3.2 进程上下文（门禁有效性前提）

- 真机证据的 `processContext = FilterKit.GUI`：探测必须发生在 FilterKit GUI 进程内，不是越狱 shell、CLI、测试桩或 Runner；
- shell / CLI / Runner / Simulator 取得的目录或文件结论，只能作为旁证，不得写入 GUI 门禁结果；
- 证据须记录进程标识（PID 摘要）与取证时刻；跨进程、跨重启的结论分别记录，不合并为一次成功。

### 3.3 当前环境限制

- 本轮 Linux 云主机不具备 RootHide 真机与 iOS 工具链；R3-B～E 真机项保持 pending/unknown，本规格不预写通过；
- 真机批次须在可部署 FilterKit App 并取得 GUI 进程上下文的环境执行。

## 4. 探针执行矩阵（G10～G15）

复用现有 Core 探针与冻结操作/分类；每个操作生成独立证据，**不得从一个成功操作推断其他操作成功**。

### 4.1 门禁与探针映射

| 门禁 | 验证目标 | 复用探针（现有 probeID） | 分类 / 操作 | 独立证据子项 |
|---|---|---|---|---|
| **G10** JBROOT 访问 | GUI 进程对真实 JBROOT 的元数据与目录访问 | `jbroot.directory.access`（D2） | `.jbroot` / `resolve`、`stat`、`list` | 路径解析结果；元数据 stat；目录枚举；三项分别落证据 |
| **G11** TweakInject 访问 | GUI 进程对 TweakInject / ElleKit 目录的元数据与枚举 | `ellekit.directory.access`（D3） | `.ellekit` / `stat`、`list` | 目录元数据；目录枚举；分别落证据 |
| **G12** 插件文件与 dpkg 读取 | dylib / plist / dpkg 只读探测 | `plugin.file.metadata`（D4）、`plugin.plist.read`（D4）、`package.database.read`（D4） | `.plugin_files` / `.package_database`；`stat`、`read`、`parse` | dylib 元数据；dylib 只读；plist 读取；plist 解析；dpkg 元数据；dpkg 读取；逐项独立 |
| **G13** Entitlement / Sandbox | D5 三类证据真机表现：Signed / Runtime / Resource Access | `entitlement.inspect`（D5）、`sandbox.resource.access`（D5） | `.entitlement`、`.sandbox` / `inspect`、`read` | signed 证据；runtime 证据；resourceAccess 证据；分别落证据 |
| **G14** `jbroot()` 调用与一致性 | RootHide API 在 FilterKit 进程内可调用，返回路径与 D2 定位一致 | `jbroot-api.inspect`（D6） | `.jbroot_api` / `invoke`；四层比较 | API 调用结果；raw；normalized；symlink；accessible；一致性 verdict |
| **G15** 冷启动权限保持 | 重启 App 后关键访问权限仍保持 | 复用 G10/G11/G12/G13/G14 对应探针复测 | 同上 | 二次启动后各关键操作复测证据；进程重启上下文记录 |

### 4.2 操作独立性规则（证据不得互相替代）

- stat 成功 ≠ opendir 成功；opendir 成功 ≠ 文件内容读取成功；
- plist 文件读取成功 ≠ plist 解析成功；dylib 可读 ≠ dylib 可加载 ≠ ElleKit 已加载；
- 签名中存在 entitlement ≠ 运行时资源访问成功；单项资源访问成功 ≠ 全部 sandbox 限制解除；
- 文件存在 ≠ 插件已加载；`loaded` 继续保持 `.unknown`，除非将来有独立、可靠的运行时加载证据；
- `standardizedFileURL` 仅为词法规范化，不代表文件系统真实路径一致；真实身份比对须结合软链解析、文件访问与目标路径身份（inode/dev）取证；
- 不得自行声明 C 函数后假设其为当前设备 `jbroot()`；必须以 RootHide ElleKit 目标版本真实头文件、符号与链接方式为准。

### 4.3 错误分类口径（沿用 Stage1/Stage2 既有约定）

| 情形 | 证据状态 | 说明 |
|---|---|---|
| 目标资源 / API 不存在 | `unavailable` | 不记为权限拒绝 |
| 明确权限拒绝 | `permissionDenied` | 错误域/码保留 |
| I/O / 解析等其他失败 | `failed` | 不统一归为 denied |
| 前置条件不满足未执行 | `notExecuted` | 不计入 failed |
| 无法得出可靠结论 | `unknown` | 不升级为 passed/failed |
| 探针执行并验证成功 | `passed` | 仅对该操作、该资源、该进程上下文成立 |

## 5. 真机证据模型（R3 局部包装层，冻结 Models 不改）

### 5.1 复用既有冻结类型

- 状态复用 `ProbeStatus` 六态；操作复用 `ProbeOperation`（resolve/stat/list/read/inspect/invoke）；分类复用 `ProbeCategory`；单条证据复用 `ProbeEvidence`；汇总信封复用 `PermissionProbeReport`。
- 建议稿五态 `DeviceProbeStatus`（passed/failed/denied/unavailable/unknown）映射到既有六态：denied → `permissionDenied`；前置未满足 → `notExecuted`；不新引入证据级状态枚举。

### 5.2 R3 包装层字段契约（R3-B 落地 Swift 类型；R3-A 仅冻结契约）

> 以下为字段契约示意，类型归属 R3 局部层（计划 `Core/PermissionProbe/Device/`），不进入冻结公共 Models；字段命名以落地时对照现有 `ProbeEvidence` 为准。

**DeviceValidationEvidence（单条真机证据）**

| 字段 | 类型 | 说明 |
|---|---|---|
| `evidenceID` | String | 证据稳定标识 |
| `gateID` | String | 关联门禁（G10～G15 / C-G10） |
| `probeID` | String | 复用现有探针 ID（§4.1） |
| `operation` | ProbeOperation | 独立操作类型 |
| `status` | ProbeStatus | 六态结论 |
| `errorDomain` | String? | 错误域，无错误 nil |
| `errorCode` | Int? | 错误码，无错误 nil |
| `executedAt` | String | ISO8601/RFC3339 时刻 |
| `processContext` | String | 固定 `FilterKit.GUI` |
| `processIdentifier` | Int32? | GUI 进程 PID 摘要 |
| `deviceID` | String? | 设备标识摘要（不录完整 UDID/序列号） |
| `deviceModel` | String? | 设备型号 |
| `iOSVersion` | String? | 精确 iOS 版本 |
| `RootHideVersion` | String? | RootHide / bootstrap 版本 |
| `ElleKitVersion` | String? | ElleKit 版本 |
| `filterKitCommitSHA` | String? | 被验收代码 commit |
| `filterKitBuildNumber` | String? | App Build Number |
| `deploymentProfile` | String? | 部署形态（A / B / C / B+C，§3.1） |
| `targetSummary` | String? | 目标摘要；不记完整敏感私有路径 |
| `artifactPath` | String? | 证据文件归档相对路径 |
| `artifactSHA256` | String? | 证据文件 SHA256 |
| `runID` | String? | 取证批次/运行标识 |

**DeviceValidationGate（门禁结果）**

| 字段 | 类型 | 说明 |
|---|---|---|
| `gateID` | String | G10～G15 / C-G10 |
| `title` | String | 门禁标题 |
| `required` | Bool | 是否正式发布阻断项 |
| `status` | GateStatus | `passed` / `failed` / `pending` / `unknown`（门禁级；证据级用六态） |
| `evidenceIDs` | [String] | 关联证据标识列表 |

**DeviceValidationReport（真机汇总）**

| 字段 | 类型 | 说明 |
|---|---|---|
| `schemaVersion` | Int | 报告模型版本 |
| `generatedAt` | String? | 生成时刻，不参与确定性比较 |
| `deviceProfile` | String | 设备摘要 |
| `processContext` | String | `FilterKit.GUI` |
| `gates` | [DeviceValidationGate] | 门禁结果数组 |
| `evidence` | [DeviceValidationEvidence] | 证据数组，顺序由产出方保持 |

### 5.3 证据约束

- 不默认记录完整敏感路径；`targetSummary` 只记类别/条目数/大小等摘要；
- 错误不统一归为 permission denied；必须区分不存在、拒绝、解析失败、接口不可用；
- 不从一个成功操作推断其他操作成功；不根据文件存在推断插件已加载；
- 每条证据可追溯到门禁、探针、操作、commit、运行标识、执行环境、证据文件与 SHA256、执行时刻、设备与进程上下文；
- 重复/过期证据须在验收阶段标记，不得覆盖既有失败记录。

## 6. 执行前检查（Preflight，R3-B 前逐项确认）

1. **设备录档**：越狱方案/版本、iOS、架构、ElleKit 版本、设备摘要齐备；
2. **部署形态冻结**：A / B / C / B+C 已拍板（§3.1），安装位置、签名与文件访问能力与形态一致；B+C 仅为优先验证方向，未取证前不记为可行；
3. **代码对齐**：待验收 App 构建产物对应 commit SHA 已记录；与离线基线（`204ef12` / Runner `121082423820`）差异可追溯；
4. **链接核实**：目标版本 libroothide 头文件、符号导出、链接方式（`-lroothide` / modulemap）已核实；未核实前不写真实调用；
5. **只读边界复核**：仅使用 lstat/stat/opendir/readdir/open/read 等只读接口；不 dlopen、不执行插件代码、不写越狱目录、不 dpkg/apt 写、不改软链；
6. **样本基线**：已知环境样本（正常/多 App/Classes-Executables/异常 plist/缺配对）双路线夹具齐备；真机结果与样本口径可对照；
7. **进程上下文确认**：取证发生在 FilterKit GUI 进程，PID 可记录；非 GUI 上下文结论不入门禁；
8. **环境纯净**：无常驻 daemon、无自动修复、无注入规则改动；取证后不留后台进程；
9. **证据通道**：真机报告与截图只写 App 临时目录或受控归档位置；证据目录、命名与 SHA256 校验规则就位；
10. **工具链**：真机构建/部署所用 SDK 与向下兼容口径已记录（既有缺口：无 17.x SDK，16.5 SDK 对 iOS 17.0.2 兼容性待实测）。

### 6.1 批次内部检查点（不做批次间正式 Runner 验收，但不得堆到 R3-F 补前置检查）

| 检查点 | 时机 | 必须确认 |
|---|---|---|
| **A** | R3-B 完成后 | JBROOT 路径正确；TweakInject 可达；操作确实发生在 FilterKit GUI 进程；未把 shell 结果当成 GUI 结果 |
| **B** | R3-C / R3-D 完成后 | 文件读取与解析状态分离；Entitlement 三类证据分离；`jbroot()` 使用真实 API；四层路径比较结果可追溯；未新增私有扫描器 |
| **C** | R3-E 完成后 | 冷启动前后使用相同设备、部署形态与代码版本；复测结果有独立证据；所有证据 SHA256 一致；G10～G15 门禁状态可由证据重新计算 |

每个批次必须先完成自身执行记录与证据归档，再进入下一批；检查点未通过的子项保持 pending/unknown，不带入 R3-F。

## 7. 0.1-C G10 独立补证口径

- 既有状态：0.1-C G10（系统 Share Sheet 面板可见性）在 C-F5 第七轮仅取得部分证据，2026-11-20 决定**搁置、不再排程、不豁免不签署**；记录见 `Tests/Stage2/evidence/c-f5-seventh-run/C-F5-Gate-Status.md` §3。
- R3 预留独立门禁位：可与 R3 共用真机/测试环境安排，但**门禁号、证据、判定独立**，不并入 0.1-D G10～G15 结果，不合并判定。
- **重启前提**：须有明确授权推翻上述搁置决定；R3-A 不自动重启该复核，不把既有搁置项记为通过。

## 8. 验收门禁（双类）

### 8.1 Runner / Simulator 离线切片（可在 CI 完成）

| 项 | 通过条件 | 证据来源 |
|---|---|---|
| 基线无回退 | 既有 458 例全量 + S1-05 15 例 + 探针专项 + 隔离七项不回退 | Runner test/isolation 日志 |
| 真机证据模型 | R3 包装层 Codable 往返、可选字段、状态统计与既有模型一致 | 新增离线单测（R3-B 落地） |
| 状态传播 | failed / permissionDenied / unavailable / unknown / notExecuted 正确传播，不被升级为 passed | 单测断言 |
| Diagnostics 映射 | 真机报告到现有展示层映射正确；unknown 不渲染为 success | Presentation 单测 |
| JSON 导出 | 真机报告可导出合法 JSON，样本往返解析等义；generatedAt 不参与比较 | 导出样本 + 往返校验 |
| 架构隔离 | Core 不实例化具体 Adapter；App 不私有实现探针；隔离七项 passed | 隔离脚本摘要 |
| App Build | XcodeGen + xcodebuild `** BUILD SUCCEEDED **`，0 error | app-build 日志 |
| Simulator 回归 | 既有 XCUITest 8 例 0 failure | ui-test 日志 |

### 8.2 RootHide 真机门禁（G10～G15，CI/Simulator 不替代）

| 门禁 | 验收目标 | 必备证据 |
|---|---|---|
| G10 | FilterKit GUI 进程访问 JBROOT | §4.1 子项独立证据 + 进程上下文 + 设备档案 |
| G11 | FilterKit GUI 进程访问 TweakInject | 元数据 + 枚举独立证据 |
| G12 | dylib / plist / dpkg 只读探测 | 六项子证据；读取与解析分列；loaded 保持 unknown |
| G13 | Entitlement / Sandbox 证据 | signed / runtime / resourceAccess 分列；runtime 不可用记 unknown |
| G14 | `jbroot()` 调用与路径一致性 | invoke 结果 + 四层比较 + 身份比对 |
| G15 | 冷启动后权限保持 | 二次启动复测证据 + 重启上下文记录 |

真机门禁规则：

- 每个门禁需要独立证据；一项成功不把整组门禁标为通过；
- 必须确认测试发生在 FilterKit GUI 进程，而非越狱 shell；
- CI 和 Simulator 证据不能满足真机门禁；未完成门禁保持 pending/unknown；
- 证据缺失、环境不符、commit 不匹配、SHA256 不一致、非 GUI 上下文，均判无效证据，不得记 passed；
- 任一必需门禁 pending/failed/无效：0.1-D 不予闭环。

### 8.3 R3-F 总体验收（独立批次，不与 R3-E 冷启动混做）

- **前置**：R3-B～E 各自执行记录与证据归档齐备；检查点 A/B/C 通过；设备/部署形态/代码基线在冷启动前后一致。
- **验收范围**：Runner 离线切片（G1～G9 口径，§8.1）与 RootHide 真机门禁（G10～G15，§8.2）统一复核；门禁状态必须由证据重算，不接受手写 `passed`。
- **复核项**：证据文件存在且可归档；`artifactSHA256` 复算一致；`filterKitCommitSHA` 与被验收代码一致；真机证据确来自 RootHide 真机 GUI 进程；无重复/过期/无效证据；必需门禁无缺证。
- **0.1-C G10**：独立门禁，R3-F 不代为判定。
- **R3-F 不承担** 冷启动复测本身（R3-E 职责），也不承担发布打包/签署（0.1-E 职责）。

## 9. 0.1-E 预冻结设想（仅设计记录，不实现）

> 0.1-E 定位为 Release Acceptance & Final Packaging（发布前证据验证与归档），不是新增插件管理功能。真机门禁全部通过前，以下仅作规格草案，不进入实现。

- **AcceptanceGate**：gateID / title / required / status（passed/failed/pending/invalidEvidence）/ evidenceIDs；`required=false` 不掩盖无效证据或失败。
- **AcceptanceEvidence**：evidenceID / gateID / runID / commitSHA / environment / artifactPath / artifactSHA256 / observedStatus / executedAt；真机门禁另含设备与进程上下文证据。
- **EvidenceValidator**：不只看 `gate.status == .passed`，须验证：证据文件存在；SHA256 复算一致；commit SHA 与被验收代码一致；Runner/运行标识一致；执行环境符合门禁要求；真机门禁确来自 RootHide 真机 GUI 进程；无重复/过期证据；必需门禁无缺证。
- **ReleaseReadinessService**：汇总 total/passed/failed/pending/invalidEvidence 计数与 blockers；`canRelease = 全部必需门禁通过 && 全部必需证据有效 && 全部证据匹配发布 commit && 无必需门禁 pending && 无必需门禁 failed`；不得由手动写入 `status = passed` 直接决定发布通过。

## 10. 既有挂起项与未决依赖

- 既有未决（维持不变）：`OwnershipResolver` 未迁移；`loaded` 恒 unknown；`permission.decision` 恒 undetermined；`pluginID` 稳定标识规则 0.2.0 定稿；PARSE-009-B 挂起。
- 待拍板：真机部署形态 A / B / C / B+C（优先验证 B+C，最终由证据决定）；双真机可用性；Mac+Xcode 原生还是沿用旧 PoC。
- 待真机/目标版本核实：GUI 进程内 libroothide 符号可解析性、调用成功、返回路径有效性；`jbroot("/")` 取基目录行为；runtime entitlement iOS 读取机制；16.5 SDK 对 iOS 17.0.2 向下兼容。
- R3-B 落地前须对照 `204ef12` 工作区与 Runner 检出 `59f3eb96` 真实文件复核现有探针/协议/模型，本规格示意字段不直接等同于可编译代码。

## 11. R3-A 本轮交付与不交付

**交付：** 本规格（批次拆分含 R3-A2 / R3-F、执行矩阵、证据字段契约、Preflight 与批次检查点、双类门禁、独立补证口径、0.1-E 预冻结边界）；R3-A2 DEB 部署包规格；里程碑与实现记录回填。

**不交付：** 真机探针实现；`jbroot()` 真实调用；DEB/IPA 实际安装脚本与安装产物；真机取证结论；0.1-E 代码；发布签署。R3-A2 本轮仅冻结规格，不编写 postinst/control 落盘脚本、不在本机或 Runner 产出可安装包。所有真机门禁在取得 GUI 进程证据前保持 pending/unknown。
