import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let plan = try HelperLifecyclePlan.make(action: .install, jbRoot: "/var/jb", socketGroupID: 501)
require(plan.artifacts.first(where: { $0.kind == .ipcParentDirectory })?.modeOctal == "0711", "IPC parent must be traverse-only")
require(plan.artifacts.first(where: { $0.kind == .auditDirectory })?.modeOctal == "0711", "Helper dir must be traverse-only")
require(plan.artifacts.first(where: { $0.kind == .socket })?.modeOctal == "0660", "socket must not be world writable")
require(plan.artifacts.first(where: { $0.kind == .socket })?.owner == "root:501", "socket group must be provisioned")

let hashA = String(repeating: "a", count: 40)
let hashB = String(repeating: "b", count: 40)
let manifest = HelperDeploymentManifest.disabledTemplate(routeIdentifier: "roothide",
    jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
    stagingRootPath: "/var/jb/var/FilterKit/Staging",
    socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock",
    appCDHashes: [hashA], helperCDHashes: [hashB], allowedClientUIDs: [501],
    stagingOwnerUID: 501, socketGroupID: 501)
try HelperTrustConfigurationValidator.validate(manifest)
var missing = manifest
missing.socketGroupID = nil
do {
    try HelperTrustConfigurationValidator.validate(missing)
    fatalError("missing socket GID must fail closed")
} catch HelperTrustConfigurationValidator.ValidationError.invalidSocketGroup {}

let provisioning = HelperInstallerProvisioningBundle(schemaVersion: 2, generation: 1,
    releaseIdentifier: "p211", bundleIdentifier: "cn.yfen.filterkit",
    jbRootPath: "/var/jb", appCDHash: hashA, helperCDHash: hashB,
    allowedClientUID: 501, socketGroupID: 501, stagingOwnerUID: 501,
    routeIdentifier: "roothide", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
    stagingRootPath: "/var/jb/var/FilterKit/Staging",
    socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock", helperVersion: "1.0")
try provisioning.validate()
print("P2-11 IPC permission policy smoke: PASS")
