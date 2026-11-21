//
//  PluginEvidenceSection.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer
//
//  证据分区：来源原值/来源证据/解析状态/完整性状态；完整性记录未链接前
//  保持 unknown，不标注 verified。
//

import SwiftUI
import Core

struct PluginEvidenceSection: View {
    let detail: PluginDetailEntry

    var body: some View {
        Section("Evidence") {
            LabeledContent("Source", value: detail.sourceRaw)
            if let sourceEvidence = detail.sourceEvidence {
                LabeledContent("Source Evidence", value: sourceEvidence)
            }
            if let parseStatus = detail.parseStatus {
                LabeledContent("Parse Status", value: parseStatus)
            }
            LabeledContent("Integrity", value: integrityText)
        }
    }

    private var integrityText: String {
        switch detail.integrityState {
        case .confirmed: "Verified"
        case .absent: "Missing"
        case .unverified: "Unverified"
        case .unknown: "Not verified in current snapshot"
        }
    }
}
