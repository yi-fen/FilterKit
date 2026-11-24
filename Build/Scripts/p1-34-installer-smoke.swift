import Foundation

func require134(_ value: @autoclosure () -> Bool, _ message: String) throws {
    guard value() else { throw NSError(domain: "P1-34", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main
struct P134InstallerSmoke {
    static func main() throws {
        let appHash = String(repeating: "a", count: 40)
        let helperHash = String(repeating: "b", count: 40)
        let bundle = HelperInstallerProvisioningBundle(schemaVersion: 1, generation: 9,
            releaseIdentifier: "1.0.0-p134", bundleIdentifier: "cn.yfen.filterkit",
            jbRootPath: "/var/jb", appCDHash: appHash, helperCDHash: helperHash,
            allowedClientUID: 501, stagingOwnerUID: 501, routeIdentifier: "dopamine-roothide",
            tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/tmp/filterkit-staging",
            socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock", helperVersion: "1.0.0")
        try bundle.validate()
        let appConfig = try bundle.appTrustConfiguration()
        let manifest = try bundle.disabledRootManifest()
        try require134(appConfig.allowedHelperCDHashes == [helperHash], "App config must pin exact Helper CDHash")
        try require134(manifest.allowedAppCDHashes == [appHash], "Root manifest must pin exact App CDHash")
        try require134(manifest.allowedHelperCDHashes == [helperHash], "Root manifest must pin exact Helper CDHash")
        try require134(!manifest.executionEnabled, "deployment must remain disabled")

        let plistData = try bundle.disabledLaunchDaemonPlist()
        let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as! [String: Any]
        try require134(plist["Disabled"] as? Bool == true, "launchd job must be disabled")
        try require134(plist["RunAtLoad"] as? Bool == false, "launchd must not run at load")
        try require134(plist["KeepAlive"] as? Bool == false, "launchd must not keep alive")

        let upgrade = try HelperInstallerTransactionPlan.make(action: .upgrade, bundle: bundle)
        try require134(upgrade.steps.contains(.preservePreviousRelease), "upgrade must preserve prior release")
        try require134(upgrade.rollbackSteps.contains(.restorePreviousRelease), "upgrade must have rollback plan")
        try require134(!upgrade.mayRunFromApp && !upgrade.executionEnabled, "App and deployment gates must remain closed")

        let digest = HelperInstallerArtifactDigest(relativePath: "usr/libexec/filterkit-helper", sha256: String(repeating: "c", count: 64))
        let launchdDigest = HelperInstallerArtifactDigest(relativePath: "Library/LaunchDaemons/cn.yfen.filterkit.helper.plist", sha256: String(repeating: "d", count: 64))
        let report = try HelperInstallerDryRun().validate(bundle: bundle, artifactDigests: [digest, launchdDigest], action: .install)
        try require134(!report.writesPerformed && !report.launchdInvoked && !report.executionEnabled, "dry run must be side-effect free")

        let invalidPath = HelperInstallerProvisioningBundle(schemaVersion: 1, generation: 1,
            releaseIdentifier: "bad", bundleIdentifier: "cn.yfen.filterkit", jbRootPath: "/var/jb",
            appCDHash: appHash, helperCDHash: helperHash, allowedClientUID: 501, stagingOwnerUID: 501,
            routeIdentifier: "roothide", tweakInjectPath: "/private/var/evil/TweakInject",
            stagingRootPath: "/var/jb/var/tmp/filterkit-staging",
            socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock", helperVersion: "1")
        do {
            try invalidPath.validate()
            throw NSError(domain: "P1-34", code: 2, userInfo: [NSLocalizedDescriptionKey: "outside jbroot path accepted"])
        } catch is HelperInstallerProvisioningBundle.ValidationError { }

        print("PASS: provisioning bundle validates final App/Helper CDHash inputs")
        print("PASS: App trust config and disabled root manifest contain complementary exact pins")
        print("PASS: launchd artifact remains Disabled/RunAtLoad=false/KeepAlive=false")
        print("PASS: upgrade plan preserves prior release and defines rollback")
        print("PASS: dry-run reports zero writes, no launchd invocation, execution disabled")
        print("PASS: paths outside validated jbroot rejected")
    }
}
