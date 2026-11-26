#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${TMPDIR:-/tmp}/filterkit-p225-authorized-recovery-smoke"
cd "$ROOT"
swiftc \
  Sources/Core/Models/FilterKitPluginManifest.swift \
  Sources/Core/Models/Helper/*.swift \
  Sources/Environment/SHA256Digest.swift \
  Sources/Environment/Helper/Execution/*.swift \
  Sources/Environment/Helper/Runtime/*.swift \
  Sources/Environment/Helper/Installer/*.swift \
  Sources/Environment/Helper/Transport/HelperPeerAuthenticationDiagnostics.swift \
  Sources/Environment/Helper/HelperDeploymentCoordinator.swift \
  Sources/Environment/Deployment/RootHideElleKitFilterStrategy.swift \
  Sources/Environment/MachOMetadataReader.swift \
  Sources/Environment/Models/ElleKitVersionMetadata.swift \
  Sources/Environment/Models/JailbreakPaths.swift \
  Sources/Environment/LibrootRuntimeProbe.swift \
  Build/Scripts/p2-25-authorized-recovery-smoke.swift \
  -o "$OUT"
"$OUT"
