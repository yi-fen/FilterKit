#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sed -n '1,267p' "$ROOT/Sources/Environment/Helper/Runtime/HelperInstallerDescriptorFilesystemObserver.swift" > "$TMP/HelperInstallerDescriptorFilesystemObserver-Core.swift"
swiftc "$ROOT/Sources/Environment/SHA256Digest.swift" "$TMP/HelperInstallerDescriptorFilesystemObserver-Core.swift" "$ROOT/Build/scripts/p245_r3_filesystem_smoke.swift" -o "$TMP/p245-r3-filesystem-smoke"
"$TMP/p245-r3-filesystem-smoke"
python3 "$ROOT/Build/scripts/p245_r3_filesystem_audit.py"
