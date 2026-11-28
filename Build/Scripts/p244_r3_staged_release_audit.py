#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
STORE = (ROOT / 'Sources/Environment/Helper/Runtime/HelperInstallerStagedReleaseStore.swift').read_text()
checks = []
def check(name, condition): checks.append((name, bool(condition)))
check('fixed Helper release staging root is separate from App payload staging', 'Library/FilterKit/Helper/StagedReleases' in STORE and 'envelope.payload.stagingRootPath' not in STORE)
check('root-owned pre-provisioned staging directory required', 'info.st_uid == 0, info.st_gid == 0' in STORE and '== 0o700' in STORE)
check('staging write requires effective root identity', 'guard geteuid() == 0 else { throw StoreError.notRoot }' in STORE)
check('descriptor-relative no-follow traversal', 'openat(' in STORE and 'O_NOFOLLOW' in STORE)
check('Darwin stage and inspection share the installer acceptance lock', STORE.count('HelperInstallerSharedTransactionLock.withExclusiveLock(jbroot: jbRootPath)') == 2)
check('JBROOT path components are traversed by descriptors', 'for (index, component) in components.enumerated()' in STORE)
check('only coordinator-created prepared install accepted', 'prepared: HelperPreparedRootInstall' in STORE)
check('provisioning envelope digest is rebound', 'SHA256Digest.hex(prepared.provisioningEnvelopeData) == prepared.provisioningEnvelopeSHA256' in STORE)
check('all three artifacts reverified through canonical release verifier', 'HelperRootReleaseSet().verify' in STORE and 'expectedDigests: expected' in STORE)
check('Mach-O code directory and Team identity checked', 'MachOMetadataReader().readSlices' in STORE and 'expectedCDHash' in STORE and 'expectedTeamIdentifier' in STORE)
check('durable Journal stage intent required before writes', 'journal.pendingOperation == .stageRelease' in STORE and 'journalStore.load(transactionID:' in STORE)
check('Journal state/action/release/generation bound to prepared plan', 'journal.releaseIdentifier == prepared.release.releaseIdentifier' in STORE and 'journal.generation == prepared.release.generation' in STORE and 'journal.action == prepared.plan.action' in STORE)
check('transaction directory is exclusive and private', 'mkdirat(baseFD, $0, 0o700)' in STORE and 'transactionAlreadyExists' in STORE)
check('base directory synced after transaction directory creation', STORE.index('mkdirat(baseFD') < STORE.index('fsync(baseFD)'))
check('temporary artifact created exclusive and no-follow', 'O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW' in STORE)
check('artifact mode and ownership are exact', 'fchmod(fd, mode)' in STORE and 'info.st_uid == 0, info.st_gid == 0' in STORE and '(info.st_mode & 0o777) == mode' in STORE)
check('artifact file fsync precedes atomic rename', STORE.index('fsync(fd)') < STORE.index('renameat(directoryFD, source, directoryFD, destination)'))
check('artifact directory fsync follows rename', STORE.index('renameat(directoryFD, source, directoryFD, destination)') < STORE.index('fsync(directoryFD)'))
check('staged artifact re-opened and hashed after write', 'hashArtifact(fileName(for: artifact), artifact: artifact' in STORE)
check('Journal completion saved only after all staged files are durable', STORE.index('fsync(transactionFD)') < STORE.index('completedJournal.apply(.stageRelease)') < STORE.index('journalStore.save(completedJournal)'))
check('uncertain Journal completion preserves staged files', 'journalCommitIndeterminate' in STORE and 'Preserve' in STORE)
check('crash injection preserves partial transaction for inspection', 'catch let StoreError.injectedCrash(artifact)' in STORE and 'no automatic promotion' in STORE)
check('read-only inspection checks regular file, owner, hardlink and exact mode', 'func inspect(prepared:' in STORE and 'st_nlink == 1' in STORE and 'expectedMode' in STORE)
check('exact staged directory inventory enforced', 'fdopendir(duplicate)' in STORE and 'readdir(stream)' in STORE and 'unexpectedEntries' in STORE)
check('read stability includes device/inode/size/time metadata', 'FileIdentity(before) == FileIdentity(after)' in STORE)
check('no activation, launchd bootstrap, or production gate opened', all(x not in STORE for x in ['bootstrapExactJob', 'launchctl', 'executionReleased = true', 'productionMutationReleased = true']))
failed = [name for name, ok in checks if not ok]
for name, ok in checks: print(('PASS ' if ok else 'FAIL ') + name)
print(f'RESULT {len(checks)-len(failed)}/{len(checks)}')
if failed:
    print('FAILED: ' + ', '.join(failed), file=sys.stderr)
    sys.exit(1)
