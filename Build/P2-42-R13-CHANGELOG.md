# P2-42-R13

## Scope

Implement the clarified lifecycle behavior while preserving the page boundary:

- APP is the only page that performs first injection and per-App enable/disable.
- A successful first injection is enabled by default; subsequent first-time injection batches also default the newly targeted App to enabled.
- Plugin page only edits Additional App Associations and requests plugin uninstall. It does not expose or mutate retained App activation bits.

## Association removal

- Plugin-page association membership removal is allowed even when that association is currently enabled.
- Added `HelperPluginAssociationFilterMutationPlanner` in the Helper execution target.
- The Helper verifies the existing Filter.plist Bundle set against the ownership Manifest, removes the departing active Bundle target from Filter.plist, and prepares the updated Filter.plist and Manifest as one existing journaled two-file commit.
- New associations remain disabled by default. Retained associations must preserve their activation bit; Plugin page cannot enable/disable them.
- If Classes/Executables rules make a safe per-App disable ambiguous, the Helper rejects the association edit rather than leaving the App able to load the plugin.

## Uninstall

- Plugin-page uninstall no longer requires every association's desired activation bit to be false.
- The Helper still verifies ownership, package-manager exclusion, file hashes, plugin identity, Filter.plist/Manifest consistency, and fresh authorization immediately before mutation.
- The existing journaled three-file transaction removes the dylib, Filter.plist, and FilterKit Manifest together. No future App launch can load this plugin after commit.
- An App process that already loaded the dylib may retain its mapped image until that process exits/restarts; uninstall cannot safely unload an image from another running process.

## Safety boundaries

- Plugin page has no per-App activation toggle or activation-bit edit path.
- Fixed Owner identity remains immutable.
- Production plugin uninstall execution and production mutation gates remain closed.
