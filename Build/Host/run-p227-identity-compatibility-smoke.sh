#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc -o "$TMP/p227-compatibility-smoke" \
  Sources/Core/Models/FilterKitPluginManifest.swift \
  Sources/Core/Models/Helper/*.swift \
  Sources/Environment/Helper/Execution/HelperDeploymentRouteResolver.swift \
  Sources/Environment/SHA256Digest.swift \
  Build/Scripts/p2-27-compatibility-smoke.swift
"$TMP/p227-compatibility-smoke"
python3 Build/scripts/p227_static_gate_audit.py
