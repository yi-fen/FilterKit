#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$ROOT"
SOURCES=(
  Build/Host/P2-37-R3-HelperPolicy-HostShim.swift
  Sources/Core/Models/PluginModels.swift
  Sources/Core/Models/PluginFilterConfiguration.swift
  Sources/Core/Models/FilterKitPluginManifest.swift
  Sources/Core/Models/PluginScanModels.swift
  Sources/Environment/Models/PluginDirectoryDiagnostics.swift
  Sources/Core/Models/PluginManagementPermission.swift
  Sources/Core/Models/Helper/HelperPluginIdentityAttestationModels.swift
  Sources/Core/Models/AppPluginActivationModels.swift
  Sources/Core/Models/PluginIdentityVerificationResult.swift
  Sources/Core/Models/AppPluginActivationPreviewLedger.swift
  Sources/Environment/Deployment/AppPluginActivationStateResolver.swift
  Build/Host/P2-37-R3-Activation-Consistency-Smoke.swift
)
swiftc "${SOURCES[@]}" -o "$TMP/p237r3-smoke"
"$TMP/p237r3-smoke"
