# P2-12 Changelog

- Added `HelperIPCServerRequestPolicy` as the single server-side allow-list for authenticated client request message types.
- Fixed a transport integration defect: plugin filter Prepare and Commit messages were implemented in the dispatcher but omitted from the AF_UNIX server allow-list. Both are now admitted to the dispatcher after peer authentication and handshake validation.
- Kept handshake-only and response-only messages disallowed as client requests.
- Added unit tests for allowed health/maintenance/operation/deployment/association request types and denied response/handshake types.
- Added device-validation and release-gate documentation.
- No production execution or plugin association commit gate was opened.
- Fixed a Darwin/Linux `timeval.tv_usec` type portability issue by using `suseconds_t`, allowing the transport source to be focused-typechecked on Linux as well as parsed for the iOS target.
- Executed a real Linux AF_UNIX host smoke using the Swift production server/client transport: nonce-bound Health round-trip passed and an untrusted test CDHash pin was rejected.
