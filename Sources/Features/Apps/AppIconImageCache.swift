import UIKit

/// One process-wide cache for every decoded app icon source.
enum AppIconImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(bundleIdentifier: String, scale: CGFloat) -> UIImage? {
        AppIconDiagnostics.recordCacheLookup()
        let value = cache.object(forKey: cacheKey(bundleIdentifier: bundleIdentifier, scale: scale))
        if value != nil { AppIconDiagnostics.recordCacheHit() }
        else { AppIconDiagnostics.recordCacheMiss() }
        return value
    }

    static func store(_ image: UIImage, bundleIdentifier: String, scale: CGFloat) {
        cache.setObject(image, forKey: cacheKey(bundleIdentifier: bundleIdentifier, scale: scale))
    }

    static func cacheKey(bundleIdentifier: String, scale: CGFloat) -> NSString {
        let scaleToken = Int((scale * 1_000).rounded())
        return "\(bundleIdentifier)|scale:\(scaleToken)" as NSString
    }
}

enum AppIconDiagnostics {
    private static let lock = NSLock()
    private static var cacheLookups = 0
    private static var cacheHits = 0
    private static var cacheMisses = 0
    private static var privateAPISuccess = 0
    private static var privateAPIEmpty = 0
    private static var privateAPIUnavailable = 0
    private static var privateAPIExceptions = 0
    private static var lastLogDate = Date.distantPast

    static func recordCacheLookup() {
        lock.lock(); defer { lock.unlock() }
        cacheLookups += 1
    }

    static func recordCacheHit() {
        lock.lock(); defer { lock.unlock() }
        cacheHits += 1
    }

    static func recordCacheMiss() {
        lock.lock(); defer { lock.unlock() }
        cacheMisses += 1
    }

    static func recordPrivateAPI(_ result: AppIconPrivateAPIResult) {
        lock.lock(); defer { lock.unlock() }
        switch result {
        case .success: privateAPISuccess += 1
        case .emptyImage: privateAPIEmpty += 1
        case .unavailable: privateAPIUnavailable += 1
        case .exception: privateAPIExceptions += 1
        }
    }

    static func logSnapshotIfNeeded() {
        #if DEBUG
        lock.lock()
        let now = Date()
        guard now.timeIntervalSince(lastLogDate) >= 30 else { lock.unlock(); return }
        lastLogDate = now
        let hitRate = cacheLookups == 0 ? 0 : cacheHits * 100 / cacheLookups
        let apiCalls = privateAPISuccess + privateAPIEmpty + privateAPIUnavailable + privateAPIExceptions
        let effectiveRate = apiCalls == 0 ? 0 : privateAPISuccess * 100 / apiCalls
        let line = "[FilterKit][AppIcon][R4] cache_hit_rate=\(hitRate)% hits=\(cacheHits) misses=\(cacheMisses) lookups=\(cacheLookups) private_api_effective_rate=\(effectiveRate)% success=\(privateAPISuccess) empty=\(privateAPIEmpty) unavailable=\(privateAPIUnavailable) exception=\(privateAPIExceptions)"
        lock.unlock()
        print(line)
        #endif
    }
}
