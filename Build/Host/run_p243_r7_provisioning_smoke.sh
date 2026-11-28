#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/Build/Host/p243_r7_provisioning_smoke.swift" "$TMP/main.swift"
swiftc "$ROOT/Sources/Core/Models/Helper/HelperSignedProvisioningManifest.swift" "$TMP/main.swift" -o "$TMP/p243-r7-provisioning-smoke"
"$TMP/p243-r7-provisioning-smoke"
