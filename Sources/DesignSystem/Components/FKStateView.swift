import SwiftUI

/// Shared visual treatment for empty, loading, and error states.
enum FKStateKind: Equatable {
    case empty
    case loading
    case error
}

struct FKStateView: View {
    let kind: FKStateKind
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: FilterKitTheme.Spacing.large) {
            VStack(spacing: FilterKitTheme.Spacing.medium) {
                if kind == .loading {
                    ProgressView()
                        .scaleEffect(1.25)
                        .frame(height: 52)
                        .accessibilityLabel(Text("state.loading"))
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size:  thirtyTwo, weight: .medium))
                        .foregroundColor(kind == .error ? FilterKitTheme.ColorToken.danger : FilterKitTheme.ColorToken.accent)
                        .frame(width: 76, height: 76)
                        .background(FilterKitTheme.ColorToken.groupedBackground)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(FilterKitTheme.Typography.title)
                    .multilineTextAlignment(.center)
                    .foregroundColor(FilterKitTheme.ColorToken.primaryText)

                Text(message)
                    .font(FilterKitTheme.Typography.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(FilterKitTheme.ColorToken.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                }
                .buttonStyle(FKPrimaryButtonStyle())
                .frame(maxWidth: 280)
            }
        }
        .padding(.horizontal, FilterKitTheme.Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private let thirtyTwo: CGFloat = 32
}
