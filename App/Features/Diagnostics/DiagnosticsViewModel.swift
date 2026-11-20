//
//  DiagnosticsViewModel.swift
//  FilterKit Features — Diagnostics（Stage 2.3 GUI Foundation / 2.4-D7）
//

import SwiftUI
import Models

@Observable
final class DiagnosticsViewModel {
    let sections: [DiagnosticsSection]

    init(provider: ReportProviding, probeReport: PermissionProbeReport? = nil) {
        let envelopeSections = DiagnosticsMapper.sections(provider.envelope)
        let probeSections = ProbeDiagnosticsMapper.sections(probeReport)
        self.sections = envelopeSections + probeSections
    }
}
