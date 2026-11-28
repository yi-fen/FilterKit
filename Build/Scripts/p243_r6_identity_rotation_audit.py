#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
policy = (root / "Sources/Core/Models/Helper/HelperClientCodeIdentityRotationPolicy.swift").read_text()
provider = (root / "Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift").read_text()
tests = (root / "Tests/UnitTests/HelperClientCodeIdentityRotationPolicyTests.swift").read_text()
dryrun = (root / "Sources/Environment/Helper/Runtime/HelperInstallerDryRun.swift").read_text()
checks = {
    "rotation requires strictly increasing generation": "next.generation > previous.generation" in policy,
    "rotation requires one-step generation": "next.generation == previous.generation + 1" in policy,
    "Bundle ID continuity enforced": "bundleIdentifierChanged" in policy and "previous.bundleIdentifier.caseInsensitiveCompare(next.bundleIdentifier)" in policy,
    "Team ID continuity enforced": "teamIdentifierChanged" in policy and "oldTeam == newTeam" in policy,
    "client UID continuity enforced": "previous.allowedClientUID == next.allowedClientUID" in policy,
    "Helper CDHash cannot rotate with App pin": "helperIdentityChanged" in policy,
    "App CDHash must actually change": "Failure.noRotation" in policy,
    "self CDHash no longer calls peer identity": "try readCDHash(pid: getpid())" in provider and "return try identity(for: credentials).cdHashHex" not in provider,
    "peer identity still reads socket audit token": "readAuditToken(socketFD)" in provider,
    "peer identity still rechecks token after CDHash": "beforeToken == afterToken" in provider,
    "tests cover team identity change": "Team identity" in tests or "team: \"ZZZZZ99999\"" in tests,
    "tests cover generation rollback": "testRejectsSameOrRegressedGeneration" in tests,
    "repin dry-run requires verifier-issued trusted baseline": "repinBaselineRequired" in dryrun and "HelperVerifiedProvisioningBaseline" in dryrun and "trustedBaseline.payload" in dryrun,
    "repin dry-run invokes rotation policy": "HelperClientCodeIdentityRotationPolicy.validate" in dryrun,
    "repin dry-run remains non-writing": "writesPerformed: false" in dryrun and "executionEnabled: false" in dryrun,
}
for name, ok in checks.items(): print(("PASS" if ok else "FAIL") + ": " + name)
print(f"{sum(checks.values())}/{len(checks)} assertions passed")
raise SystemExit(0 if all(checks.values()) else 1)
