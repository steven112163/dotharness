"""Tests for lib/ck-profile/ck_profile_utils.py — bottleneck classification and stats."""

import math

import ck_profile_utils as u


def test_classify_compute_bound():
    assert u.classify(60.0, 0.0) == "compute-bound (VALU/MFMA)"
    assert u.classify(95.0, 95.0) == "compute-bound (VALU/MFMA)"


def test_classify_memory_bound():
    assert u.classify(10.0, 60.0) == "memory-bandwidth-bound"


def test_classify_latency_bound_when_both_low():
    assert u.classify(10.0, 10.0) == "latency/occupancy-bound"


def test_classify_mixed_in_the_middle():
    assert u.classify(40.0, 40.0) == "mixed / partially bound"


def test_short_maps_known_runtime_kernels():
    assert u.short("rocclr_fillBuffer_xyz") == "memset(fill)"
    assert u.short("amd_rocclr_copyBuffer") == "memcopy"


def test_short_labels_gemm_entry():
    assert u.short("some_GemmKernel_kentry") == "gemm(kentry)"


def test_short_strips_namespace_and_args():
    assert u.short("ck::tile::my_func(int, float)") == "my_func"


def test_short_truncates_to_28_chars():
    assert len(u.short("a" * 50)) == 28


def test_msd_mean_and_stdev():
    mean, sd = u.msd([2.0, 4.0, 6.0])
    assert mean == 4.0
    assert sd == 2.0


def test_msd_single_value_has_zero_stdev():
    mean, sd = u.msd([5.0])
    assert mean == 5.0
    assert sd == 0.0


def test_msd_ignores_nan_and_returns_nan_when_empty():
    mean, sd = u.msd([float("nan")])
    assert math.isnan(mean) and math.isnan(sd)
