"""Tests for lib/ck-profile/parse_resource_usage.py — log parsing and the VGPR/spill helpers."""

import parse_resource_usage as pru


def test_effective_vgprs_cdna3_takes_max():
    rec = {"vgprs": 100, "agprs": 40}
    assert pru.effective_vgprs(rec, "gfx942") == 100


def test_effective_vgprs_cdna4_sums_unified_file():
    rec = {"vgprs": 100, "agprs": 40}
    assert pru.effective_vgprs(rec, "gfx950") == 140


def test_has_spill_detects_each_source():
    assert pru.has_spill({"scratch_size": 8, "sgpr_spill": 0, "vgpr_spill": 0})
    assert pru.has_spill({"scratch_size": 0, "sgpr_spill": 1, "vgpr_spill": 0})
    assert pru.has_spill({"scratch_size": 0, "sgpr_spill": 0, "vgpr_spill": 1})


def test_has_spill_false_when_clean():
    assert not pru.has_spill({"scratch_size": 0, "sgpr_spill": 0, "vgpr_spill": 0})


def _remark(label, value):
    return f"file.hip:1:1: remark: {label}: {value} {pru.TAG}"


def test_parse_log_builds_one_record_per_kernel(tmp_path):
    log = tmp_path / "build.log"
    log.write_text(
        "\n".join(
            [
                _remark("Function Name", "my_kernel"),
                _remark("VGPRs", "128"),
                _remark("AGPRs", "0"),
                _remark("TotalSGPRs", "48"),
                _remark("VGPRs Spill", "4"),
                "an unrelated build line that should be ignored",
            ]
        )
    )
    records = pru.parse_log(str(log))
    assert len(records) == 1
    rec = records[0]
    assert rec["kernel"] == "my_kernel"
    assert rec["vgprs"] == 128
    assert rec["total_sgprs"] == 48
    assert rec["vgpr_spill"] == 4


def test_parse_log_strips_ansi_color_codes(tmp_path):
    log = tmp_path / "build.log"
    colored = "\x1b[0;35m" + _remark("Function Name", "k") + "\x1b[0m"
    log.write_text(colored + "\n" + _remark("VGPRs", "64"))
    records = pru.parse_log(str(log))
    assert len(records) == 1
    assert records[0]["kernel"] == "k"
    assert records[0]["vgprs"] == 64


def test_parse_log_empty_when_no_remarks(tmp_path):
    log = tmp_path / "build.log"
    log.write_text("just\nordinary\nbuild output\n")
    assert pru.parse_log(str(log)) == []


def test_int_and_bool_parsers():
    assert pru._INT(" 42 ") == 42
    assert pru._BOOL(" True ") is True
    assert pru._BOOL("false") is False
