# FilterKit 0.1.0 里程碑验收计划（Milestone-Based Verification Policy）

- 状态：**计划规格冻结**。本文件只定义里程碑划分、验收分级、退出标准与门禁口径；不写生产代码、不编译、不调度 Runner、不扫描真机。
- 上游基线：`Spec/PoC-0.1.0-Specification.md`（只读范围与功能验收）；`Spec/Stage-2/Stage-2-Implementation-Plan.md`（子阶段、接口契约、风险与暂缓清单）；`Spec/Stage-2/Stage-2.2-D-Reporting-Implementation-Spec.md`（D1～D5 冻结规格）；第五轮验收证据 `Tests/Stage2/evidence/run-44106064051-acceptance/`。
- 本地基线 HEAD：`2c3d6a3`；第五轮 Runner `44106064051`（branch `D5`，检出 SHA `f4629f268e680bc0e25e911997d03959457263ec`）。
- 定位：本计划是项目管理与验收口径规格，**不替代**各子阶段实施规格；任一里程碑进入实现前仍按既有流程单独授权。

## 1. 目的

Core 主要建设已完成，后续工作按里程碑组织。核心原则：

- 小步骤开发、阶段内自检、里程碑统一 Runner 验收、版本发布前完整验收。
- 不取消测试、不降低质量；只减少每个小批次都启动 Runner 的频率。
- CLI 与 GUI 始终共用同一套已迁移验收的 Core，不在界面层另写扫描/解析器。

## 2. 验收分级（L1 / L2 / L3）

| 等级 | 方式 | 是否需要 Runner | 产出 |
|---|---|---|---|
| **L1 开发自检** | 代码结构、接口一致性、测试用例完整性、架构约束、Git Diff、冻结规格是否被改动、待验证项记录 | 否 | 自检记录与待验证清单；可在开发过程中持续补充 XCTest |
| **L2 阶段集成验收** | 阶段代码冻结后集中编译、单元测试、回归测试、双路线隔离、Core/App 构建 | 是，**每个里程碑结束时一次** | 阶段证据归档、门禁结论、阶段正式验收记录 |
| **L3 版本验收** | 0.1.0 发布前全量验收（见 §6） | 是 | 版本级验收报告、安装包与发布文档背书 |

**定向提前验证触发条件**：若阶段中途改动公共 Models、Adapter 七方法协议、Parser 语义或其他冻结接口，或出现高风险接口 / 基础构建问题，必须暂停并做针对性验证，不能机械等到阶段末尾。失败后允许针对失败项修复与定向复验，不必无条件重跑全部测试。

## 3. 里程碑划分（0.1-A ～ 0.1-E）

| 里程碑 | 对应既有阶段 | 主要内容 | L2 Runner / 验收范围 | 当前状态（2026-11-17） |
|---|---|---|---|---|
| **0.1-A** Engine C2 收口 | Stage 2.2-C3 Engine | C2-A～D 测试与代码收口、C2-E 证据体系、RootHide/Rootless Parser 集成、Engine 完整链路、三向架构隔离 | 全量 XCTest、Core Build、App Build、双路线隔离脚本 | ✅ **已闭环**：run `44106064051`，379 例 0 fail / 0 skip，Core 0 error / 0 warning，App BUILD SUCCEEDED、PID 3508 存活，隔离六项 OK；C-G1～G7 判为 passed。**仅 CI/Simulator 口径**，非真机权限、真实加载或 Rootless 真机兼容证据 |
| **0.1-B** 统一报告与 JSON 导出 | Stage 2.2-D | Report Models 审计、Report Builder、Report Validator、JSON Exporter、Report Service；确定性排序与三态保留 | 阶段末一次 Runner：D1～D5 用例 + 既有回归无损伤 + JSON 确定性深比较 | ✅ **已闭环（CI/Simulator 口径）**：第四轮 Runner run `44224350333`（SHA `9a3f087`，macos-26 / Xcode 26.6 / Swift 6.3.3），非 UI Build `Build complete! (19.62s)` 0 error / 0 warning；全量 **397 例 0 failures / 0 skipped**（既有回归 379 + Reporting 18：Builder 6 / Validator 4 / Exporter 5 / Service 3）；S1-05 独立过滤 15 例 0 failure；隔离四项 OK；App `** BUILD SUCCEEDED **`，PID 4096 存活，只读骨架截图归档；第三轮两处断言失败（`installed` nil 显式落 `null`、RV-003 样本保留 nil 路径证据）复验通过。历程：首轮 SHA `117a5df` Core 4 处 `lastPathComponent` 误当 `String` 成员（提交 `b8ba3f3`）；二轮 run `44217387852` SHA `5fcb00e` 测试目标编译错误（提交 `4c95e30`）；三轮 run `44221150319` SHA `d08f04f` 2 例断言失败（提交 `94bd7f2`）；四轮全绿。证据 `Tests/Stage2/evidence/run-44224350333-acceptance/`。**仅 CI/Simulator 口径**，非真机权限、真实加载或 Rootless 真机兼容证据。`Core/OwnershipResolver/` 仍占位未迁移，`loaded` 恒 unknown |
| **0.1-C** GUI 完整建设 | Stage 2.3 | Dashboard、Plugins 列表、Plugin Detail、Diagnostics、JSON 导出入口、加载/未知状态展示、空态/错误态/权限不足提示 | 阶段末一次 Runner：App Build、ViewModel 与 Core 快照一致性、页面只读约束核对 | 🟡 **Implementation Landed / Runner Pending**（2026-11-18）：C1～C6 代码与 GUI-01～08 Presentation 单测已落盘；`AppPresentation` 纯映射目标接入 SwiftPM，隔离脚本 GUI 禁止面扩展。本机 Linux 无 Swift 工具链未本地编译，编译/渲染/交互以阶段末 Runner 为准；合成信封仅预览，非真机权限/真实加载/Rootless 真机兼容证据。`OwnershipResolver` 未迁移、`loaded` 恒 unknown、PARSE-009-B 挂起 |
| **0.1-D** 权限探针与真机验证 | Stage 2.4 + 2.5 | GUI 进程内访问 JBROOT、TweakInject、dylib/plist 枚举、plist 读取、dpkg 来源识别、`jbroot()` 调用、冷启动后权限保持；RootHide 真机一轮完整只读扫描并与已知环境数据对比 | 真机证据为主；Runner 仅覆盖离线 / 模拟器可验证部分；Rootless 结果独立标记，不以 RootHide 代替 | 🟡 **Runner/Simulator 切片 G1～G9 通过 / 真机 G10～G15 门禁挂起，里程碑未闭环**（2026-11-20，run `120957775572`）：模型补齐（id/operation）、D2 JBROOT、D3 ElleKit、D4 文件/plist/dpkg、D5 entitlement/sandbox、D6 jbroot() 接缝占位、D7 展示映射与统一服务已落盘；合成桩单测接入；D5/D6 接口未核实保持占位 unavailable/unknown；真机证据 D-G10～D-G15 未取得；当前最大风险项。首轮 Runner build（run `5a0ac726`，SHA `967d8152`）exit 1：PlistReadProbe 可选类型 error + 服务 catch 不可达 warning，本地已修 4 文件（协议 `run()` 改 throws、observed 改 `String?`、`try` 调用、抛错桩补 throws；另修正服务隔离用例对照桩计数）。二轮 Runner test（run `92462907`，SHA `92127cd1`）Core/Models/Adapters/AppPresentation emit 通过，测试目标编译失败：证据测试字典键兜底类型不匹配、errno POSIX 成员缺前缀（级联 Equatable 误报），本地已修 2 测试文件 + Package.swift 排除 UITests。三轮 Runner test（run `d2b6f5e1`，SHA `c657da5d`）全模块 emit、Stage2Tests 编译链接通过（二轮类型错误与 unhandled 告警未复现），448 例 1 失败：dpkg 非空状态文件用例期望 `12 bytes` 偏移，夹具实为 11 字节、探针 `data.count` 口径正确，断言改 `11 bytes`。统一验收 Runner（run `120942979030`，SHA `cb130c36`，Xcode 26.6 / Swift 6.3.3 / SDK 26.5）：非 UI Build `Build complete! (15.69s)` 0 error / 0 warning；全量 **448 例 0 failures**、S1-05 15 例 0 failure；探针专项 43 例全绿；隔离七项 passed `failed: 0`；既有回归无损伤；工具链已录档——**离线/CI 口径 L2 切片通过**。真机门禁 D-G10～G15（JBROOT 权限 / TweakInject / dylib·plist·dpkg 读取 / entitlement·sandbox / `jbroot()` 调用 / 冷启动保持）全部 pending/unknown，须 RootHide 真机 GUI 进程取证；App Build/模拟器/XCUITest 本轮摘出未执行。**0.1-D 里程碑未闭环，不签署、不进入 0.1-E**；证据 `Tests/Stage2/evidence/run-120942979030-acceptance/`。**R1-A/B（2026-11-20，授权分批）**：R1-A 已恢复 `app-build`/`ui-acceptance`(XCUITest) Job 与 `artifact` 依赖，本地 YAML 解析通过，G7/G8/G9 待 Runner 实跑判定；R1-B 上游核实：`jbroot()` 属 libroothide（`-lroothide`，modulemap `import roothide`），C 声明 `const char* jbroot(const char*)`、Obj-C `NSString*` 重载，符号默认导出，rootful/rootless 走静态桩；`SecTask*` entitlement 读取接口仅 macOS/Catalyst、不含 iOS，Runtime entitlement 保持 unavailable/unknown；D5/D6 占位未替换、未写真机调用；详见 `Spec/Stage-2/Stage-2.4-R1B-APIPermission-Feasibility-Record.md`。**R1-A 接线恢复后 Runner 实跑（run `120957775572`，SHA `4b08fe1a`，Xcode 26.6 / Swift 6.3.3 / SDK 26.5）**：G1 非 UI Build `Build complete! (13.28s)` 0 error / 0 warning；G2 全量 **448 例 0 failures**、G3 S1-05 15 例 0 failure；G4 探针 43 例全绿；G5 隔离七项 passed `failed: 0`；G7 App Build `** BUILD SUCCEEDED **` 0 error（1 条 AppIntents 元数据跳过系统噪声 warning），`FilterKit.app` 产物签名 Validate 通过，模拟器 PID 4029 存活；G8 XCUITest **8 例 0 failure（192.521s）**，Dashboard/Diagnostics/列表/详情/设置全 passed；G9 导出预览 JSON 往返 `decodable=true` / `equalIgnoringGeneratedAt=true`，SHA256 复算一致，Share Sheet 与空态禁用导出 passed——**Runner/Simulator 口径 G1～G9 通过**。真机门禁 G10～G15（JBROOT 权限 / TweakInject / dylib·plist·dpkg / entitlement·sandbox / `jbroot()` 调用 / 冷启动保持）仍全部 pending/unknown，须 RootHide 真机 GUI 进程取证；截图与信封为合成预览桩，不构成真机证据。**0.1-D 里程碑仍未闭环，不签署、不进入 0.1-E**；证据 `Tests/Stage2/evidence/run-120957775572-acceptance/`。**R2-A/B（2026-11-20，授权分批）**：D5 三类证据（signed/runtime/resourceAccess）Core 层显式分离，runtime 保持 unavailable/unknown；D6 路径一致性改为 raw/normalized/symlink/accessible 四层比较，替换原始字符串 `==`；上游 libroothide 当前 main 复核无漂移；新增 10 例单测；冻结 Models/ReportEnvelope/Adapter 七方法协议与 loaded/installed/configured 语义未改。**R2 Runner 复验（run `121082423820`，SHA `59f3eb96`，Xcode 26.6 / Swift 6.3.3 / SDK 26.5）**：G1 非 UI Build `Build complete! (26.89s)` 0 error / 0 warning，两个新 Core 文件参与编译；G2 全量 **458 例 0 failures**（基线 448 + 新增 10）；G3 S1-05 15 例 0 failure；G4 探针 53 例全绿（Status 4 / Evidence 5 / Report 6 / Probe 34 / Presentation 4）；G5 隔离七项 passed `failed: 0`；G7 `** BUILD SUCCEEDED **`，模拟器 `5AB3DACF-…` PID 6302 存活；G8 XCUITest **8 例 0 failure（238.195s）**；G9 导出预览 JSON 往返 `decodable=true` / `equalIgnoringGeneratedAt=true` / `messages=[]`，SHA256 复算一致；10 例新增用例逐一 passed——**Runner/Simulator 口径 R2 切片 G1～G9 通过**。真机门禁 G10～G15 仍全部 pending/unknown，须 RootHide 真机 GUI 进程取证；截图与信封为合成预览桩，不构成真机证据。**0.1-D 里程碑仍未闭环，不签署、不进入 0.1-E**；证据 `Tests/Stage2/evidence/run-121082423820-acceptance/`。详见 D2-D7 记录 §5.10 与 R1B 记录 §8。**R3-A（2026-11-20，授权进入 0.1-D-R3，本轮仅方案冻结）**：`Spec/Stage-2/Stage-2.4-R3-Device-Validation-Plan.md` 冻结 R3-A～E 批次、G10～G15 探针执行矩阵、R3 局部真机证据字段契约（复用冻结 Models，不扩信封）、Preflight 清单与 Runner 离线切片/真机双类门禁；R3-B～E 真机只读探针、冷启动复验与归档待 RootHide 真机 + FilterKit GUI 进程上下文分批授权；0.1-C G10 独立补证（既有搁置项，重启须另行授权）；0.1-E 仅预冻结设计不实现。**R3-A2 / R3-F 规格补全（2026-11-20，离线规格冻结）**：R3 总方案新增 R3-A2 部署包规格批次（R3-B 前）与 R3-F R3 总体验收批次（R3-E 后，Runner 切片 + 真机门禁统一复核，门禁状态由证据重算）；补检查点 A/B/C 与设备/部署形态/代码版本/样本/证据环境五冻结；部署形态口径更新为 A 普通 IPA / B 特殊权限 App / C Bootstrap 通道 / B+C 组合（优先验证，证据决定）；DEB 为正式真机测试主载体、IPA 辅助对照；`Stage-2.4-R3-A2-Deployment-Package-Spec.md` 冻结包结构、命名/架构草案口径、control 字段口径、postinst 仅 uicache 注册的安全边界、entitlement 候选清单与 CI 静态检查/元数据口径；本轮不写落盘安装脚本、不打包、不签名、不真机安装。**R4-A0（2026-11-20，0.1-D-R4 Device Build & Deployment 规格冻结 + 离线脚手架）**：`Stage-2.4-R4-Device-Build-Deployment-Plan.md` 冻结两条并行路线（产品开发推进 R4；发布验收保留真机门禁不降低）；批次 R4-A 设备构建 → R4-B 签名/entitlement → R4-C IPA → R4-D DEB → R4-E 包静态校验 → R4-F 部署文档；R4-G 真机启动冒烟门禁（8 项，启动失败如实记 failed）；0.1-E 拆为 0.1-E-A 验收引擎（可提前开发，不签发布结论）与 0.1-E-B 最终验收（等 0.1-C/0.1-D 闭环）；R4 先于 R3-B～E。本轮落地 `Config/Signing/` 草稿（entitlements/xcconfig）、`Config/DEB/` control/postinst 草稿、`scripts/` 四个校验脚本 + 两个打包脚本草稿，`bash -n` 与 plist 良构通过；未编译设备包、未签名、未产出可安装包、未连真机。**R4-A～E（2026-11-20，授权接线，待 Runner 离线复验）**：CI 新增 `device-build`/`signing-prep`/`package-ipa`/`package-deb`/`package-validation` 五个 macOS job，接入 iphoneos Release 未签名构建、entitlement 静态校验、IPA/DEB 结构打包与 SHA256/元数据归集；新增 `collect-package-metadata.sh`，三态口径 Build Passed / Package Passed / Device Install Pending；本地占位桩演练 IPA 结构 passed（二进制校验如实 failed）、DEB e1～e4 passed；本机无工具链，设备产物/平台/架构/Bundle ID/Target 实测值与 Runner 日志待调度回填；未签名、未装机、未验放行。真机 G10～G15 与 R4-G 仍全部 pending/unknown；**0.1-D 里程碑未闭环，不签署、不进入 0.1-E** |
| **0.1-E** 发布准备与完整验收 | 0.1.0 L3 | Bug 修复、界面打磨、安装包、版本信息、发布说明；L3 全量验收 | §6 全部退出项 + 安装包可正常安装启动 + 发布文档完整 | ⬜ 未进入 |

## 4. 里程碑固定流程

```
阶段开始
   ▼
冻结本阶段规格
   ▼
拆分开发批次
   ▼
批次 1 开发 ── L1 自检
   ▼
批次 2 开发 ── L1 自检
   ▼
批次 3 开发 ── L1 自检
   ▼
阶段代码冻结
   ▼
统一 L2 Runner 验收
   ├── 失败 → 定向修复 → 定向复验
   ▼
证据归档
   ▼
阶段正式验收
   ▼
进入下一里程碑
```

补充规则：

1. 每个里程碑允许包含多个独立开发批次；普通批次不要求启动 Runner。
2. 同一里程碑的相关改动尽量合并到一个 Runner 验收基线。
3. 阶段验收通过才正式关闭该里程碑；未运行 / 跳过 / 待验收一律不计通过。
4. 真机权限与注入行为不得用离线测试或 CI 结果代替。

## 5. 0.1.0 正式定义

**FilterKit 0.1.0 — RootHide Read-Only Plugin Manager**。本版不定义为完整插件管理器，必须具备：

- 正确识别 RootHide / ElleKit 环境；
- 正确定位 JBROOT 与 TweakInject；
- 枚举 dylib 与 plist，正确配对插件文件；
- 按 RootHide 规则解析 Filter；
- 识别插件来源与所有权；
- 展示插件列表、详情与诊断信息；
- 导出 JSON 诊断报告；
- 在 RootHide 真机 GUI 环境完成只读验证；
- 未确认状态明确显示，不伪造 `loaded`；
- 不修改插件文件、不修改注入规则、不执行启停操作。

## 6. L3 退出标准（0.1.0 验收项）

| 验收项 | 要求 |
|---|---|
| Stage 1 回归 | 135/135 保持通过 |
| Models | 全部通过；公共契约未被界面层改动 |
| Core | 全部通过；行为与 Stage 1 基线一致 |
| Engine | 全部通过；双路线隔离未被合并 |
| Exporter | 全部通过；JSON 结构与冻结契约一致，确定性可复现 |
| GUI | 构建成功；Dashboard / Plugins / Detail / Diagnostics 功能完整；数据全部来自 Core |
| RootHide Adapter | 真机只读验证通过 |
| Rootless Adapter | 合成样本验证通过；真机状态如实标记，不被 RootHide 结果覆盖 |
| 权限 | RootHide GUI 进程内权限探针结论明确，受限项记录原因 |
| JSON | 导出结构与内容正确；Optional 三态不丢失；数组排序确定 |
| 架构隔离 | 双路线隔离、App→Core 私有扫描/解析隔离通过 |
| 安装包 | 可正常安装、启动；版本信息完整 |
| 发布文档 | 范围、已知限制、证据标签与未决项完整 |

任一退出项未达标，不授予 0.1.0 标签。

## 7. 风险与进度口径

主要风险（沿用 Stage-2 计划 §9，不新增范围）：

| 风险 | 说明 | 现状 |
|---|---|---|
| GUI 权限 | CLI 越狱 shell 可读不代表 GUI App 可读 `.jbroot-*` 与 TweakInject；安装成功也不代表权限授予 | `[权限待验证]`，0.1-D 真机探针 |
| RootHide 路径适配 | `jbroot()` 实际调用、私有 entitlement、sandbox 放行需在 GUI 进程内验证 | `[权限待验证]`，0.1-D 探针 |
| GUI 与 Core 一致性 | 不得为快速显示另写扫描器；GUI 必须消费已迁移验收的 Core，避免 CLI/GUI 结果不一致 | 架构约束，0.1-C 验收核对 |

进度估算（概览口径，**工作日估算，非承诺排期**；各阶段可能返工）：开发节奏稳定约 4～8 周；真机权限或部署受阻可能 8～12 周以上。估算不构成交付承诺，实际以各里程碑 L2/L3 证据为准。

## 8. 证据标签与计数纪律

- 沿用证据标签：`[源码确认]` / `[RootHide 真机验证]` / `[Rootless 合成样本验证]` / `[Rootless 真机待验证]` / `[权限待验证]`；离线、CI、Simulator 与真机结论不得混标。
- XCTest 实际执行数、基线覆盖数、各模块专项数、既有回归数、静态检查数五类分列，不相加。
- `loaded` 无独立运行时证据恒 `.unknown`；`permission` 未授权前恒 `undetermined`；未知 / 冲突 / 失败状态原样保留，不推断、不美化。

## 9. 边界与未决项

- 0.1-B 报告/导出实现已闭环（CI/Simulator 口径，见 run `44224350333` 证据归档）；0.1-C GUI Foundation 代码已落盘待阶段末 Runner 验收；0.1-D 探针与真机验证仍需单独授权。
- **PARSE-009-B**：元素级下标 / 观测类型词与 Stage1 粗粒度报告口径差异继续独立挂起；独立授权前不改 Parser 与基线期望。
- **归属分类器**：`Core/OwnershipResolver/` 尚未迁移，单列批次；0.1-B 的 D2/D5 归属由已解析快照注入。
- **`pluginID` 稳定标识规则**：0.2.0 定稿；离线按优先级规则生成。
- **运行时加载取证**：`loaded` 脱离 `unknown` 待后续阶段接口。
- 暂缓功能（启停、写 plist、删 dylib、改软链、装卸载、dpkg 写入、Daemon / 自研注入 / 重签名）沿用 Stage-2 计划 §8，权限通路闭合与管理门禁定义前不进入界面与接口设计。

## 10. 与既有规格的关系

- 本计划不重复各子阶段实现细节；接口与字段口径以 `Stage-2-Implementation-Plan.md`、`Plugin-Data-Model.md`、2.2-D 实施规格为准。
- 后续若真机或 CI 实测结论与本计划冲突，以实测证据回填修订；本文件随里程碑闭环状态更新。
