#!/usr/bin/env python3
from pathlib import Path
import re, sys
ROOT = Path(__file__).resolve().parents[2]
STORE = (ROOT / 'Sources/Environment/Helper/Runtime/HelperInstallerDurableJournalStore.swift').read_text()
checks = []
def check(name, condition): checks.append((name, bool(condition)))
check('descriptor-relative openat traversal', 'openat(' in STORE and 'O_NOFOLLOW' in STORE)
check('all ancestor directories checked', 'ancestor.st_uid == 0 || (ancestor.st_mode & 0o200) == 0' in STORE)
check('group/world writable ancestors rejected', '(ancestor.st_mode & 0o022) == 0' in STORE)
check('final store root-owned group-root 0700', 'ancestor.st_uid == 0, ancestor.st_gid == 0' in STORE and '== 0o700' in STORE)
check('temporary journal created exclusively and no-follow', 'O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW' in STORE)
check('journal file private 0600', '== 0o600' in STORE)
check('journal file root owned', 'info.st_uid == 0, info.st_gid == 0' in STORE)
check('journal single hardlink enforced', 'st_nlink == 1' in STORE)
check('write loop retries EINTR', 'errno == EINTR' in STORE)
check('file fsync before rename', STORE.index('fsync(fd)') < STORE.index('renameat('))
check('atomic descriptor-relative rename', 'renameat(directoryFD, source, directoryFD, destination)' in STORE)
check('directory fsync after rename', STORE.index('renameat(') < STORE.index('fsync(directoryFD)'))
check('existing journal opened no-follow and nonblocking', 'openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK' in STORE)
check('existing journal chain validated before replacement', 'existing.validateChain()' in STORE)
check('journal immutable header checked', 'existing.releaseIdentifier == candidate.releaseIdentifier' in STORE and 'existing.generation == candidate.generation' in STORE)
check('journal append-only prefix enforced', 'Array(candidate.entries.prefix(existing.entries.count)) == existing.entries' in STORE)
check('stale journal rollback rejected', 'candidate.sequence >= existing.sequence' in STORE)
check('same-head idempotent save constrained', 'candidate.sequence == existing.sequence && candidate != existing' in STORE)
check('read metadata stability checked', 'before == FileIdentity(afterInfo)' in STORE)
check('no production capability gate opened', 'executionReleased = true' not in STORE and 'productionMutationReleased = true' not in STORE)
failed = [n for n, ok in checks if not ok]
for name, ok in checks: print(('PASS ' if ok else 'FAIL ') + name)
print(f'RESULT {len(checks)-len(failed)}/{len(checks)}')
if failed: print('FAILED: ' + ', '.join(failed), file=sys.stderr); sys.exit(1)
