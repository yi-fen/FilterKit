#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for audit in \
  "$ROOT"/Build/scripts/p244_r{1..9}_*_audit.py \
  "$ROOT"/Build/scripts/p244_r1[0-3]_*_audit.py; do
  [ -f "$audit" ] || continue
  python3 "$audit"
done
"$ROOT/Build/scripts/run_p244_r13_prepared_activation_smoke.sh"
"$ROOT/Build/scripts/run_p244_r14_real_store_smoke.sh"
python3 "$ROOT/Build/scripts/p244_r14_real_store_audit.py"
