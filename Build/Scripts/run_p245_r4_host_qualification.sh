#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
python3 Build/scripts/p245_r4_static_audit.py
bash -n Build/scripts/p245_r4_device_evidence_collector.sh
bash -n Build/scripts/run_p245_r4_host_qualification.sh
python3 Build/scripts/p245_r1_static_audit.py
python3 Build/scripts/p245_r2_helper_identity_ipc_audit.py
bash Build/scripts/run_p245_r3_validation.sh
bash Build/scripts/run_p244_r18_recovery_boundary_completion.sh
python3 - <<'PY'
from pathlib import Path
import subprocess
root=Path('.')
files=sorted(list(root.glob('Sources/**/*.swift'))+list(root.glob('Tests/**/*.swift'))+list(root.glob('HelperRuntime/**/*.swift')))
for f in files:
    subprocess.run(['swiftc','-parse',str(f)],check=True,stdout=subprocess.DEVNULL)
print(f'Swift parse: {len(files)} files passed')
PY
