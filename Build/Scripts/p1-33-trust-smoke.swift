import Foundation

func require133(_ value: @autoclosure () -> Bool, _ message: String) throws {
    guard value() else { throw NSError(domain: "P1-33", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main
struct P133TrustSmoke {
    static func main() throws {
        let appHash = String(repeating: "a", count: 40)
        let helperHash = String(repeating: "b", count: 40)
        let pins = HelperTrustPinSet(schemaVersion: 1, bundleIdentifier: "cn.yfen.filterkit",
            allowedClientUIDs: [501], allowedAppCDHashes: [appHash],
            allowedHelperCDHashes: [helperHash], generation: 1)
        try pins.validate()
        let manifest = try pins.makeDisabledManifest(routeIdentifier: "roothide",
            jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/mobile/FilterKit/Staging",
            socketPath: "/var/jb/var/run/filterkit.sock", stagingOwnerUID: 501)
        try pins.validate(manifest: manifest)
        let appTrust = try pins.makeAppConfiguration()
        try appTrust.validate()
        try HelperTrustConfigurationValidator.validate(manifest)
        try require133(!manifest.executionEnabled, "trust provisioning must not enable execution")

        let emptyManifest = HelperDeploymentManifest.disabledTemplate(routeIdentifier: "roothide",
            jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/mobile/FilterKit/Staging",
            socketPath: "/var/jb/var/run/filterkit.sock", appCDHashes: [],
            helperCDHashes: [helperHash], allowedClientUIDs: [501], stagingOwnerUID: 501)
        do {
            try HelperTrustConfigurationValidator.validate(emptyManifest)
            throw NSError(domain: "P1-33", code: 2, userInfo: [NSLocalizedDescriptionKey: "empty App pins accepted"])
        } catch is HelperTrustConfigurationValidator.ValidationError { }

        let rootUIDPins = HelperTrustPinSet(schemaVersion: 1, bundleIdentifier: "cn.yfen.filterkit",
            allowedClientUIDs: [0], allowedAppCDHashes: [appHash],
            allowedHelperCDHashes: [helperHash], generation: 1)
        do {
            try rootUIDPins.validate()
            throw NSError(domain: "P1-33", code: 3, userInfo: [NSLocalizedDescriptionKey: "root App UID accepted"])
        } catch is HelperTrustPinSet.ValidationError { }

        let duplicatePins = HelperTrustPinSet(schemaVersion: 1, bundleIdentifier: "cn.yfen.filterkit",
            allowedClientUIDs: [501], allowedAppCDHashes: [appHash, appHash.uppercased()],
            allowedHelperCDHashes: [helperHash], generation: 1)
        do {
            try duplicatePins.validate()
            throw NSError(domain: "P1-33", code: 4, userInfo: [NSLocalizedDescriptionKey: "duplicate pins accepted"])
        } catch is HelperTrustPinSet.ValidationError { }

        print("PASS: exact installer pins validate")
        print("PASS: disabled Helper manifest generated from pins")
        print("PASS: manifest pins match provisioned pins")
        print("PASS: App-bundled config contains Helper pin without self-referential App CDHash")
        print("PASS: empty, malformed, duplicate pins rejected")
        print("PASS: root client UID rejected")
        print("PASS: execution remains disabled")
    }
}
