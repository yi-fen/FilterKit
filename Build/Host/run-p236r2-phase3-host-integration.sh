#!/bin/sh
# Host-side live AF_UNIX integration check. This is not a substitute for Darwin peer identity.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT"
command -v swiftc >/dev/null 2>&1 || { echo 'ERROR: swiftc is required' >&2; exit 2; }
HELPER_SOURCES="$(find HelperRuntime Sources/Core/Models/Helper Sources/Environment/Helper/Transport Sources/Environment/Helper/Runtime Sources/Environment/Helper/Execution Sources/Environment/Helper/Installer -name '*.swift' ! -name 'FilterKitHelperMain.swift' -print)"
BIN="$(mktemp "${TMPDIR:-/tmp}/p236r2-phase3-ipc.XXXXXX")"
trap 'rm -f "$BIN"' EXIT HUP INT TERM
swiftc -parse-as-library -o "$BIN" $HELPER_SOURCES \
  Sources/Environment/Helper/HelperDeploymentCoordinator.swift \
  Sources/Core/Models/FilterKitPluginManifest.swift \
  Sources/Environment/Deployment/RootHideElleKitFilterStrategy.swift \
  Sources/Environment/MachOMetadataReader.swift \
  Sources/Environment/Models/ElleKitVersionMetadata.swift \
  Sources/Environment/SHA256Digest.swift \
  Sources/Environment/Models/JailbreakPaths.swift \
  Sources/Environment/LibrootRuntimeProbe.swift \
  Build/Host/P2-36-R2-Phase3-IPC-Integration-Smoke.swift
"$BIN"
