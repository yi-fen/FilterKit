#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc -o "$TMP/p228-toggle-release-smoke" \
  Sources/Environment/Deployment/EnableDisableStrategy.swift \
  Sources/Environment/Deployment/PluginToggleReleaseGate.swift \
  Build/Scripts/p2-28-toggle-release-smoke.swift
"$TMP/p228-toggle-release-smoke"
python3 Build/scripts/p228_toggle_release_audit.py
