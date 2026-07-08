#!/usr/bin/env python3
"""MCP server exposing ckRemote ck*Profile runs as agent-callable tools.

Local only: shells out to `ckRemote` then `ckRemote pull`, then reads local
output. Registered at user level by setup.sh.
"""

import asyncio
import json
import os
import re
import signal
import sys
from pathlib import Path

from mcp.server.fastmcp import FastMCP

sys.path.insert(0, str(Path(__file__).resolve().parent))
import job_store  # noqa: E402
import validation  # noqa: E402

# Output subdir per mode under ck_profile_out/, for `ckRemote pull`.
MODE_OUTPUT_DIR = {
    "ckStaticProfile": "static",
    "ckRunProfile": "dynamic",
    "ckTraceProfile": "trace",
    "ckCfgProfile": "cfg",
    "ckComputeProfile": "compute",
}

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
    stdout, stderr = await proc.communicate()
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
    finally:
        _owned_jobs.discard(job_id)


async def _run_job_body(job_id, mode, arch, target, repo, server):
    log_path = _store.log_path(job_id)
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
        _store.set_running(job_id, proc.pid)
        timeout_s = job_store.MODE_TIMEOUTS_S[mode]
        try:
            remote_rc = await asyncio.wait_for(proc.wait(), timeout=timeout_s)
        except asyncio.TimeoutError:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            await proc.wait()
            _store.write_exit(job_id, remote_rc=None, note="timeout")
            return

    if remote_rc != 0:
        _store.write_exit(job_id, remote_rc=remote_rc, pull_rc=None)
        return

    _store.set_state(job_id, "pulling")
    pull_argv = [
        "ckRemote",
        "-t",
        server,
        "pull",
        f"ck_profile_out/{MODE_OUTPUT_DIR[mode]}",
    ]
    pull_proc = await asyncio.create_subprocess_exec(*pull_argv, cwd=repo, env=env)
    pull_rc = await pull_proc.wait()
    _store.write_exit(job_id, remote_rc=remote_rc, pull_rc=pull_rc)


@mcp.tool()
async def run_profile(
    mode: str, arch: str, target: str, repo: str, server: str | None = None
) -> dict:
    """Start a ck*Profile run as a background job; poll with get_job_status. Rejected if the server is busy."""
    validation.validate_mode(mode)
    validation.validate_arch(arch)
    repo = validation.validate_repo(repo)
    validation.validate_target(target, repo)

    async with _dispatch_lock:
        _store.prune()
        resolved_server = await _resolve_server(arch, server)
        if _store.is_server_busy(resolved_server):
            raise ValueError(
                f"server '{resolved_server}' already has a job in flight; rejected (no queue)"
            )
        job_id = _store.create(mode, arch, target, repo, resolved_server)

    asyncio.create_task(_run_job(job_id, mode, arch, target, repo, resolved_server))
    return {"job_id": job_id, "server": resolved_server, "state": "running"}


@mcp.tool()
def get_job_status(job_id: str) -> dict:
    """Poll a job: running -> pulling -> done | failed | pull_failed | timeout."""
    validation.validate_job_id(job_id)
    return _store.get_status(job_id)


@mcp.tool()
def get_summary(job_id: str) -> dict:
    """Read summary.json for a finished job. Only ckRunProfile emits one; other modes raise."""
    validation.validate_job_id(job_id)
    status = _store.get_status(job_id)
    mode_dir = Path(status["repo"]) / "ck_profile_out" / MODE_OUTPUT_DIR[status["mode"]]
    summary_path = mode_dir / "latest" / "summary.json"
    if not summary_path.exists():
        raise ValueError(
            f"no summary.json for mode '{status['mode']}'; "
            f"read the report directly under {mode_dir / 'latest'}"
        )
    with open(summary_path) as f:
        return json.load(f)


if __name__ == "__main__":
    mcp.run()
