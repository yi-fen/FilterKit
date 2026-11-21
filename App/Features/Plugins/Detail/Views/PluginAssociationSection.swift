//
//  PluginAssociationSection.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer
//
//  关联按五类固定顺序分组并标注计数；无关联记录时显示诊断事实空态，
//  不写「该插件不支持任何 App」这类产品推断。
//

import SwiftUI
import Core

struct PluginAssociationSection: View {
    let associations: [PluginAssociationEntry]
    /// 关联行导航路由；返回 nil 时行为纯展示行。
    var route: (PluginAssociationEntry) -> PluginNavigationRoute? = { _ in nil }

    private let ordered: [FKAssociationType] = [
        .exactMatch, .globalRule, .unmatchedTarget, .invalidConfiguration, .unresolved
    ]

    var body: some View {
        if associations.isEmpty {
            Text("No association evidence found")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            ForEach(ordered, id: \.self) { category in
                let rows = associations.filter { $0.category == category }
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { association in
                            if let destination = route(association) {
                                NavigationLink(value: destination) {
                                    AssociationRow(association: association)
                                }
                            } else {
                                AssociationRow(association: association)
                            }
                        }
                    } header: {
                        Text("\(category.detailTitle) (\(rows.count))")
                    }
                }
            }
        }
    }
}
