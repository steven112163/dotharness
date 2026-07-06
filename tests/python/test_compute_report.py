"""Tests for lib/ck-profile/compute_report.py — header-name-based CSV panel parsing."""

import csv

import compute_report as cr


def _write_csv(path, header, rows):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


def test_sol_rows_parses_by_header_name(tmp_path):
    _write_csv(
        tmp_path / "2.1_System_Speed-of-Light.csv",
        ["Metric", "Avg", "Unit", "Peak", "Pct of Peak"],
        [["VALU FLOPs", "10.0", "Gflop", "100.0", "10.0"]],
    )
    rows = cr.sol_rows(str(tmp_path))
    assert rows == [
        {
            "metric": "VALU FLOPs",
            "avg": "10.0",
            "unit": "Gflop",
            "peak": "100.0",
            "pct": 10.0,
        }
    ]


def test_sol_rows_survives_column_reorder_and_alias_names(tmp_path):
    # A different rocprof-compute release: columns reordered, "Value"/"Peak (Empirical)"/"PoP"
    # instead of "Avg"/"Peak"/"Pct of Peak". A fixed-index parser would silently misread this.
    _write_csv(
        tmp_path / "2.1_System_Speed-of-Light.csv",
        ["Pct", "PoP", "Metric", "Peak (Empirical)", "Value", "Unit"],
        [["ignored", "42.0", "HBM Bandwidth", "5300.0", "2226.0", "Gbyte/s"]],
    )
    rows = cr.sol_rows(str(tmp_path))
    assert rows == [
        {
            "metric": "HBM Bandwidth",
            "avg": "2226.0",
            "unit": "Gbyte/s",
            "peak": "5300.0",
            "pct": 42.0,
        }
    ]


def test_sol_rows_skips_rows_without_a_metric_column(tmp_path):
    _write_csv(
        tmp_path / "2.1_System_Speed-of-Light.csv",
        ["NotMetric", "Avg"],
        [["x", "1.0"]],
    )
    assert cr.sol_rows(str(tmp_path)) == []


def test_sol_rows_missing_panel_returns_empty(tmp_path):
    assert cr.sol_rows(str(tmp_path)) == []


def test_mean_col_to_us_converts_by_declared_unit():
    assert cr._mean_col_to_us({"Mean(ns)": "2000"}) == 2.0
    assert cr._mean_col_to_us({"Mean(us)": "2.0"}) == 2.0
    assert cr._mean_col_to_us({"Mean(ms)": "0.002"}) == 2.0
    assert cr._mean_col_to_us({"Kernel_Name": "k"}) is None


def test_build_top_kernels_uses_header_names_not_positions(tmp_path):
    _write_csv(
        tmp_path / "0.1_Top_Kernels.csv",
        ["Count", "Kernel_Name", "Mean(ns)", "Percent"],
        [["4", "my_kernel", "1500", "37.5"]],
    )
    html, md = cr.build(str(tmp_path), "wl", "gfx942")
    assert "my_kernel" in html
    assert "1.50" in html  # 1500 ns -> 1.5 us
    assert "my_kernel" in md
    assert "1.50" in md


def test_pick_returns_first_present_alias():
    assert cr.pick({"a": "1", "b": "2"}, "missing", "b", "a") == "2"
    assert cr.pick({"a": "1"}, "missing") is None
