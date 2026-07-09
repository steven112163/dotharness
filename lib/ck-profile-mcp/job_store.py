"""Job state store for the ck-profile MCP server.

Layout: <base_dir>/<job_id>/{status.json, exit.json, log}. exit.json is a
terminal sentinel written to a temp file then hardlinked into place, so it
only ever appears fully populated. Reconciliation derives terminal state
lazily on every read — via owned-job-aware timeout/dead-PID/never-started
fallbacks when exit.json hasn't landed yet — so it also recovers correctly
across a server restart.
"""

import json
import os
import shutil
import signal
import sys
import tempfile
import time
import uuid
from pathlib import Path
from types import MappingProxyType

TERMINAL_STATES = frozenset({"done", "failed", "pull_failed", "timeout"})

# Single source of truth for mode-aware timeouts, pull output dirs, and
# summary-emitting capability. Wrapped read-only so nothing can add/remove a
# mode entry; per-mode dicts stay plain (tests tweak e.g. timeout_s for speed).
MODES = MappingProxyType(
    {
        "ckStaticProfile": {
            "timeout_s": 10 * 60,
            "output_dir": "static",
            "emits_summary": False,
        },
        "ckCfgProfile": {
            "timeout_s": 10 * 60,
            "output_dir": "cfg",
            "emits_summary": False,
        },
        "ckRunProfile": {
            "timeout_s": 60 * 60,
            "output_dir": "dynamic",
            "emits_summary": True,
        },
        "ckTraceProfile": {
            "timeout_s": 60 * 60,
            "output_dir": "trace",
            "emits_summary": False,
        },
        "ckComputeProfile": {
            "timeout_s": 60 * 60,
            "output_dir": "compute",
            "emits_summary": False,
        },
    }
)

# Keep a day of history for debugging a failed run, but cap total dirs so a
# quiet server doesn't accumulate job dirs forever.
RETENTION_AGE_S = 24 * 60 * 60
RETENTION_MAX_TERMINAL = 50


def _atomic_write_json(path, data):
    d = path.parent
    fd, tmp = tempfile.mkstemp(dir=d, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _proc_start_ticks(pid):
    """/proc/<pid>/stat starttime field, used to detect PID reuse. None if gone."""
    try:
        with open(f"/proc/{pid}/stat") as f:
            raw = f.read()
        # comm (field 2) may contain spaces/parens; split after its closing ')'.
        after = raw.rsplit(")", 1)[1].split()
        return after[19]  # starttime is field 22 overall, index 19 after the split
    except (OSError, IndexError):
        return None


def _pid_alive(pid, recorded_start_ticks):
    # A None baseline (e.g. a race at spawn) also fails closed: this leaks a
    # process rather than risk killing an unrelated one that reused the PID.
    if pid is None or recorded_start_ticks is None:
        return False
    ticks = _proc_start_ticks(pid)
    if ticks is None:
        return False
    if ticks != recorded_start_ticks:
        return False  # PID reused by an unrelated process
    return True


def kill_process_group(pid):
    try:
        os.killpg(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


class JobStore:
    def __init__(self, base_dir, is_owned=None):
        # is_owned(job_id): True if an in-process task owns this job. Skips the
        # dead-PID-without-sentinel fallback for owned jobs, since reaping can
        # race ahead of that task's own write_exit call within one process.
        self.base_dir = Path(base_dir)
        self.base_dir.mkdir(parents=True, exist_ok=True)
        self._is_owned = is_owned or (lambda job_id: False)

    def _job_dir(self, job_id):
        return self.base_dir / job_id

    def _status_path(self, job_id):
        return self._job_dir(job_id) / "status.json"

    def _exit_path(self, job_id):
        return self._job_dir(job_id) / "exit.json"

    def log_path(self, job_id):
        return self._job_dir(job_id) / "log"

    def _read_status(self, job_id):
        try:
            with open(self._status_path(job_id)) as f:
                return json.load(f)
        except FileNotFoundError:
            raise ValueError(f"unknown job_id '{job_id}'") from None

    def _write_status(self, job_id, data):
        _atomic_write_json(self._status_path(job_id), data)

    def create(self, mode, arch, target, repo, server):
        # No server-busy check here; callers must check is_server_busy first,
        # inside the same lock that guards this call.
        job_id = str(uuid.uuid4())
        job_dir = self._job_dir(job_id)
        try:
            # no exist_ok: a uuid4 collision should raise, not silently merge
            job_dir.mkdir(parents=True)
        except FileExistsError:
            raise ValueError(f"job_id collision for '{job_id}'; retry") from None
        status = {
            "job_id": job_id,
            "mode": mode,
            "arch": arch,
            "target": target,
            "repo": repo,
            "server": server,
            "state": "running",
            "pid": None,
            "proc_start_ticks": None,
            "created_at": time.time(),
            "started_at": None,
            "timeout_s": MODES[mode]["timeout_s"],
        }
        self._write_status(job_id, status)
        return job_id

    def set_running(self, job_id, pid):
        status = self._read_status(job_id)
        status["pid"] = pid
        status["proc_start_ticks"] = _proc_start_ticks(pid)
        status["started_at"] = time.time()
        self._write_status(job_id, status)

    def set_pulling(self, job_id, pid):
        # Resets started_at so the timeout reconciler checks the pull phase's
        # own budget, not the run phase's already-elapsed one.
        status = self._read_status(job_id)
        status["state"] = "pulling"
        status["pid"] = pid
        status["proc_start_ticks"] = _proc_start_ticks(pid)
        status["started_at"] = time.time()
        self._write_status(job_id, status)

    def write_exit(
        self,
        job_id,
        remote_rc,
        pull_rc=None,
        note=None,
        timed_out=False,
        summary_path=None,
    ):
        exit_data = {
            "remote_rc": remote_rc,
            "pull_rc": pull_rc,
            "note": note,
            "timed_out": timed_out,
            "summary_path": summary_path,
            "finished_at": time.time(),
        }
        exit_path = self._exit_path(job_id)
        # Write the full payload to a temp file first, then hardlink it into
        # place: exit_path only ever appears once complete, so a crash
        # mid-write can't leave a wedged empty file. os.link is first-writer-
        # wins (fails if exit_path already exists), covering a second caller
        # (e.g. an exception handler racing a successful first write).
        fd, tmp = tempfile.mkstemp(dir=exit_path.parent, prefix=f".{exit_path.name}.")
        try:
            with os.fdopen(fd, "w") as f:
                json.dump(exit_data, f, indent=2)
            try:
                os.link(tmp, exit_path)
            except FileExistsError:
                if not self._discard_or_replace_stale_exit(job_id, exit_path, tmp):
                    return
        finally:
            try:
                os.unlink(tmp)
            except OSError:
                pass
        self._reconcile(job_id)

    def _discard_or_replace_stale_exit(self, job_id, exit_path, tmp):
        """Handle os.link losing the race to an existing exit.json. A valid
        existing file wins (true first-writer-wins); a corrupt/gone one is
        cleared so this call's real result can be linked in instead. Returns
        True if tmp was linked into exit_path, False if the caller should
        give up (its data is left in tmp for the finally block to clean up)."""
        try:
            existing = self._load_exit_if_valid(exit_path)
        except OSError as e:
            print(
                f"ck-profile-mcp: write_exit for job {job_id} found an unreadable "
                f"existing exit.json ({e}); leaving it in place",
                file=sys.stderr,
            )
            return False
        if existing is not None:
            print(
                f"ck-profile-mcp: write_exit for job {job_id} raced with an "
                "existing valid exit.json; keeping it",
                file=sys.stderr,
            )
            return False
        self._unlink_logged(job_id, exit_path, "corrupt/stale exit.json before retry")
        try:
            os.link(tmp, exit_path)
        except FileExistsError:
            print(
                f"ck-profile-mcp: write_exit for job {job_id} exit.json race "
                "persisted after cleanup retry; giving up",
                file=sys.stderr,
            )
            return False
        return True

    @staticmethod
    def _load_exit_if_valid(exit_path):
        """Parsed exit.json, or None if missing/corrupt (safe to discard).
        Other OSErrors (permission, I/O) propagate: those don't mean the
        content is bad, so callers must not treat them as safe to unlink."""
        try:
            with open(exit_path) as f:
                return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            return None

    @staticmethod
    def _unlink_logged(job_id, path, reason):
        try:
            os.unlink(path)
        except OSError as e:
            print(
                f"ck-profile-mcp: job {job_id} failed to unlink {reason} ({path}): {e}",
                file=sys.stderr,
            )

    def _terminal_state_from_exit(self, exit_data):
        if exit_data.get("timed_out"):
            return "timeout"
        if exit_data.get("remote_rc") not in (0, None):
            return "failed"
        if exit_data.get("pull_rc") not in (0, None):
            return "pull_failed"
        return "done"

    def _kill_job(self, status):
        # Guard against PID reuse: only signal if this is still the same
        # process we launched, not an unrelated process that reused the PID.
        pid = status.get("pid")
        if pid is None or not _pid_alive(pid, status.get("proc_start_ticks")):
            return
        kill_process_group(pid)

    def _sync_exit_if_present(self, job_id, status):
        """Merge exit.json into status once it lands. A corrupt or vanished
        exit.json (crash predating the hardlink write path, filesystem
        damage, or a TOCTOU race with prune()) is unlinked so it can't
        permanently block a later write_exit's os.link from a fallback below.
        Other read failures (permission, I/O) don't mean the content is bad,
        so they're logged and left in place rather than discarded."""
        exit_path = self._exit_path(job_id)
        if not exit_path.exists():
            return status
        try:
            exit_data = self._load_exit_if_valid(exit_path)
        except OSError as e:
            print(
                f"ck-profile-mcp: job {job_id} exit.json unreadable ({e}); "
                "leaving it in place",
                file=sys.stderr,
            )
            return status
        if exit_data is None:
            self._unlink_logged(job_id, exit_path, "corrupt/gone exit.json")
            return status
        if not status.get("_synced_from_exit"):
            status["state"] = self._terminal_state_from_exit(exit_data)
            status["remote_rc"] = exit_data.get("remote_rc")
            status["pull_rc"] = exit_data.get("pull_rc")
            status["note"] = exit_data.get("note")
            status["summary_path"] = exit_data.get("summary_path")
            status["finished_at"] = exit_data.get("finished_at")
            status["_synced_from_exit"] = True
            self._write_status(job_id, status)
        return status

    def _guess_terminal_fallback(self, job_id, status):
        # Owned jobs skip every fallback below: the owning task's own
        # write_exit call can race ahead of a concurrent reconciler here, and
        # must be allowed to land the real result instead of a guess.
        if self._is_owned(job_id):
            return status

        started_at = status.get("started_at")
        if started_at is not None and time.time() - started_at > status["timeout_s"]:
            self._kill_job(status)
            self.write_exit(job_id, remote_rc=None, timed_out=True)
            return self._read_status(job_id)

        if status.get("pid") is not None and not _pid_alive(
            status["pid"], status.get("proc_start_ticks")
        ):
            status["state"] = "failed"
            status["note"] = "subprocess died before writing a terminal sentinel"
            self._write_status(job_id, status)
            return status

        # Crashed between create() and set_running(): pid never got set, so
        # neither fallback above ever fires. Time out from created_at instead,
        # or the job (and is_server_busy for its server) wedges forever.
        created_at = status.get("created_at")
        if (
            status.get("pid") is None
            and created_at is not None
            and time.time() - created_at > status["timeout_s"]
        ):
            status["state"] = "failed"
            status["note"] = "job never started running (server likely restarted)"
            self._write_status(job_id, status)
            return status

        return status

    def _reconcile(self, job_id):
        # Assumes a single writer per job_id (unverified against FastMCP's
        # threading model); atomic writes bound the damage if that's wrong.
        status = self._read_status(job_id)

        # Fast path: nothing left to sync or guess for an already-synced
        # terminal job, so skip re-parsing exit.json on every poll.
        if status["state"] in TERMINAL_STATES and status.get("_synced_from_exit"):
            return status

        # Checked before the terminal short-circuit below: a fallback branch
        # (dead-PID, timeout-by-created_at) may have already guessed a
        # terminal state before the real exit.json landed. Always sync the
        # real result in when it shows up, rather than freezing the guess.
        status = self._sync_exit_if_present(job_id, status)
        if status["state"] in TERMINAL_STATES:
            return status

        return self._guess_terminal_fallback(job_id, status)

    def get_status(self, job_id):
        return self._reconcile(job_id)

    def _iter_reconciled(self):
        # A job dir with no status.json (e.g. create() crashed between mkdir
        # and the write) makes _reconcile raise ValueError; treat it as
        # prunable garbage rather than letting it break every job-store call.
        for job_dir in self.base_dir.iterdir():
            if not job_dir.is_dir():
                continue
            try:
                yield job_dir, self._reconcile(job_dir.name)
            except ValueError:
                shutil.rmtree(job_dir, ignore_errors=True)

    def is_server_busy(self, server):
        for _, status in self._iter_reconciled():
            if status["server"] == server and status["state"] not in TERMINAL_STATES:
                return True
        return False

    def prune(self):
        # Drop terminal entries older than RETENTION_AGE_S, then cap to the
        # RETENTION_MAX_TERMINAL most recent. Non-terminal jobs are never pruned.
        terminal = [
            (job_dir, status)
            for job_dir, status in self._iter_reconciled()
            if status["state"] in TERMINAL_STATES
        ]

        now = time.time()
        kept = []
        for job_dir, status in terminal:
            finished_at = status.get("finished_at") or status.get("started_at") or 0
            if now - finished_at > RETENTION_AGE_S:
                shutil.rmtree(job_dir, ignore_errors=True)
            else:
                kept.append((job_dir, status))

        kept.sort(
            key=lambda pair: (
                pair[1].get("finished_at") or pair[1].get("started_at") or 0
            ),
            reverse=True,
        )
        for job_dir, _ in kept[RETENTION_MAX_TERMINAL:]:
            shutil.rmtree(job_dir, ignore_errors=True)
