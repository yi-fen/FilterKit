#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
python3 Build/scripts/p245_r2_helper_identity_ipc_audit.py
python3 - <<'PY'
from pathlib import Path
import subprocess
root=Path('.')
files=sorted(list(root.glob('Sources/**/*.swift'))+list(root.glob('Tests/**/*.swift'))+list(root.glob('HelperRuntime/**/*.swift')))
for f in files:
    subprocess.run(['swiftc','-parse',str(f)],check=True,stdout=subprocess.DEVNULL)
print(f'Swift parse: {len(files)} files passed')
PY
bash -n Build/scripts/p245_r1_darwin_build_signing_preflight.sh
bash -n Build/scripts/run_p245_r2_validation.sh
python3 - <<'PY'
from pathlib import Path
try:
 import yaml
 yaml.safe_load(Path('Project.yml').read_text())
 print('Project.yml YAML: passed')
except ImportError:
 print('Project.yml YAML: skipped (PyYAML unavailable)')
PY
