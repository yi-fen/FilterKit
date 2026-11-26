# P2-15 Changelog

- Revalidate connected-socket UID/GID/PID after peer code-identity lookup on both client and server paths.
- Reject identity-provider results whose UID/GID/PID do not match the kernel socket credentials.
- Factor the binding rule into `HelperPeerIdentityBindingPolicy` and add unit tests.
- Make audit append and rotation durability explicit with file and directory `fsync` calls; synchronization failures fail the append.
- Add host AF_UNIX and audit-sink smoke runners.
- Keep Darwin PID-generation/Audit Token fields unset; no unsupported token ABI is guessed.
- Keep all plugin commit and general execution gates closed.
