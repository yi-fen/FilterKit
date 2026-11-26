#!/bin/sh
# P2-10 read-only RootHide Helper runtime probe. Never installs, starts, stops,
# chmods, chowns, removes, or edits any device file/service.
set -eu

usage() {
  echo "Usage: $0 <jbroot> <expected-helper-cdhash> <expected-app-cdhash>" >&2
  exit 64
}
[ "$#" -eq 3 ] || usage
JBROOT=${1%/}
EXPECTED_HELPER=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
EXPECTED_APP=$(printf '%s' "$3" | tr '[:upper:]' '[:lower:]')
case "$JBROOT" in /*) ;; *) usage ;; esac
case "$JBROOT" in /|*'..'*) echo "FAIL unsafe JBROOT"; exit 2 ;; esac
case "$EXPECTED_HELPER:$EXPECTED_APP" in *[!0-9a-f:]*|*:*)
  # Validate exact 40-hex fingerprints below; this branch only rejects non-hex.
  case "$EXPECTED_HELPER$EXPECTED_APP" in *[!0-9a-f]*) echo "FAIL invalid CDHash characters"; exit 2 ;; esac
  ;;
esac
[ "${#EXPECTED_HELPER}" -eq 40 ] && [ "${#EXPECTED_APP}" -eq 40 ] || { echo "FAIL CDHash must be 40 hex chars"; exit 2; }

BASE="$JBROOT/Library/FilterKit/Helper"
HELPER="$JBROOT/usr/libexec/filterkit-helper"
PLIST="$JBROOT/Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"
MANIFEST="$BASE/manifest.json"
SOCKET="$BASE/helper.sock"
LABEL="cn.yfen.filterkit.helper"
FAIL=0

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
info() { printf 'INFO  %s\n' "$1"; }

[ "$(id -u)" -eq 0 ] && pass "probe runs as root" || fail "probe should run as root for complete metadata visibility"

check_file() {
  path=$1 expected_type=$2 expected_uid=$3 expected_gid=$4 expected_mode=$5 label=$6
  if [ ! -e "$path" ]; then fail "$label missing: $path"; return; fi
  meta=$(stat -f '%HT:%u:%g:%Lp' "$path" 2>/dev/null || true)
  expected="$expected_type:$expected_uid:$expected_gid:$expected_mode"
  [ "$meta" = "$expected" ] && pass "$label metadata $meta" || fail "$label metadata expected $expected got ${meta:-unreadable}"
}

check_file "$BASE" Directory 0 0 711 "Helper directory (traverse-only; no listing)"
check_file "$HELPER" Regular\ File 0 0 755 "Helper executable"
check_file "$MANIFEST" Regular\ File 0 0 600 "Root manifest"
check_file "$PLIST" Regular\ File 0 0 644 "LaunchDaemon plist"

if [ -f "$PLIST" ]; then
  plutil -lint "$PLIST" >/dev/null 2>&1 && pass "launchd plist parses" || fail "launchd plist invalid"
  disabled=$(plutil -extract Disabled raw -o - "$PLIST" 2>/dev/null || true)
  runatload=$(plutil -extract RunAtLoad raw -o - "$PLIST" 2>/dev/null || true)
  keepalive=$(plutil -extract KeepAlive raw -o - "$PLIST" 2>/dev/null || true)
  [ "$disabled" = true ] && [ "$runatload" = false ] && [ "$keepalive" = false ] \
    && pass "launchd job remains disabled" || fail "launchd job is not in disabled safe state"
fi

if [ -f "$MANIFEST" ]; then
  plutil -lint "$MANIFEST" >/dev/null 2>&1 && pass "root manifest JSON parses" || fail "root manifest JSON invalid"
  manifest_helper=$(plutil -extract allowedHelperCDHashes.0 raw -o - "$MANIFEST" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
  manifest_app=$(plutil -extract allowedAppCDHashes.0 raw -o - "$MANIFEST" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
  [ "$manifest_helper" = "$EXPECTED_HELPER" ] && pass "manifest pins expected Helper CDHash" || fail "manifest Helper CDHash mismatch"
  [ "$manifest_app" = "$EXPECTED_APP" ] && pass "manifest pins expected App CDHash" || fail "manifest App CDHash mismatch"
  enabled=$(plutil -extract executionEnabled raw -o - "$MANIFEST" 2>/dev/null || true)
  [ "$enabled" = false ] && pass "executionEnabled remains false" || fail "executionEnabled is not false"
  manifest_socket=$(plutil -extract socketPath raw -o - "$MANIFEST" 2>/dev/null || true)
  [ "$manifest_socket" = "$SOCKET" ] && pass "manifest socket path matches fixed layout" || fail "manifest socket path mismatch"
fi

if [ -x "$HELPER" ]; then
  actual_helper=$(codesign -dv --verbose=4 "$HELPER" 2>&1 | sed -n 's/^CDHash=//p' | head -n 1 | tr '[:upper:]' '[:lower:]')
  [ "$actual_helper" = "$EXPECTED_HELPER" ] && pass "installed Helper CDHash matches release input" || fail "installed Helper CDHash mismatch/unavailable (${actual_helper:-none})"
fi

# launchctl print and lsof are observation-only. A missing service/socket is not
# automatically a failure: the provisioning template intentionally ships disabled.
if launchctl print "system/$LABEL" >/dev/null 2>&1; then
  info "launchd label is registered; inspect state manually (probe does not change it)"
else
  info "launchd label is not registered (expected for disabled/uninstalled test state)"
fi
if [ -S "$SOCKET" ]; then
  socket_meta=$(stat -f '%HT:%u:%g:%Lp' "$SOCKET" 2>/dev/null || true)
  info "socket exists: ${socket_meta:-metadata unavailable}"
  info "socket mode is recorded only; expected root:<installed-App-GID> 0660; peer credentials/CDHash still require live IPC test"
else
  info "socket absent; no Helper listener currently exposed"
fi

info "This probe is read-only. It does not prove App-to-Helper IPC, peer CDHash enforcement, or ElleKit injection."
if [ "$FAIL" -eq 0 ]; then echo "P2-10 probe: PASS (static/runtime metadata only)"; else echo "P2-10 probe: $FAIL failure(s)"; fi
exit "$FAIL"
