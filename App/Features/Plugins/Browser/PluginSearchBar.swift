//
//  PluginSearchBar.swift
//  FilterKit 0.1-E2 Plugin List & Discovery
//
//  搜索框封装；关键词只驱动内存查询，不触发扫描。
//

import SwiftUI

struct PluginSearchBar: View {
    @Binding var text: String
    var prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(prompt, text: $text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
