"""Tests for lib/ck-profile-mcp/job_store.py — job state, reconciliation, retention."""

import json
import os
import time

import pytest
from job_store import JobStore


@pytest.fixture
def store(tmp_path):
    return JobStore(tmp_path / "mcp-jobs")


def _create(store, server="shared", mode="ckRunProfile"):
    return store.create(mode, "gfx942", "test_gemm", "/repo", server)


def test_create_writes_running_state_with_no_pid(store):
    job_id = _create(store)
    status = store.get_status(job_id)
    assert status["state"] == "running"
    assert status["pid"] is None
    assert status["mode"] == "ckRunProfile"
    assert status["timeout_s"] == 60 * 60


def test_is_server_busy_true_while_non_terminal(store):
    _create(store, server="shared")
    assert store.is_server_busy("shared") is True
    assert store.is_server_busy("other") is False


def test_is_server_busy_false_after_terminal(store):
    job_id = _create(store, server="shared")
    store.write_exit(job_id, remote_rc=0, pull_rc=0)
    assert store.is_server_busy("shared") is False


def test_write_exit_success_marks_done(store):
    job_id = _create(store)
    store.write_exit(job_id, remote_rc=0, pull_rc=0)
    assert store.get_status(job_id)["state"] == "done"


def test_write_exit_remote_failure_marks_failed(store):
    job_id = _create(store)
    store.write_exit(job_id, remote_rc=1, pull_rc=None)
    assert store.get_status(job_id)["state"] == "failed"


def test_write_exit_pull_failure_marks_pull_failed(store):
    job_id = _create(store)
    store.write_exit(job_id, remote_rc=0, pull_rc=1)
    assert store.get_status(job_id)["state"] == "pull_failed"


def test_write_exit_timeout_note_marks_timeout(store):
    job_id = _create(store)
    store.write_exit(job_id, remote_rc=None, note="timeout")
    assert store.get_status(job_id)["state"] == "timeout"


def test_set_state_pulling_is_not_terminal_and_still_busy(store):
    job_id = _create(store, server="shared")
    store.set_state(job_id, "pulling")
    assert store.get_status(job_id)["state"] == "pulling"
    assert store.is_server_busy("shared") is True


def test_dead_pid_without_exit_sentinel_marks_failed(store):
    job_id = _create(store)
    # A PID that (almost certainly) does not exist on this system.
    dead_pid = 999999
    status = store._read_status(job_id)
    status["pid"] = dead_pid
    status["proc_start_ticks"] = "123"
    status["started_at"] = time.time()
    store._write_status(job_id, status)

    reconciled = store.get_status(job_id)
    assert reconciled["state"] == "failed"
    assert "sentinel" in reconciled["note"]


def test_live_pid_without_exit_sentinel_stays_running(store):
    job_id = _create(store)
    store.set_running(job_id, os.getpid())
    assert store.get_status(job_id)["state"] == "running"


def test_timeout_elapsed_kills_and_marks_timeout(store):
    job_id = _create(store, mode="ckStaticProfile")
    store.set_running(job_id, os.getpid())
    status = store._read_status(job_id)
    status["started_at"] = time.time() - (status["timeout_s"] + 1)
    status["pid"] = None  # avoid sending a real signal to this test process
    store._write_status(job_id, status)

    reconciled = store.get_status(job_id)
    assert reconciled["state"] == "timeout"


def test_exit_json_written_atomically_via_rename(store, tmp_path, monkeypatch):
    job_id = _create(store)
    seen_tmp_files = []
    real_replace = os.replace

    def spy_replace(src, dst):
        seen_tmp_files.append(src)
        real_replace(src, dst)

    monkeypatch.setattr(os, "replace", spy_replace)
    store.write_exit(job_id, remote_rc=0, pull_rc=0)
    assert len(seen_tmp_files) >= 1
    for tmp in seen_tmp_files:
        assert not os.path.exists(tmp)  # renamed away, not left behind
    exit_path = store._exit_path(job_id)
    with open(exit_path) as f:
        data = json.load(f)
    assert data["remote_rc"] == 0


def test_prune_removes_old_terminal_entries(store):
    job_id = _create(store)
    store.write_exit(job_id, remote_rc=0, pull_rc=0)
    status = store._read_status(job_id)
    status["finished_at"] = time.time() - (25 * 60 * 60)
    store._write_status(job_id, status)

    store.prune()
    assert not store._job_dir(job_id).exists()


def test_prune_keeps_recent_terminal_entries(store):
    job_id = _create(store)
    store.write_exit(job_id, remote_rc=0, pull_rc=0)
    store.prune()
    assert store._job_dir(job_id).exists()


def test_prune_never_removes_non_terminal_entries_even_if_old(store):
    job_id = _create(store)
    status = store._read_status(job_id)
    status["started_at"] = time.time() - (100 * 60 * 60)
    status["timeout_s"] = 10**9  # avoid tripping the timeout path during reconcile
    store._write_status(job_id, status)

    store.prune()
    assert store._job_dir(job_id).exists()


def test_prune_caps_terminal_entries_to_retention_max(store, monkeypatch):
    import job_store as job_store_module

    monkeypatch.setattr(job_store_module, "RETENTION_MAX_TERMINAL", 2)
    ids = []
    for _ in range(4):
        job_id = _create(store)
        store.write_exit(job_id, remote_rc=0, pull_rc=0)
        ids.append(job_id)
        time.sleep(0.01)

    store.prune()
    remaining = [j for j in ids if store._job_dir(j).exists()]
    assert len(remaining) == 2
    # The two most recently finished jobs survive.
    assert remaining == ids[-2:]
