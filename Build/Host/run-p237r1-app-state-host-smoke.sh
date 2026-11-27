#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
python3 Build/scripts/p237r1_app_state_audit.py
Build/Host/run-p237-activation-host-smoke.sh
