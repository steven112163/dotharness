"""Tests for bin/ckAggregate's COUNTER_CLASS guard (collect_counters).

ckAggregate has no .py extension (it's a bin/ CLI, per conftest.py), so it is loaded here via
importlib rather than a plain `import`.
"""

import csv
import importlib.machinery
import importlib.util
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
