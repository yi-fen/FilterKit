#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
python3 "$ROOT/Build/scripts/p244_r10_e2e_boundary_audit.py"
bash "$ROOT/Build/scripts/run_p244_r9_activation_chain_smoke.sh"
bash "$ROOT/Build/scripts/run_p243_r10_transaction_smoke.sh"
bash "$ROOT/Build/scripts/run_p243_r11_crash_recovery_smoke.sh"
bash "$ROOT/Build/scripts/run_p243_r12_filesystem_smoke.sh"
bash "$ROOT/Build/scripts/run_p243_r13_recovery_smoke.sh"
bash "$ROOT/Build/scripts/run_p243_r14_preflight_smoke.sh"
bash "$ROOT/Build/scripts/run_p243_r15_security_smoke.sh"
bash "$ROOT/Build/scripts/run_p243_r16_dryrun_smoke.sh"
