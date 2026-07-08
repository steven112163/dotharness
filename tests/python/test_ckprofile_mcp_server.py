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

import pytest

STUB_CKREMOTE = """#!/usr/bin/env python3
import json
import os
import sys

log_path = os.environ["STUB_CKREMOTE_LOG"]
with open(log_path, "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")

if "select" in sys.argv:
    print("Selected server 'stubserver' (normal, user@stubserver) for gfx942.")
    sys.exit(0)

if "pull" in sys.argv:
    sys.exit(int(os.environ.get("STUB_CKREMOTE_PULL_RC", "0")))

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


async def _run_and_wait(server, mode, target, repo):
    result = await server.run_profile(mode, "gfx942", target, str(repo))
    for _ in range(200):
        status = server.get_job_status(result["job_id"])
        if status["state"] not in ("running", "pulling"):
            return result, status
        await asyncio.sleep(0.02)
    raise AssertionError("job did not finish in time")


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
        mode_dir = "dynamic" if mode == "ckRunProfile" else "static"
        summary_dir = ck_repo / "ck_profile_out" / mode_dir / "latest"
        summary_dir.mkdir(parents=True)
        (summary_dir / "summary.json").write_text(json.dumps(summary_contents))
    for _ in range(200):
        status = server.get_job_status(result["job_id"])
        if status["state"] not in ("running", "pulling"):
            break
        await asyncio.sleep(0.02)
    else:
        raise AssertionError("job did not finish in time")
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

    result = asyncio.run(_run_and_get_summary(server, ck_repo, "ckStaticProfile", None))
    with pytest.raises(ValueError, match="no summary.json"):
        server.get_summary(result["job_id"])
