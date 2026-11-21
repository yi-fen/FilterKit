//
//  AssociationRow.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer
//
//  关联行：分类标题唯一落点；五类语义保留，不折算成单一「已关联」。
//

import SwiftUI
import Core

struct AssociationRow: View {
    let association: PluginAssociationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(association.category.detailTitle)
                .font(.body)
            if let applicationID = association.applicationID {
                Text(applicationID)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let evidence = association.evidenceDescription, !evidence.isEmpty {
                Text(evidence)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("detail.association.\(association.id)")
    }
}

extension FKAssociationType {
    var detailTitle: String {
        switch self {
        case .exactMatch: "Exact Match"
        case .globalRule: "Global Rule"
        case .unmatchedTarget: "Unmatched Target"
        case .invalidConfiguration: "Invalid Configuration"
        case .unresolved: "Unresolved"
        }
    }
}
