#!/usr/bin/env python3
"""Verify that zh-Hans and English string catalogs have matching keys."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
FILES = {
    "en": ROOT / "Resources/en.lproj/Localizable.strings",
    "zh-Hans": ROOT / "Resources/zh-Hans.lproj/Localizable.strings",
}
PATTERN = re.compile(r'^\s*"((?:\\.|[^"\\])+)"\s*=\s*"(?:\\.|[^"\\])*"\s*;\s*$')

def read_keys(path: Path) -> set[str]:
    if not path.is_file():
        raise FileNotFoundError(path)
    keys: set[str] = set()
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        match = PATTERN.match(line)
        if not match:
            raise ValueError(f"Invalid .strings syntax: {path}:{line_number}")
        key = match.group(1)
        if key in keys:
            raise ValueError(f"Duplicate key '{key}' in {path}:{line_number}")
        keys.add(key)
    return keys

try:
    catalogs = {name: read_keys(path) for name, path in FILES.items()}
except (OSError, ValueError) as error:
    print(f"Localization check failed: {error}", file=sys.stderr)
    sys.exit(1)

missing_in_zh = sorted(catalogs["en"] - catalogs["zh-Hans"])
missing_in_en = sorted(catalogs["zh-Hans"] - catalogs["en"])
if missing_in_zh or missing_in_en:
    if missing_in_zh:
        print("Missing in zh-Hans:", ", ".join(missing_in_zh))
    if missing_in_en:
        print("Missing in en:", ", ".join(missing_in_en))
    sys.exit(1)

print(f"Localization check passed: {len(catalogs['en'])} matching keys in both languages.")
