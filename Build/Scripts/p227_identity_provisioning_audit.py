#!/usr/bin/env python3
"""Read-only macOS audit of final signed FilterKit App/Helper identity provisioning.

This tool does not sign, install, modify, launch, or enable anything. The client UID/GID
must be measured on the target device and supplied explicitly; they are not inferred from
host account IDs.
"""
import argparse
import json
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

CDHASH_RE = re.compile(r"(?im)^\s*CDHash\s*=?\s*([0-9a-f]{40})\s*$")
IDENTIFIER_RE = re.compile(r"(?im)^\s*Identifier\s*=\s*(\S+)\s*$")
TEAM_RE = re.compile(r"(?im)^\s*TeamIdentifier\s*=\s*(\S+)\s*$")


def fail(message):
    raise ValueError(message)


def signature(path: Path):
    verify = subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "--deep", str(path)],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if verify.returncode:
        fail(f"codesign verify failed: {path}: {(verify.stderr or verify.stdout).strip()}")
    detail = subprocess.run(["/usr/bin/codesign", "-dv", "--verbose=4", str(path)],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    output = detail.stdout + "\n" + detail.stderr
    if detail.returncode:
        fail(f"cannot inspect code signature: {path}")
    cdhash = CDHASH_RE.search(output)
    identifier = IDENTIFIER_RE.search(output)
    team = TEAM_RE.search(output)
    if not cdhash or not identifier:
        fail(f"signature identity fields unavailable: {path}")
    return {"cdhash": cdhash.group(1).lower(), "identifier": identifier.group(1),
            "teamIdentifier": team.group(1) if team else None}


def load_json(path):
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, help="final signed FilterKit.app")
    parser.add_argument("--helper", required=True, help="final signed FilterKitHelper executable")
    parser.add_argument("--provisioning", required=True, help="FilterKit-Helper-InstallerProvisioning.json")
    parser.add_argument("--client-uid", required=True, type=int, help="UID measured on target device")
    parser.add_argument("--client-gid", required=True, type=int, help="primary GID measured on target device")
    parser.add_argument("--helper-identifier", default="cn.yfen.filterkit.helper")
    parser.add_argument("--expected-team-id", help="optional expected Team ID for both signatures")
    args = parser.parse_args()

    if sys.platform != "darwin" or not Path("/usr/bin/codesign").exists():
        fail("BLOCKED: run on macOS with Apple's codesign tool")
    app = Path(args.app).resolve()
    helper = Path(args.helper).resolve()
    if not app.is_dir() or not helper.is_file():
        fail("App bundle or Helper executable path is invalid")
    provisioning = load_json(Path(args.provisioning))
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)

    app_sig = signature(app)
    helper_sig = signature(helper)
    if app_sig["identifier"] != provisioning.get("bundleIdentifier"):
        fail("signed App identifier does not match installer provisioning")
    if info.get("CFBundleIdentifier") != provisioning.get("bundleIdentifier"):
        fail("App Info.plist bundle identifier does not match installer provisioning")
    if helper_sig["identifier"] != args.helper_identifier:
        fail("signed Helper identifier does not match expected Helper identifier")
    if app_sig["cdhash"] != str(provisioning.get("appCDHash", "")).lower():
        fail("final App CDHash does not match installer provisioning")
    if helper_sig["cdhash"] != str(provisioning.get("helperCDHash", "")).lower():
        fail("final Helper CDHash does not match installer provisioning")
    if args.client_uid == 0 or args.client_gid == 0:
        fail("measured App UID/GID must be non-root")
    if args.client_uid != provisioning.get("allowedClientUID"):
        fail("measured App UID does not match installer provisioning")
    if args.client_gid != provisioning.get("socketGroupID"):
        fail("measured App primary GID does not match socket group provisioning")
    if args.expected_team_id:
        if app_sig["teamIdentifier"] != args.expected_team_id or helper_sig["teamIdentifier"] != args.expected_team_id:
            fail("Team ID mismatch")

    trust_candidates = list(app.rglob("FilterKit-Helper-AppTrust.json"))
    if len(trust_candidates) != 1:
        fail(f"expected exactly one embedded FilterKit-Helper-AppTrust.json, found {len(trust_candidates)}")
    app_trust = load_json(trust_candidates[0])
    if app_trust.get("bundleIdentifier") != provisioning.get("bundleIdentifier"):
        fail("embedded App Trust bundle identifier mismatch")
    if app_trust.get("generation") != provisioning.get("generation"):
        fail("embedded App Trust generation mismatch")
    if [x.lower() for x in app_trust.get("allowedHelperCDHashes", [])] != [helper_sig["cdhash"]]:
        fail("embedded App Trust Helper CDHash mismatch")
    if app_trust.get("allowedHelperUIDs", [0]) != [0] or app_trust.get("allowedHelperGIDs", [0]) != [0]:
        fail("embedded App Trust Helper UID/GID policy must be root-only")

    print("P2-27 final identity provisioning audit: PASS")
    print(f"App Identifier: {app_sig['identifier']}\nApp CDHash: {app_sig['cdhash']}")
    print(f"Helper Identifier: {helper_sig['identifier']}\nHelper CDHash: {helper_sig['cdhash']}")
    print(f"Client UID/GID: {args.client_uid}/{args.client_gid}")
    print(f"Generation: {provisioning.get('generation')} (App Trust matched)")
    print("Read-only: no signing, installation, launch, or production gate changes performed.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, json.JSONDecodeError, plistlib.InvalidFileException) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(2)
