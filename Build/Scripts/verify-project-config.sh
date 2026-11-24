#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPEC="$ROOT/Project.yml"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$SPEC" ] || fail "Project.yml not found"
grep -Eq '^name: FilterKit$' "$SPEC" || fail "Project name must be FilterKit"
grep -Eq 'PRODUCT_BUNDLE_IDENTIFIER: cn\.yfen\.filterkit$' "$SPEC" || fail "Bundle ID must be cn.yfen.filterkit"
grep -Eq 'INFOPLIST_KEY_CFBundleDisplayName: FilterKit$' "$SPEC" || fail "Display name must be FilterKit"
grep -Eq 'MARKETING_VERSION: 1\.0\.0$' "$SPEC" || fail "Marketing version must be 1.0.0"
grep -Eq 'CURRENT_PROJECT_VERSION: 1$' "$SPEC" || fail "Build number must be 1"
grep -Eq 'CODE_SIGN_STYLE: Automatic$' "$SPEC" || fail "Signing style must remain Automatic"
if grep -Eq 'DEVELOPMENT_TEAM:|PROVISIONING_PROFILE_SPECIFIER:' "$SPEC"; then
  fail "Do not hardcode a developer team or provisioning profile"
fi
pass "Project identity and signing configuration"
