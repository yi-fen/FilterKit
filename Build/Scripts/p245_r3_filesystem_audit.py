from pathlib import Path
root = Path(__file__).resolve().parents[2]
observer = (root / "Sources/Environment/Helper/Runtime/HelperInstallerDescriptorFilesystemObserver.swift").read_text()
executor = (root / "Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift").read_text()
checks = {
    "observer opens JBROOT from filesystem root": 'open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)' in observer,
    "JBROOT components reject symlinks": 'O_NOFOLLOW | O_CLOEXEC' in observer,
    "relative paths reject absolute paths": '!relativePath.hasPrefix("/")' in observer,
    "relative paths reject dot traversal": '$0 != ".."' in observer and '$0 != "."' in observer,
    "intermediate directories owner checked": 'directoryInfo.st_uid == expectedOwnerUID' in observer,
    "intermediate directories group/world write rejected": '(directoryInfo.st_mode & 0o022) == 0' in observer,
    "artifact must be regular file": '(before.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)' in observer,
    "artifact owner checked": 'before.st_uid == expectedOwnerUID' in observer,
    "hard links rejected": 'before.st_nlink == 1' in observer,
    "group/world writable artifacts rejected": '(before.st_mode & 0o022) == 0' in observer,
    "private file permissions constrained": '(!privateFile || (before.st_mode & 0o077) == 0)' in observer,
    "bounded artifact reads": 'before.st_size <= limit' in observer,
    "stable inode checked across read": 'before.st_ino == after.st_ino' in observer,
    "stable timestamps checked across read": 'timestampsEqual(before, after)' in observer,
    "missing state only maps ENOENT": 'where code == ENOENT { result[artifact] = .missing }' in observer,
    "executor uses descriptor-relative openat": 'openat(' in executor,
    "executor rejects symlinks on writes": 'O_NOFOLLOW' in executor,
    "Darwin no-replace rename primitive": 'renameatx_np(fd, a, fd, b, UInt32(RENAME_EXCL))' in executor,
    "Host no-replace rename primitive": 'fk_renameat2(fd, a, fd, b, 1)' in executor,
    "file data fsync before publish": 'guard fsync(fd) == 0' in executor,
    "parent directory fsync after journal publish": 'guard result == 0, fsync(rootFD) == 0' in executor,
    "persistent flock lock": 'flock(fd, LOCK_EX | LOCK_NB)' in executor,
    "lock inode ownership/mode verified": 'st.st_uid == 0, st.st_gid == 0, st.st_nlink == 1' in executor,
    "production activation documented gated": 'wired to HelperRuntime or the production deployment backend' in executor and 'release gate is closed' in executor,
}
failed = 0
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'} {name}")
    failed += not ok
print(f"SUMMARY passed={len(checks)-failed} failed={failed}")
raise SystemExit(1 if failed else 0)
