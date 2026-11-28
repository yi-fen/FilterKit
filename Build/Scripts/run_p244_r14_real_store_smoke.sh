#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${TMPDIR:-/tmp}/p244-r14-real-store-smoke"
TMP_DIR="${TMPDIR:-/tmp}/p244-r14-build"
mkdir -p "$TMP_DIR"
TMP_MAIN="$TMP_DIR/main.swift"
cp "$ROOT/Build/scripts/p244_r14_real_store_smoke.swift" "$TMP_MAIN"
swiftc \
  "$ROOT/Sources/Environment/SHA256Digest.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerTransactionJournal.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerDurableJournalStore.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerStagedReleaseStore.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerPreviousReleaseStore.swift" \
  "$TMP_MAIN" -o "$OUT"
"$OUT"
