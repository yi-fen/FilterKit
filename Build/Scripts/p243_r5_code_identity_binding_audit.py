#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
checks = {
    "identity model carries OS-observed identifier": (root/"Sources/Core/Models/Helper/HelperIPCModels.swift", "verifiedCodeIdentifier"),
    "identity model carries OS-observed Team ID": (root/"Sources/Core/Models/Helper/HelperIPCModels.swift", "verifiedTeamIdentifier"),
    "runtime requires provisioned bundle and Team ID": (root/"Sources/Environment/Helper/Runtime/HelperTrustConfigurationValidator.swift", "missingClientCodeIdentity"),
    "runtime trust binds expected bundle": (root/"Sources/Environment/Helper/Runtime/HelperRuntime.swift", "expectedBundleIdentifier: manifest.allowedClientBundleIdentifier"),
    "runtime trust binds expected Team ID": (root/"Sources/Environment/Helper/Runtime/HelperRuntime.swift", "expectedTeamIdentifier: manifest.allowedClientTeamIdentifier"),
    "Darwin provider uses audit-token SecTask": (root/"Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift", "SecTaskCreateWithAuditToken"),
    "Darwin provider reads signed identifier": (root/"Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift", "SecTaskCopySigningIdentifier"),
    "Darwin provider reads signed Team ID entitlement": (root/"Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift", "com.apple.developer.team-identifier"),
    "HelperPolicy checks verified code identity": (root/"Sources/Core/Models/Helper/HelperDeploymentModels.swift", "HelperPeerIdentityBindingPolicy.codeSigningIdentityMatches(peer"),
    "bundle and Team ID comparison is centralized": (root/"Sources/Environment/Helper/Transport/HelperCodeSigningIdentityBindingPolicy.swift", "codeSigningIdentityMatches"),
    "installer pins Bundle ID": (root/"Sources/Core/Models/Helper/HelperTrustProvisioning.swift", "allowedClientBundleIdentifier: bundleIdentifier"),
    "installer propagates Team ID": (root/"Sources/Core/Models/Helper/HelperInstallerProvisioning.swift", "clientTeamIdentifier: teamIdentifier"),
    "Helper target compiles identity policy extension": (root/"Project.yml", "HelperCodeSigningIdentityBindingPolicy.swift"),
}
failed=[]
for label,(path,needle) in checks.items():
    ok=needle in path.read_text()
    print(("PASS" if ok else "FAIL")+" "+label)
    if not ok: failed.append(label)
print(f"RESULT {len(checks)-len(failed)}/{len(checks)}")
raise SystemExit(bool(failed))
