import Foundation

struct HelperInstallerProvisioningBundle {
    let generation: UInt64
    let bundleIdentifier: String
    let jbRootPath: String
    let appCDHash: String
    let helperCDHash: String
    let allowedClientUID: UInt32
    let socketGroupID: UInt32
    let routeIdentifier: String
    let tweakInjectPath: String
    let stagingRootPath: String
    let socketPath: String
    let teamIdentifier: String?
    func validate() throws {
        guard appCDHash.range(of: "^[0-9a-fA-F]{40}$", options: .regularExpression) != nil,
              helperCDHash.range(of: "^[0-9a-fA-F]{40}$", options: .regularExpression) != nil else { throw NSError(domain: "invalid", code: 1) }
    }
}

func bundle(_ generation: UInt64, _ app: String = String(repeating: "a", count: 40),
            _ team: String? = "ABCDE12345", _ helper: String = String(repeating: "b", count: 40),
            _ id: String = "cn.yfen.filterkit", _ uid: UInt32 = 501) -> HelperInstallerProvisioningBundle {
    .init(generation: generation, bundleIdentifier: id, jbRootPath: "/var/jb", appCDHash: app,
          helperCDHash: helper, allowedClientUID: uid, socketGroupID: 501, routeIdentifier: "roothide",
          tweakInjectPath: "/var/jb/usr/lib/TweakInject", stagingRootPath: "/var/jb/var/tmp/filterkit-staging",
          socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock", teamIdentifier: team)
}

var passed = 0
func check(_ name: String, _ condition: Bool) {
    if condition { passed += 1; print("PASS: \(name)") }
    else { fputs("FAIL: \(name)\n", stderr); exit(1) }
}
func accepts(_ old: HelperInstallerProvisioningBundle, _ new: HelperInstallerProvisioningBundle) -> Bool {
    (try? HelperClientCodeIdentityRotationPolicy.validate(previous: old, next: new)) != nil
}
let old = bundle(10)
check("valid monotonic CDHash rotation accepted", accepts(old, bundle(11, String(repeating: "c", count: 40))))
check("generation rollback rejected", !accepts(old, bundle(9, String(repeating: "c", count: 40))))
check("Team ID change rejected", !accepts(old, bundle(11, String(repeating: "c", count: 40), "ZZZZZ99999")))
check("Bundle ID change rejected", !accepts(old, bundle(11, String(repeating: "c", count: 40), "ABCDE12345", String(repeating: "b", count: 40), "cn.other.app")))
check("Helper pin change rejected", !accepts(old, bundle(11, String(repeating: "c", count: 40), "ABCDE12345", String(repeating: "d", count: 40))))
print("\(passed)/5 assertions passed")
