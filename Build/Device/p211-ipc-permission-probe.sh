#!/bin/sh
# P2-11 read-only metadata probe. Run as root on the target RootHide device.
# It never creates, chmods, chowns, starts, stops, or removes anything.
set -eu
[ "$#" -eq 4 ] || { echo "Usage: $0 <jbroot> <app-uid> <app-primary-gid> <expected-app-cdhash>" >&2; exit 64; }
JBROOT=${1%/}; APP_UID=$2; APP_GID=$3; APP_HASH=$(printf '%s' "$4" | tr '[:upper:]' '[:lower:]')
case "$JBROOT" in /*) ;; *) exit 64 ;; esac
case "$APP_UID:$APP_GID" in *[!0-9:]*) exit 64 ;; esac
[ "$APP_UID" -gt 0 ] && [ "$APP_GID" -gt 0 ] || exit 64
[ "${#APP_HASH}" -eq 40 ] || exit 64
case "$APP_HASH" in *[!0-9a-f]*) exit 64 ;; esac
BASE="$JBROOT/Library/FilterKit/Helper"
SOCKET="$BASE/helper.sock"
MANIFEST="$BASE/manifest.json"
FAIL=0
pass(){ echo "PASS  $1"; }
fail(){ echo "FAIL  $1"; FAIL=$((FAIL+1)); }
[ "$(id -u)" -eq 0 ] && pass "running as root" || fail "must run as root"

# Check POSIX search bits for the measured App UID/GID on each path component.
# ACLs, sandbox policy, and RootHide vnode redirection still require a live App test.
check_search() {
  path=$1
  meta=$(stat -f '%u:%g:%Lp' "$path" 2>/dev/null || true)
  [ -n "$meta" ] || { fail "cannot stat path component: $path"; return; }
  owner=${meta%%:*}; rest=${meta#*:}; group=${rest%%:*}; mode=${rest#*:}
  bits=$((0$(printf '%s' "$mode" | sed 's/^0*//')))
  if [ "$owner" -eq "$APP_UID" ]; then perm=$(( (bits / 64) % 8 ))
  elif [ "$group" -eq "$APP_GID" ]; then perm=$(( (bits / 8) % 8 ))
  else perm=$(( bits % 8 )); fi
  [ $((perm & 1)) -eq 1 ] && pass "App has search bit on $path" || fail "App lacks search bit on $path ($meta)"
}
check_search /
cur=
oldIFS=$IFS; IFS=/
for component in $(printf '%s' "$JBROOT" | sed 's#^/##'); do
  [ -n "$component" ] || continue
  cur="$cur/$component"; check_search "$cur"
done
IFS=$oldIFS
check_search "$JBROOT/Library"
check_search "$JBROOT/Library/FilterKit"
check_search "$BASE"
parent_meta=$(stat -f '%u:%g:%Lp' "$JBROOT/Library/FilterKit" 2>/dev/null || true)
[ "$parent_meta" = "0:0:711" ] && pass "IPC parent root:wheel 0711" || fail "IPC parent expected 0:0:711, got ${parent_meta:-unavailable}"

if [ -d "$BASE" ]; then
  meta=$(stat -f '%u:%g:%Lp' "$BASE" 2>/dev/null || true)
  [ "$meta" = "0:0:711" ] && pass "Helper directory root:wheel 0711" || fail "Helper directory expected 0:0:711, got ${meta:-unavailable}"
else fail "Helper directory missing"; fi
if [ -S "$SOCKET" ]; then
  meta=$(stat -f '%u:%g:%Lp' "$SOCKET" 2>/dev/null || true)
  expected="0:$APP_GID:660"
  [ "$meta" = "$expected" ] && pass "socket root:App-GID 0660" || fail "socket expected $expected, got ${meta:-unavailable}"
else echo "INFO  socket absent; Helper may intentionally be stopped"; fi
if [ -f "$MANIFEST" ]; then
  gid=$(plutil -extract socketGroupID raw -o - "$MANIFEST" 2>/dev/null || true)
  [ "$gid" = "$APP_GID" ] && pass "manifest socketGroupID matches measured App GID" || fail "manifest socketGroupID mismatch (${gid:-missing})"
  hash=$(plutil -extract allowedAppCDHashes.0 raw -o - "$MANIFEST" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
  [ "$hash" = "$APP_HASH" ] && pass "manifest App CDHash matches expected" || fail "manifest App CDHash mismatch"
else fail "manifest missing"; fi

echo "NOTE This checks mode bits only. It does not prove sandbox access, getpeereid, peer PID, csops(CS_OPS_CDHASH), or live IPC rejection."
[ "$FAIL" -eq 0 ] && exit 0 || exit "$FAIL"
