#!/usr/bin/env python3
"""Aggregate rocprofv3 trace + PMC output produced by run_profile.sh.

Counter-set agnostic: it scans every pmc_*/p_counter_collection.csv, so adding
or removing lines in counters.txt does not require editing this script. Known
counters are turned into reported metrics; unknown ones are summed and ignored.

For each variant (sweep value), averaged over all runs:
  runtime (total GPU kernel time, program-reported time), L2 hit ratio,
  HBM fetch/write MB, occupancy, VALU%/SALU%/MFMA% busy, memory-unit stall %,
  LDS bank conflicts, wavefronts, achieved HBM bandwidth, roofline-lite verdict.

Usage:
  aggregate.py --raw DIR [--arch gfx942] [--iters N | --marker SUBSTR] [--out DIR]
"""
import argparse, csv, glob, os, re, statistics

PEAK_HBM_GBS = {"gfx942": 5300.0, "gfx950": 8000.0}  # gfx950 approximate — verify
COMPUTE_BOUND_PCT = 60.0
BW_BOUND_PCT = 60.0
# Counters reported as a duration-weighted mean (percentages/rates); the rest summed.
MEAN_COUNTERS = {"VALUBusy", "SALUBusy", "MeanOccupancyPerCU", "MemUnitStalled"}


def short(name):
    for k, l in [("rocclr_fillBuffer", "memset(fill)"), ("rocclr_copyBuffer", "memcopy"),
                 ("fillBuffer", "memset(fill)"), ("copyBuffer", "memcopy")]:
        if k in name:
            return l
    if "kentry" in name or "GemmKernel" in name or "BatchedGemm" in name:
        return "gemm(kentry)"
    base = name.split("(")[0]
    base = base.split("::")[-1] if "::" in base else base
    return base[:28] if base else name[:28]


def read_csv(p):
    with open(p) as f:
        return list(csv.DictReader(f))


def trace_metrics(run_dir, marker):
    dom = read_csv(os.path.join(run_dir, "t_domain_stats.csv"))
    total_ns = sum(float(r["TotalDurationNs"]) for r in dom)
    trace = read_csv(os.path.join(run_dir, "t_kernel_trace.csv"))
    n_marker = sum(1 for r in trace if marker and marker in r["Kernel_Name"])
    per = {}
    for r in trace:
        lbl = short(r["Kernel_Name"])
        d = float(r["End_Timestamp"]) - float(r["Start_Timestamp"])
        e = per.setdefault(lbl, {"dur": 0.0, "calls": 0, "vgpr": 0, "sgpr": 0, "lds": 0, "scr": 0})
        e["dur"] += d; e["calls"] += 1
        e["vgpr"] = max(e["vgpr"], int(r["VGPR_Count"]))
        e["sgpr"] = max(e["sgpr"], int(r["SGPR_Count"]))
        e["lds"] = max(e["lds"], int(r["LDS_Block_Size"]))
        e["scr"] = max(e["scr"], int(r["Scratch_Size"]))
    prog_ms = float("nan")
    sp = os.path.join(run_dir, "t.stdout")
    if os.path.exists(sp):
        m = re.search(r"([0-9.]+)\s*ms", open(sp).read())
        if m:
            prog_ms = float(m.group(1))
    return total_ns, n_marker, prog_ms, per


def collect_counters(run_dir):
    """Return {counter: sum} and {counter: duration-weighted mean} over all passes."""
    sums, wnum, wden = {}, {}, {}
    for f in glob.glob(os.path.join(run_dir, "pmc_*", "p_counter_collection.csv")):
        for r in read_csv(f):
            name = r["Counter_Name"]
            val = float(r["Counter_Value"])
            w = float(r["End_Timestamp"]) - float(r["Start_Timestamp"])
            sums[name] = sums.get(name, 0.0) + val
            wnum[name] = wnum.get(name, 0.0) + val * w
            wden[name] = wden.get(name, 0.0) + w
    means = {k: (wnum[k] / wden[k] if wden[k] else 0.0) for k in sums}
    return sums, means


def pmc_metrics(run_dir):
    s, m = collect_counters(run_dir)
    hit, miss = s.get("TCC_HIT", 0.0), s.get("TCC_MISS", 0.0)
    return {
        "hr": 100.0 * hit / (hit + miss) if (hit + miss) else 0.0,
        "fetch_kb": s.get("FETCH_SIZE", 0.0),
        "write_kb": s.get("WRITE_SIZE", 0.0),
        "occ": m.get("MeanOccupancyPerCU", 0.0),
        "valu": m.get("VALUBusy", 0.0),
        "salu": m.get("SALUBusy", 0.0),
        # Raw matrix-engine busy cycles (informational; non-zero = MFMA used).
        # Not converted to a % — that needs per-CU normalization (use omniperf).
        "mfma_cyc": s.get("SQ_VALU_MFMA_BUSY_CYCLES", 0.0),
        "memstall": m.get("MemUnitStalled", 0.0),
        "lds_conf": s.get("LDSBankConflict", 0.0),
        "waves": s.get("SQ_WAVES", 0.0),
    }


def msd(xs):
    xs = [x for x in xs if x == x]
    if not xs:
        return float("nan"), float("nan")
    return statistics.mean(xs), (statistics.stdev(xs) if len(xs) > 1 else 0.0)


def classify(compute_pct, bw_util_pct):
    if compute_pct >= COMPUTE_BOUND_PCT:
        return "compute-bound (VALU/MFMA)"
    if bw_util_pct >= BW_BOUND_PCT:
        return "memory-bandwidth-bound"
    if compute_pct < 25 and bw_util_pct < 25:
        return "latency/occupancy-bound"
    return "mixed / partially bound"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--arch", default="gfx942")
    ap.add_argument("--iters", type=int, default=0)
    ap.add_argument("--marker", default="")
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    out = a.out or os.path.dirname(a.raw.rstrip("/")) or "."
    peak = PEAK_HBM_GBS.get(a.arch)

    variants = sorted(d for d in glob.glob(os.path.join(a.raw, "*")) if os.path.isdir(d))
    overall = []
    for vd in variants:
        name = os.path.basename(vd)
        runs = sorted(glob.glob(os.path.join(vd, "run_*")))
        if not runs:
            continue
        acc = {k: [] for k in ["gpu_ms", "prog", "hr", "fmb", "wmb", "occ", "valu",
                               "salu", "mfma_cyc", "memstall", "lds", "waves", "bw"]}
        kern = {}
        for rd in runs:
            try:
                total_ns, nmark, pms, per = trace_metrics(rd, a.marker)
                p = pmc_metrics(rd)
            except FileNotFoundError:
                continue
            div = a.iters or (nmark if a.marker and nmark else 1)
            acc["gpu_ms"].append(total_ns / div / 1e6)
            acc["prog"].append(pms)
            acc["hr"].append(p["hr"])
            acc["fmb"].append(p["fetch_kb"] / 1024.0 / div)
            acc["wmb"].append(p["write_kb"] / 1024.0 / div)
            acc["occ"].append(p["occ"]); acc["valu"].append(p["valu"])
            acc["salu"].append(p["salu"]); acc["mfma_cyc"].append(p["mfma_cyc"] / div)
            acc["memstall"].append(p["memstall"]); acc["lds"].append(p["lds_conf"] / div)
            acc["waves"].append(p["waves"] / div)
            acc["bw"].append((p["fetch_kb"] + p["write_kb"]) * 1024.0 / (total_ns / 1e9) / 1e9)
            for lbl, e in per.items():
                k = kern.setdefault(lbl, {"us": [], "calls": e["calls"] // max(div, 1),
                                          "vgpr": e["vgpr"], "sgpr": e["sgpr"], "lds": e["lds"], "scr": e["scr"]})
                k["us"].append(e["dur"] / div / 1e3)
        m = {k: msd(v) for k, v in acc.items()}
        bw_util = 100.0 * m["bw"][0] / peak if peak else float("nan")
        compute_util = max(m["valu"][0], m["salu"][0])
        verdict = classify(compute_util, bw_util) if peak else "n/a (unknown arch peak)"
        overall.append((name, len(runs), m, bw_util, verdict))

        with open(os.path.join(out, f"per_kernel_{name}.csv"), "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["kernel", "calls", "us_total", "pct", "VGPR", "SGPR", "LDS_bytes", "scratch"])
            tot = sum(statistics.mean(k["us"]) for k in kern.values()) or 1
            for lbl, k in sorted(kern.items(), key=lambda x: -statistics.mean(x[1]["us"])):
                us = statistics.mean(k["us"])
                w.writerow([lbl, k["calls"], f"{us:.2f}", f"{100*us/tot:.1f}",
                            k["vgpr"], k["sgpr"], k["lds"], k["scr"]])

    with open(os.path.join(out, "summary_overall.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["variant", "runs", "gpu_ms", "gpu_ms_sd", "prog_ms", "L2_hit_pct",
                    "fetch_MB", "write_MB", "occupancy", "valu_pct", "salu_pct",
                    "mem_stall_pct", "lds_bank_conflicts", "mfma_busy_cycles", "wavefronts",
                    "achieved_BW_GBs", "BW_util_pct", "verdict"])
        for name, nr, m, bwu, verdict in overall:
            w.writerow([name, nr, f"{m['gpu_ms'][0]:.4f}", f"{m['gpu_ms'][1]:.4f}",
                        f"{m['prog'][0]:.4f}", f"{m['hr'][0]:.2f}", f"{m['fmb'][0]:.3f}",
                        f"{m['wmb'][0]:.3f}", f"{m['occ'][0]:.2f}", f"{m['valu'][0]:.2f}",
                        f"{m['salu'][0]:.2f}", f"{m['memstall'][0]:.2f}",
                        f"{m['lds'][0]:.0f}", f"{m['mfma_cyc'][0]:.0f}", f"{m['waves'][0]:.0f}",
                        f"{m['bw'][0]:.1f}", f"{bwu:.1f}", verdict])

    unit = "per-iter" if (a.iters or a.marker) else "per-run"
    print(f"arch={a.arch}  peak_HBM={peak} GB/s  normalization={unit}")
    print(f"{'variant':9} {'runs':4} {'gpu_ms':>8} {'L2%':>6} {'fetMB':>7} {'wrMB':>7} "
          f"{'occ':>5} {'VALU%':>6} {'SALU%':>6} {'memStl%':>7} {'BW%':>5}  verdict")
    for name, nr, m, bwu, verdict in overall:
        print(f"{name:9} {nr:4d} {m['gpu_ms'][0]:8.4f} {m['hr'][0]:6.1f} {m['fmb'][0]:7.2f} "
              f"{m['wmb'][0]:7.2f} {m['occ'][0]:5.2f} {m['valu'][0]:6.2f} {m['salu'][0]:6.2f} "
              f"{m['memstall'][0]:7.2f} {bwu:5.1f}  {verdict}")
    print(f"\nwrote {os.path.join(out, 'summary_overall.csv')} and per_kernel_*.csv")


if __name__ == "__main__":
    main()
