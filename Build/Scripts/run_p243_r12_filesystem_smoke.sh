#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/Build/scripts/p243_r12_filesystem_smoke.swift" "$TMP/main.swift"
swiftc \
  "$ROOT/Sources/Environment/SHA256Digest.swift" \
  "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerDescriptorFilesystemObserver.swift" \
  "$TMP/main.swift" -o "$TMP/p243_r12_filesystem_smoke"
"$TMP/p243_r12_filesystem_smoke"
