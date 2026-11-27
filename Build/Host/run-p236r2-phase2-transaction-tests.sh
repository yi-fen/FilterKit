#!/bin/sh
# Main entry point: run host transaction/IPC smoke, then XCTest when Apple tooling is present.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
"$ROOT/Build/Host/run-p236r2-phase2-host-smoke.sh"
if command -v xcodebuild >/dev/null 2>&1 && command -v xcodegen >/dev/null 2>&1; then
  "$ROOT/Build/Host/run-p236r2-phase2-xcode-tests.sh"
else
  echo 'SKIP Xcode XCTest: requires macOS + Xcode + XcodeGen; host transaction smoke completed.'
fi
