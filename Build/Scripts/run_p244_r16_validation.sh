#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
"$ROOT/Build/scripts/run_p244_r16_full_upgrade_smoke.sh"
python3 "$ROOT/Build/scripts/p244_r16_full_upgrade_audit.py"
"$ROOT/Build/scripts/run_p244_r15_validation.sh"
