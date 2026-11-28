#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
loader = (root / 'Sources/Environment/Helper/Runtime/HelperSignedReleaseRuntimeLoader.swift').read_text()
envelope = (root / 'Sources/Core/Models/Helper/HelperSignedProvisioningManifest.swift').read_text()
journal = (root / 'Sources/Environment/Helper/Runtime/HelperInstallerTransactionJournal.swift').read_text()
trusted_store = (root / 'Sources/Environment/Helper/Runtime/HelperTrustedProvisioningStore.swift').read_text()
checks = {
    'trusted store reads signed provisioning artifact': 'provisioning.signed.json' in trusted_store,
    'runtime no longer reads unsigned provisioning.json': 'base + "/provisioning.json"' not in loader,
    'runtime delegates provisioning load to trusted verifier/store': 'loadTrustedBaseline()' in loader and 'HelperTrustedProvisioningStore(' in loader,
    'trusted store verifies signed envelope before payload acceptance': 'try verifier.verify(envelope)' in trusted_store,
    'canonical sorted JSON signing bytes': '.sortedKeys' in envelope and '.withoutEscapingSlashes' in envelope,
    'Ed25519-only envelope': 'guard algorithm == Self.ed25519Algorithm' in envelope,
    'key generation bounds enforced': 'envelope.payload.generation < minimum' in envelope and 'envelope.payload.generation > maximum' in envelope,
    'revoked key rejected': 'key.status != .revoked' in envelope,
    'journal recovery validates legal transitions': 'Self.replay(entry.event, state: expectedPriorState' in journal and 'expectedPending == pendingOperation' in journal,
    'repin requires durable preserve intent before stage intent': 'intentPreservePreviousRelease' in journal and 'guard pendingOperation == .preservePreviousRelease' in journal and 'intentStageRelease' in journal,
}
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ' ' + name)
print(f'{sum(checks.values())}/{len(checks)} assertions passed')
raise SystemExit(0 if all(checks.values()) else 1)
