#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${TMPDIR:-/tmp}/filterkit-p215-audit-smoke"
cd "$ROOT"
swiftc Sources/Environment/Helper/Runtime/HelperAuditFileSink.swift \
  Build/Host/P2-15-Audit-Sink-Smoke.swift -o "$OUT"
"$OUT"
