# P1-03 — ElleKit installation and version inspection

## Scope
Read-only inspection only. This phase does not invoke dpkg, run shell commands,
modify package databases, load libraries, or alter ElleKit configuration.

## Evidence model
- `binaryOnly`: an expected ElleKit-related file exists; this does not prove a
  package version or a running/injected state.
- `packageMetadataOnly`: exactly one installed `Package: ellekit` stanza is
  found in a readable dpkg status database, but no expected ElleKit file was found.
- `metadataFallbackOnly`: the only package record came from `status-old`; it is
  historical evidence, not proof of the currently installed package.
- `installed`: exactly one current installed stanza and the primary
  `usr/lib/libellekit.dylib` are both present.
- `inconsistent`: package metadata and auxiliary files exist, but the primary
  ElleKit library is missing.
- `inconsistent` / `ambiguous`: reserved for conflicting or incomplete evidence.
- `notDetected`: neither evidence source is available.

Version and architecture are read only from an installed dpkg status stanza
(`Status: install ok installed`). Repository `Packages` indexes and filenames
are not treated as proof of installation. `status-old` is a fallback and is
explicitly marked as such.

## Profile handling
The RootHide reference baseline records ElleKit `1.2-3` and commit `16e3e7e`.
If installed package metadata reports version `1.2-3`, the result is only
`versionMatchesCommitUnverified`. The package status stanza does not prove that
the installed binary was built from commit `16e3e7e`; `commit` remains nil and
`commitVerified` remains false. Rootless remains unsupported until a verified
Rootless profile is registered.

## Path references
The binary candidates follow the upstream ElleKit builder's install manifest:
`usr/lib/libellekit.dylib`, `usr/lib/ellekit/pspawn.dylib`,
`usr/lib/ellekit/libinjector.dylib`, `usr/lib/ellekit/MobileSafety.dylib`,
`usr/libexec/ellekit/loader`, and the `usr/lib/TweakLoader.dylib` symlink.
The builder shows `/var/jb` as the Rootless install prefix and an empty prefix
for the non-Rootless package layout. These are reference paths; the runtime
JBROOT adapter still determines the actual root.

## Limitations
- The candidate dpkg status locations and binary paths are probes, not a claim
  that every jailbreak distribution uses the same layout.
- File presence does not prove that ElleKit is currently running or that a
  tweak has loaded into a target process.
- Real Dopamine RootHide and Rootless device validation remains required.

## External references
- ElleKit upstream build/install manifest: https://github.com/dhinakg/ellekit-builder/blob/main/build.sh
- RootHide package index entry for `Package: ellekit`, `Version: 1.2-3`, `Architecture: iphoneos-arm64e`: https://github.com/roothide/roothide.github.io/blob/main/Packages
