#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$ROOT"
swiftc \
  Sources/Core/Models/InstalledApp.swift \
  Sources/Core/Models/PluginAssociationReadModels.swift \
  Sources/Core/Models/PluginAssociationPlan.swift \
  Build/Host/P2-35-Soft-Association-Smoke.swift \
  -o "$TMP/p235-soft-association-smoke"
"$TMP/p235-soft-association-smoke"
python3 Build/scripts/p235_soft_association_audit.py
