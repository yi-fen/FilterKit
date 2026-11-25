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
                    // Supplement partial LS results from readable app containers; LS metadata wins on duplicates.
                    let fallback = (try? directoryScanner.scan()) ?? []
                    return Self.merge(primary: launchServicesApps, secondary: fallback)
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

        var proxies: [NSObject] = []
        let enumerateSelector = NSSelectorFromString("enumerateApplicationsOfType:block:")
        if workspace.responds(to: enumerateSelector),
           let method = class_getInstanceMethod(type(of: workspace), enumerateSelector) {
            typealias Enumerator = @convention(c) (AnyObject, Selector, Int, AnyObject) -> Void
            let implementation = method_getImplementation(method)
            let enumerate = unsafeBitCast(implementation, to: Enumerator.self)
            let callback: @convention(block) (AnyObject) -> Void = { object in
                if let proxy = object as? NSObject { proxies.append(proxy) }
            }
            // AltList's mature implementation enumerates both public app-type buckets (0 and 1).
            // The numeric values and method ABI are private SPI and remain device-validation items.
            enumerate(workspace, enumerateSelector, 0, callback as AnyObject)
            enumerate(workspace, enumerateSelector, 1, callback as AnyObject)
        }

        // Enumeration buckets can be incomplete on some iOS/rootless combinations.
        // Merge both workspace inventories even when the callback returned results.
        // Bundle identifiers are deduplicated below, preserving richer LS metadata.
        proxies += invokeArray(workspace, selectorName: "allInstalledApplications")
        proxies += invokeArray(workspace, selectorName: "allApplications")
        guard !proxies.isEmpty else { throw AppDiscoveryError.enumerationUnavailable }

        var apps: [String: InstalledApp] = [:]
        var readableBundleCount = 0
        for proxy in proxies {
            guard let bundleID = stringValue("applicationIdentifier", on: proxy),
                  isValidBundleIdentifier(bundleID) else { continue }
            let bundleURL = urlValue("bundleURL", on: proxy)
            if let bundleURL, FileManager.default.isReadableFile(atPath: bundleURL.appendingPathComponent("Info.plist").path) {
                readableBundleCount += 1
            }
            let name = stringValue("_localizedName", on: proxy)
                ?? stringValue("localizedName", on: proxy)
                ?? infoPlistString("CFBundleDisplayName", bundleURL: bundleURL)
                ?? infoPlistString("CFBundleName", bundleURL: bundleURL)
                ?? bundleID
            let info = infoPlistValues(bundleURL: bundleURL)
            let appType = stringValue("applicationType", on: proxy)
            let tags = arrayValue("appTags", on: proxy)
            let classification = classify(applicationType: appType, bundleID: bundleID, tags: tags, bundleURL: bundleURL)
            let icon = proxyIconDescriptor(proxy: proxy, bundleURL: bundleURL, plist: info)
            apps[bundleID] = InstalledApp(bundleIdentifier: bundleID, displayName: name,
                systemClassification: classification, bundleURL: bundleURL,
                shortVersion: info["CFBundleShortVersionString"] as? String,
                buildVersion: info["CFBundleVersion"] as? String,
                executableName: info["CFBundleExecutable"] as? String,
                iconDescriptor: icon, discoverySource: .launchServices)
        }
        guard !apps.isEmpty else { throw AppDiscoveryError.noReadableInventory }
        // An LS proxy inventory with inaccessible bundle paths is still useful; do not turn it into an empty result.
        _ = readableBundleCount
        return apps.values.sorted {
            let order = $0.displayName.localizedStandardCompare($1.displayName)
            return order == .orderedSame ? $0.bundleIdentifier < $1.bundleIdentifier : order == .orderedAscending
        }
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

    private static func arrayValue(_ selectorName: String, on object: NSObject) -> [String]? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector),
              let value = object.perform(selector)?.takeUnretainedValue() else { return nil }
        return value as? [String]
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

    private static func infoPlistString(_ key: String, bundleURL: URL?) -> String? {
        infoPlistValues(bundleURL: bundleURL)[key] as? String
    }

    private static func proxyIconDescriptor(proxy: NSObject, bundleURL: URL?, plist: [String: Any]) -> AppIconDescriptor? {
        var candidates: [URL] = []
        var embeddedData: Data?
        for dataSelectorName in ["iconData", "primaryIconData"] {
            let dataSelector = NSSelectorFromString(dataSelectorName)
            if proxy.responds(to: dataSelector),
               let raw = proxy.perform(dataSelector)?.takeUnretainedValue() {
                if let data = raw as? Data { embeddedData = data; break }
                if let data = raw as? NSData { embeddedData = data as Data; break }
            }
        }
        for selectorName in ["iconsDictionary", "boundIconsDictionary"] {
            let selector = NSSelectorFromString(selectorName)
            guard proxy.responds(to: selector),
                  let raw = proxy.perform(selector)?.takeUnretainedValue(),
                  let dictionary = raw as? [String: Any] else { continue }
            let primary = (dictionary["CFBundlePrimaryIcon"] as? [String: Any]) ?? dictionary
            if let files = primary["CFBundleIconFiles"] as? [String] {
                let resourceURL = urlValue("resourcesDirectoryURL", on: proxy) ?? bundleURL
                if let resourceURL {
                    candidates += files.map { resourceURL.appendingPathComponent($0) }
                }
            }
        }
        let plistDescriptor = ContainerDirectoryAppScannerIconBuilder.make(plist: plist, bundleURL: bundleURL)
        candidates += plistDescriptor?.fileCandidates ?? []
        let nestedAsset = ((plist["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any])?["CFBundleIconName"] as? String
        let asset = nestedAsset ?? plist["CFBundleIconName"] as? String ?? plistDescriptor?.assetName
        guard !candidates.isEmpty || asset != nil || embeddedData != nil else { return nil }
        return AppIconDescriptor(fileCandidates: Array(NSOrderedSet(array: candidates)) as? [URL] ?? candidates,
                                 assetName: asset, bundleURL: bundleURL, embeddedIconData: embeddedData)
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

    private static func merge(primary: [InstalledApp], secondary: [InstalledApp]) -> [InstalledApp] {
        var byID = Dictionary(uniqueKeysWithValues: secondary.map { ($0.bundleIdentifier, $0) })
        for app in primary { byID[app.bundleIdentifier] = app }
        return byID.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}


#else
final class LaunchServicesAppDiscoveryProvider: AppDiscoveryProvider {
    func scanInstalledApps() async throws -> [InstalledApp] { throw AppDiscoveryError.launchServicesUnavailable }
    func findApp(bundleIdentifier: String) async throws -> InstalledApp? { throw AppDiscoveryError.launchServicesUnavailable }
}
#endif
