import Foundation

/// Read-only fallback for environments where LaunchServices is unavailable or restricted.
final class ContainerDirectoryAppScanner {
    private let rootURL: URL
    init(rootURL: URL = URL(fileURLWithPath: "/var/containers/Bundle/Application", isDirectory: true)) {
        self.rootURL = rootURL
    }

    func scan() throws -> [InstalledApp] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: rootURL.path) else {
            throw AppDiscoveryError.accessRestricted
        }
        let containers: [URL]
        do {
            containers = try FileManager.default.contentsOfDirectory(
                at: rootURL, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
        } catch { throw AppDiscoveryError.accessRestricted }

        var result: [String: InstalledApp] = [:]
        for container in containers {
            guard (try? container.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let children = (try? FileManager.default.contentsOfDirectory(
                at: container, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            for appURL in children where appURL.pathExtension == "app" {
                let infoURL = appURL.appendingPathComponent("Info.plist")
                guard let data = try? Data(contentsOf: infoURL),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                      let bundleID = plist["CFBundleIdentifier"] as? String,
                      Self.isValidBundleIdentifier(bundleID) else { continue }
                let name = (plist["CFBundleDisplayName"] as? String)
                    ?? (plist["CFBundleName"] as? String) ?? bundleID
                let icon = Self.iconDescriptor(plist: plist, bundleURL: appURL)
                let app = InstalledApp(bundleIdentifier: bundleID, displayName: name,
                    systemClassification: .user, bundleURL: appURL,
                    shortVersion: plist["CFBundleShortVersionString"] as? String,
                    buildVersion: plist["CFBundleVersion"] as? String,
                    executableName: plist["CFBundleExecutable"] as? String,
                    iconDescriptor: icon, discoverySource: .directoryScan)
                result[bundleID] = app
            }
        }
        guard !result.isEmpty else { throw AppDiscoveryError.noReadableInventory }
        return result.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private static func iconDescriptor(plist: [String: Any], bundleURL: URL) -> AppIconDescriptor? {
        ContainerDirectoryAppScannerIconBuilder.make(plist: plist, bundleURL: bundleURL)
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return value.count <= 255 && parts.count >= 2 && parts.allSatisfy {
            !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }
}
