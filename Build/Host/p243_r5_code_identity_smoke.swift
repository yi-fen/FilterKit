import Foundation
enum HelperPeerIdentityBindingPolicy {}
struct HelperPeerIdentity {
    let verifiedCodeIdentifier: String?
    let verifiedTeamIdentifier: String?
}
let valid = HelperPeerIdentity(verifiedCodeIdentifier: "cn.yfen.filterkit", verifiedTeamIdentifier: "ABCDE12345")
let wrongBundle = HelperPeerIdentity(verifiedCodeIdentifier: "com.attacker.clone", verifiedTeamIdentifier: "ABCDE12345")
let wrongTeam = HelperPeerIdentity(verifiedCodeIdentifier: "cn.yfen.filterkit", verifiedTeamIdentifier: "ZZZZZ99999")
let absent = HelperPeerIdentity(verifiedCodeIdentifier: nil, verifiedTeamIdentifier: nil)
let checks: [(String, Bool)] = [
    ("matching signed Bundle ID + Team ID accepted", HelperPeerIdentityBindingPolicy.codeSigningIdentityMatches(valid, bundleIdentifier: "CN.YFEN.FILTERKIT", teamIdentifier: "ABCDE12345")),
    ("wrong Bundle ID rejected", !HelperPeerIdentityBindingPolicy.codeSigningIdentityMatches(wrongBundle, bundleIdentifier: "cn.yfen.filterkit", teamIdentifier: "ABCDE12345")),
    ("wrong Team ID rejected", !HelperPeerIdentityBindingPolicy.codeSigningIdentityMatches(wrongTeam, bundleIdentifier: "cn.yfen.filterkit", teamIdentifier: "ABCDE12345")),
    ("missing OS identity rejected", !HelperPeerIdentityBindingPolicy.codeSigningIdentityMatches(absent, bundleIdentifier: "cn.yfen.filterkit", teamIdentifier: "ABCDE12345"))
]
for (name, passed) in checks { print("\(passed ? "PASS" : "FAIL") \(name)") }
print("RESULT \(checks.filter { $0.1 }.count)/\(checks.count)")
if checks.contains(where: { !$0.1 }) { exit(1) }
