#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
python3 "$ROOT/Build/scripts/p244_r12_prepared_activation_boundary_audit.py"
bash "$ROOT/Build/scripts/run_p244_r11_validation.sh"
