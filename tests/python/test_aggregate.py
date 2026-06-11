"""Tests for skills/ck-profile/scripts/aggregate.py — the pure helpers: bottleneck
classification, kernel-name shortening, and mean/stdev."""

import math

import aggregate


def test_classify_compute_bound():
    assert aggregate.classify(60.0, 0.0) == "compute-bound (VALU/MFMA)"
    assert aggregate.classify(95.0, 95.0) == "compute-bound (VALU/MFMA)"


def test_classify_memory_bound():
    assert aggregate.classify(10.0, 60.0) == "memory-bandwidth-bound"


def test_classify_latency_bound_when_both_low():
    assert aggregate.classify(10.0, 10.0) == "latency/occupancy-bound"


def test_classify_mixed_in_the_middle():
    assert aggregate.classify(40.0, 40.0) == "mixed / partially bound"


def test_short_maps_known_runtime_kernels():
    assert aggregate.short("rocclr_fillBuffer_xyz") == "memset(fill)"
    assert aggregate.short("amd_rocclr_copyBuffer") == "memcopy"


def test_short_labels_gemm_entry():
    assert aggregate.short("some_GemmKernel_kentry") == "gemm(kentry)"


def test_short_strips_namespace_and_args():
    assert aggregate.short("ck::tile::my_func(int, float)") == "my_func"


def test_short_truncates_to_28_chars():
    assert len(aggregate.short("a" * 50)) == 28


def test_msd_mean_and_stdev():
    mean, sd = aggregate.msd([2.0, 4.0, 6.0])
    assert mean == 4.0
    assert sd == 2.0


def test_msd_single_value_has_zero_stdev():
    mean, sd = aggregate.msd([5.0])
    assert mean == 5.0
    assert sd == 0.0


def test_msd_ignores_nan_and_returns_nan_when_empty():
    mean, sd = aggregate.msd([float("nan")])
    assert math.isnan(mean) and math.isnan(sd)
