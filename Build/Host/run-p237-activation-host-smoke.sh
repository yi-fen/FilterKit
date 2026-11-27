#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
python3 Build/scripts/p237_activation_audit.py
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
cp Build/Host/P2-37-Activation-Model-Smoke.swift "$TMP_DIR/main.swift"
swiftc \
  Build/Host/P2-37-Activation-Model-Stubs.swift \
  Sources/Core/Models/AppPluginActivationModels.swift \
  Sources/Core/Models/PluginIdentityVerificationResult.swift \
  Sources/Core/Models/AppPluginActivationPreviewLedger.swift \
  Sources/Core/Models/PluginScanGenerationTracker.swift \
  Sources/Environment/Deployment/AppPluginActivationStateResolver.swift \
  "$TMP_DIR/main.swift" \
  -o "$TMP_DIR/p237-activation-smoke"
"$TMP_DIR/p237-activation-smoke"
find Sources App HelperRuntime Tests/UnitTests -name '*.swift' -print0 | xargs -0 swiftc -parse
python3 - <<'PY'
from pathlib import Path
import re
for path in [Path('Resources/en.lproj/Localizable.strings'), Path('Resources/zh-Hans.lproj/Localizable.strings')]:
    keys = re.findall(r'^\s*"((?:[^"\\]|\\.)+)"\s*=', path.read_text(), re.M)
    duplicates = sorted({key for key in keys if keys.count(key) > 1})
    if duplicates:
        raise SystemExit(f'{path}: duplicate keys: {duplicates}')
print('P2-37 localization duplicate-key check: passed')
PY
