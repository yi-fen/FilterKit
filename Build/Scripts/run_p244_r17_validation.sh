#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
python3 Build/scripts/p244_r17_recovery_fault_matrix_audit.py
Build/scripts/run_p244_r17_recovery_fault_matrix.sh
python3 Build/scripts/p244_r16_full_upgrade_audit.py
Build/scripts/run_p244_r16_full_upgrade_smoke.sh
python3 Build/scripts/p244_r15_store_write_integration_audit.py
Build/scripts/run_p244_r15_store_write_integration_smoke.sh
