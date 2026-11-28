#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="${TMPDIR:-/tmp}/p244-r15-build"
OUT="${TMPDIR:-/tmp}/p244-r15-store-write-smoke"
mkdir -p "$TMP_DIR"
MAIN="$TMP_DIR/main.swift"
cp "$ROOT/Build/scripts/p244_r15_store_write_integration_smoke.swift" "$MAIN"
swiftc -parse-as-library \
  "$ROOT/Sources/Environment/SHA256Digest.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerTransactionJournal.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerDurableJournalStore.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerStagedReleaseStore.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerPreviousReleaseStore.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperTrustedInstallerCoordinator.swift" \
  "$MAIN" -o "$OUT"
"$OUT"
