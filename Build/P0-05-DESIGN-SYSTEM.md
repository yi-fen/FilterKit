# P0-05 — FilterKit Design System

## Scope

This phase introduces reusable visual foundations without changing the four-tab product structure or implementing feature workflows.

## Design tokens

- Semantic system colors: system background, secondary/grouped background, primary/secondary text, separator, accent, success, warning, and danger.
- Spacing scale: 4, 8, 12, 16, 24, 32, and 40 points.
- Corner radii: 8, 12, and 16 points, plus capsule.
- Typography: Dynamic Type-backed SwiftUI text styles.
- iPad readable content width: 720 points.

Semantic UIKit colors are used so Light/Dark Mode adapts automatically. No fixed light-only background or text colors are introduced.

## Reusable components

- `FKCard`: adaptive secondary-background card with subtle separator border.
- `FKPrimaryButtonStyle` and `FKSecondaryButtonStyle`: consistent touch target and pressed feedback.
- `FKSectionHeader`: consistent section title and optional subtitle.
- `FKStateView`: shared empty, loading, and error state presentation, with optional action.
- `FeaturePlaceholderView`: feature placeholder now delegates to the shared empty-state component.

## Accessibility and layout

- Buttons have a minimum 44-point height.
- State illustrations are hidden from VoiceOver when decorative.
- Loading state has an accessibility label.
- Text supports Dynamic Type and wraps instead of truncating.
- Content is centered with a maximum readable width on larger iPad layouts.

## Compatibility

The implementation targets the project's current iOS 15.0 deployment target and uses SwiftUI APIs available on iOS 15. This source has not been compiled with Xcode in the current Linux environment; Xcode and device validation remain required.
