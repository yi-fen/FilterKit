//
//  ApplicationRow.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer
//
//  App 列表行：名称 + Bundle ID + 精确关联数；全局规则等不计入精确关联数。
//

import SwiftUI
import Core

struct ApplicationRow: View {
    let entry: ApplicationDetailEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.displayName)
                .font(.body)
            Text(entry.bundleIdentifier)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(entry.exactMatchCount) Exact Match\(entry.exactMatchCount == 1 ? "" : "es")")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("detail.app.\(entry.id)")
    }
}
