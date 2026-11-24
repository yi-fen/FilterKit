#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for tool in bash python3; do command -v "$tool" >/dev/null 2>&1 || { echo "Missing required tool: $tool" >&2; exit 1; }; done
bash -n "$ROOT/Build/Scripts/build-local.sh"
bash -n "$ROOT/Build/Scripts/ci-build.sh"
bash -n "$ROOT/Build/Scripts/build.sh"
python3 -m py_compile "$ROOT/Build/Scripts/resolve-profile.py" "$ROOT/Build/Scripts/verify-architecture.py" "$ROOT/Build/Scripts/verify-localizations.py"
python3 "$ROOT/Build/Scripts/resolve-profile.py" --environment RootHide --profile Auto --output /tmp/filterkit-p008-profile.json
if python3 "$ROOT/Build/Scripts/resolve-profile.py" --environment Rootless --profile Auto --output /tmp/filterkit-p008-rootless.json; then
  echo 'ERROR: unverified Rootless profile unexpectedly resolved.' >&2; exit 1
else
  echo 'Rootless profile rejection: PASS'
fi
python3 "$ROOT/Build/Scripts/verify-localizations.py"
echo 'Local build static checks: PASS'
