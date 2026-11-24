import SwiftUI
import UIKit

/// Loads icons lazily when a row appears; file decode and asset lookup run away from the main thread.
struct ApplicationIconView: View {
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
        .task(id: descriptor) { await loadIcon() }
    }

    @MainActor
    private func loadIcon() async {
        guard let descriptor else { return }
        let targetScale = UIScreen.main.scale
        let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
            if let data = descriptor.embeddedIconData, let image = UIImage(data: data) { return image }
            let orderedCandidates = descriptor.fileCandidates.sorted { lhs, rhs in
                Self.scaleDistance(for: lhs, targetScale: targetScale) < Self.scaleDistance(for: rhs, targetScale: targetScale)
            }
            for url in orderedCandidates {
                if let image = UIImage(contentsOfFile: url.path) { return image }
            }
            if let asset = descriptor.assetName, let bundleURL = descriptor.bundleURL,
               let bundle = Bundle(url: bundleURL) {
                return UIImage(named: asset, in: bundle, compatibleWith: nil)
            }
            return nil
        }.value
        image = loaded
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
