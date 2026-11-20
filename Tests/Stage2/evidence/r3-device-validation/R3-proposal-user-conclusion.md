我的结论：现在仍然不建议正式进入 0.1-E。建议先完成 0.1-D-R3：RootHide 真机权限验证与 0.1-C G10 缺口补证。

这次 R2 的进展是实质性的：D5/D6 不再只是设计占位，已经有代码参与编译，并有 10 项新增测试通过。但它解决的是离线代码和模拟器验收问题，不是最后的真机权限问题。

一、为什么现在还不能进入 0.1-E？

先区分三个层次：

层次	当前状态	判断
代码实现	R2 D5/D6 已落地	通过当前 Runner 验证
CI / Simulator	G1～G9 通过	离线验收通过
RootHide 真机 GUI 进程	G10～G15 全部 pending/unknown	尚未验证

尤其是下面六项：

1. GUI 进程能否访问真实 JBROOT。
2. GUI 进程能否访问 TweakInject。
3. 能否读取真实 dylib、plist、dpkg 信息。
4. Entitlement 与 sandbox 是否真正允许这些访问。
5. RootHide jbroot() 能否在 FilterKit 进程内调用，且路径一致。
6. FilterKit 冷启动后，访问权限是否保持。

这些都是 0.1-D 的核心验收目标，不能由 Simulator 的合成预览桩代替。

另外，0.1-C G10 仍然是独立的未完成门禁。不能因为 0.1-D 的 G8/G9 通过，就将它视为已经补齐。

所以当前状态应保持：

* 0.1-D-R2：代码与 Runner/Simulator 验收通过。
* 0.1-D：未闭环。
* 0.1-C：G10 缺口仍未解决。
* 0.1-E：不进入、不签署。

⸻

二、建议的下一阶段：0.1-D-R3

建议命名：

0.1-D-R3 — RootHide Device Validation & Release Readiness

这一阶段不再以增加大量离线测试为主要目标，而是将已经实现的探针放到真实 RootHide 环境中，验证 FilterKit GUI 进程的访问能力。

建议拆成五批。

批次	开发内容	主要交付
R3-A	真机测试准备	真机环境清单、探针执行矩阵
R3-B	JBROOT / TweakInject 访问验证	真实目录访问证据
R3-C	插件文件与 dpkg 读取验证	dylib、plist、dpkg 只读证据
R3-D	Entitlement / jbroot() 验证	D5、D6 真实运行证据
R3-E	冷启动复验、Diagnostics 与归档	真机报告、门禁判定、证据包

注意：R3-B～R3-D 的实现应优先复用 R2 已完成的代码，不要再造一套扫描器。

R3-A：真机测试准备

首先冻结测试对象和预期结果。

建议测试对象：

FilterKit GUI Process
    |
    +-- JBROOT
    |
    +-- TweakInject
    |     |
    |     +-- Directory metadata
    |     +-- Directory enumeration
    |
    +-- Plugin files
    |     |
    |     +-- dylib metadata
    |     +-- dylib read
    |     +-- plist read
    |     +-- plist parse
    |
    +-- dpkg metadata
    |
    +-- Entitlement inspection
    |
    +-- RootHide jbroot()

每个操作必须独立记录结果。

例如：

* stat 成功，不代表 opendir 成功。
* opendir 成功，不代表文件内容读取成功。
* plist 文件读取成功，不代表 plist 解析成功。
* 签名中存在 entitlement，不代表运行时资源访问一定成功。

建议统一使用以下结果：

enum DeviceProbeStatus: String, Codable {
    case passed
    case failed
    case denied
    case unavailable
    case unknown
}

这只是 R3 专用模型示意，不建议直接扩展已经冻结的公共 Models。

⸻

三、关键代码设计

下面是建议的代码结构和接口设计。

说明：目前没有实际读取本轮 DevDocs ZIP 和仓库源码，因此以下是设计示例，不是对现有仓库 API 的描述，也不能直接认定为可复制编译的代码。 实际落地前必须先对照 10d74a4、59f3eb96 及当前仓库真实文件。

1. 统一真机探针证据模型

建议新增：

Sources/PermissionProbe/Device/
    DeviceProbeStatus.swift
    DeviceProbeEvidence.swift
    DeviceProbeReport.swift
    DeviceProbeContext.swift

示意：

struct DeviceProbeEvidence: Codable {
    let probeID: String
    let profile: String
    let operation: String
    let targetCategory: String
    let status: DeviceProbeStatus
    let errorDomain: String?
    let errorCode: Int?
    let executedAt: Date
    let processIdentifier: Int32
}

这里有几个重要约束：

* 不默认记录完整敏感路径。
* 不将错误统一归为 permission denied。
* 必须区分资源不存在、权限拒绝、路径解析失败和接口不可用。
* 不从一个成功操作推断其他操作成功。
* 不根据文件存在推断插件已加载。

2. JBROOT / TweakInject 探测

建议建立独立的只读文件系统探针：

protocol DeviceFileSystemProbing {
    func inspectMetadata(
        at url: URL
    ) -> DeviceProbeEvidence
    func enumerateDirectory(
        at url: URL
    ) -> DeviceProbeEvidence
    func readFile(
        at url: URL
    ) -> DeviceProbeEvidence
}

底层应使用适当的 POSIX 文件接口，例如：

* lstat
* stat
* opendir
* readdir
* open
* read
* close

不能只用 FileManager.fileExists() 作为权限探测依据。

核心原则是：每个文件操作都生成独立证据，且不修改目标文件。

3. dylib / plist / dpkg 探测

这里尤其要避免将文件读取与解析混为一谈。

建议：

struct PluginReadEvidence: Codable {
    let pluginID: String
    let dylibMetadataStatus: DeviceProbeStatus
    let dylibReadStatus: DeviceProbeStatus
    let plistReadStatus: DeviceProbeStatus
    let plistParseStatus: DeviceProbeStatus
    let dpkgMetadataStatus: DeviceProbeStatus
}

具体实现要求：

* dylib 只读取，不执行。
* plist 读取复用现有 Reader。
* plist 解析复用现有 RootHide Parser。
* dpkg 只读，不调用安装、卸载或修改命令。
* 不重新实现插件枚举和配对逻辑。

特别注意：能够读取 dylib 不代表能够加载 dylib，更不代表 ElleKit 已经加载该插件。

loaded 继续保持 unknown，除非将来有独立、可靠的运行时证据。

4. D5 Entitlement 探测

R2 已经将三类证据分离：

1. Signed Entitlements
2. Runtime Entitlements
3. Actual Resource Access

R3 应该做的是验证这三类证据在真机上的实际表现，而不是将它们重新合并。

建议输出：

struct EntitlementProbeReport: Codable {
    let signedEntitlements: [EntitlementEvidence]
    let runtimeEntitlements: [EntitlementEvidence]
    let actualResourceAccess: [DeviceProbeEvidence]
}

如果运行时 entitlement 检查机制在当前 iOS 环境中不可用：

runtimeEntitlements = unknown

不能通过签名文件中的 entitlement 推断运行时状态。

另外，资源访问成功只能证明对应资源、对应操作在当前进程上下文中成功，不能证明所有 sandbox 限制都已解除。

5. D6 RootHide jbroot() 验证

R2 已经增加了 raw、normalized、symlink、accessible 四层路径比较。

R3 需要在真实 RootHide 进程中完成验证。

建议报告：

struct JBRootRuntimeEvidence: Codable {
    let rawPath: String?
    let normalizedPath: String?
    let resolvedSymlinkPath: String?
    let accessible: DeviceProbeStatus
    let pathConsistency: DeviceProbeStatus
}

这里需要特别注意：

standardizedFileURL 只能做词法路径规范化，不代表文件系统中的真实路径一致。

实际验证需要结合：

* RootHide jbroot() 的真实 API 返回值；
* 软链接解析；
* 文件系统访问；
* 目标路径身份比较。

不能自行声明一个 C 函数，然后假设它就是当前设备的 jbroot()。

必须以 RootHide ElleKit 目标版本的真实头文件、符号和链接方式为准。

⸻

四、Diagnostics 页面需要做什么？

R3 不应该重新开发 GUI。

只需要将真实真机探针报告接入现有 Diagnostics 展示层。

建议页面增加一个只读分组：

RootHide Device Validation
JBROOT
  Metadata           PASSED
  Directory Access   PASSED
TweakInject
  Metadata           PASSED
  Enumeration        PASSED
Plugin Files
  dylib Metadata     PASSED
  dylib Read         PASSED
  plist Read         PASSED
  plist Parse        PASSED
Dpkg
  Metadata           PASSED
  Read               PASSED
Entitlements
  Signed             PASSED
  Runtime            UNKNOWN
  Resource Access    PASSED
RootHide API
  jbroot()           PASSED
  Path Consistency   PASSED
Cold Launch
  Revalidation       PENDING

以上是展示示例，不代表当前真实状态。

GUI 只能展示统一报告，不允许自行扫描文件、调用 Parser 或自行推断权限。

⸻

五、R3 最终验收门禁

建议将 R3 的验收分为两类。

A. Runner / Simulator

主要验证：

* 现有 458 项测试不回退。
* 新增真机证据模型测试。
* 失败状态和 unknown 状态正确传播。
* Diagnostics 映射正确。
* JSON 导出正确。
* 架构隔离检查通过。
* App Build 成功。
* Simulator GUI 回归通过。

这些可以由 Runner 完成。

B. RootHide 真机

门禁	验收目标
G10	FilterKit GUI 进程访问 JBROOT
G11	FilterKit GUI 进程访问 TweakInject
G12	dylib / plist / dpkg 只读探测
G13	Entitlement / Sandbox 证据
G14	jbroot() 调用与路径一致性
G15	FilterKit 冷启动后的权限保持

必须注意：

* 每个门禁需要独立证据。
* 必须确认测试发生在 FilterKit GUI 进程，而不是越狱 shell。
* CI 和 Simulator 证据不能满足真机门禁。
* 未完成的门禁必须保持 pending/unknown。
* 不能因为一项成功，就将整组门禁标为通过。

⸻

六、0.1-E 应该开发什么？

虽然我不建议现在正式进入 0.1-E，但可以提前冻结它的技术设计。

0.1-E 的职责应该是：

Release Acceptance & Final Packaging

它不是新增插件管理功能，而是一个发布前的证据验证和归档阶段。

建议模块：

Sources/ReleaseAcceptance/
    Models/
        AcceptanceGate.swift
        AcceptanceEvidence.swift
        AcceptanceReport.swift
    Services/
        AcceptanceEvaluator.swift
        EvidenceValidator.swift
        ReleaseReadinessService.swift
    Export/
        AcceptanceReportExporter.swift

1. AcceptanceGate

enum AcceptanceStatus: String, Codable {
    case passed
    case failed
    case pending
    case invalidEvidence
}
struct AcceptanceGate: Codable {
    let gateID: String
    let title: String
    let required: Bool
    let status: AcceptanceStatus
    let evidenceIDs: [String]
}

required 用来区分正式发布阻断项和非阻断项。

但不能因为 required == false 就忽略无效证据或掩盖失败。

2. AcceptanceEvidence

struct AcceptanceEvidence: Codable {
    let evidenceID: String
    let gateID: String
    let runID: String?
    let commitSHA: String
    let environment: String
    let artifactPath: String
    let artifactSHA256: String
    let observedStatus: AcceptanceStatus
    let executedAt: Date
}

证据必须能追溯到：

* 具体门禁；
* Runner；
* Git Commit；
* 执行环境；
* 证据文件；
* SHA256；
* 执行时间。

真机门禁还应有设备与进程上下文证据。

3. EvidenceValidator

这是整个 0.1-E 最重要的部分。

不能只判断：

gate.status == .passed

而要验证：

1. 证据文件是否存在。
2. SHA256 是否复算一致。
3. Commit SHA 是否与被验收代码一致。
4. Runner ID 是否一致。
5. 证据执行环境是否符合门禁要求。
6. 真机门禁是否确实来自 RootHide 真机 GUI 进程。
7. 是否存在重复或过期证据。
8. 是否有必需门禁缺少证据。

示意：

protocol EvidenceValidating {
    func validate(
        evidence: AcceptanceEvidence,
        expectedCommitSHA: String,
        requiredEnvironment: String
    ) throws -> EvidenceValidationResult
}

不要让 AcceptanceEvaluator 自己承担所有证据校验工作。

4. ReleaseReadinessService

建议最终统一返回：

struct ReleaseReadinessReport: Codable {
    let commitSHA: String
    let totalGates: Int
    let passedGates: Int
    let failedGates: Int
    let pendingGates: Int
    let invalidEvidenceGates: Int
    let canRelease: Bool
    let blockers: [String]
}

核心判定应该是：

canRelease =
    allRequiredGatesPassed &&
    allRequiredEvidenceValid &&
    allEvidenceMatchesReleaseCommit &&
    noRequiredGatePending &&
    noRequiredGateFailed

这只是逻辑示意。正式实现还要处理必需门禁的证据数量、环境约束、时间有效性、证据重复、非必需门禁以及归档完整性。

最重要的是：不能让一个手动写入的 status = passed 就直接决定发布通过。

⸻

七、建议的实际开发顺序

我建议这样安排：

顺序	阶段	目标
1	0.1-D-R3-A	冻结真机验证方案
2	0.1-D-R3-B～D	RootHide 真机探针验证
3	0.1-D-R3-E	冷启动复验和归档
4	0.1-C G10 补证	关闭独立 GUI 真机门禁
5	0.1-D Final Acceptance	正式签署 0.1-D
6	0.1-E Specification	冻结发布验收规格
7	0.1-E Implementation	开发验收引擎
8	0.1-E Final	发布构建、最终验收与归档

其中，0.1-C G10 如果可以与 R3 共用真机测试环境，可以合并安排测试，但必须保留独立门禁和独立证据，不能合并判定。

⸻

八、我的最终建议

当前最合适的决策是：

不进入 0.1-E，先完成 0.1-D-R3。

理由很简单：现在的主要问题已经不是代码能否编译、测试能否通过，而是 FilterKit 在真实 RootHide GUI 进程中到底有没有所需的文件访问能力。

这正是产品能否成立的关键。

我建议下一步只授权：

* R3-A 真机验证准备；
* R3-B～D 真机只读探针验证；
* R3-E 冷启动复验与证据归档；
* 0.1-C G10 独立补证。

暂时不授权：

* 0.1-E 正式实现；
* 插件启停；
* plist 写入；
* dylib 删除或移动；
* dpkg 写操作；
* 自动修复；
* 发布签署。

可以提前冻结 0.1-E 的规格，但不应在真机门禁全部通过之前把它作为正式开发阶段。

当前你可以先让开发工作进入 R3-A：只做真机测试矩阵、证据字段、执行前检查和验收标准，不触碰设备、不修改插件、不执行写操作。