//
//  PluginStatusCard.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer
//
//  三态分行卡片：installed / configured / loaded 不合并；分级文案复用 E2
//  BrowserLabels 唯一落点。
//

import SwiftUI
import Core

struct PluginStatusCard: View {
    let installed: FKPluginState
    let configured: FKPluginState
    let loaded: FKPluginState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow(title: "Installed", status: BrowserLabels.installed(installed))
            statusRow(title: "Configured", status: BrowserLabels.configured(configured))
            statusRow(title: "Loaded", status: BrowserLabels.loaded(loaded))
        }
    }

    private func statusRow(title: String, status: DisplayStatus) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            StatusBadgeView(status: status)
        }
    }
}
