#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/Build/scripts/p243_r16_dryrun_smoke.swift" "$TMP/main.swift"
swiftc "$TMP/main.swift" "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerRecoveryDryRun.swift" -o "$TMP/p243-r16-dryrun"
"$TMP/p243-r16-dryrun"
