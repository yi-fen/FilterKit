#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
command -v swiftc >/dev/null 2>&1 || { echo 'ERROR: swiftc is required'; exit 2; }
python3 Build/scripts/p237r2_helper_identity_audit.py
mapfile -t ALL_SWIFT < <(find Sources HelperRuntime Tests/UnitTests -name '*.swift' -type f | sort)
swiftc -parse "${ALL_SWIFT[@]}"
mapfile -t HELPER_SWIFT < <(find HelperRuntime Sources/Core/Models Sources/Environment/Helper Sources/Environment/Models Sources/Environment/Profiles -name '*.swift' -type f | sort)
HELPER_SWIFT+=(Sources/Environment/Deployment/RootHideElleKitFilterStrategy.swift)
HELPER_SWIFT+=(Sources/Environment/Deployment/EnableDisableStrategy.swift)
HELPER_SWIFT+=(Sources/Environment/MachOMetadataReader.swift Sources/Environment/SHA256Digest.swift Sources/Environment/LibrootRuntimeProbe.swift)
swiftc -typecheck "${HELPER_SWIFT[@]}"
mapfile -t CORE_MODELS < <(find Sources/Core/Models -name '*.swift' -type f | sort)
mapfile -t ENV_MODELS < <(find Sources/Environment/Models Sources/Environment/Profiles -name '*.swift' -type f | sort)
swiftc -typecheck "${CORE_MODELS[@]}" "${ENV_MODELS[@]}" \
  Sources/Environment/SHA256Digest.swift \
  Sources/Environment/Deployment/EnableDisableStrategy.swift \
  Sources/Environment/Deployment/AppPluginActivationStateResolver.swift \
  Sources/Environment/Helper/Execution/HelperDeploymentRouteResolver.swift
echo 'PASS App activation model/resolver semantic typecheck'
python3 - <<'PY'
from pathlib import Path
import plistlib
p = Path('Project.yml')
text = p.read_text()
assert 'Sources/Core/Models/PluginFilterConfiguration.swift' in text
assert 'Sources/Environment/Helper/Runtime' in text
print('PASS Project.yml Helper source inclusion')
for lang in ('en', 'zh-Hans'):
    f = Path(f'Resources/{lang}.lproj/Localizable.strings')
    with f.open('rb') as stream:
        # strings is not a plist; check duplicate keys textually instead.
        pass
    keys = []
    for line in f.read_text().splitlines():
        if line.startswith('"') and '" =' in line:
            keys.append(line.split('"', 2)[1])
    assert len(keys) == len(set(keys)), f'duplicate localization key: {lang}'
    assert 'apps.detail.activation_helper_attestation_required' in keys
    assert 'apps.detail.activation_helper_attestation_mismatch' in keys
    print(f'PASS {lang} localization keys ({len(keys)})')
PY
echo 'P2-37-R2 Helper identity Host Smoke: PASS'
