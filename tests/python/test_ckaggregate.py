"""Tests for bin/ckAggregate: the COUNTER_CLASS guard and summary.json emission.

ckAggregate has no .py extension (it's a bin/ CLI, per conftest.py), so it is loaded here via
importlib rather than a plain `import`.
"""

import csv
import importlib.machinery
import importlib.util
import json
import sys
from pathlib import Path

import pytest

_BIN = Path(__file__).resolve().parent.parent.parent / "bin" / "ckAggregate"
_loader = importlib.machinery.SourceFileLoader("ckAggregate", str(_BIN))
_spec = importlib.util.spec_from_loader("ckAggregate", _loader)
ckAggregate = importlib.util.module_from_spec(_spec)
sys.modules["ckAggregate"] = ckAggregate
_loader.exec_module(ckAggregate)


def _write_counter_csv(pmc_dir, rows):
    pmc_dir.mkdir(parents=True, exist_ok=True)
    with open(pmc_dir / "p_counter_collection.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            ["Counter_Name", "Counter_Value", "Start_Timestamp", "End_Timestamp"]
        )
        w.writerows(rows)


def test_collect_counters_sums_and_means_classified_counters(tmp_path):
    _write_counter_csv(
        tmp_path / "pmc_0",
        [["TCC_HIT", "10", "0", "100"], ["VALUBusy", "50", "0", "100"]],
    )
    sums, means = ckAggregate.collect_counters(str(tmp_path))
    assert sums["TCC_HIT"] == 10.0
    assert means["VALUBusy"] == 50.0


def test_collect_counters_drops_ignore_classified_counters(tmp_path, monkeypatch):
    monkeypatch.setitem(ckAggregate.COUNTER_CLASS, "SCRATCH_EXPLORATORY", "ignore")
    _write_counter_csv(
        tmp_path / "pmc_0",
        [["SCRATCH_EXPLORATORY", "999", "0", "100"], ["TCC_HIT", "10", "0", "100"]],
    )
    sums, means = ckAggregate.collect_counters(str(tmp_path))
    assert "SCRATCH_EXPLORATORY" not in sums
    assert "SCRATCH_EXPLORATORY" not in means
    assert sums["TCC_HIT"] == 10.0


def test_collect_counters_fails_loudly_on_unclassified_counter(tmp_path):
    _write_counter_csv(
        tmp_path / "pmc_0",
        [["SOME_NEW_COUNTER_NOBODY_CLASSIFIED", "1", "0", "100"]],
    )
    with pytest.raises(SystemExit, match="SOME_NEW_COUNTER_NOBODY_CLASSIFIED"):
        ckAggregate.collect_counters(str(tmp_path))


def _fake_overall_row(name="default"):
    m = {
        "gpu_ms": (1.5, 0.1),
        "prog": (2.0, 0.2),
        "hr": (90.0, 1.0),
        "fmb": (10.0, 0.5),
        "wmb": (5.0, 0.3),
        "occ": (4.0, 0.1),
        "valu": (70.0, 2.0),
        "salu": (10.0, 1.0),
        "mfma_cyc": (1000.0, 50.0),
        "memstall": (5.0, 0.5),
        "lds": (2.0, 0.1),
        "lds_per_wave": (0.03, 0.005),
        "mfma_per_wave": (15.6, 1.2),
        "waves": (64.0, 1.0),
        "bw": (1000.0, 20.0),
    }
    return (name, 20, m, 45.0, "compute-bound (VALU/MFMA)", 80.0)


def test_build_summary_json_shape_and_schema_version():
    out = ckAggregate.build_summary_json(
        [_fake_overall_row()], arch="gfx942", unit="per-run", peak=5300.0
    )
    assert out["schema_version"] == ckAggregate.SUMMARY_SCHEMA_VERSION == 2
    assert out["arch"] == "gfx942"
    assert out["unit"] == "per-run"
    assert out["peak_mem_gbs"] == 5300.0
    assert len(out["variants"]) == 1
    v = out["variants"][0]
    assert v["name"] == "default"
    assert v["runs"] == 20
    assert v["verdict"] == "compute-bound (VALU/MFMA)"
    assert v["occ_util_pct"] == 80.0
    assert v["bw_util_pct"] == 45.0
    assert v["gpu_ms"] == {"mean": 1.5, "stdev": 0.1}
    assert v["lds_bank_conflicts_per_wavefront"] == {"mean": 0.03, "stdev": 0.005}
    assert v["mfma_busy_cycles_per_wavefront"] == {"mean": 15.6, "stdev": 1.2}


def test_build_summary_json_is_json_serializable():
    out = ckAggregate.build_summary_json(
        [_fake_overall_row("a"), _fake_overall_row("b")],
        arch="gfx942",
        unit="per-run",
        peak=5300.0,
    )
    dumped = json.dumps(out)
    assert json.loads(dumped)["variants"][1]["name"] == "b"


def test_build_summary_json_normalizes_nan_to_null(tmp_path):
    name, nr, m, bwu, verdict, occu = _fake_overall_row()
    m = dict(m, prog=(float("nan"), float("nan")))
    row = (name, nr, m, float("nan"), verdict, float("nan"))
    out = ckAggregate.build_summary_json(
        [row], arch="gfx_unknown", unit="per-run", peak=0.0
    )
    v = out["variants"][0]
    assert v["occ_util_pct"] is None
    assert v["bw_util_pct"] is None
    assert v["prog_ms"] == {"mean": None, "stdev": None}
    with open(tmp_path / "summary.json", "w") as f:
        json.dump(
            out, f, allow_nan=False
        )  # raises if any bare NaN/Infinity slipped through


def test_build_summary_json_normalizes_nan_peak(tmp_path):
    row = _fake_overall_row()
    out = ckAggregate.build_summary_json(
        [row], arch="gfx942", unit="per-run", peak=float("nan")
    )
    assert out["peak_mem_gbs"] is None
    with open(tmp_path / "summary.json", "w") as f:
        json.dump(out, f, allow_nan=False)
