import UIKit
#if canImport(ObjectiveC)
import ObjectiveC.runtime
#endif

enum AppIconPrivateAPIResult: String {
    case success
    case unavailable
    case emptyImage
    case exception
}

/// Bundle-ID icon lookup. Objective-C catches NSException around the private UIKit call.
enum AppIconPrivateAPI {
    static func applicationIcon(bundleIdentifier: String, scale: CGFloat) -> (UIImage?, AppIconPrivateAPIResult) {
        #if canImport(ObjectiveC)
        var image: UIImage?
        let status = FKLookupApplicationIcon(bundleIdentifier, scale, &image)
        switch status {
        case .success:
            guard let image else {
                AppIconDiagnostics.recordPrivateAPI(.emptyImage)
                return (nil, .emptyImage)
            }
            AppIconDiagnostics.recordPrivateAPI(.success)
            return (image, .success)
        case .unavailable:
            AppIconDiagnostics.recordPrivateAPI(.unavailable)
            return (nil, .unavailable)
        case .emptyImage:
            AppIconDiagnostics.recordPrivateAPI(.emptyImage)
            return (nil, .emptyImage)
        case .exception:
            AppIconDiagnostics.recordPrivateAPI(.exception)
            return (nil, .exception)
        @unknown default:
            AppIconDiagnostics.recordPrivateAPI(.unavailable)
            return (nil, .unavailable)
        }
        #else
        AppIconDiagnostics.recordPrivateAPI(.unavailable)
        return (nil, .unavailable)
        #endif
    }
}
