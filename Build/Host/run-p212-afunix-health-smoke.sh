#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${TMPDIR:-/tmp}/filterkit-p212-afunix-health-smoke"
cd "$ROOT"
swiftc \
  Sources/Core/Models/FilterKitPluginManifest.swift \
  Sources/Environment/SHA256Digest.swift \
  Sources/Core/Models/Helper/HelperDeploymentModels.swift \
  Sources/Core/Models/Helper/HelperIPCModels.swift \
  Sources/Core/Models/Helper/HelperHandshake.swift \
  Sources/Environment/Helper/Execution/HelperDeploymentRouteResolver.swift \
  Build/Host/P2-12-Transport-Protocol-Stub.swift \
  Sources/Environment/Helper/Transport/HelperPeerAuthenticationDiagnostics.swift \
  Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift \
  Build/Host/P2-12-AFUnix-Health-Smoke.swift \
  -o "$OUT"
"$OUT"
