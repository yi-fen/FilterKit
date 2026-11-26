import Foundation

#if canImport(ObjectiveC)
import ObjectiveC

/// LaunchServices private-API adapter with conservative API fallback and a read-only container scan fallback.
final class LaunchServicesAppDiscoveryProvider: AppDiscoveryProvider {
    private let directoryScanner: ContainerDirectoryAppScanner

    init(directoryScanner: ContainerDirectoryAppScanner = ContainerDirectoryAppScanner()) {
        self.directoryScanner = directoryScanner
    }

    func scanInstalledApps() async throws -> [InstalledApp] {
        try await Task.detached(priority: .userInitiated) { [directoryScanner] in
            do {
                let launchServicesApps = try Self.scanLaunchServices()
                if !launchServicesApps.isEmpty {
                    // LaunchServices is the primary inventory (as in R16/TrollFools).
                    // Do not walk every app container on the successful fast path:
                    // that duplicates I/O and delays the first visible list. The
                    // container scanner remains a fallback only when LS is empty.
                    return launchServicesApps
                }
                return try directoryScanner.scan()
            } catch let lsError as AppDiscoveryError {
                do { return try directoryScanner.scan() }
                catch { throw lsError == .accessRestricted ? lsError : AppDiscoveryError.noReadableInventory }
            } catch {
                return try directoryScanner.scan()
            }
        }.value
    }

    func findApp(bundleIdentifier: String) async throws -> InstalledApp? {
        try await scanInstalledApps().first { $0.bundleIdentifier == bundleIdentifier }
    }

    private static func scanLaunchServices() throws -> [InstalledApp] {
        // AltList documents lsd as unsafe for this IPC path; fail closed before messaging LaunchServices.
        if Bundle.main.executableURL?.lastPathComponent == "lsd" { throw AppDiscoveryError.lsdProcessGuard }
        guard let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type else {
            throw AppDiscoveryError.launchServicesUnavailable
        }
        let defaultWorkspace = NSSelectorFromString("defaultWorkspace")
        guard let workspace = workspaceClass.perform(defaultWorkspace)?.takeUnretainedValue() as? NSObject else {
            throw AppDiscoveryError.workspaceUnavailable
        }

        // R16 and TrollFools use allApplications/allInstalledApplications as the
        // primary inventory. Prefer allInstalledApplications and call the broader
        // allApplications API only when the primary result is empty/unavailable.
        var proxies = invokeArray(workspace, selectorName: "allInstalledApplications")
        if proxies.isEmpty {
            proxies = invokeArray(workspace, selectorName: "allApplications")
        }
        guard !proxies.isEmpty else { throw AppDiscoveryError.enumerationUnavailable }

        var apps: [String: InstalledApp] = [:]
        for proxy in proxies {
            guard let bundleID = stringValue("applicationIdentifier", on: proxy),
                  isValidBundleIdentifier(bundleID) else { continue }
            let bundleURL = urlValue("bundleURL", on: proxy)
            // Read Info.plist exactly once per application. The previous path read it
            // separately for display name and again for version/build/executable/icon,
            // multiplying filesystem I/O across hundreds of installed apps.
            let info = infoPlistValues(bundleURL: bundleURL)
            let name = stringValue("localizedName", on: proxy)
                ?? (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? bundleID
            // R16 classifies by the resolved bundle path. Avoid two extra private
            // proxy calls per app; icon cache lookup is deferred until the row appears.
            let classification = classify(applicationType: nil, bundleID: bundleID, tags: nil, bundleURL: bundleURL)
            let icon = proxyIconDescriptor(bundleURL: bundleURL, plist: info)
            apps[bundleID] = InstalledApp(bundleIdentifier: bundleID, displayName: name,
                systemClassification: classification, bundleURL: bundleURL,
                shortVersion: info["CFBundleShortVersionString"] as? String,
                buildVersion: info["CFBundleVersion"] as? String,
                executableName: info["CFBundleExecutable"] as? String,
                iconDescriptor: icon, discoverySource: .launchServices)
        }
        guard !apps.isEmpty else { throw AppDiscoveryError.noReadableInventory }
        // Ordering is finalized by the cache layer (`deduplicatedAndSorted`) and
        // the display filter (`AppInventoryQuery`). This fast path returns the
        // deduplicated inventory without a second per-scan sort.
        return Array(apps.values)
    }

    private static func invokeArray(_ object: NSObject, selectorName: String) -> [NSObject] {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector),
              let value = object.perform(selector)?.takeUnretainedValue() else { return [] }
        return value as? [NSObject] ?? []
    }

    private static func stringValue(_ selectorName: String, on object: NSObject) -> String? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector),
              let value = object.perform(selector)?.takeUnretainedValue() else { return nil }
        return value as? String
    }

    private static func urlValue(_ selectorName: String, on object: NSObject) -> URL? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector),
              let value = object.perform(selector)?.takeUnretainedValue() else { return nil }
        if let url = value as? URL { return url }
        if let url = value as? NSURL { return url as URL }
        return nil
    }

    private static func infoPlistValues(bundleURL: URL?) -> [String: Any] {
        guard let bundleURL,
              let data = try? Data(contentsOf: bundleURL.appendingPathComponent("Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }

    private static func proxyIconDescriptor(bundleURL: URL?, plist: [String: Any]) -> AppIconDescriptor? {
        // Keep plist-declared file/asset candidates cheap. Bundle-ID icon cache lookup
        // is performed lazily by ApplicationIconView, matching TrollFools' App.icon.
        let plistDescriptor = ContainerDirectoryAppScannerIconBuilder.make(plist: plist, bundleURL: bundleURL)
        let nestedAsset = ((plist["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any])?["CFBundleIconName"] as? String
        let asset = nestedAsset ?? plist["CFBundleIconName"] as? String ?? plistDescriptor?.assetName
        guard let plistDescriptor else {
            guard let bundleURL, asset != nil else { return nil }
            return AppIconDescriptor(fileCandidates: [], assetName: asset, bundleURL: bundleURL)
        }
        return AppIconDescriptor(fileCandidates: plistDescriptor.fileCandidates,
                                 assetName: asset, bundleURL: bundleURL)
    }

    static func classify(applicationType: String?, bundleID: String, tags: [String]?, bundleURL: URL? = nil) -> AppSystemClassification {
        // Match R16's proven path-first rule. In particular, an IPA installed by
        // TrollStore under the ordinary Application container is a user app even
        // when LaunchServices reports applicationType == "System".
        guard let bundleURL else { return .unknown }
        let path = bundleURL.standardizedFileURL.path
        // R16's established behavior: only the two Apple system bundle roots are
        // classified as system. Everything with a readable bundle path elsewhere,
        // including TrollStore-installed IPA containers, remains a user app.
        if path.hasPrefix("/Applications/") || path.hasPrefix("/System/") { return .system }
        return .user
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        // R16 accepted any non-empty LS applicationIdentifier. Avoid excluding
        // legitimate installed apps because a private identifier uses an unusual
        // character or component layout.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 255
    }


}


#else
final class LaunchServicesAppDiscoveryProvider: AppDiscoveryProvider {
    func scanInstalledApps() async throws -> [InstalledApp] { throw AppDiscoveryError.launchServicesUnavailable }
    func findApp(bundleIdentifier: String) async throws -> InstalledApp? { throw AppDiscoveryError.launchServicesUnavailable }
}
#endif
