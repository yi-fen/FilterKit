可以。我的建议是：R3-A～R3-E 连续推进，最后统一进行 R3 总体验收；但每批必须完成自己的执行记录和证据归档，不能等到最后才补做前置检查。

另外，你说的 RootHide 真机环境冻结，理解是正确的：应该以安装了 RootHide 越狱环境的实体 iPhone 作为最终测试设备，并在这台设备上安装 FilterKit，验证 FilterKit GUI 进程的真实访问能力。

下面具体说明。

一、R3-B～R3-E 可以最后统一验收吗？

可以，但需要区分开发检查点和最终验收。

建议采用以下流程：

批次	工作内容	执行时机	验收方式
R3-A	测试方案冻结、Preflight 规格	当前	规格审查
R3-B	JBROOT / TweakInject 访问	真机就绪后	记录原始证据
R3-C	dylib / plist / dpkg 读取	R3-B 后	记录原始证据
R3-D	Entitlement / jbroot()	R3-C 后	记录原始证据
R3-E	冷启动复验、证据归档	最后	完整性检查
R3-F	R3 总体验收	全部完成后	Runner + 真机统一验收

我建议增加一个 R3-F，专门负责最终验收。

这样可以避免 R3-E 一边执行冷启动，一边又承担整个 R3 的验收职责。

需要保留三个内部检查点

虽然不需要每批单独进行正式 Runner 验收，但仍然需要：

检查点 A：R3-B 完成后

确认：

* JBROOT 路径正确；
* TweakInject 可达；
* 操作确实发生在 FilterKit GUI 进程；
* 没有将 shell 结果当成 GUI 结果。

检查点 B：R3-C / R3-D 完成后

确认：

* 文件读取和解析状态分离；
* Entitlement 三类证据分离；
* jbroot() 使用真实 API；
* 四层路径比较结果可追溯；
* 没有新增私有扫描器。

检查点 C：R3-E 完成后

确认：

* 冷启动前后使用相同设备、部署形态和代码版本；
* 复测结果有独立证据；
* 所有证据 SHA256 一致；
* G10～G15 的门禁状态可以由证据重新计算。

最后再执行 R3-F。

不建议跳过内部检查点，只把所有代码和证据堆到最后。

⸻

二、RootHide 真机环境应该怎么冻结？

是的，应该使用一台真实安装 RootHide 的越狱 iPhone。

这里的关键不是单纯安装 RootHide，而是冻结整个测试环境。

建议将测试环境分为五部分。

1. 设备环境

记录：

项目	要求
设备型号	真实 iPhone
iOS 版本	精确记录
CPU 架构	精确记录
越狱类型	RootHide
RootHide 版本	精确记录
ElleKit 版本	精确记录
Bootstrap 版本	精确记录
JBROOT	实际路径及校验结果

设备必须是实际 RootHide 环境，不能用 Rootless 或模拟器替代。

2. FilterKit 部署形态

这是 R3-B 开始前最重要的决策。

你之前的部署研究中有三个方向：

方案	部署形态	特点
A	普通 IPA	默认沙盒，不能假设可以访问 JBROOT
B	特殊权限 App	通过 entitlement 和 sandbox 放行实现访问
C	Bootstrap 安装通道	通过越狱环境安装和注册 App

需要特别强调：

B 和 C 并不是完全互斥的选项。

C 是安装通道，B 是权限形态。可以存在通过 C 安装、同时采用 B 权限形态的组合。

因此我建议将部署方案重新定义为：

* A：普通 IPA。
* B：特殊权限 App。
* C：Bootstrap 安装通道。
* B+C：Bootstrap 安装特殊权限 App。

我的建议是优先验证 B+C，但不能直接将它认定为最终方案。

原因是：

* 特殊 entitlement 是否真正生效尚未证明；
* Bootstrap 安装成功不等于权限放行；
* uicache 注册成功不等于 App 可以读取 JBROOT；
* App 能启动不等于 jbroot() 可调用。

最终必须由真机证据决定。

3. 代码版本冻结

真机测试期间，必须固定：

FilterKit Commit SHA
FilterKit App Build Number
FilterKit Bundle ID
RootHide Version
ElleKit Version
iOS Version
Deployment Profile

建议 R3-B～R3-E 使用同一份 FilterKit 代码基线。

如果中途修改了探针实现、entitlement 或部署配置，应记录新的 SHA，并重新判断受影响的门禁是否需要复测。

4. 测试样本冻结

不要在测试过程中随意安装、卸载或修改插件。

建议记录：

* TweakInject 目录基线；
* dylib 文件清单；
* plist 文件清单；
* dpkg 数据库读取基线；
* 测试前后文件状态。

所有探测均为只读。

5. 证据环境冻结

每条真机证据至少需要：

deviceID
deviceModel
iOSVersion
RootHideVersion
ElleKitVersion
filterKitCommitSHA
filterKitBuildNumber
deploymentProfile
probeID
gateID
processContext
processIdentifier
operation
status
errorDomain
errorCode
executedAt
artifactSHA256

其中：

processContext = FilterKit.GUI

必须由真实 GUI 进程产生，不能由 SSH、越狱终端或 Runner 代替。

⸻

三、实际测试时，手机上需要安装什么？

最终测试环境至少需要：

1. 已经正常工作的 RootHide 越狱环境。
2. 与目标版本匹配的 ElleKit。
3. FilterKit 测试版 App。
4. 供只读探测的真实插件样本。
5. 必要的设备日志和证据导出通道。

FilterKit 必须作为真正的 iOS GUI App 启动。

不是通过 SSH 执行 CLI 探针，然后把结果显示在 App 中。

因为我们需要证明的是：

FilterKit 自身进程拥有真实的访问能力。

建议测试顺序：

RootHide 越狱环境正常启动
        ↓
冻结设备和系统版本
        ↓
确认 ElleKit 版本
        ↓
冻结 FilterKit 部署形态
        ↓
安装 FilterKit
        ↓
从 iOS 主屏幕启动 FilterKit
        ↓
执行 GUI 进程 PermissionProbe
        ↓
验证 JBROOT / TweakInject
        ↓
验证插件文件 / dpkg
        ↓
验证 Entitlement / jbroot()
        ↓
退出 FilterKit
        ↓
重新启动 FilterKit
        ↓
复测权限
        ↓
导出真机证据

注意：冷启动复测的是 FilterKit 本身，而不是目标插件所在的 App。

⸻

四、R3 最终验收应该增加哪些门禁？

建议最终形成：

门禁	验收目标	证据来源
G1	非 UI Build	Runner
G2	全量 XCTest	Runner
G3	S1-05 回归	Runner
G4	PermissionProbe 测试	Runner
G5	架构隔离	Runner
G6	App Build	Runner
G7	Simulator 启动	Simulator
G8	GUI / XCUITest	Simulator
G9	JSON 导出	Simulator
G10	JBROOT GUI 访问	RootHide 真机
G11	TweakInject GUI 访问	RootHide 真机
G12	dylib / plist / dpkg 只读读取	RootHide 真机
G13	Entitlement / Sandbox	RootHide 真机
G14	jbroot() 和路径一致性	RootHide 真机
G15	冷启动权限保持	RootHide 真机

另有一项：

0.1-C G10 独立补证。

它必须独立记录，不能把 R3 的某个 G 门禁直接映射成它已经通过。

⸻

五、R3 完成后才进入 0.1-E

建议最终顺序：

0.1-D-R3
    R3-A 方案冻结       已完成
    R3-B JBROOT         待真机
    R3-C 文件读取       待真机
    R3-D Entitlement    待真机
    R3-E 冷启动复验     待真机
    R3-F 总体验收       待完成
        ↓
0.1-C G10 独立补证
        ↓
0.1-D Final Acceptance
        ↓
0.1-E Specification Freeze
        ↓
0.1-E Implementation
        ↓
0.1-E Release Acceptance

0.1-E 的核心是发布验收、证据校验、发布构建和归档，不应该反过来承担 R3 真机权限验证。

⸻

六、我的最终建议

你的 R3-A 已经完成，下一步不应该继续在当前 Linux 云主机上开发更多真机探针。

应该先准备一台 RootHide 越狱 iPhone，并在设备上完成部署形态验证。

我建议：

* 真机：一台实际安装 RootHide 的 iPhone。
* App：FilterKit GUI 测试版。
* 部署：优先验证 B+C 组合，但最终由实测决定。
* 验收：R3-B～E 分批留证，R3-F 统一验收。
* 写操作：整个 R3 仍然保持只读。

目前只建议授权 R3-B 开始前的部署形态评估和 Preflight 执行，不建议直接授权全部真机操作。

等部署形态确认、Preflight 十项全部通过，再授权 R3-B～R3-E。这样可以避免 App 装上手机却没有实际访问权限，导致后续测试全部失去意义。