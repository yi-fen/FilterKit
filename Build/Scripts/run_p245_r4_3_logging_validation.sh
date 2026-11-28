#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
python3 Build/scripts/p245_r4_3_logging_audit.py
swiftc Sources/Environment/RuntimeEventLogger.swift Build/Host/RuntimeEventLoggerSmoke.swift -o /tmp/filterkit-p245-r4_3-logger-smoke
/tmp/filterkit-p245-r4_3-logger-smoke
bash -n Build/scripts/run_p245_r4_3_logging_validation.sh
sh -n Build/scripts/p245_r4_3_collect_helper_audit.sh
