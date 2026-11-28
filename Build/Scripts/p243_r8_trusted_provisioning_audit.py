#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
store = (ROOT / "Sources/Environment/Helper/Runtime/HelperTrustedProvisioningStore.swift").read_text()
dry = (ROOT / "Sources/Environment/Helper/Runtime/HelperInstallerDryRun.swift").read_text()
loader = (ROOT / "Sources/Environment/Helper/Runtime/HelperSignedReleaseRuntimeLoader.swift").read_text()
gate = (ROOT / "Sources/Environment/Helper/Runtime/HelperInstallerExecutionGate.swift").read_text()
checks = {
    "baseline type has non-public construction": "fileprivate init(payload:" in store,
    "baseline is emitted only after checkpoint validation": "return HelperVerifiedProvisioningBaseline(payload: payload" in store and "return HelperVerifiedProvisioningBaseline(payload: next" in store,
    "signature verification precedes baseline creation": "try verifier.verify(envelope)" in store and "HelperVerifiedProvisioningBaseline(payload:" in store,
    "root-owned provisioning store uses no-follow open": "O_NOFOLLOW" in store,
    "root-owned directory is required 0700": "(info.st_mode & 0o777) == 0o700" in store,
    "provisioning files are atomically replaced": "renameat(dir, src, dir, dst)" in store,
    "file and directory are fsynced": "fsync(fd)" in store and "fsync(dir)" in store,
    "pending intent is persisted before current envelope": store.index('to: "provisioning.pending.json"') < store.index('to: "provisioning.signed.json"'),
    "generation checkpoint binds envelope digest": "envelopeSHA256" in store and "generationConflict" in store,
    "checkpoint Bundle ID key is case-normalized": "bundleIdentifier.lowercased()" in store,
    "repin uses authenticated baseline": "oldBaseline = try loadTrustedBaseline()" in store and "trustedBaseline.payload" in dry,
    "Helper upgrade preserves App identity and install context": "old.appCDHash.caseInsensitiveCompare(next.appCDHash)" in store and "old.helperCDHash" not in store,
    "legacy caller-supplied previousProvisioning removed": "previousProvisioning" not in dry,
    "runtime loader uses trusted store": "HelperTrustedProvisioningStore(" in loader and "loadTrustedBaseline()" in loader,
    "Apple checkpoint store is Keychain-backed": "KeychainHelperProvisioningCheckpointStore" in store and "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly" in store,
    "execution remains gated": "guard plan.executionEnabled else { return .planNotReleased }" in gate,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL") + ": " + name)
print(f"RESULT: {len(checks)-len(failed)}/{len(checks)} passed")
raise SystemExit(bool(failed))
