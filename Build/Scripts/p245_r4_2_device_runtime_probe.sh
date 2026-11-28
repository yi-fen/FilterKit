#!/bin/sh
# P2-45-R4.2: read-only RootHide runtime snapshot. Does not start/stop jobs or mutate JBROOT.
set -eu
fail(){ echo "ERROR: $*" >&2; exit 2; }
[ "$(uname -s 2>/dev/null || true)" = Darwin ] || fail "must run on Darwin/iOS device"
[ "$(id -u)" = 0 ] || fail "run from an explicitly authorized root shell"
: "${FILTERKIT_JBROOT:?Set device-verified JBROOT}"
: "${FILTERKIT_HELPER_BIN:?Set exact deployed Helper executable path}"
: "${FILTERKIT_SOCKET_PATH:?Set exact Helper socket path}"
: "${FILTERKIT_LAUNCHD_LABEL:?Set exact launchd label}"
: "${FILTERKIT_REPORT:?Set report path outside JBROOT}"
case "$FILTERKIT_REPORT" in "$FILTERKIT_JBROOT"/*) fail "report must be outside JBROOT";; esac
case "$FILTERKIT_HELPER_BIN" in "$FILTERKIT_JBROOT"/*) :;; *) fail "Helper path must be under JBROOT";; esac
case "$FILTERKIT_SOCKET_PATH" in "$FILTERKIT_JBROOT"/*) :;; *) fail "Socket path must be under JBROOT";; esac
umask 077
mkdir -p "$(dirname "$FILTERKIT_REPORT")"
{
 echo 'FILTERKIT_P245_R4_2_RUNTIME_PROBE=1'
 echo "timestamp_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
 echo "os=$(sw_vers -productVersion 2>/dev/null || echo unavailable)"
 echo "uid=$(id -u) gid=$(id -g) groups=$(id -G)"
 echo "jbroot=$FILTERKIT_JBROOT"
 for p in "$FILTERKIT_JBROOT" "$FILTERKIT_HELPER_BIN" "$FILTERKIT_SOCKET_PATH"; do
   echo "path=$p"
   if [ -L "$p" ]; then echo 'state=SYMLINK'; stat -f '%Su:%Sg:%Sp:%i:%l' "$p" 2>&1 || true
   elif [ -e "$p" ]; then echo 'state=PRESENT'; stat -f '%Su:%Sg:%Sp:%i:%l' "$p" 2>&1 || true
   else echo 'state=ABSENT'; fi
 done
 echo "launchd_label=$FILTERKIT_LAUNCHD_LABEL"
 if launchctl print "system/$FILTERKIT_LAUNCHD_LABEL" > /tmp/filterkit-r4_2-launchd.$$.txt 2>&1; then
   echo 'launchd_state=PRESENT'
   grep -E 'state =|pid =|path =|program =|last exit code' /tmp/filterkit-r4_2-launchd.$$.txt || true
 else echo 'launchd_state=ABSENT_OR_NOT_VISIBLE'; cat /tmp/filterkit-r4_2-launchd.$$.txt; fi
 rm -f /tmp/filterkit-r4_2-launchd.$$.txt
 echo 'probe_scope=READ_ONLY; NO launchctl bootstrap/bootout/kickstart; NO IPC request; NO JBROOT mutation'
 echo 'ipc_round_trip=NOT_TESTED_BY_THIS_PROBE'
 echo 'sectask_team_entitlement=NOT_TESTED_BY_THIS_PROBE'
} > "$FILTERKIT_REPORT"
echo "Evidence written: $FILTERKIT_REPORT"
