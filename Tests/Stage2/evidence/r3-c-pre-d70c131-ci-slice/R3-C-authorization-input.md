我的判断是：先选路线 A，暂时不做路线 B。

这次审计找到了一个比 D-R2-03/04 更直接影响真机数据的问题：诊断引擎已经运行，但导出链路没有消费引擎结果。现在应该先打通这条链路，让真机扫描结果能够完整进入 JSON，而不是立即重构整个 ReportService。

你提到需要拍板两个点，我建议如下。

决策一：采用哪条改动路线？

选择 A：最小闭环。

目标链路：

Diagnostics 页面
       │
       ▼
runReadOnlyDiagnostics()
       │
       ▼
ReadOnlyDiagnosticsEngine.scan()
       │
       ▼
FKDiagnosticReport
       │
       ▼
DiagnosticsReportStore
       │
       ├──────────────┐
       ▼              ▼
Diagnostics 页面    JSON Exporter
                      │
                      ▼
                ReportEnvelope
                      │
                      ▼
                 diagnostics
                      │
                      ▼
                   JSON

这里有一个实现细节需要明确：

不要直接把松散的 FKDiagnosticReport 原样塞进 JSON，也不要为了导出而修改现有公共 Models。

建议新增独立的 Codable 导出模型：

struct DiagnosticsExportSection: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let evidenceScope: String
    let sections: [DiagnosticsExportItem]
}
struct DiagnosticsExportItem: Codable {
    let id: String
    let category: String
    let title: String
    let status: String
    let detail: String?
    let evidence: String?
}

以上是结构示意，最终字段应根据 FKDiagnosticReport 的真实定义映射，不能凭空丢失字段。

导出时采用兼容性方案：

{
  "existingEnvelopeFields": "...",
  "diagnostics": {
    "schemaVersion": 1,
    "generatedAt": "...",
    "evidenceScope": "read-only",
    "sections": []
  }
}

现有信封字段保持原样，新增 diagnostics 扩展段。

特别要求：

* 没有扫描记录时导出空数组，不得生成 Preview/Broken/Orphan 替代数据。
* 扫描失败与扫描成功但结果为空必须区分。
* 导出旧扫描结果时，要能识别其生成时间。
* 新增字段不能覆盖旧字段。
* loaded 继续保持 unknown，没有运行时证据绝不推断已加载。
* 不改变现有 Dashboard、Plugins 的数据来源。

决策二：扫描结果如何保存？

我建议使用 DiagnosticsReportStore，作为 App 运行期间共享的最近一次扫描快照。

不要让 DiagnosticsViewModel 和 SettingsViewModel 各自保存一份结果，否则很容易出现：

Diagnostics 页面显示本次扫描结果
Settings 导出上一次扫描结果

建议：

@MainActor
final class DiagnosticsReportStore: ObservableObject {
    @Published private(set) var latestReport:
        DiagnosticsExportSection?
    @Published private(set) var scanState:
        ScanState = .neverRun
    func update(
        report: DiagnosticsExportSection
    ) {
        latestReport = report
        scanState = .completed
    }
    func markFailed() {
        scanState = .failed
    }
    func clear() {
        latestReport = nil
        scanState = .neverRun
    }
}

ScanState 建议区分：

enum ScanState {
    case neverRun
    case running
    case completed
    case failed
}

然后由 App 根容器创建唯一实例，同时注入 Diagnostics 和 Settings。

这样扫描与导出就共享同一个数据源。

第一阶段只要求内存保存，不需要新增数据库、文件缓存或持久化机制。避免把只读诊断变成额外的文件写入系统。

⸻

三、我建议的实际开发顺序

阶段	工作	验收标准
A1	新增 Codable 导出模型	所有引擎诊断字段可映射
A2	新增 DiagnosticsReportStore	两个页面共享同一快照
A3	Diagnostics 扫描后写入 Store	真正的 scan 结果进入 Store
A4	Settings 导出接入 Store	JSON 包含实际 diagnostics
A5	空扫描、失败、重复扫描测试	不出现合成数据或旧数据冒充新数据
A6	真机 Runner 验收	新构建安装后扫描并导出真实数据

A1～A5 应当独立提交，便于定位问题和回退。

需要增加的核心测试

1. 扫描成功后，导出包含本次扫描全部诊断项。
2. 扫描结果为空时，导出空 sections。
3. 从未扫描时，不得导出合成插件。
4. 扫描失败时，不得把上一次成功结果冒充本次结果。
5. 连续扫描两次，第二次结果正确覆盖第一次。
6. JSON 编码和解码后，字段及状态保持一致。
7. 旧 ReportEnvelope 字段保持兼容。
8. loaded=unknown 不被转换成其他状态。

四、这轮暂时不做什么

明确排除：

* 路线 B 的 ReportService 全面接线。
* Dashboard 和 Plugins 的真实数据化。
* 真实插件归属推断重构。
* D-R2-06 真机诊断验收。
* #331 截图计数与去重。
* 任何插件启用、禁用、注入或文件修改。
* 签名模块重写。

路线 A 完成后，我们就能回答一个最重要的问题：

当前 RootHide 真机上，诊断引擎实际发现了什么，哪些文件能访问，哪些规则命中，哪些状态仍然无法确认？

这才是后续路线 B 的可靠输入。

⸻

五、正式授权建议

我建议本轮授权名称：

R3-C：Live Diagnostics Export Bridge

授权内容：

1. 审计现有 FKDiagnosticReport 的完整字段和嵌套类型。
2. 新增确定性 Codable 导出模型。
3. 新增共享 DiagnosticsReportStore。
4. 将 Diagnostics 扫描结果接入 Store。
5. 将 Settings 导出接入 Store。
6. 增加离线测试和 JSON 兼容性测试。
7. 保留只读边界及现有签名、DEB 打包路径。

不授权路线 B，不授权真机写操作，不授权 GitHub 推送。

我的建议是：先把这个桥打通，拿到第一份真正来自 RootHide 真机的完整诊断 JSON，再决定是否启动 D-R2-03/04 的引擎基础设施改造。这样能避免在还没证明导出链路有效之前，就投入更大规模的引擎重构。

如果你认可这两个决定，就按 A 路线和共享 Store 开始；第一步先核对模型字段与导出器接口，再动代码。