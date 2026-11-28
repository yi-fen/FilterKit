#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
activation = (root / "Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift").read_text()
smoke = (root / "Build/scripts/p244_r17_recovery_fault_matrix.swift").read_text()
runner = (root / "Build/scripts/run_p244_r17_recovery_fault_matrix.sh").read_text()
start = activation.index("// Validate the complete rollback set before changing any Active destination.")
preflight_end = activation.index("record.phase = .rollingBack", start)
preflight = activation[start:preflight_end]
mutation_start = activation.index("record.phase = .rollingBack", start)
mutation_end = activation.index("record.phase = .rolledBack", mutation_start)
mutation = activation[mutation_start:mutation_end]
checks = [
    ("R17 compiles production activation executor", "HelperRootAtomicActivationExecutor.swift" in runner),
    ("R17 compiles production Durable Journal Store", "HelperInstallerDurableJournalStore.swift" in runner),
    ("R17 compiles production Previous and Staged Stores", "HelperInstallerPreviousReleaseStore.swift" in runner and "HelperInstallerStagedReleaseStore.swift" in runner),
    ("R17 uses Coordinator.prepare", "coordinator.prepare(" in smoke),
    ("R17 uses real Previous preserve", "previousStore.preserve(" in smoke),
    ("R17 uses real Staged stage", "stagedStore.stage(" in smoke),
    ("R17 uses prepared production activation overload", "prepared:preparedCase" in smoke),
    ("R17 uses durable recovery overload", "executor.recover(durableJournal:" in smoke),
    ("Executable activation crash boundary exercised", '"crash after executable rename"' in smoke),
    ("Deployment manifest activation crash boundary exercised", '"crash after deployment manifest rename"' in smoke),
    ("Launch daemon activation crash boundary exercised", '"crash after launch daemon rename"' in smoke),
    ("Partial rollback asserts manual intervention", "rollback requires explicit manual intervention" in smoke),
    ("Partial rollback verifies all previous Active bytes", "restored to prior bytes" in smoke),
    ("Partial rollback verifies idempotency", "second recovery is idempotent" in smoke),
    ("Unknown Active bytes test blocks recovery", "unknown Active bytes block recovery" in smoke),
    ("Unknown Active bytes test verifies no overwrite", "unknown Active bytes remain untouched" in smoke),
    ("Unknown Active bytes move Durable Journal to manual intervention", "unknown Active bytes mark Durable Journal manual intervention" in smoke),
    ("Unknown Active state remains blocked on repeat", "unknown Active manual state remains blocked on repeated recovery" in smoke),
    ("Rollback preflight checks every artifact", "for item in Artifact.allCases.reversed()" in preflight),
    ("Rollback preflight classifies current Active hashes", "currentIsKnown" in preflight),
    ("Rollback preflight classifies backup hashes", "backupIsKnown" in preflight),
    ("Rollback preflight requires sufficient trusted backup", "backupIsSufficient" in preflight),
    ("Rollback preflight occurs before rollingBack phase", start < mutation_start),
    ("Rollback preflight performs no Active unlink", "unlinkat" not in preflight),
    ("Rollback mutation occurs only after preflight", "record.phase = .rollingBack" in mutation),
    ("Unknown or missing evidence persists manual record", "record.phase = .manualIntervention" in preflight and "writeRecord(record, rootFD: rootFD)" in preflight),
    ("Unknown or missing evidence marks Durable Journal manual", "manual.apply(.requireManualIntervention)" in preflight),
    ("Service-start APIs absent from executor", all(x not in activation for x in ("launchctl", "bootstrap", "kickstart"))),
    ("Smoke confirms no service-start operation", "activation and recovery contain no service-start operation" in smoke),
]
failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(("PASS" if ok else "FAIL") + ": " + name)
print(f"RESULT: {len(checks)-len(failed)}/{len(checks)}")
if failed:
    sys.exit(1)
