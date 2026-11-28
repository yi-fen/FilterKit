#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/Build/scripts/p243_r14_preflight_smoke.swift" "$TMP/main.swift"
swiftc "$TMP/main.swift" "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerRecoveryPreflight.swift" -o "$TMP/p243-r14-smoke"
"$TMP/p243-r14-smoke"
