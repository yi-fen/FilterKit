//
//  PermissionProbe.swift
//  FilterKit App — 权限探针（Stage 2.4-D7 已迁移）
//
//  本占位文件在 2.1 阶段保留过 `ProbeItem` / `PermissionProbeService` 轮廓；
//  0.1-D 起探针模型归入 `Models/PermissionProbe`，编排服务归入
//  `Core/PermissionProbe/Services/PermissionProbeService.swift`，界面映射归入
//  `App/Presentation/ProbeDiagnostics.swift`。App 层只消费探针报告，不重复定义
//  探针结果模型，也不直接执行文件访问。
//

import Foundation
