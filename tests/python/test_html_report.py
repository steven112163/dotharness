"""Tests for lib/ck-profile/html_report.py — bar-fill color thresholds."""

import ck_profile_utils as U
import html_report as H


def test_fill_color_thresholds_match_ck_profile_utils_bound_pcts():
    just_below_compute = (U.COMPUTE_BOUND_PCT - 1) / 100
    at_compute = U.COMPUTE_BOUND_PCT / 100
    just_below_latency = (U.LATENCY_BOUND_PCT - 1) / 100
    at_latency = U.LATENCY_BOUND_PCT / 100

    assert H._fill_color(at_compute) == "#4cc2ff"
    assert H._fill_color(just_below_compute) != "#4cc2ff"
    assert H._fill_color(at_latency) == "#3a8fbf"
    assert H._fill_color(just_below_latency) == "#33566b"
