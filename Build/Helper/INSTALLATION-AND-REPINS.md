# FilterKit Helper — Installation, lifecycle and re-pin contract

## Status

This is a deployment contract and artifact template, not an installer. P1-21 does not bootstrap, bootout, install, remove, or re-sign a Helper on a device.

## Fixed layout (derived from the validated jbroot)

- Executable: `<jbroot>/usr/libexec/filterkit-helper` — `root:wheel`, `0755`
- LaunchDaemon plist: `<jbroot>/Library/LaunchDaemons/cn.yfen.filterkit.helper.plist` — `root:wheel`, `0644`
- Manifest: `<jbroot>/Library/FilterKit/Helper/manifest.json` — `root:wheel`, `0600`
- Audit directory: `<jbroot>/Library/FilterKit/Helper` — `root:wheel`, `0700`
- Socket: `<jbroot>/Library/FilterKit/Helper/helper.sock` — runtime-created; mode `0666` is reachability only, never trust evidence.

The runtime resolves jbroot through the existing libroot runtime probe. If libroot cannot provide a validated jbroot, startup fails closed; no `/var/jb` fallback is guessed.

## Launchd lifecycle

The supplied plist template is deliberately disabled (`Disabled=true`, `RunAtLoad=false`, `KeepAlive=false`). A future trusted root installer may generate the final plist only after device validation. The candidate persistent profile is RunAtLoad + KeepAlive with ThrottleInterval 10 seconds; this candidate is not enabled by this template.

## Install / start / stop / uninstall

All lifecycle transitions belong to a trusted root package installer/repair flow, never the App and never the Helper's three-operation IPC API. The installer must:

1. Validate the selected jbroot and route profile.
2. Install the executable and plist with the fixed owner/modes above.
3. Compute fresh App and Helper CDHashes after final signing.
4. Write a root-owned `0600` manifest with `executionEnabled=false` initially.
5. Bootstrap only the exact FilterKit label through the target jailbreak's supported launchd path.
6. On stop/uninstall: stop/bootout the exact label, verify socket path is a socket owned by root and inside the FilterKit helper directory, then unlink it; never unlink an arbitrary pre-existing path.
7. Remove only FilterKit-owned executable/plist/manifest/audit/staging artifacts. Do not scan or remove other jailbreak files.

P1-21 intentionally supplies no generic `launchctl` shell script because RootHide and Rootless bootstrap entry points and package lifecycle hooks have not been device-verified.

## Re-pin

CDHash change is a trust break, not a prompt for the App to accept a new hash. Stop the service, verify the new App and Helper artifacts in a trusted root installer, compute fresh hashes, atomically replace the root-owned manifest, then restart. App requests cannot update the manifest or authorize a re-pin.

## Execution gate

Even if a future manifest sets `executionEnabled=true`, the P1-21 runtime still rejects every operation request: no root file executor is linked. Health check is the only accepted operation. P1-22 must add fd-relative path handling and a separate explicit release gate before any deployment execution.
