# FilterKit RootHide DEB Profile

> This is the default **RootHide rootfs-layout packaging profile**. It describes the DEB package-manager metadata and payload layout only. It does not mean the app binary is RootHide-native, signed, entitled, installable, accepted by amfid, or verified on a RootHide device.

## Profile

`Config/DEB/roothide.env` is the single source for the packaging profile identifier and expected package metadata:

| Key | Value | Meaning |
|---|---|---|
| `DEB_PROFILE_ID` | `roothide-rootfs` | Default DEB packaging profile |
| `DEB_PACKAGE_ARCH` | `iphoneos-arm64e` | dpkg package Architecture field, based on the archived same-device package comparison |
| `DEB_PAYLOAD_RELATIVE_PATH` | `Applications/FilterKit.app` | Rootfs-relative payload path; no `var/jb/` prefix |
| `DEB_MINIMUM_BINARY_ARCH` | `arm64` | Minimum Mach-O slice checked separately from the dpkg Architecture field |
| `DEB_REQUIRE_ROOT_OWNER_GROUP` | `1` | Requires `dpkg-deb --root-owner-group`; no ownership downgrade |

**Important distinction:** `Architecture: iphoneos-arm64e` is the package-manager architecture label. It is not a command to compile the app as an arm64e Mach-O slice. The iOS device binary is independently checked for an `arm64` slice. Do not force `arm64e`, add `-weak-lroothide`, add an rpath, or link `libroothide` without verifying the target RootHide SDK/header/library and actual API use.

## Package layout

```text
FilterKit.deb
├── Applications/
│   └── FilterKit.app/
│       ├── FilterKit
│       ├── Info.plist
│       └── app resources / Frameworks / PlugIns (when present)
└── DEBIAN/
    ├── control
    └── postinst
```

- `control` Package must match `CFBundleIdentifier`.
- Debian Version base (before the final `-<revision>`) must match `CFBundleShortVersionString`.
- Version single source: `project.yml` `MARKETING_VERSION` (`0.1.0`) → App `CFBundleShortVersionString`; `CURRENT_PROJECT_VERSION` (`1`) → `CFBundleVersion`. The DEB control Version is `0.1.0-1` (marketing base `0.1.0` + packaging revision `-1`); do not maintain a third independent version string.
- Payload is rootfs-relative `Applications/FilterKit.app`; do not add `var/jb/`.
- `postinst` remains byte-identical to the reviewed registration-only script and is syntax checked.
- `dpkg-deb --root-owner-group` is mandatory. If unsupported, packaging fails rather than retaining host uid/gid.

## Build and validate

```bash
APP_PATH=/path/to/Release-iphoneos/FilterKit.app \
DEB_PROFILE_ID=roothide-rootfs \
OUT_DEB=build/deb/filterkit_0.1.0-1_iphoneos-arm64e.deb \
  bash scripts/package-deb.sh

SOURCE_APP_PATH=/path/to/Release-iphoneos/FilterKit.app \
DEB_PATH=build/deb/filterkit_0.1.0-1_iphoneos-arm64e.deb \
PACKAGE_VALIDATION_SUMMARY_PATH=build/deb/deb-summary.json \
  bash scripts/validate-deb.sh
```

`validate-deb.sh` checks archive extraction, control/profile identity, postinst policy, rootfs-relative layout, root:root ownership, declared executable, complete source-vs-packaged bundle parity, Mach-O arm64 slice (when `lipo` is available), and signature state. CI sets `REQUIRE_DEB_VALIDATION_TOOLS=1`, so required tool checks cannot silently remain unavailable.

## Status vocabulary

| Status | Meaning |
|---|---|
| RootHide package layout passed | Static package metadata and layout checks passed |
| Unsigned | Structure package has no device signing; not an installability claim |
| Signed valid | Apple codesign verification passed; still not proof RootHide/amfid acceptance |
| ldid signed embedded | `LC_CODE_SIGNATURE` and embedded entitlement payload statically verified; RootHide acceptance remains pending |
| Device install pending | Bootstrap install, uicache registration, GUI launch and permission evidence not yet obtained |
| Device verified | Reserved for separately authorized RootHide real-device evidence |

## Not established by this profile

- RootHide-specific binary linkage, `libroothide` weak-linking or rpath requirements;
- private entitlement acceptance or runtime sandbox permissions;
- Bootstrap's actual `/Applications` mapping and `uicache` behavior;
- DEB installation success or GUI launch stability;
- RootHide GUI-process JBROOT/TweakInject access or actual ElleKit plugin loading.

These remain separate R4-G / R3 real-device gates. A package-validation pass must never be reported as `RootHide-Ready` or `Device-Verified`.
