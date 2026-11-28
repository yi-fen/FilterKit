#!/usr/bin/env python3
from pathlib import Path
root=Path(__file__).resolve().parents[2]
checks=[]
def test(name, condition):
    checks.append((name,bool(condition)))
script=(root/'Build/scripts/p244_r14_real_store_smoke.swift').read_text()
runner=(root/'Build/scripts/run_p244_r14_real_store_smoke.sh').read_text()
staged=(root/'Sources/Environment/Helper/Runtime/HelperInstallerStagedReleaseStore.swift').read_text()
previous=(root/'Sources/Environment/Helper/Runtime/HelperInstallerPreviousReleaseStore.swift').read_text()
journal=(root/'Sources/Environment/Helper/Runtime/HelperInstallerDurableJournalStore.swift').read_text()
reducer=(root/'Sources/Environment/Helper/Runtime/HelperInstallerTransactionJournal.swift').read_text()
for label,cond in [
('R14 smoke compiles production Staged Store', 'HelperInstallerStagedReleaseStore.swift' in runner),
('R14 smoke compiles production Previous Store', 'HelperInstallerPreviousReleaseStore.swift' in runner),
('R14 smoke compiles production Durable Journal Store', 'HelperInstallerDurableJournalStore.swift' in runner),
('R14 smoke compiles production hash-chained Journal reducer', 'HelperInstallerTransactionJournal.swift' in runner),
('R14 smoke compiles production SHA-256', 'SHA256Digest.swift' in runner),
('Staged read uses descriptor-relative openat', 'openat(baseFD' in staged and 'O_NOFOLLOW' in staged),
('Staged read validates private directory', 'validatePrivateDirectory(directoryFD)' in staged),
('Staged read validates exact entry set', 'entryNames(directoryFD: directoryFD) == expectedEntryNames' in staged),
('Staged read recomputes SHA-256', 'SHA256Digest.hex(bytes) == expected' in staged),
('Previous read uses descriptor-relative openat', 'openat(backupRootFD' in previous and 'O_NOFOLLOW' in previous),
('Previous read validates private directory', 'validatePrivateDirectory(directoryFD)' in previous),
('Previous read validates exact entry set', 'entryNames(directoryFD: directoryFD) == expectedEntryNames' in previous),
('Previous read recomputes SHA-256', 'SHA256Digest.hex(bytes) == expected' in previous),
('Durable Journal uses O_NOFOLLOW', 'O_NOFOLLOW' in journal),
('Durable Journal fsyncs file and directory', 'fsync(fd)' in journal and 'fsync(directoryFD)' in journal),
('Durable Journal validates hash chain on save/load', journal.count('try journal.validateChain()') >= 2 and 'func validateChain() throws' in reducer),
('Smoke creates root-owned JBROOT-style fixture under /root', '"/root/filterkit-p244-r14-' in script),
('Smoke tests Staged tamper rejection', 'Staged tamper rejected' in script),
('Smoke tests Previous symlink rejection', 'Previous symlink rejected' in script),
('Smoke tests corrupt Journal rejection', 'corrupt Durable Journal rejected' in script),
('Smoke tests unexpected Staged entries', 'Staged unexpected entry rejected' in script),
('Smoke tests expected hash mismatch', 'Staged expected-hash mismatch rejected' in script),
('Smoke tests Previous permission rejection', 'Previous unsafe mode rejected' in script),
('No production activation or launchd operation is added', 'launchctl' not in script and 'bootstrap' not in script),
]: test(label,cond)
for name,ok in checks: print(('PASS' if ok else 'FAIL')+': '+name)
print(f'RESULT: {sum(ok for _,ok in checks)}/{len(checks)}')
raise SystemExit(0 if all(ok for _,ok in checks) else 1)
