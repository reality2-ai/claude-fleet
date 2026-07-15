#!/usr/bin/env python3
# fleet-safeio.py — the fd-bound primitives bash cannot express.
#
# WHY THIS EXISTS
#   A validated member id keeps a path inside its dir, but a pre-planted (or
#   race-replanted) SYMLINK at that in-tree path redirects an open to an
#   out-of-tree target. The shell fallbacks (`[[ -L ]]` then `>>`/`jq`) are
#   check-then-open: a concurrent same-dir writer can swap a regular file for a
#   symlink in the window between the test and the open. Only an atomic
#   O_NOFOLLOW open closes that window, and bash has no way to pass O_NOFOLLOW.
#   Likewise, killing a bg-controller by a pid discovered in an earlier step
#   races pid REUSE: the number can name a different process by signal time.
#   pidfd binds the signal to the exact process instance instead.
#
# CONTRACT (all subcommands operate on the FINAL path component no-follow):
#   read    <path>          O_RDONLY|O_NOFOLLOW; copy fd -> stdout
#   append  <path>          O_WRONLY|O_APPEND|O_CREAT|O_NOFOLLOW; copy stdin -> fd
#   write   <path>          atomic same-dir replace: O_EXCL temp -> fsync ->
#                           rename() over dest (rename NEVER descends into a dir, so a
#                           dest that races to a directory fails atomically; a symlink is
#                           replaced, a foreign-owned regular file / dir / special -> refuse)
#   enqueue <inbox> <lock>  ONE locked transaction: flock(lock, no-follow) then no-follow
#                           APPEND stdin -> inbox, then release. Replaces the shell's
#                           `exec 9>>lock` + `>>inbox`.
#   rotate  <src> <dst>     identity-checked snapshot: O_NOFOLLOW-open+fstat src, rename to
#                           dst, reopen dst and require the SAME (dev,ino,regular,owner), then
#                           emit that verified inode's content -> stdout. Immune to a decoy
#                           swapped in the open->rename window (exit 6 on mismatch, 4 if absent).
#   hold-lock <lock>        flock(lock, no-follow), print "LOCKED", hold until stdin EOF,
#                           release. Lets a bash coproc run the drain read-modify-write
#                           under a no-follow lock without opening the lock in shell.
#   signal  <signum> <id>   reap bg-controllers whose argv is [..,*bg-controller.sh,<id>]
#                           via pidfd_open + cmdline re-validation + pidfd_send_signal
#
# EXIT CODES (stable — the shell wrappers branch on them):
#   0  ok
#   2  usage / bad arguments
#   3  refused: target is a symlink or a non-regular / foreign-owned file
#   4  absent: target does not exist (read only)
#   5  primitive unavailable on this platform (e.g. no pidfd) — caller fails closed
#   6  identity mismatch (rotate): the inode was swapped in the open->rename window
#   1  other I/O error
#
# PLATFORM: O_NOFOLLOW is POSIX (Linux + macOS). pidfd_open/pidfd_send_signal are
# Linux-only; `signal` exits 5 elsewhere and the caller falls back to the tmux
# window kill. This helper never follows a final-component symlink on any path.

import errno
import fcntl
import os
import signal as _signal
import stat
import sys

BUFSIZE = 1 << 16


def _open_nofollow_lock(path):
    """Open <path> O_WRONLY|O_CREAT|O_NOFOLLOW as a lock fd. Returns (fd, None) or
    (None, rc) where rc is 3 (symlink/non-regular) or 1 (other)."""
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o644)
    except OSError as e:
        return None, (3 if e.errno in (errno.ELOOP, errno.EMLINK) else 1)
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        return None, 3
    return fd, None


def _die_usage(msg):
    sys.stderr.write("fleet-safeio: %s\n" % msg)
    return 2


def _copy(src_fd, dst_fd):
    while True:
        chunk = os.read(src_fd, BUFSIZE)
        if not chunk:
            break
        off = 0
        while off < len(chunk):
            off += os.write(dst_fd, chunk[off:])


def cmd_read(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as e:
        if e.errno in (errno.ELOOP, errno.EMLINK):
            return 3  # final component is a symlink — refuse
        if e.errno == errno.ENOENT:
            return 4  # absent
        return 1
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            return 3  # fifo/dir/device/socket — not a state doc
        _copy(fd, 1)
        return 0
    finally:
        os.close(fd)


def cmd_append(path):
    try:
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, 0o644)
    except OSError as e:
        if e.errno in (errno.ELOOP, errno.EMLINK):
            return 3  # pre-planted/replanted symlink — refuse, never follow
        return 1
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            return 3
        _copy(0, fd)
        return 0
    finally:
        os.close(fd)


def cmd_write(path):
    d = os.path.dirname(path) or "."
    try:
        os.makedirs(d, exist_ok=True)
    except OSError:
        return 1
    # Refuse to replace anything that is not a plain file we own. lstat so a
    # symlink at dest is inspected as a symlink (never followed). rename() would
    # itself fail on a dir, but we reject up front for a clear, uniform verdict.
    prev_mode = 0o644
    try:
        dst_st = os.lstat(path)
    except OSError as e:
        if e.errno != errno.ENOENT:
            return 1
        dst_st = None
    if dst_st is not None:
        if stat.S_ISLNK(dst_st.st_mode):
            pass  # squatted symlink: rename() below REPLACES the link entry (never
            #       follows it, target untouched) — self-healing, so allow it through.
        elif not stat.S_ISREG(dst_st.st_mode):
            return 3  # dir / fifo / socket / device at dest — refuse (never descend)
        elif dst_st.st_uid != os.geteuid():
            return 3  # foreign-owned regular file — refuse to clobber someone else's doc
        else:
            prev_mode = stat.S_IMODE(dst_st.st_mode)
    # Create a private temp in the SAME directory (so rename is atomic, no cross-
    # device copy). O_EXCL|O_NOFOLLOW: we own this inode, nobody squatted it.
    tmp = "%s/.safeio.%d.%d" % (d, os.getpid(), int.from_bytes(os.urandom(4), "big"))
    try:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, prev_mode)
    except OSError:
        return 1
    try:
        _copy(0, fd)
        os.fsync(fd)
    except OSError:
        os.close(fd)
        _unlink_quiet(tmp)
        return 1
    os.close(fd)
    try:
        os.chmod(tmp, prev_mode)
        os.rename(tmp, path)  # atomic; replaces a dir entry, never descends
        return 0
    except OSError:
        _unlink_quiet(tmp)
        return 1


def _unlink_quiet(p):
    try:
        os.unlink(p)
    except OSError:
        pass


def _cmdline(pid):
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as fh:
            raw = fh.read()
    except OSError:
        return None
    parts = raw.split(b"\0")
    if parts and parts[-1] == b"":
        parts.pop()
    return parts


def _matches(argv, idb):
    # argv == [.., <*bg-controller.sh>, <id>]  (byte-for-byte on the id; the id
    # never enters a regex, so a dotted id cannot widen the match).
    if argv is None or len(argv) < 2:
        return False
    return argv[-1] == idb and argv[-2].endswith(b"bg-controller.sh")


def cmd_signal(signum, mid):
    if not hasattr(os, "pidfd_open") or not hasattr(_signal, "pidfd_send_signal"):
        return 5  # no pidfd on this platform — caller falls back, fails safe
    if not os.path.isdir("/proc"):
        return 5
    idb = mid.encode("utf-8", "surrogateescape")
    signaled = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        if not _matches(_cmdline(pid), idb):
            continue
        try:
            pfd = os.pidfd_open(pid)
        except OSError:
            continue  # died between listdir and open — nothing to signal
        try:
            # Re-validate AFTER binding the pidfd: if the number was recycled to a
            # different process in the gap, its cmdline no longer matches -> skip.
            # The pidfd guarantees the signal below hits THIS instance or ESRCHs;
            # it can never land on a reused pid.
            if not _matches(_cmdline(pid), idb):
                continue
            try:
                _signal.pidfd_send_signal(pfd, signum)
                signaled.append(pid)
            except ProcessLookupError:
                pass  # already gone — safe no-op
            except OSError:
                pass
        finally:
            os.close(pfd)
    for pid in signaled:
        sys.stdout.write("%d\n" % pid)
    return 0


def cmd_enqueue(inbox, lock):
    # ONE transaction: take the no-follow flock, then no-follow APPEND stdin to the inbox,
    # then release. No shell-side `exec 9>>lock` / `>>inbox` — every open here is O_NOFOLLOW
    # + fstat-regular, so a pre-planted OR race-replanted symlink at EITHER path is refused
    # (exit 3), never followed. Mutual exclusion is unchanged: the same lock inode serializes
    # concurrent enqueues and the drain holder (hold-lock).
    lfd, rc = _open_nofollow_lock(lock)
    if lfd is None:
        return rc
    try:
        fcntl.flock(lfd, fcntl.LOCK_EX)
        try:
            ifd = os.open(inbox, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, 0o644)
        except OSError as e:
            return 3 if e.errno in (errno.ELOOP, errno.EMLINK) else 1
        try:
            if not stat.S_ISREG(os.fstat(ifd).st_mode):
                return 3
            _copy(0, ifd)
            return 0
        finally:
            os.close(ifd)
    finally:
        os.close(lfd)  # closing the lock fd releases the flock


def cmd_rotate(src, dst):
    # Atomically GRAB <src> as <dst> AND emit its content, as ONE identity-checked snapshot —
    # so the drain reads exactly the inode it validated, immune to a same-owner regular-file
    # swap in the open->rename window (rename-by-name alone would capture a decoy swapped in
    # that gap). Steps: O_NOFOLLOW-open src + fstat (regular, ours); rename(src->dst); reopen
    # dst O_NOFOLLOW + fstat and require the SAME (st_dev, st_ino, regular, owner); only then
    # copy the verified fd to stdout. Exit: 0 ok, 3 src is a symlink/non-regular/foreign,
    # 4 src absent, 6 identity MISMATCH (a swap happened -> fail closed, emit nothing), 1 other.
    try:
        fd = os.open(src, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as e:
        if e.errno == errno.ENOENT:
            return 4
        if e.errno in (errno.ELOOP, errno.EMLINK):
            return 3
        return 1
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.geteuid():
            return 3
        try:
            os.rename(src, dst)
        except OSError:
            return 1
        try:
            vfd = os.open(dst, os.O_RDONLY | os.O_NOFOLLOW)
        except OSError:
            return 6  # dst is not openable no-follow (a symlink/decoy raced in) -> mismatch
        try:
            vst = os.fstat(vfd)
            if ((vst.st_dev, vst.st_ino) != (st.st_dev, st.st_ino)
                    or not stat.S_ISREG(vst.st_mode)
                    or vst.st_uid != os.geteuid()):
                return 6  # a swap happened in the window: dst is NOT our validated inode
            _copy(vfd, 1)  # emit the exact validated snapshot content
            return 0
        finally:
            os.close(vfd)
    finally:
        os.close(fd)


def cmd_rename(src, dst):
    # Plain atomic rename(src -> dst), used ONLY to RESTORE a snapshot ($snap -> inbox) when
    # the drain aborts, so mail is never lost. rename never descends (a dir at dst fails
    # atomically) and never follows a final symlink. Exit: 0 ok, 4 src absent, 1 other.
    try:
        os.rename(src, dst)
        return 0
    except OSError as e:
        return 4 if e.errno == errno.ENOENT else 1


def cmd_hold_lock(lock):
    # Acquire the no-follow flock and HOLD it until stdin closes, so a bash coprocess can
    # run an arbitrary read-modify-write (the drain) under it without ever opening the lock
    # itself. Prints "LOCKED" once the flock is held; releases on EOF (shell closes the
    # coproc write end) or on any signal. Refuses a symlinked/non-regular lock (exit 3).
    lfd, rc = _open_nofollow_lock(lock)
    if lfd is None:
        return rc
    try:
        fcntl.flock(lfd, fcntl.LOCK_EX)
        sys.stdout.write("LOCKED\n")
        sys.stdout.flush()
        # Block until the controlling shell closes our stdin, then fall through to release.
        try:
            while os.read(0, BUFSIZE):
                pass
        except OSError:
            pass
        return 0
    finally:
        os.close(lfd)


def main(argv):
    if len(argv) < 2:
        return _die_usage("usage: fleet-safeio {read|append|write|signal} ...")
    cmd = argv[1]
    if cmd in ("read", "append", "write", "hold-lock"):
        if len(argv) != 3:
            return _die_usage("%s needs exactly one <path>" % cmd)
        path = argv[2]
        if cmd == "read":
            return cmd_read(path)
        if cmd == "append":
            return cmd_append(path)
        if cmd == "hold-lock":
            return cmd_hold_lock(path)
        return cmd_write(path)
    if cmd == "enqueue":
        if len(argv) != 4:
            return _die_usage("enqueue needs <inbox> <lock>")
        return cmd_enqueue(argv[2], argv[3])
    if cmd == "rotate":
        if len(argv) != 4:
            return _die_usage("rotate needs <src> <dst>")
        return cmd_rotate(argv[2], argv[3])
    if cmd == "rename":
        if len(argv) != 4:
            return _die_usage("rename needs <src> <dst>")
        return cmd_rename(argv[2], argv[3])
    if cmd == "signal":
        if len(argv) != 4:
            return _die_usage("signal needs <signum> <id>")
        try:
            signum = int(argv[2])
        except ValueError:
            return _die_usage("signal <signum> must be an integer")
        return cmd_signal(signum, argv[3])
    return _die_usage("unknown subcommand %r" % cmd)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except BrokenPipeError:
        # reader (e.g. jq) closed early; not our failure
        try:
            os.close(1)
        except OSError:
            pass
        sys.exit(0)
    except KeyboardInterrupt:
        sys.exit(130)
