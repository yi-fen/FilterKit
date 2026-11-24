import SwiftUI

struct FKPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FilterKitTheme.Typography.headline)
            .foregroundColor(.white)
            .padding(.horizontal, FilterKitTheme.Spacing.large)
            .padding(.vertical, FilterKitTheme.Spacing.medium)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(FilterKitTheme.ColorToken.accent.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: FilterKitTheme.Radius.medium, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct FKSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FilterKitTheme.Typography.headline)
            .foregroundColor(FilterKitTheme.ColorToken.accent)
            .padding(.horizontal, FilterKitTheme.Spacing.large)
            .padding(.vertical, FilterKitTheme.Spacing.medium)
            .frame(minHeight: 44)
            .background(FilterKitTheme.ColorToken.secondaryBackground.opacity(configuration.isPressed ? 0.65 : 1))
            .clipShape(RoundedRectangle(cornerRadius: FilterKitTheme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FilterKitTheme.Radius.medium, style: .continuous)
                    .stroke(FilterKitTheme.ColorToken.separator.opacity(0.4), lineWidth: 0.75)
            )
    }
}
