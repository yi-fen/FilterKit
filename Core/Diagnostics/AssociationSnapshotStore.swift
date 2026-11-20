//
// AssociationSnapshotStore.swift
// Optional persistence for static plugin↔App associations.
// The caller must provide a URL inside FilterKit's own app sandbox.
// No system, jailbreak, dpkg, or plugin configuration path is accepted.
//

import Foundation

public enum AssociationSnapshotStore {
    public static func save(_ associations: [[String: String]], to sandboxURL: URL) throws {
        let standardized = sandboxURL.standardizedFileURL
        let appContainer = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL
        guard standardized.path == appContainer.path || standardized.path.hasPrefix(appContainer.path + "/") else {
            throw NSError(domain: "FilterKit.AssociationSnapshotStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Refusing to write outside the app sandbox"])
        }
        let data = try JSONSerialization.data(withJSONObject: associations, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: standardized, options: [.atomic])
    }
}
