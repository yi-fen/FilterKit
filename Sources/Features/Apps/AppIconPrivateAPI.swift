import UIKit
#if canImport(ObjectiveC)
import ObjectiveC.runtime
#endif

/// Bundle-ID icon fallback modeled on TrollFools 4.4's UIImage._applicationIconImage.
/// The selector is resolved dynamically so the app has no link-time private-API dependency.
enum AppIconPrivateAPI {
    private static let cache = NSCache<NSString, UIImage>()

    static func applicationIcon(bundleIdentifier: String, scale: CGFloat) -> UIImage? {
        if let cached = cache.object(forKey: bundleIdentifier as NSString) { return cached }
        #if canImport(ObjectiveC)
        let selector = NSSelectorFromString("_applicationIconImageForBundleIdentifier:format:scale:")
        guard let method = class_getClassMethod(UIImage.self, selector) else { return nil }
        typealias IconFunction = @convention(c) (AnyObject, Selector, NSString, Int, CGFloat) -> Unmanaged<AnyObject>?
        let function = unsafeBitCast(method_getImplementation(method), to: IconFunction.self)
        guard let image = function(UIImage.self, selector, bundleIdentifier as NSString, 0, scale)?
            .takeUnretainedValue() as? UIImage else { return nil }
        cache.setObject(image, forKey: bundleIdentifier as NSString)
        return image
        #else
        return nil
        #endif
    }
}
