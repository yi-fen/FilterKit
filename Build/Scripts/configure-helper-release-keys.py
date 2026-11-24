#!/usr/bin/env python3
"""Generate compile-time Swift trust anchors from an offline-reviewed JSON keyring."""
import json, re, sys
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("usage: configure-helper-release-keys.py keyring.json HelperReleaseTrustAnchors.swift")
src, dst = map(Path, sys.argv[1:])
obj = json.loads(src.read_text(encoding="utf-8"))
if not isinstance(obj, dict) or obj.get("schemaVersion") != 1 or not isinstance(obj.get("keys"), list) or not obj["keys"]:
    raise SystemExit("invalid keyring schema or empty key list")
seen = set(); rows = []
for item in obj["keys"]:
    kid, status, key = item.get("identifier"), item.get("status"), item.get("publicKeyBase64")
    if not isinstance(kid, str) or not re.fullmatch(r"[A-Za-z0-9._-]{1,64}", kid) or kid in seen:
        raise SystemExit("invalid or duplicate key identifier")
    seen.add(kid)
    if status not in ("active", "retired", "revoked"):
        raise SystemExit(f"invalid status for {kid}")
    import base64
    try: raw = base64.b64decode(key, validate=True)
    except Exception: raise SystemExit(f"invalid base64 key for {kid}")
    if len(raw) != 32: raise SystemExit(f"Ed25519 public key must be 32 bytes: {kid}")
    minimum, maximum = item.get("minimumGeneration"), item.get("maximumGeneration")
    for value in (minimum, maximum):
        if value is not None and (not isinstance(value, int) or isinstance(value, bool) or value < 1):
            raise SystemExit(f"invalid generation bound for {kid}")
    if minimum is not None and maximum is not None and minimum > maximum:
        raise SystemExit(f"inverted generation range for {kid}")
    if status == "retired" and maximum is None:
        raise SystemExit(f"retired key requires maximumGeneration: {kid}")
    if status == "active" and maximum is not None:
        raise SystemExit(f"active key must not have maximumGeneration: {kid}")
    rows.append((kid, status, key, minimum, maximum))
if not any(r[1] == "active" for r in rows):
    raise SystemExit("keyring must contain at least one active key")
active_starts = [r[3] for r in rows if r[1] == "active" and r[3] is not None]
if active_starts:
    earliest_active = min(active_starts)
    for kid, status, _key, _minimum, maximum in rows:
        if status == "retired" and maximum >= earliest_active:
            raise SystemExit(f"retired key generation overlaps active key window: {kid}")
lines = ["import Foundation", "", "/// Generated from an offline-reviewed release keyring. Do not edit by hand.", "enum HelperReleaseTrustAnchors {", "    static let keys: [HelperReleaseSigningKey] = ["]
for kid, status, key, minimum, maximum in rows:
    lines.append(f'        HelperReleaseSigningKey(identifier: "{kid}", publicKeyBase64: "{key}", status: .{status}, minimumGeneration: {str(minimum) if minimum is not None else "nil"}, maximumGeneration: {str(maximum) if maximum is not None else "nil"}),')
lines += ["    ]", "}", ""]
dst.parent.mkdir(parents=True, exist_ok=True)
dst.write_text("\n".join(lines), encoding="utf-8")
print(f"generated {len(rows)} trust anchor(s): {dst}")
