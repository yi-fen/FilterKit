#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$ROOT"
swiftc \
  Sources/Environment/SHA256Digest.swift \
  Sources/Environment/Models/*.swift \
  Sources/Environment/Profiles/*.swift \
  Sources/Environment/Deployment/EnableDisableStrategy.swift \
  Sources/Environment/MachOMetadataReader.swift \
  Sources/Core/Models/*.swift \
  Sources/Environment/PluginDirectoryLocator.swift \
  Sources/Environment/ReadOnlyPluginScanner.swift \
  Sources/Environment/PluginIdentityAnalyzer.swift \
  Build/Host/P2-33-Plugin-Identity-Smoke.swift \
  -o "$TMP/p233-smoke"
"$TMP/p233-smoke"
