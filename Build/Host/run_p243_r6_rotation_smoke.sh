#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/Build/Host/p243_r6_rotation_smoke.swift" "$TMP/main.swift"
swiftc "$ROOT/Sources/Core/Models/Helper/HelperClientCodeIdentityRotationPolicy.swift" "$TMP/main.swift" -o "$TMP/p243-r6-rotation-smoke"
"$TMP/p243-r6-rotation-smoke"
