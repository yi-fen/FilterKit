// swift-tools-version:5.7
//
// Package.swift — Stage 2.1 离线草稿（未在 Apple 工具链验证）。
//
// 用途：为 macOS runner 提供一个不依赖 Xcode 工程文件的编译入口，先编译
// Models / Adapters / Core 非界面层并跑 Models Codable 往返测试；UI App target
// 待 SwiftUI/UIKit 选型（子规格 B4）与 Xcode 工程补齐后再接入。
//
// 注意：tools-version、Deployment Target、Theos/Swift 工具链配置均为待确认项
// （Stage-2.1 子规格 §14 B1/B2/B5）；本文件不得视为已可构建。

import PackageDescription

let package = Package(
    name: "FilterKit",
    // SPM 仅作为 macOS runner 上的非界面层离线编译/测试入口；Core 插件功能
    // Store 使用 Observation 框架（@Observable，macOS 14 / iOS 17 起可用），
    // 故 SPM 平台下限声明 macOS 14。Xcode App target 的 iOS 17.0 部署目标
    // 由 project.yml 独立控制，不受本声明影响。
    platforms: [.macOS(.v14)],
    products: [
        // 供 Xcode App target 链接的本地库产品；非界面层编译路径不变。
        .library(name: "Models", targets: ["Models"]),
        .library(name: "Adapters", targets: ["Adapters"]),
        .library(name: "Core", targets: ["Core"]),
        // GUI 纯 Foundation 映射层（Stage 2.3）：不依赖 SwiftUI / Core 具体实现。
        .library(name: "AppPresentation", targets: ["AppPresentation"]),
        // C-F5 P2：G9 导出 JSON 往返解析校验工具（仅解码 Models，比对合成基线）。
        .executable(name: "ReportRoundtripValidator", targets: ["ReportRoundtripValidator"])
    ],
    targets: [
        // 公共模型：无路线依赖
        .target(
            name: "Models",
            path: "Models"
        ),
        // GUI 纯 Foundation 映射层：只依赖 Models；不含 SwiftUI / UIKit，
        // 不引用 Core 具体扫描器、解析器或归属实现。
        .target(
            name: "AppPresentation",
            dependencies: ["Models"],
            path: "App/Presentation"
        ),
        // 双路线 Adapter：依赖 Models；RootHide / Rootless 独立编译、互不引用
        .target(
            name: "Adapters",
            dependencies: ["Models"],
            path: "Adapters",
            sources: [
                "ElleKitAdapter.swift",
                "RootHide/RootHideAdapter.swift",
                "Rootless/RootlessAdapter.swift"
            ]
        ),
        // 共享核心：依赖 Models 与 Adapters 协议
        .target(
            name: "Core",
            dependencies: ["Models", "Adapters"],
            path: "Core",
            exclude: [
                "README.md",
                "Environment/.gitkeep",
                "OwnershipResolver/.gitkeep",
                "PathResolver/.gitkeep",
                "PlistParser/.gitkeep",
                "PluginPairing/.gitkeep",
                "PluginScanner/.gitkeep",
                "ReportExporter/.gitkeep"
            ],
            sources: [
                "CoreServices.swift",
                "Diagnostics/ReadOnlyDiagnosticsEngine.swift",
                "Diagnostics/ReadOnlyFileHasher.swift",
                "Diagnostics/AssociationSnapshotStore.swift",
                "Diagnostics/Infrastructure/DiagnosticFileSystem.swift",
                "Diagnostics/Infrastructure/LocalDiagnosticFileSystem.swift",
                "Diagnostics/Infrastructure/DiagnosticFileSystemError.swift",
                "Diagnostics/Evidence/DiagnosticEvidenceLevel.swift",
                "Diagnostics/Evidence/DiagnosticEvidence.swift",
                "Diagnostics/Evidence/DiagnosticEvidenceValidator.swift",
                "Diagnostics/Export/DiagnosticsExportModels.swift",
                "Diagnostics/Export/DiagnosticsReportMapper.swift",
                "PermissionProbe/Protocols/PermissionProbing.swift",
                "PermissionProbe/Protocols/PermissionProbeServiceProtocol.swift",
                "PermissionProbe/FileAccess/FileAccessChecking.swift",
                "PermissionProbe/FileAccess/FoundationFileAccessChecker.swift",
                "PermissionProbe/FileAccess/ProbeStatusClassifier.swift",
                "PermissionProbe/Shared/ProbeTimestamp.swift",
                "PermissionProbe/Entitlement/EntitlementInspecting.swift",
                "PermissionProbe/Entitlement/UnavailableEntitlementInspector.swift",
                "PermissionProbe/Entitlement/EntitlementEvidenceSource.swift",
                "PermissionProbe/JBRootAPI/JBRootResolving.swift",
                "PermissionProbe/JBRootAPI/UnavailableJBRootResolver.swift",
                "PermissionProbe/JBRootAPI/JBRootPathComparison.swift",
                "PermissionProbe/Probes/JBRootProbe.swift",
                "PermissionProbe/Probes/ElleKitDirectoryProbe.swift",
                "PermissionProbe/Probes/PluginFileProbe.swift",
                "PermissionProbe/Probes/PlistReadProbe.swift",
                "PermissionProbe/Probes/DpkgDatabaseProbe.swift",
                "PermissionProbe/Probes/EntitlementProbe.swift",
                "PermissionProbe/Probes/SandboxAccessProbe.swift",
                "PermissionProbe/Probes/JBRootAPIProbe.swift",
                "PermissionProbe/Services/PermissionProbeReportBuilder.swift",
                "PermissionProbe/Services/PermissionProbeService.swift",
                "Environment/EnvironmentSnapshot.swift",
                "Environment/VersionParser.swift",
                "Environment/EnvironmentDetector.swift",
                "PathResolver/JBRoot/JBRootCandidateSnapshot.swift",
                "PathResolver/JBRoot/JBRootCandidateCollector.swift",
                "PathResolver/JBRoot/JBRootNameValidator.swift",
                "PathResolver/JBRoot/JBRootStatusClassifier.swift",
                "PathResolver/JBRoot/JBRootValidator.swift",
                "PathResolver/JBRoot/JBRootDecisionResolver.swift",
                "PathResolver/JBRoot/JBRootResolver.swift",
                "PathResolver/ElleKit/ElleKitDirectorySnapshot.swift",
                "PathResolver/ElleKit/ElleKitPathDeriver.swift",
                "PathResolver/ElleKit/ElleKitDirectoryValidator.swift",
                "PathResolver/ElleKit/ElleKitSymlinkInspector.swift",
                "PathResolver/ElleKit/ElleKitDirectoryResolution.swift",
                "PathResolver/ElleKit/ElleKitDirectoryResolver.swift",
                "PathResolver/Pipeline/EnvironmentRouteMapper.swift",
                "PathResolver/Pipeline/JBRootToDirectoryBridge.swift",
                "PathResolver/Pipeline/ElleKitDirectoryPipeline.swift",
                "PluginScanner/Enumeration/EnumerationStatus.swift",
                "PluginScanner/Enumeration/PluginKindCounts.swift",
                "PluginScanner/Enumeration/PluginInventoryFixtureSignal.swift",
                "PluginScanner/Enumeration/PluginEntryClassifier.swift",
                "PluginScanner/Enumeration/PluginFileEvidenceBuilder.swift",
                "PluginScanner/Enumeration/PluginInventorySnapshot.swift",
                "PluginScanner/Enumeration/PluginInventoryBuilder.swift",
                "PluginScanner/Enumeration/PluginDirectoryEnumerator.swift",
                "PluginPairing/PairingCategory.swift",
                "PluginPairing/PairingStatus.swift",
                "PluginPairing/PluginPairingCounts.swift",
                "PluginPairing/PairingEvidenceBasis.swift",
                "PluginPairing/PluginPairingRecord.swift",
                "PluginPairing/PluginPairingSnapshot.swift",
                "PluginPairing/Key/PluginPairingKeyBuilder.swift",
                "PluginPairing/Index/PluginPairingIndex.swift",
                "PluginPairing/Index/PluginPairingIndexBuilder.swift",
                "PluginPairing/Engine/PluginPairingClassifier.swift",
                "PluginPairing/Engine/PluginPairingEngine.swift",
                "PluginPairing/Engine/PluginPairingSnapshotBuilder.swift",
                "PluginPairing/Integration/PluginPairingInput.swift",
                "PluginPairing/Integration/PluginPairingInputAdapter.swift",
                "PluginPairing/Integration/PluginPairingIntegrationResult.swift",
                "PluginPairing/Integration/PluginPairingIntegrationValidator.swift",
                "PluginPairing/Integration/PluginPairingPipeline.swift",
                "PlistParser/Reader/PlistReadStatus.swift",
                "PlistParser/Reader/PlistReadResult.swift",
                "PlistParser/Reader/PlistDataReader.swift",
                "PlistParser/Decoder/PlistDecodeStatus.swift",
                "PlistParser/Decoder/PlistDecodedObject.swift",
                "PlistParser/Decoder/PlistDecodeResult.swift",
                "PlistParser/Decoder/PlistDecoder.swift",
                "PlistParser/Decoder/PlistValueKind.swift",
                "PlistParser/Result/FilterParseStatus.swift",
                "PlistParser/Result/SkippedField.swift",
                "PlistParser/Result/FilterParseResult.swift",
                "PlistParser/Result/FilterParseCounts.swift",
                "PlistParser/Result/FilterParseSnapshot.swift",
                "PlistParser/RootHide/RootHideFilterTypeChecker.swift",
                "PlistParser/RootHide/RootHideFilterValidator.swift",
                "PlistParser/RootHide/RootHideFilterMapper.swift",
                "PlistParser/RootHide/RootHideFilterParser.swift",
                "PlistParser/Rootless/RootlessFilterCodable.swift",
                "PlistParser/Rootless/RootlessFilterMapper.swift",
                "PlistParser/Rootless/RootlessFilterParser.swift",
                "PlistParser/Engine/FilterParseRoute.swift",
                "PlistParser/Engine/FilterParsing.swift",
                "PlistParser/Engine/FilterParseRouteResolver.swift",
                "PlistParser/Engine/PluginFilterParseEngine.swift",
                "PlistParser/Engine/FilterParseSnapshotBuilder.swift",
                "PlistParser/Engine/FilterParseIntegrationValidator.swift",
                "Reporting/ReportBuilder.swift",
                "Reporting/ReportValidator.swift",
                "Reporting/ReportService.swift",
                "Reporting/CombinedReportEncoder.swift",
                "ReportExporter/ReportExporter.swift",
                "ReportExporter/ReportSerialization.swift",
                // 0.1-E1 Plugin Data Foundation：只读领域模型 / 映射 / 仓库 / 快照
                "Plugins/Models/FKPluginStatus.swift",
                "Plugins/Models/FKPluginSource.swift",
                "Plugins/Models/FKPluginConfiguration.swift",
                "Plugins/Models/FKPluginAssociation.swift",
                "Plugins/Models/FKApplication.swift",
                "Plugins/Models/FKPlugin.swift",
                "Plugins/Models/PluginSnapshot.swift",
                "Plugins/Mapping/PluginDataMapper.swift",
                "Plugins/Repository/PluginRepository.swift",
                "Plugins/Repository/DiagnosticPluginRepository.swift",
                // 0.1-E2 Plugin List & Discovery：纯内存查询层
                "Plugins/Query/PluginListFilter.swift",
                "Plugins/Query/PluginListSort.swift",
                "Plugins/Query/PluginListQuery.swift",
                "Plugins/Query/PluginListEntry.swift",
                "Plugins/Query/PluginListProjection.swift",
                "Plugins/Query/PluginListQueryEngine.swift",
                // 0.1-E3 Plugin Detail & App Association Explorer：详情投影与双向 Resolver
                "Plugins/Detail/PluginAssociationEntry.swift",
                "Plugins/Detail/PluginDetailEntry.swift",
                "Plugins/Detail/ApplicationDetailEntry.swift",
                "Plugins/Detail/PluginDetailProjection.swift",
                "Plugins/Detail/ApplicationDetailProjection.swift",
                "Plugins/Detail/PluginAssociationResolver.swift",
                // 0.1-E4 Plugin Feature Integration & Dependency：统一状态 / 共享 Store
                "Plugins/Integration/PluginFeatureState.swift",
                "Plugins/Integration/PluginFeatureStore.swift"
            ]
        ),
        // 骨架阶段模型单测（Codable 往返 / 枚举口径）；2.2 接入 Stage 1 夹具回归
        .testTarget(
            name: "Stage2Tests",
            dependencies: ["Models", "Adapters", "Core", "AppPresentation"],
            path: "Tests/Stage2",
            exclude: [
                "evidence",
                "UITests",
                "README.md",
                "repo-boundary.md",
                "2.1-bootstrap-acceptance.md",
                "Stage-2.1-CI-Acceptance.md",
                "Stage-2.1-Final-Acceptance.md"
            ],
            sources: [
                "ModelsCodableTests.swift",
                "EnvironmentDetectionTests.swift",
                "JBRootCandidateCollectionTests.swift",
                "JBRootValidationTests.swift",
                "ElleKitDirectoryTests.swift",
                "B5IntegrationTests.swift",
                "B5FixtureComparisonTests.swift",
                "B5DeterminismTests.swift",
                "PluginEnumerationTests.swift",
                "PluginInventoryCodableTests.swift",
                "PluginPairingCodableTests.swift",
                "PluginPairingKeyTests.swift",
                "PluginPairingIndexTests.swift",
                "PluginPairingEngineTests.swift",
                "PluginPairingIntegrationTests.swift",
                "PlistReaderTests.swift",
                "PlistDecoderTests.swift",
                "PlistValueKindTests.swift",
                "S105FixtureLoader.swift",
                "PluginPairingS105FixtureTests.swift",
                "FilterParseResultTests.swift",
                "RootHideFilterParserTests.swift",
                "RootlessFilterParserTests.swift",
                "FilterParseEngineTests.swift",
                "EngineC1-BaselineModels.swift",
                "EngineC1-BaselineLoader.swift",
                "EngineC1-BaselineRegistry.swift",
                "EngineC1-ResultComparator.swift",
                "EngineC1-ParserBaselineTests.swift",
                "EngineC1-EngineStubs.swift",
                "EngineC1-EngineBaselineTests.swift",
                "EngineC2-TestSupport.swift",
                "EngineC2-EndToEndTests.swift",
                "EngineC2-BatchIsolationTests.swift",
                "EngineC2-SnapshotWarningsTests.swift",
                "EngineC2BaselineIntegrationTests.swift",
                "EngineC2RouteSymmetryTests.swift",
                "EngineC2EvidenceTraceTests.swift",
                "EngineC2CombinedScenarioTests.swift",
                "EngineC2E-RegressionRegistry.swift",
                "EngineC2E-RegressionPlanTests.swift",
                "ReportBuilderTests.swift",
                "ReportValidatorTests.swift",
                "ReportExporterTests.swift",
                "ReportServiceTests.swift",
                "GUIPresentationTests.swift",
                "PermissionProbeStatusTests.swift",
                "PermissionProbeEvidenceTests.swift",
                "PermissionProbeReportTests.swift",
                "PermissionProbeProbeTests.swift",
                "PermissionProbePresentationTests.swift",
                // Stage 2.5 D-R2-02：18 项诊断离线测试（纯函数/纯聚合表面；
                // FS/私有 API/dyld 运行时表面 deferred，详见
                // Spec/Stage-2/Stage-2.5-D-R2-Acceptance-Plan.md §3）。
                "Diagnostics/JBRootDetectorTests.swift",
                "Diagnostics/DynamicLibrariesTests.swift",
                "Diagnostics/DylibScannerTests.swift",
                "Diagnostics/FilterPlistTests.swift",
                "Diagnostics/FilterRulesTests.swift",
                "Diagnostics/InjectorDetectorTests.swift",
                "Diagnostics/DPKGStatusParserTests.swift",
                "Diagnostics/DPKGOwnershipTests.swift",
                "Diagnostics/PackageMetadataTests.swift",
                "Diagnostics/FileIntegrityTests.swift",
                "Diagnostics/FileSourceTests.swift",
                "Diagnostics/ConffilesTests.swift",
                "Diagnostics/PackageConflictTests.swift",
                "Diagnostics/HelperPreflightTests.swift",
                "Diagnostics/AppInventoryTests.swift",
                "Diagnostics/AppMetadataTests.swift",
                "Diagnostics/PluginAssociationTests.swift",
                "Diagnostics/DiagnosticSummaryTests.swift",
                "Diagnostics/DiagnosticFileSystemTests.swift",
                "Diagnostics/DiagnosticEvidenceValidatorTests.swift",
                "Diagnostics/DiagnosticsExportBridgeTests.swift",
                // 0.1-E1 Plugin Data Foundation 离线测试
                "Plugins/PluginDataFoundationTests.swift",
                // 0.1-E2 Plugin List & Discovery 查询层离线测试
                "Plugins/PluginListQueryTests.swift",
                // 0.1-E3 Plugin Detail & App Association Explorer 离线测试
                "Plugins/PluginDetailTests.swift",
                // 0.1-E4 Plugin Feature Integration & Dependency 集成测试
                "Plugins/PluginFeatureIntegrationTests.swift"
            ]
        ),
        // C-F5 P2：导出样本往返解析校验可执行入口；只依赖 Models 与 AppPresentation
        // 合成基线，不链接 Core 扫描/解析/归属实现。
        .executableTarget(
            name: "ReportRoundtripValidator",
            dependencies: ["Models", "AppPresentation"],
            path: "Tools/ReportRoundtripValidator"
        )
    ]
)
