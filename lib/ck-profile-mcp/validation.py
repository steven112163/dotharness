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
    path = Path(repo)
    if not path.is_dir():
        raise ValueError(f"repo '{repo}' is not a directory")
    if not (path / "script" / "cmake-ck-dev.sh").exists():
        raise ValueError(
            f"repo '{repo}' is not a CK project root (missing script/cmake-ck-dev.sh)"
        )
    return str(path.resolve())


def validate_target(target, repo):
    """CMake target names (no '/') are checked by character class only. Anything
    containing '/' is treated as a binary path and must resolve inside repo."""
    if not _TARGET_CHARS_RE.match(target):
        raise ValueError(f"invalid target '{target}' (allowed: A-Za-z0-9_./:+-)")
    if "/" not in target:
        return target
    repo_root = Path(repo).resolve()
    resolved = (repo_root / target).resolve()
    try:
        resolved.relative_to(repo_root)
    except ValueError:
        raise ValueError(
            f"target '{target}' resolves outside repo root '{repo_root}'"
        ) from None
    return target


def validate_job_id(job_id):
    try:
        parsed = uuid.UUID(job_id, version=4)
    except (ValueError, AttributeError, TypeError):
        raise ValueError(f"invalid job_id '{job_id}' (expected a UUID4)") from None
    if str(parsed) != str(job_id).lower():
        raise ValueError(f"invalid job_id '{job_id}' (expected a UUID4)")
    return job_id
