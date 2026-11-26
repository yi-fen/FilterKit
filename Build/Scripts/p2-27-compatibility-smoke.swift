import Foundation

@main
struct P227CompatibilitySmoke {
    static func main() throws {
        let appHash = String(repeating: "a", count: 40)
        let helperHash = String(repeating: "b", count: 40)
        let installer = HelperInstallerProvisioningBundle(schemaVersion: 2, generation: 27,
            releaseIdentifier: "p227-test", bundleIdentifier: "cn.yfen.filterkit",
            jbRootPath: "/var/jb", appCDHash: appHash, helperCDHash: helperHash,
            allowedClientUID: 501, socketGroupID: 501, stagingOwnerUID: 501,
            routeIdentifier: "roothide-ellekit", tweakInjectPath: "/var/jb/Library/TweakInject",
            stagingRootPath: "/var/jb/var/FilterKit/Staging",
            socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock", helperVersion: "1.0.0")
        let appTrust = HelperAppTrustConfiguration(schemaVersion: 1, bundleIdentifier: "cn.yfen.filterkit",
            allowedHelperCDHashes: [helperHash], generation: 27,
            allowedHelperUIDs: [0], allowedHelperGIDs: [0])
        try HelperMaintenanceChannelCompatibilityPolicy.validate(installer: installer, appTrust: appTrust,
            observedAppCDHash: appHash, observedHelperCDHash: helperHash,
            observedClientUID: 501, observedClientGID: 501, observedHelperUID: 0, observedHelperGID: 0)

        do {
            try HelperMaintenanceChannelCompatibilityPolicy.validate(installer: installer, appTrust: appTrust,
                observedAppCDHash: String(repeating: "c", count: 40), observedHelperCDHash: helperHash,
                observedClientUID: 501, observedClientGID: 501, observedHelperUID: 0, observedHelperGID: 0)
            fatalError("App CDHash mismatch was accepted")
        } catch HelperMaintenanceChannelCompatibilityPolicy.Failure.appCDHashMismatch { }

        do {
            try HelperMaintenanceChannelCompatibilityPolicy.validate(installer: installer, appTrust: appTrust,
                observedAppCDHash: appHash, observedHelperCDHash: helperHash,
                observedClientUID: 501, observedClientGID: 501, observedHelperUID: 501, observedHelperGID: 0)
            fatalError("non-root Helper identity was accepted")
        } catch HelperMaintenanceChannelCompatibilityPolicy.Failure.helperUIDMismatch { }

        let legacyJSON = "{\"schemaVersion\":1,\"bundleIdentifier\":\"cn.yfen.filterkit\",\"allowedHelperCDHashes\":[\"\(helperHash)\"],\"generation\":27}"
        let legacy = try JSONDecoder().decode(HelperAppTrustConfiguration.self, from: Data(legacyJSON.utf8))
        try legacy.validate()
        guard legacy.allowedHelperUIDs == nil, legacy.allowedHelperGIDs == nil else {
            fatalError("legacy optional identity fields unexpectedly changed")
        }
        print("PASS: matching App/Helper pins and UID/GID accepted; mismatched App CDHash and non-root Helper rejected; legacy schema-1 trust remains decodable")
    }
}
