"""Shared utilities imported by ckAggregate and ckDepgraph."""

import statistics

COMPUTE_BOUND_PCT = 60.0
BW_BOUND_PCT = 60.0
LATENCY_BOUND_PCT = 25.0


def classify(compute_pct, bw_util_pct):
    if compute_pct >= COMPUTE_BOUND_PCT:
        return "compute-bound (VALU/MFMA)"
    if bw_util_pct >= BW_BOUND_PCT:
        return "memory-bandwidth-bound"
    if compute_pct < LATENCY_BOUND_PCT and bw_util_pct < LATENCY_BOUND_PCT:
        return "latency/occupancy-bound"
    return "mixed / partially bound"


def msd(xs):
    xs = [x for x in xs if x == x]
    if not xs:
        return float("nan"), float("nan")
    return statistics.mean(xs), (statistics.stdev(xs) if len(xs) > 1 else 0.0)


def short(name):
    for k, label in [
        ("rocclr_fillBuffer", "memset(fill)"),
        ("rocclr_copyBuffer", "memcopy"),
        ("fillBuffer", "memset(fill)"),
        ("copyBuffer", "memcopy"),
    ]:
        if k in name:
            return label
    if "kentry" in name or "GemmKernel" in name or "BatchedGemm" in name:
        return "gemm(kentry)"
    base = name.split("(")[0]
    base = base.split("::")[-1] if "::" in base else base
    return base[:28] if base else name[:28]
