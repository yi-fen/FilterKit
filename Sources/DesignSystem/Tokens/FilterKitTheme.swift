import SwiftUI
import UIKit

/// Semantic, system-adaptive design tokens. Colors automatically respond to Light/Dark Mode.
enum FilterKitTheme {
    enum ColorToken {
        static let background = Color(UIColor.systemBackground)
        static let secondaryBackground = Color(UIColor.secondarySystemBackground)
        static let groupedBackground = Color(UIColor.systemGroupedBackground)
        static let separator = Color(UIColor.separator)
        static let primaryText = Color.primary
        static let secondaryText = Color.secondary
        static let accent = Color.accentColor
        static let success = Color(UIColor.systemGreen)
        static let warning = Color(UIColor.systemOrange)
        static let danger = Color(UIColor.systemRed)
    }

    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let standard: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
        static let xxLarge: CGFloat = 40
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let capsule: CGFloat = 999
    }

    enum Typography {
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title2.weight(.semibold)
        static let headline = Font.headline
        static let body = Font.body
        static let subheadline = Font.subheadline
        static let caption = Font.caption
    }

    /// Keeps content readable on iPad without stretching cards across the full screen.
    static let readableContentWidth: CGFloat = 720
}
