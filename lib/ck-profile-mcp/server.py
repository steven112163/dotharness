#!/usr/bin/env python3
"""MCP server exposing ckRemote ck*Profile runs as agent-callable tools.

Local only: shells out to `ckRemote` then `ckRemote pull`, then reads local
output. Registered at user level by setup.sh.
"""

import asyncio
import json
import os
import re
import sys
from pathlib import Path

from mcp.server.fastmcp import FastMCP

sys.path.insert(0, str(Path(__file__).resolve().parent))
import job_store  # noqa: E402
import validation  # noqa: E402

_JOBS_DIR = Path(
    os.environ.get(
        "CK_PROFILE_MCP_JOBS_DIR",
        str(Path.home() / ".claude" / ".dotharness" / "mcp-jobs"),
    )
)
_SELECT_RE = re.compile(r"(?:Forced|Selected) server '([^']+)'")

mcp = FastMCP("ck-profile")
_owned_jobs = set()
_store = job_store.JobStore(_JOBS_DIR, is_owned=lambda job_id: job_id in _owned_jobs)
_dispatch_lock = asyncio.Lock()
_background_tasks = set()  # strong refs so fire-and-forget tasks aren't GC'd
_SELECT_TIMEOUT_S = 30


async def _resolve_server(arch, forced_server):
    # Asks ckRemote which server it would pick, without dispatching anything,
    # so the name returned matches the later dispatch call's own -t choice.
    argv = ["ckRemote"]
    if forced_server:
        argv += ["-t", forced_server]
    argv += ["-a", arch, "select"]
    proc = await asyncio.create_subprocess_exec(
        *argv, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
    )
    try:
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(), timeout=_SELECT_TIMEOUT_S
        )
    except asyncio.TimeoutError:
        await _ensure_dead(proc)
        raise ValueError(
            f"ckRemote server selection timed out after {_SELECT_TIMEOUT_S}s"
        ) from None
    if proc.returncode != 0:
        raise ValueError(
            f"ckRemote server selection failed: {stderr.decode(errors='replace').strip()}"
        )
    match = _SELECT_RE.search(stdout.decode(errors="replace"))
    if not match:
        raise ValueError("could not parse selected server from ckRemote output")
    return match.group(1)


async def _run_job(job_id, mode, arch, target, repo, server):
    _owned_jobs.add(job_id)
    try:
        await _run_job_body(job_id, mode, arch, target, repo, server)
    except asyncio.CancelledError:
        _write_exit_best_effort(job_id, remote_rc=-1, note="cancelled")
        raise
    except Exception as exc:
        # Any failure here must still reach a terminal state, or the job
        # stays "running" forever and is_server_busy never releases the server.
        _write_exit_best_effort(job_id, remote_rc=-1, note=f"exception: {exc}")
    finally:
        _owned_jobs.discard(job_id)


def _write_exit_best_effort(job_id, **kwargs):
    # Runs from a fire-and-forget task; if write_exit itself raises, log it
    # instead of silently leaving the job non-terminal forever.
    try:
        _store.write_exit(job_id, **kwargs)
    except Exception as exc:
        print(
            f"ck-profile-mcp: failed to write exit for job {job_id}: {exc}",
            file=sys.stderr,
        )


async def _ensure_dead(proc):
    """Kill proc's process group and reap it if it isn't already dead."""
    if proc.returncode is None:
        job_store.kill_process_group(proc.pid)
        await proc.wait()


async def _wait_for_exit(proc, timeout_s):
    """Wait for proc, guaranteeing it's dead (killed and reaped) on any exit
    path. Returns (rc, timed_out)."""
    try:
        rc = await asyncio.wait_for(proc.wait(), timeout=timeout_s)
        return rc, False
    except asyncio.TimeoutError:
        await _ensure_dead(proc)
        return None, True
    finally:
        await _ensure_dead(proc)


async def _run_job_body(job_id, mode, arch, target, repo, server):
    log_path = _store.log_path(job_id)
    timeout_s = job_store.MODES[mode]["timeout_s"]
    # arch is passed twice: -a picks the ckRemote server, --arch is forwarded
    # to the inner ck<Mode>Profile invocation that runs on that server.
    argv = ["ckRemote", "-t", server, "-a", arch, mode, "--arch", arch, target]
    env = dict(os.environ, CK_LOCAL_REPO=repo)
    with open(log_path, "wb") as log_file:
        proc = await asyncio.create_subprocess_exec(
            *argv,
            cwd=repo,
            env=env,
            stdout=log_file,
            stderr=asyncio.subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            _store.set_running(job_id, proc.pid)
            remote_rc, timed_out = await _wait_for_exit(proc, timeout_s)
        finally:
            # Covers set_running raising before _wait_for_exit's own cleanup runs.
            await _ensure_dead(proc)

    if timed_out:
        _store.write_exit(job_id, remote_rc=None, timed_out=True)
        return
    if remote_rc != 0:
        _store.write_exit(job_id, remote_rc=remote_rc, pull_rc=None)
        return

    pull_argv = [
        "ckRemote",
        "-t",
        server,
        "pull",
        f"ck_profile_out/{job_store.MODES[mode]['output_dir']}",
    ]
    with open(log_path, "ab") as log_file:
        pull_proc = await asyncio.create_subprocess_exec(
            *pull_argv,
            cwd=repo,
            env=env,
            stdout=log_file,
            stderr=asyncio.subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            # Resets started_at so the reconciler uses this phase's own
            # budget (worst case 2 * timeout_s across both phases).
            _store.set_pulling(job_id, pull_proc.pid)
            pull_rc, timed_out = await _wait_for_exit(pull_proc, timeout_s)
        finally:
            await _ensure_dead(pull_proc)

    if timed_out:
        _store.write_exit(job_id, remote_rc=remote_rc, pull_rc=None, timed_out=True)
        return

    summary_path = None
    mode_info = job_store.MODES[mode]
    if mode_info["emits_summary"] and pull_rc == 0:
        # Freeze the resolved path now: "latest" is a shared symlink that a
        # later job on the same repo/mode can repoint before get_summary runs.
        candidate = (
            Path(repo)
            / "ck_profile_out"
            / mode_info["output_dir"]
            / "latest"
            / "summary.json"
        )
        if candidate.exists():
            summary_path = str(candidate.resolve())
    _store.write_exit(
        job_id, remote_rc=remote_rc, pull_rc=pull_rc, summary_path=summary_path
    )


@mcp.tool()
async def run_profile(
    mode: str, arch: str, target: str, repo: str, server: str | None = None
) -> dict:
    """Start a ck*Profile run as a background job; poll with get_job_status. Rejected if the server is busy."""
    validation.validate_mode(mode)
    validation.validate_arch(arch)
    repo = validation.validate_repo(repo)
    target = validation.validate_target(target, repo)
    server = validation.validate_server(server)

    # Resolution is a read-only network round-trip; only the busy-check +
    # create need to be atomic, so the lock is held for just that section.
    resolved_server = await _resolve_server(arch, server)
    async with _dispatch_lock:
        _store.prune()
        if _store.is_server_busy(resolved_server):
            raise ValueError(
                f"server '{resolved_server}' already has a job in flight; rejected (no queue)"
            )
        job_id = _store.create(mode, arch, target, repo, resolved_server)

    task = asyncio.create_task(
        _run_job(job_id, mode, arch, target, repo, resolved_server)
    )
    _background_tasks.add(task)
    task.add_done_callback(_background_tasks.discard)
    return {"job_id": job_id, "server": resolved_server, "state": "running"}


@mcp.tool()
def get_job_status(job_id: str) -> dict:
    """Poll a job: running -> pulling -> done | failed | pull_failed | timeout."""
    validation.validate_job_id(job_id)
    status = _store.get_status(job_id)
    _store.prune()
    return status


@mcp.tool()
def get_summary(job_id: str) -> dict:
    """Read summary.json for a finished job. Only ckRunProfile emits one; other modes raise."""
    validation.validate_job_id(job_id)
    status = _store.get_status(job_id)
    mode_info = job_store.MODES[status["mode"]]
    if not mode_info["emits_summary"]:
        raise ValueError(f"mode '{status['mode']}' does not emit a summary.json")
    if status["state"] != "done":
        raise ValueError(
            f"job '{job_id}' has state '{status['state']}', not 'done'; no summary available"
        )
    # Read the path captured right after this job's own pull phase, not the
    # shared "latest" symlink, which a later job on the same repo/mode may
    # have since repointed.
    summary_path = status.get("summary_path")
    if not summary_path or not Path(summary_path).exists():
        mode_dir = Path(status["repo"]) / "ck_profile_out" / mode_info["output_dir"]
        raise ValueError(
            f"no summary.json for mode '{status['mode']}'; "
            f"read the report directly under {mode_dir / 'latest'}"
        )
    with open(summary_path) as f:
        return json.load(f)


if __name__ == "__main__":
    mcp.run()
