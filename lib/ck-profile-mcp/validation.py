"""Validate MCP tool inputs before they reach a subprocess argv or filesystem path.

All inputs here are agent-originated (per rules/code-review.md, boundary input must be
validated). Each validator raises ValueError with an actionable message on rejection.
"""

import re
import uuid
from pathlib import Path

import job_store

# Same regex as ckCommon::_validate_arch, kept in sync manually (bash vs. Python).
_ARCH_RE = re.compile(r"^gfx[0-9a-z]{1,16}$")
_TARGET_CHARS_RE = re.compile(r"^[A-Za-z0-9_./:+-]+$")
_SERVER_RE = re.compile(r"^[A-Za-z0-9_.-]{1,64}$")

# Sourced from job_store.MODES so mode names stay in sync with timeouts/output dirs.
MODE_NAMES = tuple(job_store.MODES.keys())


def validate_mode(mode):
    if mode not in MODE_NAMES:
        raise ValueError(
            f"invalid mode '{mode}' (want one of: {', '.join(MODE_NAMES)})"
        )
    return mode


def validate_arch(arch):
    if not _ARCH_RE.match(arch):
        raise ValueError(f"invalid arch '{arch}' (expected e.g. gfx942)")
    return arch


def validate_repo(repo):
    # Same two markers as bin/ckCommon::_require_ck_root, so a repo accepted
    # here is also accepted by the ckRemote/ckRunProfile calls it feeds into.
    path = Path(repo)
    if not path.is_dir():
        raise ValueError(f"repo '{repo}' is not a directory")
    if (
        not (path / "script" / "cmake-ck-dev.sh").exists()
        or not (path / "CMakeLists.txt").exists()
    ):
        raise ValueError(
            f"repo '{repo}' is not a CK project root "
            "(missing script/cmake-ck-dev.sh or CMakeLists.txt)"
        )
    return str(path.resolve())


def validate_target(target, repo):
    """CMake target names (no '/') are checked by character class only. Anything
    containing '/' is treated as a binary path and must resolve inside repo,
    and is normalized to a repo-relative string (the remote host mirrors the
    repo at a different absolute path, so a local absolute path is meaningless
    there)."""
    if not _TARGET_CHARS_RE.match(target):
        raise ValueError(f"invalid target '{target}' (allowed: A-Za-z0-9_./:+-)")
    if "/" not in target:
        return target
    repo_root = Path(repo)  # validate_repo already returns a resolved path
    resolved = (repo_root / target).resolve()
    try:
        rel = resolved.relative_to(repo_root)
    except ValueError:
        raise ValueError(
            f"target '{target}' resolves outside repo root '{repo_root}'"
        ) from None
    return str(rel)


def validate_server(server):
    if server is None:
        return None
    if not _SERVER_RE.match(server):
        raise ValueError(f"invalid server '{server}' (allowed: A-Za-z0-9_.-)")
    return server


def validate_job_id(job_id):
    # uuid.UUID(..., version=4) doesn't reject a non-v4 UUID by itself — it
    # forces the version/variant bits into the parsed value regardless of
    # input. The string round-trip is what actually catches a mismatch.
    try:
        parsed = uuid.UUID(job_id, version=4)
    except (ValueError, AttributeError, TypeError):
        raise ValueError(f"invalid job_id '{job_id}' (expected a UUID4)") from None
    if str(parsed) != str(job_id).lower():
        raise ValueError(f"invalid job_id '{job_id}' (expected a UUID4)")
    return job_id
