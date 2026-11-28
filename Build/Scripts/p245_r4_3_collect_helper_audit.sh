#!/bin/sh
# Read-only Helper audit collector for RootHide device testing.
# Usage (as root): p245_r4_3_collect_helper_audit.sh <absolute-jbroot> <absolute-output-dir>
set -eu
umask 077

fail() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -u)" = "0" ] || fail "run as root to read the root-owned Helper audit log"
[ "$#" -eq 2 ] || fail "usage: $0 <absolute-jbroot> <absolute-output-dir>"
JBROOT=$1
OUTPUT=$2
case "$JBROOT" in /*) ;; *) fail "JBROOT must be absolute" ;; esac
case "$OUTPUT" in /*) ;; *) fail "output directory must be absolute" ;; esac
case "$JBROOT" in *"/../"*|*/..) fail "JBROOT contains traversal" ;; esac
case "$OUTPUT" in *"/../"*|*/..) fail "output directory contains traversal" ;; esac
[ -d "$JBROOT" ] && [ ! -L "$JBROOT" ] || fail "JBROOT is missing or a symlink"
JBROOT_REAL=$(cd -P "$JBROOT" && pwd)
mkdir -p "$OUTPUT"
[ ! -L "$OUTPUT" ] || fail "output directory is a symlink"
OUTPUT_REAL=$(cd -P "$OUTPUT" && pwd)
case "$OUTPUT_REAL/" in "$JBROOT_REAL/"*) fail "output must be outside JBROOT" ;; esac
chmod 700 "$OUTPUT_REAL"

for DIRECTORY in "$JBROOT_REAL/Library" "$JBROOT_REAL/Library/FilterKit" "$JBROOT_REAL/Library/FilterKit/Helper"; do
    [ -d "$DIRECTORY" ] && [ ! -L "$DIRECTORY" ] || fail "unsafe Helper audit directory component"
    DIR_OWNER=$(stat -f '%u' "$DIRECTORY")
    DIR_MODE=$(stat -f '%Lp' "$DIRECTORY")
    [ "$DIR_OWNER" = "0" ] || fail "unexpected directory owner: $DIRECTORY"
    [ $((0$DIR_MODE & 18)) -eq 0 ] || fail "group/world writable directory: $DIRECTORY"
done
SOURCE_DIR="$JBROOT_REAL/Library/FilterKit/Helper"
COPIED=0
for NAME in audit.jsonl audit.jsonl.1 audit.jsonl.2 audit.jsonl.3; do
    SOURCE="$SOURCE_DIR/$NAME"
    [ -e "$SOURCE" ] || continue
    [ ! -L "$SOURCE" ] || fail "refusing symlink: $NAME"
    [ -f "$SOURCE" ] || fail "refusing non-regular file: $NAME"
    OWNER=$(stat -f '%u' "$SOURCE")
    GROUP=$(stat -f '%g' "$SOURCE")
    LINKS=$(stat -f '%l' "$SOURCE")
    MODE=$(stat -f '%Lp' "$SOURCE")
    [ "$OWNER" = "0" ] && [ "$GROUP" = "0" ] || fail "unexpected owner/group for $NAME"
    [ "$LINKS" = "1" ] || fail "unexpected hard-link count for $NAME"
    [ "$MODE" = "600" ] || fail "unexpected permissions for $NAME"
    cp "$SOURCE" "$OUTPUT_REAL/helper-$NAME"
    chmod 600 "$OUTPUT_REAL/helper-$NAME"
    shasum -a 256 "$OUTPUT_REAL/helper-$NAME"
    COPIED=$((COPIED + 1))
done
[ "$COPIED" -gt 0 ] || fail "no Helper audit records found"
printf 'helper_audit_files=%s\noutput=%s\n' "$COPIED" "$OUTPUT_REAL"
