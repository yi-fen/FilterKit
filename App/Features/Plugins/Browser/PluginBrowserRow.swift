//
//  PluginBrowserRow.swift
//  FilterKit 0.1-E2 Plugin List & Discovery
//
//  列表行：三态分行展示，不合并成单一状态；关联数量只统计 exactMatch。
//

import SwiftUI
import Core

struct PluginBrowserRow: View {
    let entry: PluginListEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.displayName)
                    .font(.headline)
                Spacer()
                if let version = entry.version {
                    Text(version)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Text(entry.fileName)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                StatusBadgeView(status: BrowserLabels.installed(entry.installed))
                StatusBadgeView(status: BrowserLabels.configured(entry.configured))
                StatusBadgeView(status: BrowserLabels.loaded(entry.loaded))
            }
            Text(BrowserLabels.associationSummary(entry))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("browser.row.\(entry.id)")
    }
}
