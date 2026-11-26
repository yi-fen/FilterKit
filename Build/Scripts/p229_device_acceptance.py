#!/usr/bin/env python3
"""Read-only validator for manually captured first-device acceptance evidence.

This validates completeness and freshness, not authenticity or device behavior.
It never invokes signing tools, connects to a device, or changes jailbreak files.
"""
import argparse, json, re, sys
from datetime import datetime, timezone
from pathlib import Path

REQUIRED_TEXT = {
    "device.model": "device model",
    "device.os_version": "iOS version",
    "device.jailbreak_version": "RootHide version",
    "device.ellekit_version": "ElleKit version",
    "device.build_id": "device build identifier",
    "artifacts.app_bundle_id": "App bundle identifier",
    "artifacts.app_cdhash": "signed App CDHash",
    "artifacts.helper_cdhash": "signed Helper CDHash",
    "artifacts.generation": "App/Helper generation",
    "plugin.bundle_id": "test plugin bundle identifier",
    "plugin.dylib_sha256": "test dylib SHA-256",
    "plugin.filter_plist_sha256": "test filter plist SHA-256",
    "target.bundle_id": "non-system target App bundle identifier",
    "operator": "operator identifier",
}
REQUIRED_TRUE = {
    "checks.codesign_app_verified": "App codesign verification",
    "checks.codesign_helper_verified": "Helper codesign verification",
    "checks.app_helper_cdhash_crosscheck": "App/Helper CDHash cross-check",
    "checks.helper_peer_uid_gid_verified": "Helper peer UID/GID verification",
    "checks.live_ipc_health_roundtrip": "live App-to-Helper IPC health round-trip",
    "checks.ellekit_enable_mechanism_observed": "ElleKit enable mechanism observation",
    "checks.ellekit_disable_mechanism_observed": "ElleKit disable mechanism observation",
    "checks.target_injection_observed": "target process injection observation",
    "checks.disable_prevents_injection_after_restart": "disabled state verified after target restart",
    "checks.recovery_after_interruption": "interrupted-operation recovery test",
    "checks.audit_record_persisted": "durable audit record verification",
    "checks.backup_restore_verified": "backup and restore verification",
}

def get_path(obj, dotted):
    for part in dotted.split('.'):
        if not isinstance(obj, dict) or part not in obj:
            return None
        obj = obj[part]
    return obj

def validate(doc, now=None):
    now = now or datetime.now(timezone.utc)
    blockers = []
    if not isinstance(doc, dict):
        return ["root must be a JSON object"]
    if doc.get("schema_version") != 1:
        blockers.append("schema_version must equal 1")
    if doc.get("evidence_kind") != "manual-device-capture":
        blockers.append("evidence_kind must be manual-device-capture (synthetic/host evidence is not accepted)")
    for key, label in REQUIRED_TEXT.items():
        value = get_path(doc, key)
        if not isinstance(value, str) or not value.strip():
            blockers.append(f"missing {label}: {key}")
    for key, label in REQUIRED_TRUE.items():
        if get_path(doc, key) is not True:
            blockers.append(f"not verified: {label} ({key})")
    for key in ("artifacts.app_cdhash", "artifacts.helper_cdhash"):
        value = get_path(doc, key)
        if isinstance(value, str) and value and not re.fullmatch(r"[0-9a-fA-F]{20,64}", value):
            blockers.append(f"invalid CDHash format: {key}")
    for key in ("plugin.dylib_sha256", "plugin.filter_plist_sha256"):
        value = get_path(doc, key)
        if isinstance(value, str) and value and not re.fullmatch(r"[0-9a-fA-F]{64}", value):
            blockers.append(f"invalid SHA-256 format: {key}")
    stamp = doc.get("captured_at")
    try:
        captured = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
        if captured.tzinfo is None:
            raise ValueError("timezone required")
        age = (now - captured.astimezone(timezone.utc)).total_seconds()
        if age < -300:
            blockers.append("captured_at is more than five minutes in the future")
        elif age > 24 * 3600:
            blockers.append("evidence is older than 24 hours; recapture on the current device build")
    except (AttributeError, TypeError, ValueError):
        blockers.append("captured_at must be an ISO-8601 timestamp with timezone")
    if get_path(doc, "checks.tested_non_system_target") is not True:
        blockers.append("first rollout must use a non-system test target")
    if get_path(doc, "checks.no_system_or_hard_bound_target_modified") is not True:
        blockers.append("system/hard-bound target immutability was not verified")
    return blockers

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    try:
        doc = json.loads(args.evidence.read_text())
    except Exception as exc:
        print(f"BLOCKED: cannot read evidence JSON: {exc}")
        return 2
    blockers = validate(doc)
    if blockers:
        print(f"BLOCKED: {len(blockers)} acceptance item(s) missing or invalid")
        for item in blockers:
            print(f"- {item}")
        print("No release switch was changed. This validator does not authenticate operator claims.")
        return 1
    print("COMPLETE: required manual device evidence fields are present and fresh.")
    print("This is not cryptographic attestation and does not itself authorize production mutation.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
