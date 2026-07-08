"""Tests for lib/ck-profile-mcp/validation.py — MCP tool input validation."""

import uuid

import pytest
import validation


def test_validate_mode_accepts_known_mode():
    assert validation.validate_mode("ckRunProfile") == "ckRunProfile"


def test_validate_mode_rejects_unknown_mode():
    with pytest.raises(ValueError, match="invalid mode"):
        validation.validate_mode("ckHold")


def test_validate_arch_accepts_gfx942():
    assert validation.validate_arch("gfx942") == "gfx942"


@pytest.mark.parametrize(
    "arch",
    ["gfx942; rm -rf /", "gfx942`whoami`", "GFX942", "gfx" + "9" * 20, ""],
)
def test_validate_arch_rejects_bad_input(arch):
    with pytest.raises(ValueError, match="invalid arch"):
        validation.validate_arch(arch)


def test_validate_repo_accepts_ck_project_root(tmp_path):
    (tmp_path / "script").mkdir()
    (tmp_path / "script" / "cmake-ck-dev.sh").write_text("")
    assert validation.validate_repo(str(tmp_path)) == str(tmp_path.resolve())


def test_validate_repo_rejects_missing_dir(tmp_path):
    with pytest.raises(ValueError, match="not a directory"):
        validation.validate_repo(str(tmp_path / "nope"))


def test_validate_repo_rejects_non_ck_dir(tmp_path):
    with pytest.raises(ValueError, match="not a CK project root"):
        validation.validate_repo(str(tmp_path))


@pytest.fixture
def ck_repo(tmp_path):
    (tmp_path / "script").mkdir()
    (tmp_path / "script" / "cmake-ck-dev.sh").write_text("")
    (tmp_path / "build").mkdir()
    (tmp_path / "build" / "some_target").write_text("")
    return tmp_path


def test_validate_target_accepts_cmake_target_name(ck_repo):
    assert validation.validate_target("test_gemm", str(ck_repo)) == "test_gemm"


def test_validate_target_accepts_path_inside_repo(ck_repo):
    target = "build/some_target"
    assert validation.validate_target(target, str(ck_repo)) == target


def test_validate_target_rejects_bad_characters(ck_repo):
    with pytest.raises(ValueError, match="invalid target"):
        validation.validate_target("test; rm -rf /", str(ck_repo))


def test_validate_target_rejects_traversal_outside_repo(ck_repo):
    with pytest.raises(ValueError, match="outside repo root"):
        validation.validate_target("../../etc/passwd", str(ck_repo))


def test_validate_target_rejects_absolute_path_outside_repo(ck_repo):
    with pytest.raises(ValueError, match="outside repo root"):
        validation.validate_target("/etc/passwd", str(ck_repo))


def test_validate_job_id_accepts_uuid4():
    job_id = str(uuid.uuid4())
    assert validation.validate_job_id(job_id) == job_id


@pytest.mark.parametrize(
    "job_id",
    ["not-a-uuid", "../../etc/passwd", "00000000-0000-0000-0000-000000000000"],
)
def test_validate_job_id_rejects_bad_input(job_id):
    with pytest.raises(ValueError, match="invalid job_id"):
        validation.validate_job_id(job_id)
