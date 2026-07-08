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


def test_mean_col_to_us_returns_none_on_unrecognized_or_missing_unit():
    # No parenthesized unit at all: must not guess ns (a bare-µs release would be off 1000x).
    assert cr._mean_col_to_us({"Mean": "2.0"}) is None
    # Unit present but not one of the known ones.
    assert cr._mean_col_to_us({"Mean(fortnights)": "2.0"}) is None


def test_fmt_us_renders_na_instead_of_zero_for_none():
    # A None mean_us must not collapse to "0.00", which reads as a real near-zero time.
    assert cr._fmt_us(None, ".2f") == "n/a"
    assert cr._fmt_us(2.0, ".2f") == "2.00"


def test_top_kernel_rows_keeps_none_mean_us_for_unrecognized_unit(tmp_path):
    _write_csv(
        tmp_path / "0.1_Top_Kernels.csv",
        ["Kernel_Name", "Count", "Mean(fortnights)", "Percent"],
        [["k1", "3", "2.0", "10.0"]],
    )
    rows = cr._top_kernel_rows(tmp_path)
    assert rows[0]["mean_us"] is None


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


def test_launch_stats_rows_parses_by_header_name(tmp_path):
    _write_csv(
        tmp_path / "7.1_Launch_Stats.csv",
        [
            "Kernel_Name",
            "VGPRs",
            "AGPRs",
            "SGPRs",
            "LDS Allocation",
            "Total Wavefronts",
        ],
        [["my_kernel", "64", "0", "16", "8192", "128"]],
    )
    rows = cr.launch_stats_rows(str(tmp_path))
    assert rows == [
        {
            "kernel": "my_kernel",
            "vgprs": 64.0,
            "agprs": 0.0,
            "sgprs": 16.0,
            "lds_bytes": 8192.0,
            "wavefronts": 128.0,
        }
    ]


def test_launch_stats_rows_missing_panel_returns_empty(tmp_path):
    assert cr.launch_stats_rows(str(tmp_path)) == []


def test_top_launch_stats_row_matches_top_kernel_by_name(tmp_path):
    _write_csv(
        tmp_path / "0.1_Top_Kernels.csv",
        ["Kernel_Name", "Count", "Mean(ns)", "Percent"],
        [["my_kernel", "4", "1500", "37.5"]],
    )
    _write_csv(
        tmp_path / "7.1_Launch_Stats.csv",
        [
            "Kernel_Name",
            "VGPRs",
            "AGPRs",
            "SGPRs",
            "LDS Allocation",
            "Total Wavefronts",
        ],
        [
            ["other_kernel", "32", "0", "8", "0", "64"],
            ["my_kernel", "64", "0", "16", "8192", "128"],
        ],
    )
    row = cr.top_launch_stats_row(str(tmp_path))
    assert row["kernel"] == "my_kernel"
    assert row["vgprs"] == 64.0


def test_top_launch_stats_row_none_on_no_name_match(tmp_path):
    _write_csv(
        tmp_path / "0.1_Top_Kernels.csv",
        ["Kernel_Name", "Count", "Mean(ns)", "Percent"],
        [["unrelated_kernel", "4", "1500", "37.5"]],
    )
    _write_csv(
        tmp_path / "7.1_Launch_Stats.csv",
        [
            "Kernel_Name",
            "VGPRs",
            "AGPRs",
            "SGPRs",
            "LDS Allocation",
            "Total Wavefronts",
        ],
        [["other_kernel", "32", "0", "8", "0", "64"]],
    )
    assert cr.top_launch_stats_row(str(tmp_path)) is None


def test_top_launch_stats_row_none_when_panel_absent(tmp_path):
    assert cr.top_launch_stats_row(str(tmp_path)) is None


def test_build_omits_occupancy_section_when_launch_stats_panel_absent(tmp_path):
    _write_csv(
        tmp_path / "0.1_Top_Kernels.csv",
        ["Kernel_Name", "Count", "Mean(ns)", "Percent"],
        [["my_kernel", "4", "1500", "37.5"]],
    )
    html, md = cr.build(str(tmp_path), "wl", "gfx942")
    assert "Measured occupancy inputs" not in html
    assert "Measured occupancy inputs" not in md


def test_build_includes_occupancy_section_matched_to_top_kernel(tmp_path):
    _write_csv(
        tmp_path / "0.1_Top_Kernels.csv",
        ["Kernel_Name", "Count", "Mean(ns)", "Percent"],
        [["my_kernel", "4", "1500", "37.5"]],
    )
    _write_csv(
        tmp_path / "7.1_Launch_Stats.csv",
        [
            "Kernel_Name",
            "VGPRs",
            "AGPRs",
            "SGPRs",
            "LDS Allocation",
            "Total Wavefronts",
        ],
        [
            ["other_kernel", "32", "0", "8", "0", "64"],
            ["my_kernel", "64", "0", "16", "8192", "128"],
        ],
    )
    html, md = cr.build(str(tmp_path), "wl", "gfx942")
    assert "Measured occupancy inputs — my_kernel" in html
    assert "Measured occupancy inputs — my_kernel" in md
    assert "VGPRs: <b>64.0</b>" in html  # my_kernel's, not other_kernel's 32.0
    assert "max waves/CU (ceiling): <b>32</b>" in html  # gfx942 spec
