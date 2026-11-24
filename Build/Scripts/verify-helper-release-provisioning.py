#!/usr/bin/env python3
"""Fail-closed structural audit for generated Helper release trust anchors."""
import base64
import re
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: verify-helper-release-provisioning.py HelperReleaseTrustAnchors.swift")
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
pattern = re.compile(r'HelperReleaseSigningKey\(identifier: "([A-Za-z0-9._-]{1,64})", publicKeyBase64: "([A-Za-z0-9+/=]+)", status: \.(active|retired|revoked), minimumGeneration: (nil|[0-9]+), maximumGeneration: (nil|[0-9]+)\)')
rows = pattern.findall(text)
if not rows:
    raise SystemExit("FAIL: no provisioned trust anchors; production startup must remain closed")
if len({row[0] for row in rows}) != len(rows):
    raise SystemExit("FAIL: duplicate Key ID")
active = []
retired = []
for kid, encoded, status, minimum, maximum in rows:
    try:
        key = base64.b64decode(encoded, validate=True)
    except Exception as exc:
        raise SystemExit(f"FAIL: invalid public key encoding for {kid}: {exc}")
    if len(key) != 32:
        raise SystemExit(f"FAIL: Ed25519 public key for {kid} must be 32 bytes")
    lo = None if minimum == "nil" else int(minimum)
    hi = None if maximum == "nil" else int(maximum)
    if lo is not None and lo < 1 or hi is not None and hi < 1 or lo is not None and hi is not None and lo > hi:
        raise SystemExit(f"FAIL: invalid generation range for {kid}")
    if status == "active":
        if hi is not None:
            raise SystemExit(f"FAIL: active key {kid} must not have maximumGeneration")
        active.append(lo)
    elif status == "retired":
        if hi is None:
            raise SystemExit(f"FAIL: retired key {kid} requires maximumGeneration")
        retired.append((kid, hi))
if not active:
    raise SystemExit("FAIL: at least one active signing key is required")
active_starts = [value for value in active if value is not None]
if active_starts:
    first_active = min(active_starts)
    for kid, ceiling in retired:
        if ceiling >= first_active:
            raise SystemExit(f"FAIL: retired key {kid} overlaps active key generation range")
print(f"PASS: {len(rows)} structurally valid release trust anchor(s); active key present")
print("NOTE: this is a structural audit, not a signature or certificate-chain verification")
