"""Job state store for the ck-profile MCP server.

Layout: <base_dir>/<job_id>/{status.json, exit.json, log}. exit.json is a
terminal sentinel written atomically (temp file + rename) by whatever ran the
job. Reconciliation derives terminal state lazily on every read, so it also
recovers correctly across a server restart.
"""

import json
import os
import signal
import tempfile
import time
import uuid
from pathlib import Path

TERMINAL_STATES = frozenset({"done", "failed", "pull_failed", "timeout", "rejected"})

# Mode-aware timeouts: static/cfg are fast local build/disassemble steps; the
# rest can legitimately run long on a slurm-queued shared server.
MODE_TIMEOUTS_S = {
    "ckStaticProfile": 10 * 60,
    "ckCfgProfile": 10 * 60,
    "ckRunProfile": 60 * 60,
    "ckTraceProfile": 60 * 60,
    "ckComputeProfile": 60 * 60,
}

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
    if pid is None:
        return False
    ticks = _proc_start_ticks(pid)
    if ticks is None:
        return False
    if recorded_start_ticks is not None and ticks != recorded_start_ticks:
        return False  # PID reused by an unrelated process
    return True


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
        with open(self._status_path(job_id)) as f:
            return json.load(f)

    def _write_status(self, job_id, data):
        _atomic_write_json(self._status_path(job_id), data)

    def create(self, mode, arch, target, repo, server):
        # No server-busy check here; callers must check is_server_busy first,
        # inside the same lock that guards this call.
        job_id = str(uuid.uuid4())
        job_dir = self._job_dir(job_id)
        job_dir.mkdir(parents=True)
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
            "started_at": None,
            "timeout_s": MODE_TIMEOUTS_S[mode],
        }
        self._write_status(job_id, status)
        return job_id

    def set_running(self, job_id, pid):
        status = self._read_status(job_id)
        status["pid"] = pid
        status["proc_start_ticks"] = _proc_start_ticks(pid)
        status["started_at"] = time.time()
        self._write_status(job_id, status)

    def set_state(self, job_id, state, **extra):
        status = self._read_status(job_id)
        status["state"] = state
        status.update(extra)
        self._write_status(job_id, status)

    def write_exit(self, job_id, remote_rc, pull_rc=None, note=None):
        exit_data = {
            "remote_rc": remote_rc,
            "pull_rc": pull_rc,
            "note": note,
            "finished_at": time.time(),
        }
        _atomic_write_json(self._exit_path(job_id), exit_data)
        self._reconcile(job_id)

    def _terminal_state_from_exit(self, exit_data):
        if exit_data.get("note") == "timeout":
            return "timeout"
        if exit_data.get("remote_rc") not in (0, None):
            return "failed"
        if exit_data.get("pull_rc") not in (0, None):
            return "pull_failed"
        return "done"

    def _kill_job(self, job_id, status):
        pid = status.get("pid")
        if pid is not None:
            try:
                os.killpg(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            except PermissionError:
                pass

    def _reconcile(self, job_id):
        status = self._read_status(job_id)
        if status["state"] in TERMINAL_STATES:
            return status

        exit_path = self._exit_path(job_id)
        if exit_path.exists():
            with open(exit_path) as f:
                exit_data = json.load(f)
            status["state"] = self._terminal_state_from_exit(exit_data)
            status["remote_rc"] = exit_data.get("remote_rc")
            status["pull_rc"] = exit_data.get("pull_rc")
            status["note"] = exit_data.get("note")
            status["finished_at"] = exit_data.get("finished_at")
            self._write_status(job_id, status)
            return status

        started_at = status.get("started_at")
        if started_at is not None and time.time() - started_at > status["timeout_s"]:
            self._kill_job(job_id, status)
            self.write_exit(job_id, remote_rc=None, note="timeout")
            return self._read_status(job_id)

        if (
            not self._is_owned(job_id)
            and status.get("pid") is not None
            and not _pid_alive(status["pid"], status.get("proc_start_ticks"))
        ):
            status["state"] = "failed"
            status["note"] = "subprocess died before writing a terminal sentinel"
            self._write_status(job_id, status)
            return status

        return status

    def get_status(self, job_id):
        return self._reconcile(job_id)

    def is_server_busy(self, server):
        for job_dir in self.base_dir.iterdir():
            if not job_dir.is_dir():
                continue
            status = self._reconcile(job_dir.name)
            if status["server"] == server and status["state"] not in TERMINAL_STATES:
                return True
        return False

    def prune(self):
        # Drop terminal entries older than RETENTION_AGE_S, then cap to the
        # RETENTION_MAX_TERMINAL most recent. Non-terminal jobs are never pruned.
        import shutil

        terminal = []
        for job_dir in self.base_dir.iterdir():
            if not job_dir.is_dir():
                continue
            status = self._reconcile(job_dir.name)
            if status["state"] in TERMINAL_STATES:
                terminal.append((job_dir, status))

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
