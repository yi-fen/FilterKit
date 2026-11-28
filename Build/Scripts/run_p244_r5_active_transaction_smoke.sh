#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${TMPDIR:-/tmp}/p244-r5-active-transaction-smoke"
swiftc "$ROOT/Sources/Environment/SHA256Digest.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerActiveReleasePointerWriter.swift" \
  "$ROOT/Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift" \
  "$ROOT/Build/scripts/p244_r5_active_transaction_smoke.swift" -o "$OUT"
"$OUT"
