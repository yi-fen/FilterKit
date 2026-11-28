#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/Build/scripts/p243_r11_crash_recovery_smoke.swift" "$TMP/main.swift"
swiftc \
  "$ROOT/Sources/Environment/SHA256Digest.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerTransactionJournal.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerTransactionExecution.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerDurableJournalStore.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerRecoveryAssessment.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerCrashRecoveryEngine.swift" \
  "$TMP/main.swift" -o "$TMP/p243_r11_crash_recovery_smoke"
"$TMP/p243_r11_crash_recovery_smoke"
