#!/usr/bin/env python3
"""Read-only macOS preflight for the exact signed FilterKit App and Helper artifacts."""
import argparse, json, plistlib, re, subprocess, sys
from pathlib import Path


def run(args):
    return subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

def details(path):
    verify = run(["/usr/bin/codesign", "--verify", "--strict", "--deep", str(path)])
    display = run(["/usr/bin/codesign", "-dv", "--verbose=4", str(path)])
    info_path = path / "Info.plist"
    info = plistlib.loads(info_path.read_bytes()) if info_path.is_file() else {}
    output = display.stdout
    cdhash = re.search(r"(?m)^CDHash=([0-9a-fA-F]+)$", output)
    ident = re.search(r"(?m)^Identifier=(.+)$", output)
    team = re.search(r"(?m)^TeamIdentifier=(.+)$", output)
    return {
        "path": str(path.resolve()), "codesign_verify_exit": verify.returncode,
        "codesign_verify_output": verify.stdout, "codesign_display_output": output,
        "cdhash": cdhash.group(1).lower() if cdhash else "",
        "codesign_identifier": ident.group(1).strip() if ident else "",
        "team_identifier": team.group(1).strip() if team else "",
        "info_bundle_identifier": info.get("CFBundleIdentifier", ""),
    }

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--app", required=True, type=Path)
    p.add_argument("--helper", required=True, type=Path)
    p.add_argument("--output", required=True, type=Path)
    a = p.parse_args()
    if sys.platform != "darwin":
        print("BLOCKED: this preflight requires macOS and Apple's codesign.")
        return 2
    for path in (a.app, a.helper):
        if not path.exists():
            print(f"BLOCKED: artifact does not exist: {path}")
            return 2
    app, helper = details(a.app), details(a.helper)
    blockers = []
    for label, item in (("App", app), ("Helper", helper)):
        if item["codesign_verify_exit"] != 0: blockers.append(f"{label} codesign verification failed")
        if not item["cdhash"]: blockers.append(f"{label} CDHash unavailable")
        if not item["codesign_identifier"]: blockers.append(f"{label} signed identifier unavailable")
    if app["info_bundle_identifier"] and app["codesign_identifier"] != app["info_bundle_identifier"]:
        blockers.append("App signed identifier does not match Info.plist bundle identifier")
    trust_candidates = list(a.app.rglob("FilterKit-Helper-AppTrust.json"))
    trust = []
    for item in trust_candidates:
        try: trust.append({"path": str(item.relative_to(a.app)), "json": json.loads(item.read_text())})
        except Exception as exc: blockers.append(f"embedded AppTrust JSON invalid: {exc}")
    if not trust_candidates: blockers.append("embedded FilterKit-Helper-AppTrust.json missing")
    result = {"schema_version": 1, "read_only": True, "app": app, "helper": helper,
              "embedded_helper_app_trust": trust, "blockers": blockers,
              "release_authorized": False}
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Wrote read-only artifact report: {a.output}")
    if blockers:
        print("BLOCKED:")
        for b in blockers: print(f"- {b}")
        return 1
    print("ARTIFACT PREFLIGHT PASS (does not authorize mutation or prove device IPC/injection)")
    return 0

if __name__ == "__main__": sys.exit(main())
