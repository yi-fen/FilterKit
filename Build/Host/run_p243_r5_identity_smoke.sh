#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/Build/Host/p243_r5_code_identity_smoke.swift" "$TMP/main.swift"
swiftc "$ROOT/Sources/Environment/Helper/Transport/HelperCodeSigningIdentityBindingPolicy.swift" \
  "$TMP/main.swift" -o "$TMP/p243-r5-identity-smoke"
"$TMP/p243-r5-identity-smoke"
