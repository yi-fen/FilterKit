import SwiftUI
import UIKit

/// Icons are loaded only when a visible row appears. No inventory scan decodes images.
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
        .task(id: "\(bundleIdentifier)|\(descriptor?.hashValue ?? 0)|\(UIScreen.main.scale)") {
            await loadIcon()
        }
    }

    @MainActor
    private func loadIcon() async {
        image = nil
        let targetScale = UIScreen.main.scale
        if let cached = AppIconImageCache.image(bundleIdentifier: bundleIdentifier, scale: targetScale) {
            image = cached
            AppIconDiagnostics.logSnapshotIfNeeded()
            return
        }

        // TrollFools-compatible Bundle-ID lookup is primary. The wrapper catches
        // Objective-C exceptions and distinguishes unavailable/empty/effective results.
        let (privateImage, _) = AppIconPrivateAPI.applicationIcon(
            bundleIdentifier: bundleIdentifier, scale: targetScale)
        if let privateImage {
            AppIconImageCache.store(privateImage, bundleIdentifier: bundleIdentifier, scale: targetScale)
            image = privateImage
            AppIconDiagnostics.logSnapshotIfNeeded()
            return
        }

        let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
            if let descriptor {
                let orderedCandidates = descriptor.fileCandidates.sorted { lhs, rhs in
                    Self.scaleDistance(for: lhs, targetScale: targetScale) < Self.scaleDistance(for: rhs, targetScale: targetScale)
                }
                for url in orderedCandidates {
                    AppDiscoveryPerformanceDiagnostics.recordIconFileRead()
                    if let candidate = UIImage(contentsOfFile: url.path), Self.isUsable(candidate) { return candidate }
                }
                if let asset = descriptor.assetName, let bundleURL = descriptor.bundleURL,
                   let bundle = Bundle(url: bundleURL) {
                    AppDiscoveryPerformanceDiagnostics.recordIconAssetRead()
                    if let candidate = UIImage(named: asset, in: bundle, compatibleWith: nil), Self.isUsable(candidate) {
                    return candidate
                    }
                }
                if let data = descriptor.embeddedIconData,
                   let candidate = UIImage(data: data), Self.isUsable(candidate) { return candidate }
            }
            return nil
        }.value

        if let loaded {
            AppIconImageCache.store(loaded, bundleIdentifier: bundleIdentifier, scale: targetScale)
        }
        image = loaded
        AppIconDiagnostics.logSnapshotIfNeeded()
    }

    private nonisolated static func isUsable(_ image: UIImage) -> Bool {
        image.size.width.isFinite && image.size.height.isFinite && image.size.width > 0 && image.size.height > 0
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
