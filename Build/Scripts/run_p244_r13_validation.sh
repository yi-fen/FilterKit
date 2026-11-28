#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
python3 "$ROOT/Build/scripts/p244_r13_prepared_activation_audit.py"
bash "$ROOT/Build/scripts/run_p244_r13_prepared_activation_smoke.sh"
