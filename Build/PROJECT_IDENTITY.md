# FilterKit App Identity — P0-02

| Field | Value |
|---|---|
| Xcode project / scheme | `FilterKit` |
| Target | `FilterKit` (iOS application) |
| Product name | `FilterKit` |
| Display name | `FilterKit` |
| Bundle identifier | `cn.yfen.filterkit` |
| Marketing version | `1.0.0` (initial baseline) |
| Build number | `1` (initial baseline) |
| Deployment target | iOS `15.0` (provisional; compatibility validation remains open) |
| Device families | iPhone and iPad |

## Code signing policy

- Xcode project signing style is `Automatic` for a developer's local Xcode workflow.
- No Apple Developer Team ID, certificate, provisioning profile, or entitlement is hardcoded.
- The shared build scripts and CI currently pass `CODE_SIGNING_ALLOWED=NO` to produce an unsigned build artifact. This is not an App Store distribution-signed build and does not claim installation readiness on a stock device.
- Jailbreak packaging/signing policy will be decided in the environment-specific packaging phase after RootHide/Rootless requirements are verified. Do not add privileged entitlements speculatively.

## Verification

Run `./Build/Scripts/verify-project-config.sh` on macOS or Linux for static project-setting checks.
Run `xcodegen generate --spec Project.yml` and `xcodebuild -list -project FilterKit.xcodeproj` on macOS with XcodeGen/Xcode to verify generated Xcode metadata. A successful static check does not replace an actual Xcode build.
