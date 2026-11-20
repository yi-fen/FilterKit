#!/usr/bin/env python3
"""Compare source and DEB-extracted .app trees without following symlinks."""
import argparse
import hashlib
import json
import os
import plistlib
import stat
import sys
from pathlib import Path


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def inventory(root: Path):
    result = {}
    for base, dirs, files in os.walk(root, topdown=True, followlinks=False):
        base_path = Path(base)
        # Include directory entries, including directory symlinks.
        for name in list(dirs):
            path = base_path / name
            rel = path.relative_to(root).as_posix()
            if path.is_symlink():
                result[rel] = ("symlink", os.readlink(path), stat.S_IMODE(path.lstat().st_mode))
                dirs.remove(name)
            else:
                result[rel] = ("directory", stat.S_IMODE(path.lstat().st_mode))
        for name in files:
            path = base_path / name
            rel = path.relative_to(root).as_posix()
            mode = stat.S_IMODE(path.lstat().st_mode)
            if path.is_symlink():
                result[rel] = ("symlink", os.readlink(path), mode)
            elif path.is_file():
                result[rel] = ("file", digest(path), mode)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--packaged", required=True)
    args = parser.parse_args()
    source, packaged = Path(args.source), Path(args.packaged)
    report = {"source": str(source), "packaged": str(packaged), "equal": False, "mismatches": []}
    if not source.is_dir() or not packaged.is_dir():
        report["mismatches"].append("source_or_packaged_app_missing")
    else:
        try:
            with (source / "Info.plist").open("rb") as f:
                source_info = plistlib.load(f)
            with (packaged / "Info.plist").open("rb") as f:
                packaged_info = plistlib.load(f)
            report["bundleIdentifier"] = source_info.get("CFBundleIdentifier")
            report["executable"] = source_info.get("CFBundleExecutable")
            if source_info != packaged_info:
                report["mismatches"].append("Info.plist differs")
            src_inv, pkg_inv = inventory(source), inventory(packaged)
            for key in sorted(set(src_inv) | set(pkg_inv)):
                if src_inv.get(key) != pkg_inv.get(key):
                    report["mismatches"].append(f"payload differs: {key}")
                    if len(report["mismatches"]) >= 100:
                        report["mismatches"].append("additional_mismatches_truncated")
                        break
            executable = source_info.get("CFBundleExecutable")
            if not isinstance(executable, str) or not executable:
                report["mismatches"].append("CFBundleExecutable missing")
            elif not (packaged / executable).is_file():
                report["mismatches"].append("packaged executable missing")
            elif not os.access(packaged / executable, os.X_OK):
                report["mismatches"].append("packaged executable not executable")
        except Exception as exc:  # malformed plist or inaccessible bundle
            report["mismatches"].append(f"bundle inspection error: {type(exc).__name__}: {exc}")
        report["equal"] = not report["mismatches"]
    print(json.dumps(report, sort_keys=True))
    return 0 if report["equal"] else 1


if __name__ == "__main__":
    sys.exit(main())
