//
//  PluginFilterView.swift
//  FilterKit 0.1-E2 Plugin List & Discovery
//
//  配置 / 关联 / 证据三维筛选；loaded 属运行时状态，不出现在筛选项中。
//

import SwiftUI
import Core

struct PluginFilterView: View {
    @Binding var filter: PluginListFilter

    var body: some View {
        NavigationStack {
            Form {
                Section("Configuration") {
                    Picker("Configuration", selection: $filter.configuration) {
                        ForEach(PluginConfigurationFilter.allCases, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                }
                Section("Association") {
                    Picker("Association", selection: $filter.association) {
                        ForEach(PluginAssociationFilter.allCases, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                }
                Section("Evidence") {
                    Picker("Evidence", selection: $filter.evidence) {
                        ForEach(PluginEvidenceFilter.allCases, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                Button("Clear") { filter = .all }
            }
        }
    }
}

extension PluginConfigurationFilter {
    var title: String {
        switch self {
        case .all: "All"
        case .configured: "Configured"
        case .notConfigured: "Not Configured"
        case .unverified: "Unverified"
        case .unknown: "Unknown"
        }
    }
}

extension PluginAssociationFilter {
    var title: String {
        switch self {
        case .all: "All"
        case .associated: "Associated"
        case .unassociated: "Unassociated"
        case .globalRule: "Global Rule"
        case .unmatched: "Unmatched"
        case .invalid: "Invalid"
        case .unresolved: "Unresolved"
        }
    }
}

extension PluginEvidenceFilter {
    var title: String {
        switch self {
        case .all: "All"
        case .confirmed: "Confirmed"
        case .absent: "Missing"
        case .unverified: "Unverified"
        case .unknown: "Unknown"
        }
    }
}
