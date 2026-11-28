#!/bin/sh
# Read-only RootHide device evidence collector. It never writes below JBROOT.
set -eu

fail() { echo "ERROR: $*" >&2; exit 2; }
[ "$(uname -s 2>/dev/null || true)" = "Darwin" ] || fail "must run on Darwin/iOS device shell"
[ "$(id -u)" = "0" ] || fail "run from an explicitly authorized root shell"
[ -n "${FILTERKIT_JBROOT:-}" ] || fail "set FILTERKIT_JBROOT to the device-validated JBROOT path"
[ -d "$FILTERKIT_JBROOT" ] || fail "FILTERKIT_JBROOT is not a directory"
[ -n "${FILTERKIT_REPORT:-}" ] || fail "set FILTERKIT_REPORT to an output path outside JBROOT"
case "$FILTERKIT_REPORT" in "$FILTERKIT_JBROOT"/*) fail "report path must be outside JBROOT";; esac

umask 077
mkdir -p "$(dirname "$FILTERKIT_REPORT")"
: > "$FILTERKIT_REPORT"
exec 3> "$FILTERKIT_REPORT"

emit() { printf '%s\n' "$*" >&3; }
meta() {
  label="$1"; path="$2"
  if [ -e "$path" ] || [ -L "$path" ]; then
    emit "$label.path=$path"
    emit "$label.type=$( [ -L "$path" ] && echo symlink || { [ -d "$path" ] && echo directory || { [ -f "$path" ] && echo regular || echo other; }; } )"
    emit "$label.stat=$(stat -f '%Su:%Sg:%Sp:%i:%l' "$path" 2>&1 || echo STAT_FAILED)"
    [ ! -L "$path" ] || emit "$label.no_follow=FAIL_SYMLINK"
  else
    emit "$label.path=$path"
    emit "$label.state=ABSENT"
  fi
}

emit 'FILTERKIT_P245_R4_DEVICE_EVIDENCE=1'
emit "timestamp_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
emit "device_uname=$(uname -a)"
emit "device_uid=$(id -u)"
emit "device_gid=$(id -g)"
emit "device_groups=$(id -G)"
emit "os_product=$(sw_vers -productName 2>/dev/null || echo unavailable)"
emit "os_version=$(sw_vers -productVersion 2>/dev/null || echo unavailable)"
emit "os_build=$(sw_vers -buildVersion 2>/dev/null || echo unavailable)"
emit "boot_session_uuid=$(sysctl -n kern.bootsessionuuid 2>/dev/null || echo unavailable)"
meta jbroot "$FILTERKIT_JBROOT"

# Optional paths must come from device-side inspection / the actual signed deployment manifest.
[ -z "${FILTERKIT_HELPER_DIR:-}" ] || meta helper_dir "$FILTERKIT_HELPER_DIR"
[ -z "${FILTERKIT_ACTIVE_DIR:-}" ] || meta active_dir "$FILTERKIT_ACTIVE_DIR"
[ -z "${FILTERKIT_SOCKET_PATH:-}" ] || meta helper_socket "$FILTERKIT_SOCKET_PATH"
[ -z "${FILTERKIT_HELPER_BIN:-}" ] || meta helper_binary "$FILTERKIT_HELPER_BIN"
[ -z "${FILTERKIT_LAUNCHD_LABEL:-}" ] || {
  emit "launchd_label=$FILTERKIT_LAUNCHD_LABEL"
  if launchctl print "system/$FILTERKIT_LAUNCHD_LABEL" >/dev/null 2>&1; then
    emit 'launchd_job=present'
  else
    emit 'launchd_job=not_visible_or_absent'
  fi
}
if [ -n "${FILTERKIT_HELPER_BIN:-}" ] && [ -f "$FILTERKIT_HELPER_BIN" ]; then
  if command -v codesign >/dev/null 2>&1; then
    emit 'codesign_identity_begin'
    codesign -dv --verbose=4 "$FILTERKIT_HELPER_BIN" 2>&1
    emit 'codesign_identity_end'
  else
    emit 'codesign=unavailable'
  fi
fi
emit 'collector_write_scope=REPORT_FILE_ONLY; NO_JBROOT_MUTATION'
emit 'device_transaction_test=NOT_RUN_BY_READ_ONLY_COLLECTOR'
exec 3>&-
echo "Evidence written: $FILTERKIT_REPORT"
