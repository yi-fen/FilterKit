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
        let totalScanStartedAt = Date()
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
        var validBundleIDCount = 0
        var proxyMethodCalls = 0
        var proxyFieldHits = 0
        var infoPlistReadCount = 0
        var executableNameCompleteCount = 0
        for proxy in proxies {
            guard let bundleID = stringValue("applicationIdentifier", on: proxy),
                  isValidBundleIdentifier(bundleID) else { continue }
            validBundleIDCount += 1
            guard let bundleURL = urlValue("bundleURL", on: proxy) else { continue }

            // R1: LaunchServices proxy is authoritative per metadata field. Read the
            // bundle plist once only if at least one optional field is unavailable.
            // Bundle ID and bundle URL remain required proxy values; never infer them.
            let metadata = resolveProxyMetadata(proxy: proxy, bundleURL: bundleURL)
            proxyMethodCalls += metadata.proxyMethodCalls
            proxyFieldHits += metadata.proxyFieldHits
            if metadata.didReadInfoPlist { infoPlistReadCount += 1 }
            if metadata.executableName != nil { executableNameCompleteCount += 1 }
            let classification = classify(applicationType: nil, bundleID: bundleID, tags: nil, bundleURL: bundleURL)
            let icon = proxyIconDescriptor(bundleURL: bundleURL, plist: metadata.plist,
                                           proxyIconName: metadata.iconName)
            apps[bundleID] = InstalledApp(bundleIdentifier: bundleID, displayName: metadata.displayName ?? bundleID,
                systemClassification: classification, bundleURL: bundleURL,
                shortVersion: metadata.shortVersion, buildVersion: metadata.buildVersion,
                executableName: metadata.executableName,
                iconDescriptor: icon, discoverySource: .launchServices)
        }
        guard !apps.isEmpty else { throw AppDiscoveryError.noReadableInventory }
        let elapsedMS = Int(Date().timeIntervalSince(totalScanStartedAt) * 1_000)
        let executableRate = validBundleIDCount == 0 ? 0 : Int(Double(executableNameCompleteCount) / Double(validBundleIDCount) * 100)
        let proxyHitRate = proxyMethodCalls == 0 ? 0 : Int(Double(proxyFieldHits) / Double(proxyMethodCalls) * 100)
        NSLog("[FilterKit][AppDiscovery][R4] ls_total_ms=%d proxies=%d valid_bundle_ids=%d proxy_calls=%d proxy_field_hits=%d proxy_hit_rate=%d%% plist_reads=%d executable_complete=%d/%d executable_rate=%d%%", elapsedMS, proxies.count, validBundleIDCount, proxyMethodCalls, proxyFieldHits, proxyHitRate, infoPlistReadCount, executableNameCompleteCount, validBundleIDCount, executableRate)
        AppDiscoveryPerformanceDiagnostics.logSummaryIfNeeded()
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
              let value = object.perform(selector)?.takeUnretainedValue() else {
            AppDiscoveryPerformanceDiagnostics.recordProxy(selector: selectorName, hit: false)
            return nil
        }
        let result = value as? String
        AppDiscoveryPerformanceDiagnostics.recordProxy(selector: selectorName, hit: result?.isEmpty == false)
        return result
    }

    private static func urlValue(_ selectorName: String, on object: NSObject) -> URL? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector),
              let value = object.perform(selector)?.takeUnretainedValue() else {
            AppDiscoveryPerformanceDiagnostics.recordProxy(selector: selectorName, hit: false)
            return nil
        }
        let result: URL?
        if let url = value as? URL { result = url }
        else if let url = value as? NSURL { result = url as URL }
        else { result = nil }
        AppDiscoveryPerformanceDiagnostics.recordProxy(selector: selectorName, hit: result != nil)
        return result
    }

    struct ProxyMetadataResolution {
        let displayName: String?
        let shortVersion: String?
        let buildVersion: String?
        let executableName: String?
        let iconName: String?
        let plist: [String: Any]
        let proxyMethodCalls: Int
        let proxyFieldHits: Int
        let didReadInfoPlist: Bool
    }

    /// Internal for offline stub tests. Each proxy field is queried independently;
    /// a missing field is filled from one shared Info.plist read, never guessed.
    static func resolveProxyMetadata(proxy: NSObject, bundleURL: URL,
                                      plistReader: ((URL) -> [String: Any])? = nil) -> ProxyMetadataResolution {
        let readPlist = plistReader ?? infoPlistValues
        var calls = 0
        var hits = 0
        func proxyString(_ selectors: [String]) -> String? {
            for selectorName in selectors {
                calls += 1
                let value = stringValue(selectorName, on: proxy)
                if let value, !value.isEmpty {
                    hits += 1
                    return value
                }
            }
            return nil
        }

        let proxyName = proxyString(["localizedName"])
        let proxyShortVersion = proxyString(["shortVersionString"])
        let proxyBuildVersion = proxyString(["bundleVersion", "buildVersion"])
        let proxyExecutable = proxyString(["executableName"])
        let proxyIcon = proxyString(["iconName"])
        let needsPlist = proxyName == nil || proxyShortVersion == nil || proxyBuildVersion == nil ||
            proxyExecutable == nil || proxyIcon == nil
        let plist = needsPlist ? readPlist(bundleURL) : [:]

        let displayName = proxyName ?? (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
        let shortVersion = proxyShortVersion ?? (plist["CFBundleShortVersionString"] as? String)
        let buildVersion = proxyBuildVersion ?? (plist["CFBundleVersion"] as? String)
        let executableName = proxyExecutable ?? (plist["CFBundleExecutable"] as? String)
        let iconName = proxyIcon
            ?? (((plist["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any])?["CFBundleIconName"] as? String)
            ?? (plist["CFBundleIconName"] as? String)
        return ProxyMetadataResolution(displayName: displayName, shortVersion: shortVersion,
            buildVersion: buildVersion, executableName: executableName, iconName: iconName,
            plist: plist, proxyMethodCalls: calls, proxyFieldHits: hits, didReadInfoPlist: needsPlist)
    }

    private static func infoPlistValues(_ bundleURL: URL) -> [String: Any] {
        AppDiscoveryPerformanceDiagnostics.recordInfoPlistRead()
        guard let data = try? Data(contentsOf: bundleURL.appendingPathComponent("Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }

    private static func proxyIconDescriptor(bundleURL: URL?, plist: [String: Any],
                                            proxyIconName: String?) -> AppIconDescriptor? {
        let plistDescriptor = ContainerDirectoryAppScannerIconBuilder.make(plist: plist, bundleURL: bundleURL)
        let nestedAsset = ((plist["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any])?["CFBundleIconName"] as? String
        let asset = proxyIconName ?? nestedAsset ?? plist["CFBundleIconName"] as? String ?? plistDescriptor?.assetName
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
