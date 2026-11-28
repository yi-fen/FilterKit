#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

printf '\n== R4.4 Swift syntax ==\n'
swiftc -parse $(find Sources Tests -name '*.swift' -print)
printf 'Swift syntax parse passed.\n'

printf '\n== R4.4 Shell syntax ==\n'
bash -n Build/scripts/*.sh
printf 'Shell syntax passed.\n'

printf '\n== R4.4 static audit ==\n'
python3 Build/scripts/p245_r4_4_static_audit.py

printf '\n== R4.4 localization plist validation ==\n'
plutil -lint Resources/en.lproj/Localizable.strings
plutil -lint Resources/zh-Hans.lproj/Localizable.strings
printf '\nR4.4 validation completed. This runner does not perform Xcode/XCTest or RootHide device acceptance.\n'
