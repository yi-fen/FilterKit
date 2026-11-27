#!/bin/sh
# Cross-platform host validation; filesystem mutations are isolated to temporary directories.
# This does not deploy to a jailbreak device or open production write gates.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT"
python3 "$ROOT/Build/scripts/p236r2_phase2_transaction_audit.py"
find "$ROOT/Sources" "$ROOT/App" "$ROOT/HelperRuntime" "$ROOT/Tests" "$ROOT/Build/Host" -name '*.swift' -print0 | xargs -0 swiftc -frontend -parse
printf '%s\n' 'PASS Swift source and test syntax parse'

HELPER_SOURCES="$(find HelperRuntime Sources/Core/Models/Helper Sources/Environment/Helper/Transport Sources/Environment/Helper/Runtime Sources/Environment/Helper/Execution Sources/Environment/Helper/Installer -name '*.swift' ! -name 'FilterKitHelperMain.swift' -print)"
swiftc -typecheck $HELPER_SOURCES \
  Sources/Environment/Helper/HelperDeploymentCoordinator.swift \
  Sources/Core/Models/FilterKitPluginManifest.swift \
  Sources/Environment/Deployment/RootHideElleKitFilterStrategy.swift \
  Sources/Environment/MachOMetadataReader.swift \
  Sources/Environment/Models/ElleKitVersionMetadata.swift \
  Sources/Environment/SHA256Digest.swift \
  Sources/Environment/Models/JailbreakPaths.swift \
  Sources/Environment/LibrootRuntimeProbe.swift
printf '%s\n' 'PASS FilterKitHelper target source-set semantic typecheck (host Swift SDK)'

BIN="$(mktemp "${TMPDIR:-/tmp}/p236r2-transaction-smoke.XXXXXX")"
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
  Build/Host/P2-36-R2-Transaction-Smoke.swift
"$BIN"
