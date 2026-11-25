import SwiftUI
import UIKit

/// Loads icons lazily when a row appears; file decode and asset lookup run away from the main thread.
struct ApplicationIconView: View {
    let bundleIdentifier: String
    let descriptor: AppIconDescriptor?
    let classification: AppSystemClassification
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
            if let image {
                Image(uiImage: image).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 11))
            } else {
                Image(systemName: classification == .system ? "gearshape.fill" : "app.fill")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundColor(FilterKitTheme.ColorToken.accent)
            }
        }
        .frame(width: 48, height: 48)
        .task(id: "\(bundleIdentifier)|\(descriptor?.hashValue ?? 0)") { await loadIcon() }
    }

    @MainActor
    private func loadIcon() async {
        image = nil
        let targetScale = UIScreen.main.scale
        let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
            if let data = descriptor?.embeddedIconData, let image = UIImage(data: data) { return image }
            if let descriptor {
                let orderedCandidates = descriptor.fileCandidates.sorted { lhs, rhs in
                    Self.scaleDistance(for: lhs, targetScale: targetScale) < Self.scaleDistance(for: rhs, targetScale: targetScale)
                }
                for url in orderedCandidates {
                    if let image = UIImage(contentsOfFile: url.path) { return image }
                }
                if let asset = descriptor.assetName, let bundleURL = descriptor.bundleURL,
                   let bundle = Bundle(url: bundleURL),
                   let image = UIImage(named: asset, in: bundle, compatibleWith: nil) {
                    return image
                }
            }
            return nil
        }.value
        // TrollFools 4.4 uses UIImage._applicationIconImage for bundle-ID based
        // lookup. Run this UIKit/LaunchServices fallback on the main actor after
        // cheap file/asset resolution fails (Chrome/QQ Browser/Dopamine cases).
        image = loaded ?? AppIconPrivateAPI.applicationIcon(bundleIdentifier: bundleIdentifier, scale: targetScale)
    }

    private nonisolated static func scaleDistance(for url: URL, targetScale: CGFloat) -> CGFloat {
        let name = url.lastPathComponent.lowercased()
        let scale: CGFloat
        if name.contains("@3x") { scale = 3 }
        else if name.contains("@2x") { scale = 2 }
        else { scale = 1 }
        return abs(scale - targetScale)
    }
}
