"""Tests for lib/ck-profile-mcp/server.py — the MCP tool surface.

ckRemote is stubbed via a fake PATH entry (records argv, returns a
configurable exit code) so these tests never touch SSH/GPU infrastructure.

Each test drives run_profile + polling inside a single asyncio.run() call:
run_profile schedules its background job as a task on the *current* loop, so
polling must happen on that same loop before it is torn down.
"""

import asyncio
import importlib
import json
import os
import stat
import sys
import time

import pytest

STUB_CKREMOTE = """#!/usr/bin/env python3
import json
import os
import sys
import time

log_path = os.environ["STUB_CKREMOTE_LOG"]
with open(log_path, "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")

if "select" in sys.argv:
    time.sleep(float(os.environ.get("STUB_CKREMOTE_SELECT_SLEEP_S", "0")))
    print("Selected server 'stubserver' (normal, user@stubserver) for gfx942.")
    sys.exit(0)

if "pull" in sys.argv:
    time.sleep(float(os.environ.get("STUB_CKREMOTE_PULL_SLEEP_S", "0")))
    print("pull-phase-stdout-marker")
    sys.exit(int(os.environ.get("STUB_CKREMOTE_PULL_RC", "0")))

time.sleep(float(os.environ.get("STUB_CKREMOTE_RUN_SLEEP_S", "0")))
print("run-phase-stdout-marker")
sys.exit(int(os.environ.get("STUB_CKREMOTE_RUN_RC", "0")))
"""


@pytest.fixture
def stub_ckremote(tmp_path):
    bin_dir = tmp_path / "stub-bin"
    bin_dir.mkdir()
    script = bin_dir / "ckRemote"
    script.write_text(STUB_CKREMOTE)
    script.chmod(script.stat().st_mode | stat.S_IEXEC)
    log_path = tmp_path / "ckremote-calls.log"
    return bin_dir, log_path


@pytest.fixture
def ck_repo(tmp_path):
    repo = tmp_path / "repo"
    (repo / "script").mkdir(parents=True)
    (repo / "script" / "cmake-ck-dev.sh").write_text("")
    (repo / "CMakeLists.txt").write_text("")
    return repo


@pytest.fixture
def server(tmp_path, stub_ckremote, monkeypatch):
    bin_dir, log_path = stub_ckremote
    monkeypatch.setenv("PATH", f"{bin_dir}:{os.environ['PATH']}")
    monkeypatch.setenv("STUB_CKREMOTE_LOG", str(log_path))
    monkeypatch.setenv("CK_PROFILE_MCP_JOBS_DIR", str(tmp_path / "mcp-jobs"))
    if "server" in sys.modules:
        module = importlib.reload(sys.modules["server"])
    else:
        module = importlib.import_module("server")
    module._log_path = log_path
    return module


def _read_calls(log_path):
    if not log_path.exists():
        return []
    return [json.loads(line) for line in log_path.read_text().splitlines()]


_POLL_MAX_ITERS = 200
_POLL_INTERVAL_S = 0.02


async def _wait_for_terminal_job(server, job_id):
    for _ in range(_POLL_MAX_ITERS):
        status = server.get_job_status(job_id)
        if status["state"] not in ("running", "pulling"):
            return status
        await asyncio.sleep(_POLL_INTERVAL_S)
    raise AssertionError("job did not finish in time")


async def _run_and_wait(server, mode, target, repo):
    result = await server.run_profile(mode, "gfx942", target, str(repo))
    status = await _wait_for_terminal_job(server, result["job_id"])
    return result, status


def test_run_profile_happy_path_reaches_done(server, ck_repo, monkeypatch):
    monkeypatch.delenv("STUB_CKREMOTE_RUN_RC", raising=False)
    monkeypatch.delenv("STUB_CKREMOTE_PULL_RC", raising=False)

    result, status = asyncio.run(
        _run_and_wait(server, "ckRunProfile", "test_gemm", ck_repo)
    )

    assert result["server"] == "stubserver"
    assert status["state"] == "done"

    calls = _read_calls(server._log_path)
    dispatch_argv = calls[1]
    assert dispatch_argv == [
        "-t",
        "stubserver",
        "-a",
        "gfx942",
        "ckRunProfile",
        "--arch",
        "gfx942",
        "test_gemm",
    ]
    pull_argv = calls[2]
    assert pull_argv == ["-t", "stubserver", "pull", "ck_profile_out/dynamic"]


def test_run_and_pull_stdout_redirected_to_job_log(server, ck_repo, monkeypatch):
    monkeypatch.delenv("STUB_CKREMOTE_RUN_RC", raising=False)
    monkeypatch.delenv("STUB_CKREMOTE_PULL_RC", raising=False)

    result, status = asyncio.run(
        _run_and_wait(server, "ckRunProfile", "test_gemm", ck_repo)
    )
    assert status["state"] == "done"

    log_contents = server._store.log_path(result["job_id"]).read_text()
    assert "run-phase-stdout-marker" in log_contents
    assert "pull-phase-stdout-marker" in log_contents


def test_run_profile_dispatch_failure_marks_failed(server, ck_repo, monkeypatch):
    monkeypatch.setenv("STUB_CKREMOTE_RUN_RC", "1")

    _, status = asyncio.run(
        _run_and_wait(server, "ckStaticProfile", "test_gemm", ck_repo)
    )
    assert status["state"] == "failed"


def test_run_profile_pull_failure_marks_pull_failed(server, ck_repo, monkeypatch):
    monkeypatch.setenv("STUB_CKREMOTE_PULL_RC", "1")

    _, status = asyncio.run(_run_and_wait(server, "ckRunProfile", "test_gemm", ck_repo))
    assert status["state"] == "pull_failed"


def test_pull_phase_timeout_kills_and_marks_timeout(server, ck_repo, monkeypatch):
    # A hanging pull phase must reach "timeout". The reconciler no longer
    # independently times out owned (in-process) jobs — that raced the
    # owning task's own write_exit call — so shrink the mode's real timeout
    # instead; monkeypatch.setitem restores it after the test.
    monkeypatch.setenv("STUB_CKREMOTE_PULL_SLEEP_S", "5")
    monkeypatch.setitem(server.job_store.MODES["ckStaticProfile"], "timeout_s", 0.1)

    async def run():
        result = await server.run_profile(
            "ckStaticProfile", "gfx942", "test_gemm", str(ck_repo)
        )
        return await _wait_for_terminal_job(server, result["job_id"])

    status = asyncio.run(run())
    assert status["state"] == "timeout"


def test_resolve_server_timeout_kills_hung_select(server, monkeypatch):
    # Without start_new_session=True on the select subprocess, killpg targets
    # the wrong process group and silently no-ops, hanging past the timeout.
    monkeypatch.setenv("STUB_CKREMOTE_SELECT_SLEEP_S", "5")
    monkeypatch.setattr(server, "_SELECT_TIMEOUT_S", 0.1)
    real_kill = server.job_store.kill_process_group
    killed = []

    def spy_kill(pid):
        killed.append(pid)
        real_kill(pid)

    monkeypatch.setattr(server.job_store, "kill_process_group", spy_kill)

    async def run():
        with pytest.raises(ValueError, match="timed out"):
            await server._resolve_server("gfx942", None)

    start = time.monotonic()
    asyncio.run(run())
    assert time.monotonic() - start < 4
    # Confirms the process was actually reachable and killed, not just that
    # asyncio.wait_for's own timeout fired while the stub kept running.
    assert len(killed) == 1
    with pytest.raises(ProcessLookupError):
        os.kill(killed[0], 0)


def test_run_profile_normalizes_path_target_in_dispatch_argv(
    server, ck_repo, monkeypatch
):
    monkeypatch.delenv("STUB_CKREMOTE_RUN_RC", raising=False)
    monkeypatch.delenv("STUB_CKREMOTE_PULL_RC", raising=False)
    binary = ck_repo / "build" / "test_gemm"
    binary.parent.mkdir(parents=True)
    binary.write_text("")

    _, status = asyncio.run(
        _run_and_wait(server, "ckStaticProfile", str(binary), ck_repo)
    )
    assert status["state"] == "done"

    calls = _read_calls(server._log_path)
    dispatch_argv = calls[1]
    assert dispatch_argv[-1] == "build/test_gemm"


def test_get_summary_path_frozen_survives_later_latest_repoint(
    server, ck_repo, monkeypatch
):
    monkeypatch.delenv("STUB_CKREMOTE_RUN_RC", raising=False)
    monkeypatch.delenv("STUB_CKREMOTE_PULL_RC", raising=False)
    summary_root = ck_repo / "ck_profile_out" / "dynamic"

    async def run():
        result = await server.run_profile(
            "ckRunProfile", "gfx942", "test_gemm", str(ck_repo)
        )
        # Point "latest" at run1 before the job's pull phase finishes, so its
        # summary_path capture resolves through the symlink like real ckRemote.
        run1 = summary_root / "run1"
        run1.mkdir(parents=True)
        (run1 / "summary.json").write_text(json.dumps({"run": 1}))
        (summary_root / "latest").symlink_to(run1)
        await _wait_for_terminal_job(server, result["job_id"])
        return result

    result = asyncio.run(run())
    assert server.get_summary(result["job_id"])["run"] == 1

    # A later job on the same repo/mode repoints "latest" to a new run dir.
    run2 = summary_root / "run2"
    run2.mkdir()
    (run2 / "summary.json").write_text(json.dumps({"run": 2}))
    (summary_root / "latest").unlink()
    (summary_root / "latest").symlink_to(run2)

    assert server.get_summary(result["job_id"])["run"] == 1


def test_cancelled_task_kills_subprocess_and_marks_terminal(
    server, ck_repo, monkeypatch
):
    monkeypatch.setenv("STUB_CKREMOTE_RUN_SLEEP_S", "5")
    real_kill = server.job_store.kill_process_group
    killed = []

    def spy_kill(pid):
        killed.append(pid)
        real_kill(pid)

    monkeypatch.setattr(server.job_store, "kill_process_group", spy_kill)

    async def run():
        job_id = server._store.create(
            "ckRunProfile", "gfx942", "test_gemm", str(ck_repo), "stubserver"
        )
        task = asyncio.create_task(
            server._run_job(
                job_id,
                "ckRunProfile",
                "gfx942",
                "test_gemm",
                str(ck_repo),
                "stubserver",
            )
        )
        for _ in range(_POLL_MAX_ITERS):
            if server.get_job_status(job_id)["pid"] is not None:
                break
            await asyncio.sleep(_POLL_INTERVAL_S)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        return job_id

    job_id = asyncio.run(run())
    status = server.get_job_status(job_id)
    assert status["state"] == "failed"
    assert len(killed) == 1


def test_run_job_body_kills_subprocess_on_exception_before_timeout_branch(
    server, ck_repo, monkeypatch
):
    # Any exception before normal completion, not just TimeoutError, must
    # still kill the process group or it leaks running after the job goes terminal.
    killed = []
    monkeypatch.setattr(
        server.job_store, "kill_process_group", lambda pid: killed.append(pid)
    )

    def boom_set_running(job_id, pid):
        raise RuntimeError("boom")

    monkeypatch.setattr(server._store, "set_running", boom_set_running)

    async def run():
        job_id = server._store.create(
            "ckRunProfile", "gfx942", "test_gemm", str(ck_repo), "stubserver"
        )
        await server._run_job(
            job_id, "ckRunProfile", "gfx942", "test_gemm", str(ck_repo), "stubserver"
        )
        return job_id

    job_id = asyncio.run(run())
    status = server.get_job_status(job_id)
    assert status["state"] == "failed"
    assert len(killed) == 1


async def _run_twice_same_server(server, ck_repo):
    first = await server.run_profile(
        "ckRunProfile", "gfx942", "test_gemm", str(ck_repo)
    )
    with pytest.raises(ValueError, match="rejected"):
        await server.run_profile("ckRunProfile", "gfx942", "test_gemm2", str(ck_repo))
    return first


def test_run_profile_rejects_second_job_on_busy_server(server, ck_repo):
    first = asyncio.run(_run_twice_same_server(server, ck_repo))
    assert first["state"] == "running"


def test_run_profile_rejects_invalid_target(server, ck_repo):
    async def run():
        with pytest.raises(ValueError, match="invalid target"):
            await server.run_profile(
                "ckRunProfile", "gfx942", "bad; rm -rf /", str(ck_repo)
            )

    asyncio.run(run())


async def _run_and_get_summary(server, ck_repo, mode, summary_contents):
    result = await server.run_profile(mode, "gfx942", "test_gemm", str(ck_repo))
    if summary_contents is not None:
        mode_dir = server.job_store.MODES[mode]["output_dir"]
        summary_dir = ck_repo / "ck_profile_out" / mode_dir / "latest"
        summary_dir.mkdir(parents=True)
        (summary_dir / "summary.json").write_text(json.dumps(summary_contents))
    await _wait_for_terminal_job(server, result["job_id"])
    return result


def test_get_summary_reads_dynamic_summary_json(server, ck_repo, monkeypatch):
    monkeypatch.delenv("STUB_CKREMOTE_RUN_RC", raising=False)
    monkeypatch.delenv("STUB_CKREMOTE_PULL_RC", raising=False)

    result = asyncio.run(
        _run_and_get_summary(
            server,
            ck_repo,
            "ckRunProfile",
            {"schema_version": 2, "verdict": "compute_bound"},
        )
    )
    summary = server.get_summary(result["job_id"])
    assert summary["schema_version"] == 2


def test_get_summary_missing_json_raises_actionable_error(server, ck_repo, monkeypatch):
    monkeypatch.delenv("STUB_CKREMOTE_RUN_RC", raising=False)
    monkeypatch.delenv("STUB_CKREMOTE_PULL_RC", raising=False)

    result = asyncio.run(_run_and_get_summary(server, ck_repo, "ckRunProfile", None))
    with pytest.raises(ValueError, match="no summary.json"):
        server.get_summary(result["job_id"])


def test_get_summary_not_done_raises(server, ck_repo):
    async def run():
        result = await server.run_profile(
            "ckRunProfile", "gfx942", "test_gemm", str(ck_repo)
        )
        with pytest.raises(ValueError, match="not 'done'"):
            server.get_summary(result["job_id"])
        await _wait_for_terminal_job(server, result["job_id"])

    asyncio.run(run())


def test_run_job_exception_before_set_running_reaches_failed(
    server, ck_repo, monkeypatch
):
    async def boom(*args, **kwargs):
        raise RuntimeError("simulated failure before set_running")

    monkeypatch.setattr(server, "_run_job_body", boom)

    async def run():
        job_id = server._store.create(
            "ckRunProfile", "gfx942", "test_gemm", str(ck_repo), "stubserver"
        )
        await server._run_job(
            job_id, "ckRunProfile", "gfx942", "test_gemm", str(ck_repo), "stubserver"
        )
        return job_id

    job_id = asyncio.run(run())
    status = server.get_job_status(job_id)
    assert status["state"] == "failed"
    assert "simulated failure" in status["note"]


def test_get_summary_wrong_mode_raises(server, ck_repo, monkeypatch):
    monkeypatch.delenv("STUB_CKREMOTE_RUN_RC", raising=False)
    monkeypatch.delenv("STUB_CKREMOTE_PULL_RC", raising=False)

    result = asyncio.run(_run_and_get_summary(server, ck_repo, "ckStaticProfile", None))
    with pytest.raises(ValueError, match="does not emit a summary"):
        server.get_summary(result["job_id"])
