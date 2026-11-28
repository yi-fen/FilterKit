#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${TMPDIR:-/tmp}/p244-r4-previous-release-smoke"
swiftc "$ROOT/Sources/Environment/SHA256Digest.swift" "$ROOT/Sources/Environment/MachOMetadataReader.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerPreviousReleaseStore.swift" \
  "$ROOT/Build/scripts/p244_r4_previous_release_smoke.swift" -o "$OUT"
"$OUT"
