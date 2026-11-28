from pathlib import Path

root = Path(__file__).resolve().parents[2]
identity = (root / "Sources/Core/Models/BackupBundleIdentity.swift").read_text()
models = (root / "Sources/Core/Models/BackupModels.swift").read_text()
service = (root / "Sources/Environment/FilterKitBackupService.swift").read_text()
codec_tests = (root / "Tests/UnitTests/FilterKitBackupCodecTests.swift").read_text()

checks = [
    ("comparison-only canonical identity helper", "HelperBundleIdentifierKey.make" in identity),
    ("optional fixed-owner canonical comparison", "static func matches(_ lhs: String?, _ rhs: String?)" in identity),
    ("duplicate canonical association rejection", "left.count == lhs.count && right.count == rhs.count" in identity),
    ("association enabled-bit comparison", "return left == right" in identity),
    ("schema-3 backup topology mirror canonicalized", "BackupBundleIdentity.sameStates" in models and "BackupBundleIdentity.sameSet" in models),
    ("manifest owner canonicalized", "BackupBundleIdentity.matches(manifest.hardBoundBundleIdentifier" in models),
    ("restore installed-app set canonicalized", "let installedKeys = HelperBundleIdentifierKey.set(installedBundleIdentifiers)" in models),
    ("export manifest owner canonicalized", "BackupBundleIdentity.matches(decodedManifest.hardBoundBundleIdentifier" in service),
    ("export association state canonicalized", "BackupBundleIdentity.sameStates" in service),
    ("mixed-case backup regression test", "testSchemaThreeAcceptsCaseVariantBundleIdentityMirrors" in codec_tests),
    ("case-variant duplicate regression test", "testSchemaThreeRejectsCaseVariantDuplicateAssociations" in codec_tests),
    ("restore preview case regression test", "testRestorePreviewMatchesInstalledAppsCaseInsensitively" in codec_tests),
]
for label, passed in checks:
    if not passed:
        raise SystemExit(f"FAIL: {label}")
print(f"P2-43-R1 backup lifecycle audit: {len(checks)} assertions passed")
