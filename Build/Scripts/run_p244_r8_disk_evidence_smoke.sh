#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${TMPDIR:-/tmp}/p244-r8-disk-evidence-smoke"
swiftc "$ROOT/Sources/Environment/SHA256Digest.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerStagedReleaseStore.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerPreviousReleaseStore.swift" \
  "$ROOT/Build/scripts/p244_r8_disk_evidence_smoke.swift" -o "$OUT"
"$OUT"
