#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
OUT="$(mktemp -d)"
cp Build/Host/p243_r8_provisioning_store_smoke.swift "$OUT/main.swift"
trap 'rm -rf "$OUT"' EXIT
swiftc \
  Build/Host/p243_r8_typecheck_stubs.swift \
  Sources/Environment/SHA256Digest.swift \
  Sources/Core/Models/Helper/HelperInstallerProvisioning.swift \
  Sources/Core/Models/Helper/HelperSignedProvisioningManifest.swift \
  Sources/Core/Models/Helper/HelperClientCodeIdentityRotationPolicy.swift \
  Sources/Environment/Helper/Runtime/HelperTrustedProvisioningStore.swift \
  "$OUT/main.swift" \
  -o "$OUT/p243_r8_smoke"
"$OUT/p243_r8_smoke"
