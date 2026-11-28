#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
python3 "$ROOT/Build/scripts/p244_r11_prepared_activation_audit.py"
bash "$ROOT/Build/scripts/run_p244_r5_active_transaction_smoke.sh"
bash "$ROOT/Build/scripts/run_p244_r8_disk_evidence_smoke.sh"
bash "$ROOT/Build/scripts/run_p244_r10_validation.sh"
