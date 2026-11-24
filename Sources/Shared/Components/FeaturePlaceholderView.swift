import SwiftUI

/// Standard empty-state view used by feature roots until their data workflows are implemented.
struct FeaturePlaceholderView: View {
    let systemImage: String
    let titleKey: LocalizedStringKey
    let messageKey: LocalizedStringKey

    var body: some View {
        FKStateView(
            kind: .empty,
            systemImage: systemImage,
            title: titleKey,
            message: messageKey
        )
        .frame(maxWidth: FilterKitTheme.readableContentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FilterKitTheme.ColorToken.background)
    }
}
