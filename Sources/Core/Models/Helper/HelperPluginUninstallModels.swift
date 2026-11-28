import Foundation

/// Narrow uninstall intent. The client supplies identity expectations, never paths or file bytes.
struct HelperPluginUninstallRequest: Codable, Equatable {
    let requestID: UUID
    let pluginID: UUID
    let dylibFileName: String
    let plistFileName: String
    let expectedDylibSHA256: String
    let expectedPlistSHA256: String
    let expectedManifestSHA256: String
    let createdAt: Date
    let operatorConfirmed: Bool

    func validate(now: Date = Date(), clockSkewLimit: TimeInterval = 120) -> Bool {
        guard requestID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
              pluginID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
              HelperPolicy.isSafeLeafName(dylibFileName), dylibFileName.lowercased().hasSuffix(".dylib"),
              HelperPolicy.isSafeLeafName(plistFileName), plistFileName.lowercased().hasSuffix(".plist"),
              String(dylibFileName.dropLast(6)).lowercased() == String(plistFileName.dropLast(6)).lowercased(),
              [expectedDylibSHA256, expectedPlistSHA256, expectedManifestSHA256].allSatisfy(HelperPolicy.isValidHash),
              abs(now.timeIntervalSince(createdAt)) <= clockSkewLimit else { return false }
        return true
    }
}

enum HelperPluginUninstallStatus: String, Codable, Equatable {
    case authorizedReadOnly
    case executionNotReleased
    case uninstalled
}

struct HelperPluginUninstallResponse: Codable, Equatable {
    let requestID: UUID
    let pluginID: UUID
    let status: HelperPluginUninstallStatus
    let reasonCode: String
    let transactionID: UUID?
    let completedAt: Date
}
