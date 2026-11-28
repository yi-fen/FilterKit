#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
activation = (root / "Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift").read_text()
pointer = (root / "Sources/Environment/Helper/Runtime/HelperInstallerActiveReleasePointerWriter.swift").read_text()
staged = (root / "Sources/Environment/Helper/Runtime/HelperInstallerStagedReleaseStore.swift").read_text()
previous = (root / "Sources/Environment/Helper/Runtime/HelperInstallerPreviousReleaseStore.swift").read_text()
journal = (root / "Sources/Environment/Helper/Runtime/HelperInstallerDurableJournalStore.swift").read_text()
smoke = (root / "Build/scripts/p244_r16_full_upgrade_smoke.swift").read_text()
runner = (root / "Build/scripts/run_p244_r16_full_upgrade_smoke.sh").read_text()
checks = [
    ("R16 compiles the production activation executor", "HelperRootAtomicActivationExecutor.swift" in runner),
    ("R16 compiles the production Active Pointer writer", "HelperInstallerActiveReleasePointerWriter.swift" in runner),
    ("R16 compiles the production Coordinator", "HelperTrustedInstallerCoordinator.swift" in runner),
    ("R16 compiles the production Staged Store", "HelperInstallerStagedReleaseStore.swift" in runner),
    ("R16 compiles the production Previous Store", "HelperInstallerPreviousReleaseStore.swift" in runner),
    ("R16 compiles the production Durable Journal Store", "HelperInstallerDurableJournalStore.swift" in runner),
    ("R16 compiles the production authenticated Observer validator", "HelperInstallerAuthenticatedServiceObserver.swift" in runner),
    ("Prepared value originates from Coordinator.prepare", "coordinator.prepare(" in smoke and "struct HelperPreparedRootInstall" not in smoke),
    ("Real Previous preserve is executed", "previousStore.preserve(" in smoke),
    ("Real Staged stage is executed", "stagedStore.stage(" in smoke),
    ("Durable Journal is reloaded from disk", "journalStore.load(transactionID:" in smoke),
    ("Activation intent is persisted before execution", "apply(.intentActivateRelease)" in smoke and "journalStore.save(activationJournal)" in smoke),
    ("Production prepared activation overload is called", "prepared:prepared" in smoke and "stagedInspection:" not in smoke),
    ("Upgrade supplies verified Previous Release", "previousRelease:oldVerified,previousStore:previousStore" in smoke),
    ("Activation validates signed Envelope digest", "SHA256Digest.hex(prepared.provisioningEnvelopeData) == prepared.provisioningEnvelopeSHA256" in activation),
    ("Activation reloads real Staged bytes", "stagedStore.loadVerifiedArtifactsForActivation" in activation),
    ("Activation reloads real Previous bytes", "previousStore.loadVerifiedArtifactsForActivation" in activation),
    ("Activation verifies Staged bytes against release bytes", "stagedBytes[artifact] == release.bytes" in activation),
    ("Activation validates authenticated stopped-service observation", "HelperInstallerAuthenticatedServiceObserver.validate" in activation and "observation.state == .stopped" in activation),
    ("Activation acquires persistent root transaction lock", "acquireTransactionLock(rootFD)" in activation),
    ("Active artifacts are re-hashed before Pointer publication", "observedPointerHashes[artifact] = observed" in activation),
    ("Pointer writer requires exact three-artifact hash set", "release.hashes == observedActiveHashes" in pointer),
    ("Pointer writer uses private temporary file", "0o600" in pointer and "openat(parentFD" in pointer),
    ("Pointer writer fsyncs file and parent directory", "fsync(fd)" in pointer and "fsync(parentFD)" in pointer),
    ("Pointer publication uses atomic renameat", "renameat(parentFD" in pointer),
    ("Post-write verification checks pointer transaction identity", "pointer.transactionID == record.id" in activation),
    ("Post-write verification checks Journal activated state", "durableJournal.state == .activated" in activation),
    ("Pointer fault injection is exercised", "faultAt:.beforePointerRename" in smoke),
    ("Committed Pointer failure is recovered", "executor.recover(durableJournal:committedBeforeRecovery" in smoke),
    ("Recovery is checked for idempotency", "secondRecovery == nil" in smoke),
    ("Previous Store preserves actual Active bytes", "readActiveArtifact(path" in previous),
    ("Staged Store uses descriptor-relative no-follow opens", "openat(directoryFD" in staged and "O_NOFOLLOW" in staged),
    ("Journal store fsyncs file and directory", "fsync(fd)" in journal and "fsync(directoryFD)" in journal),
]
failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(("PASS" if ok else "FAIL") + ": " + name)
print(f"RESULT: {len(checks)-len(failed)}/{len(checks)}")
if failed:
    sys.exit(1)
