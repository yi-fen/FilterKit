import SwiftUI

struct FKCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(FilterKitTheme.Spacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FilterKitTheme.ColorToken.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: FilterKitTheme.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FilterKitTheme.Radius.large, style: .continuous)
                    .stroke(FilterKitTheme.ColorToken.separator.opacity(0.25), lineWidth: 0.5)
            )
    }
}
