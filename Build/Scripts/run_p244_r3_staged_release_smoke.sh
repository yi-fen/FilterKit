#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${TMPDIR:-/tmp}/p244-r3-staged-release-smoke"
swiftc \
  "$ROOT/Sources/Environment/SHA256Digest.swift" \
  "$ROOT/Sources/Environment/MachOMetadataReader.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerStagedReleaseStore.swift" \
  "$ROOT/Build/scripts/p244_r3_staged_release_smoke.swift" \
  -o "$OUT"
"$OUT"
