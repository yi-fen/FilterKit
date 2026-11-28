#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
OUT="${TMPDIR:-/tmp}/p244-r2-durable-store-smoke-$$"
trap 'rm -f "$OUT"' EXIT
swiftc "$ROOT/Sources/Environment/SHA256Digest.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerTransactionJournal.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerDurableJournalStore.swift" \
  "$ROOT/Build/scripts/p244_r2_durable_store_smoke.swift" -o "$OUT"
"$OUT"
