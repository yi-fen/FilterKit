//
//  SectionCardView.swift
//  FilterKit App 共享组件（Stage 2.3 GUI Foundation）
//

import SwiftUI

/// 分区卡片：标题 + 内容容器。
struct SectionCardView<Content: View>: View {
    let title: String
    let identifier: String?
    @ViewBuilder let content: () -> Content

    init(title: String, identifier: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.identifier = identifier
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // 先声明为可容纳子元素的真实 AX 锚点，再挂卡片标识；否则容器标识会
        // 向下覆盖、抹掉子级叶子（计数 Text / 行名 Text）上的自有标识。
        // 顺序不能反：先挂标识再 .contain 会把根标识推到每个叶子上。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier ?? title)
    }
}
