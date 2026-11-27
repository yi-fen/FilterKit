#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
python3 "$ROOT/Build/scripts/p236r1_association_audit.py"
find "$ROOT/Sources" "$ROOT/App" -name '*.swift' -print0 | xargs -0 swiftc -frontend -parse
printf '%s\n' 'PASS Swift source parse'
