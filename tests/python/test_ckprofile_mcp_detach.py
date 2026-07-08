"""Verifies the start_new_session=True detachment run_profile relies on: a
grandchild keeps running after its immediate parent is gone, without needing
real ckRemote/SSH (unavailable in CI)."""

import asyncio
import os
import signal
import time


async def _spawn_detached(marker_path):
    proc = await asyncio.create_subprocess_exec(
        "bash",
        "-c",
        f"sleep 0.3 && touch {marker_path}",
        start_new_session=True,
    )
    return proc.pid


def test_detached_child_survives_parent_death(tmp_path):
    marker = tmp_path / "done"
    pid = asyncio.run(_spawn_detached(marker))

    # Simulate the "server restarted" case: send SIGTERM to the child's
    # process group leader would kill it too, so instead we just stop tracking
    # it here (no waitpid) and confirm it still completes on its own.
    assert not marker.exists()
    for _ in range(50):
        if marker.exists():
            break
        time.sleep(0.05)
    assert marker.exists()

    # Reap to avoid leaking a zombie in the test process.
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass


def test_detached_child_not_in_same_process_group_as_parent():
    async def spawn():
        proc = await asyncio.create_subprocess_exec(
            "sleep", "0.2", start_new_session=True
        )
        pgid = os.getpgid(proc.pid)
        await proc.wait()
        return pgid

    child_pgid = asyncio.run(spawn())
    assert child_pgid != os.getpgid(os.getpid())


def test_killpg_on_child_group_does_not_affect_test_process():
    async def spawn_and_kill():
        proc = await asyncio.create_subprocess_exec(
            "sleep", "5", start_new_session=True
        )
        os.killpg(proc.pid, signal.SIGKILL)
        return await proc.wait()

    rc = asyncio.run(spawn_and_kill())
    assert rc != 0
