#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${TMPDIR:-/tmp}/p244-r18-recovery-boundary-completion"
cd "$ROOT"
swiftc -parse-as-library \
  "$ROOT/Sources/Environment/SHA256Digest.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerTransactionJournal.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerDurableJournalStore.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerStagedReleaseStore.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerPreviousReleaseStore.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperTrustedInstallerCoordinator.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerAuthenticatedServiceObserver.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerActiveReleasePointerWriter.swift" \
  "$ROOT/Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift" \
  "$ROOT/Build/scripts/p244_r18_recovery_boundary_completion.swift" -o "$OUT"
"$OUT"
