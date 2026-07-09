"""Tests for lib/ck-profile-mcp/job_store.py — job state, reconciliation, retention."""

import json
import os
import time
from pathlib import Path

import pytest
from job_store import JobStore, _pid_alive

# A PID that (almost certainly) does not exist on this system.
_DEAD_PID = 999999


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


def test_create_raises_value_error_on_job_id_collision(store, monkeypatch):
    import uuid as uuid_module

    fixed = uuid_module.uuid4()
    monkeypatch.setattr(uuid_module, "uuid4", lambda: fixed)

    _create(store)
    with pytest.raises(ValueError, match="collision"):
        _create(store)


def test_modes_mapping_is_read_only():
    from job_store import MODES

    with pytest.raises(TypeError):
        MODES["new_mode"] = {"timeout_s": 1, "output_dir": "x", "emits_summary": False}


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


def test_write_exit_timed_out_marks_timeout(store):
    job_id = _create(store)
    store.write_exit(job_id, remote_rc=None, timed_out=True)
    assert store.get_status(job_id)["state"] == "timeout"


def test_set_pulling_resets_timeout_budget_for_pull_phase(store):
    job_id = _create(store, mode="ckStaticProfile")
    status = store._read_status(job_id)
    # Simulate the run phase having already exhausted its own budget.
    # pid stays None so a misfiring timeout branch can't send a real signal
    # to this test process — a mutant set_pulling that ignores its `pid`
    # argument would leave this None untouched.
    status["started_at"] = time.time() - (status["timeout_s"] + 1)
    store._write_status(job_id, status)

    store.set_pulling(job_id, os.getpid())

    # If the pull phase reused the run phase's stale started_at, this
    # reconcile would misfire the job into "timeout" immediately.
    reconciled = store.get_status(job_id)
    assert reconciled["state"] == "pulling"


def test_set_pulling_is_not_terminal_and_still_busy(store):
    job_id = _create(store, server="shared")
    store.set_pulling(job_id, None)
    assert store.get_status(job_id)["state"] == "pulling"
    assert store.is_server_busy("shared") is True


def test_dead_pid_without_exit_sentinel_marks_failed(store):
    job_id = _create(store)
    status = store._read_status(job_id)
    status["pid"] = _DEAD_PID
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


def test_pid_alive_fails_closed_without_recorded_start_ticks():
    # Without a recorded baseline, PID reuse can't be ruled out — must not
    # treat a live PID as "our job" just because recorded_start_ticks is None.
    assert _pid_alive(os.getpid(), None) is False


def test_owned_job_with_dead_pid_stays_running(tmp_path):
    owned = set()
    store = JobStore(tmp_path / "mcp-jobs", is_owned=lambda job_id: job_id in owned)
    job_id = _create(store)
    owned.add(job_id)
    status = store._read_status(job_id)
    status["pid"] = _DEAD_PID
    status["proc_start_ticks"] = "123"
    status["started_at"] = time.time()
    store._write_status(job_id, status)

    # is_owned=True means an in-process task still owns this job, so the
    # dead-PID fallback must not fire even though the PID looks dead.
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


def test_timeout_kill_skips_reused_pid(store, monkeypatch):
    # Regression test: _kill_job must not signal a PID whose start-time ticks
    # no longer match what was recorded (i.e. the original process is gone
    # and the PID was reused by something else).
    job_id = _create(store, mode="ckStaticProfile")
    store.set_running(job_id, os.getpid())
    status = store._read_status(job_id)
    status["started_at"] = time.time() - (status["timeout_s"] + 1)
    status["proc_start_ticks"] = "not-the-real-ticks"
    store._write_status(job_id, status)

    calls = []
    monkeypatch.setattr(os, "killpg", lambda pid, sig: calls.append((pid, sig)))

    reconciled = store.get_status(job_id)
    assert reconciled["state"] == "timeout"
    assert calls == []


def test_corrupt_exit_json_does_not_wedge_a_timed_out_job(store):
    # Regression: a corrupt exit.json (crash, filesystem damage, or leftover
    # from a restart) used to permanently block write_exit's os.link inside
    # the timeout fallback, wedging the job in "running" forever.
    job_id = _create(store, mode="ckStaticProfile")
    store.set_running(job_id, os.getpid())
    status = store._read_status(job_id)
    status["started_at"] = time.time() - (status["timeout_s"] + 1)
    status["pid"] = None  # avoid sending a real signal to this test process
    store._write_status(job_id, status)
    store._exit_path(job_id).write_text("not valid json")

    reconciled = store.get_status(job_id)
    assert reconciled["state"] == "timeout"


def test_exit_json_read_race_falls_through_instead_of_raising(store, monkeypatch):
    # Regression: exit_path.exists() then open() is a TOCTOU race with
    # prune() removing the file in between; open() raises FileNotFoundError,
    # an OSError, not the json.JSONDecodeError the old code caught.
    job_id = _create(store, mode="ckStaticProfile")
    store.set_running(job_id, os.getpid())
    status = store._read_status(job_id)
    status["started_at"] = time.time() - (status["timeout_s"] + 1)
    status["pid"] = None
    store._write_status(job_id, status)
    exit_path = store._exit_path(job_id)
    real_exists = Path.exists

    def fake_exists(self):
        return True if self == exit_path else real_exists(self)

    monkeypatch.setattr(Path, "exists", fake_exists)  # exit_path never actually exists

    reconciled = store.get_status(job_id)
    assert reconciled["state"] == "timeout"


def test_owned_job_past_timeout_is_not_reconciled_as_timeout(tmp_path):
    # Regression for the race where a concurrent reconcile could time out a
    # job microseconds before the owning task's own write_exit call landed.
    owned = set()
    store = JobStore(tmp_path / "mcp-jobs", is_owned=lambda job_id: job_id in owned)
    job_id = _create(store, mode="ckStaticProfile")
    owned.add(job_id)
    status = store._read_status(job_id)
    status["started_at"] = time.time() - (status["timeout_s"] + 1)
    status["pid"] = None  # avoid sending a real signal to this test process
    store._write_status(job_id, status)

    assert store.get_status(job_id)["state"] == "running"


def test_never_started_job_times_out_from_created_at(store):
    # Regression: a crash between create() and set_running() left pid=None
    # forever, wedging is_server_busy with no recovery path.
    job_id = _create(store, mode="ckStaticProfile")
    status = store._read_status(job_id)
    status["created_at"] = time.time() - (status["timeout_s"] + 1)
    store._write_status(job_id, status)

    reconciled = store.get_status(job_id)
    assert reconciled["state"] == "failed"


def test_iter_reconciled_prunes_job_dir_missing_status_json(store):
    # A job dir with no status.json (create() crashed mid-write) must not
    # break every other job-store call.
    job_id = _create(store)
    store._status_path(job_id).unlink()

    assert store.is_server_busy("shared") is False
    assert not store._job_dir(job_id).exists()


def test_write_exit_first_writer_wins(store):
    job_id = _create(store)
    store.write_exit(job_id, remote_rc=0, pull_rc=0)
    store.write_exit(job_id, remote_rc=1, pull_rc=1)

    status = store.get_status(job_id)
    assert status["state"] == "done"
    assert status["remote_rc"] == 0


def test_write_exit_after_dead_pid_guess_overwrites_it(store):
    # The dead-PID fallback only guesses "failed"; a real exit.json arriving
    # afterwards must still be synced in rather than frozen out.
    job_id = _create(store)
    status = store._read_status(job_id)
    status["pid"] = _DEAD_PID
    status["proc_start_ticks"] = "123"
    status["started_at"] = time.time()
    store._write_status(job_id, status)
    assert store.get_status(job_id)["state"] == "failed"

    store.write_exit(job_id, remote_rc=0, pull_rc=0)
    assert store.get_status(job_id)["state"] == "done"


def test_exit_json_written_atomically_via_hardlink(store, monkeypatch):
    job_id = _create(store)
    exit_path = store._exit_path(job_id)
    seen_links = []
    real_link = os.link

    def spy_link(src, dst):
        seen_links.append((src, dst))
        real_link(src, dst)

    monkeypatch.setattr(os, "link", spy_link)
    store.write_exit(job_id, remote_rc=0, pull_rc=0)
    matches = [(src, dst) for src, dst in seen_links if Path(dst) == exit_path]
    assert matches
    for src, _ in matches:
        assert not os.path.exists(src)  # temp file cleaned up after linking
    with open(exit_path) as f:
        data = json.load(f)
    assert data["remote_rc"] == 0


def test_write_exit_never_leaves_a_partial_file(store, monkeypatch):
    job_id = _create(store)
    exit_path = store._exit_path(job_id)
    real_dump = json.dump

    def failing_dump(*args, **kwargs):
        real_dump(*args, **kwargs)
        raise RuntimeError("simulated crash mid-write")

    monkeypatch.setattr(json, "dump", failing_dump)
    with pytest.raises(RuntimeError, match="simulated crash"):
        store.write_exit(job_id, remote_rc=0, pull_rc=0)
    assert not exit_path.exists()  # never hardlinked; no partial file visible


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
    fake_now = [1_000_000.0]
    monkeypatch.setattr(job_store_module.time, "time", lambda: fake_now[0])

    ids = []
    for _ in range(4):
        job_id = _create(store)
        store.write_exit(job_id, remote_rc=0, pull_rc=0)
        ids.append(job_id)
        fake_now[0] += 1

    store.prune()
    remaining = [j for j in ids if store._job_dir(j).exists()]
    assert len(remaining) == 2
    # The two most recently finished jobs survive.
    assert remaining == ids[-2:]
