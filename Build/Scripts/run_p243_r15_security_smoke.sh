#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/Build/scripts/p243_r15_security_smoke.swift" "$TMP/main.swift"
swiftc "$TMP/main.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerAuthenticatedServiceObserver.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerCrashInjectionMatrix.swift" \
  -o "$TMP/p243-r15-smoke"
"$TMP/p243-r15-smoke"
