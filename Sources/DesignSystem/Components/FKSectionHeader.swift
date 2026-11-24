import SwiftUI

struct FKSectionHeader: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: FilterKitTheme.Spacing.xSmall) {
            Text(title)
                .font(FilterKitTheme.Typography.title)
                .foregroundColor(FilterKitTheme.ColorToken.primaryText)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(FilterKitTheme.Typography.subheadline)
                    .foregroundColor(FilterKitTheme.ColorToken.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
