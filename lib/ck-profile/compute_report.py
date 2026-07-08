#!/usr/bin/env python3
"""Render rocprof-compute's CSV panels into a styled HTML + Markdown report.

rocprof-compute `analyze --output-format csv --output-name <dir>` writes one CSV
per panel (e.g. `2.1_System_Speed-of-Light.csv`, `0.1_Top_Kernels.csv`). This
turns the headline panels into the same dark "telemetry" HTML the other modes use
(via html_report.py) — Speed-of-Light rows become %-of-peak gauges, top kernels
become bars — plus a Markdown twin. Raw per-panel CSVs and the text dump stay in
raw/ for power users.

    compute_report.py --csv <csvdir> --out <dir> --name <workload> --arch gfx942
"""

import argparse
import csv
import glob
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import html_report as H  # noqa: E402
from ck_profile_utils import classify  # noqa: E402
from gpu_specs import get_spec  # noqa: E402


# rocprof-compute has renamed panel columns across releases (e.g. "Avg" vs
# "Value", "Peak" vs "Peak (Empirical)", "Pct of Peak" vs "PoP"). Pick by name,
# trying aliases in order, instead of a fixed column index that silently reads
# the wrong field (or 0.0) the moment a release reorders columns.
def pick(row, *names):
    for n in names:
        if n in row:
            return row[n]
    return None


def read_panel(csvdir, stem):
    """Find <stem>*.csv (panels are prefixed by id) and return a list of dict rows."""
    hits = glob.glob(os.path.join(csvdir, f"{stem}*.csv"))
    if not hits:
        return []
    with open(hits[0], newline="") as f:
        return list(csv.DictReader(f))


def fnum(s):
    """Parse a CSV cell to float, or None if missing/non-numeric/non-finite
    (NaN/Inf CSV cells shouldn't render as literal "nan"/"inf")."""
    try:
        v = float(str(s).replace(",", "").strip())
    except (ValueError, AttributeError):
        return None
    return v if math.isfinite(v) else None


# Mean/Sum/Median columns are named e.g. "Mean(ns)"/"Mean(us)"/"Mean(ms)" per
# --time-unit; convert whatever unit is present to microseconds for display.
_TIME_TO_US = {"ns": 1e-3, "us": 1.0, "µs": 1.0, "ms": 1e3, "s": 1e6}


def _mean_col_to_us(row):
    """Find the Mean(<unit>) column and return its value converted to µs, or
    None if the column is absent or its unit is unrecognized (never guess)."""
    col = next((h for h in row if h.startswith("Mean")), None)
    if col is None:
        return None
    m = re.search(r"\(([^)]+)\)", col)
    if m is None or m.group(1) not in _TIME_TO_US:
        return None
    v = fnum(row[col])
    return None if v is None else v * _TIME_TO_US[m.group(1)]


def _fmt_us(mean_us, fmt):
    return "n/a" if mean_us is None else format(mean_us, fmt)


def short_kernel(name):
    s = " ".join(str(name).split())  # collapse the wrapped multi-line cell
    s = re.sub(r"^void\s+", "", s)
    s = s.split("(")[0].split("<")[0]
    s = s.split("::")[-1].strip()
    return s[:34] if s else "kernel"


def _top_kernel_rows(csvdir):
    """Top-Kernels panel decoded once (name/unit aliasing) for both HTML and Markdown."""
    out = []
    for r in read_panel(csvdir, "0.1_Top_Kernels"):
        kname = pick(r, "Kernel_Name", "KernelName", "Kernel")
        if kname is None:
            continue
        out.append(
            {
                "kernel": short_kernel(kname),
                "count": pick(r, "Count"),
                "mean_us": _mean_col_to_us(r),
                "pct": fnum(pick(r, "Percent", "Pct", "% time")) or 0.0,
            }
        )
    return out


def launch_stats_rows(csvdir):
    """Per-kernel VGPR/AGPR/SGPR/LDS/wavefronts from the Launch Stats panel.
    [] if not found (unverified panel name/columns; see profile_readme.md)."""
    out = []
    for r in read_panel(csvdir, "7.1_Launch_Stats"):
        kname = pick(r, "Kernel_Name", "KernelName", "Kernel")
        if kname is None:
            continue
        out.append(
            {
                "kernel": short_kernel(kname),
                "vgprs": fnum(pick(r, "VGPRs", "VGPR")),
                "agprs": fnum(pick(r, "AGPRs", "AGPR")),
                "sgprs": fnum(pick(r, "SGPRs", "SGPR")),
                "lds_bytes": fnum(pick(r, "LDS Allocation", "LDS_Allocation", "LDS")),
                "wavefronts": fnum(
                    pick(r, "Total Wavefronts", "Total_Wavefronts", "Wavefronts")
                ),
            }
        )
    return out


def top_launch_stats_row(csvdir):
    """Launch Stats row for the top kernel by time. None if the Launch Stats
    panel isn't present or its top-kernel name doesn't match Top Kernels'
    (the two panels may format kernel names differently) — never guess."""
    ls = launch_stats_rows(csvdir)
    if not ls:
        return None
    tk = _top_kernel_rows(csvdir)
    top_name = tk[0]["kernel"] if tk else None
    return next((r for r in ls if r["kernel"] == top_name), None)


def sol_rows(csvdir):
    """System Speed-of-Light as list of dicts: metric, avg, unit, peak, pct."""
    out = []
    for r in read_panel(csvdir, "2.1_System_Speed-of-Light"):
        metric = pick(r, "Metric")
        if metric is None:
            continue
        out.append(
            {
                "metric": metric,
                "avg": pick(r, "Avg", "Value"),
                "unit": pick(r, "Unit"),
                "peak": pick(r, "Peak (Empirical)", "Peak"),
                "pct": fnum(pick(r, "Pct of Peak", "PoP", "Pct")),
            }
        )
    return out


def build(csvdir, name, arch):
    spec = get_spec(arch)

    def sv(x, suffix=""):
        return f"{x}{suffix}" if x is not None else "n/a"

    sol = sol_rows(csvdir)
    flops = [
        r["pct"]
        for r in sol
        if r["pct"] is not None and ("FLOP" in r["metric"] or "IOP" in r["metric"])
    ]
    bw = [
        r["pct"]
        for r in sol
        if r["pct"] is not None and ("BW" in r["metric"] or "Bandwidth" in r["metric"])
    ]
    compute_pct = max(flops) if flops else 0.0
    bw_pct = max(bw) if bw else 0.0
    verdict = classify(compute_pct, bw_pct)

    parts = [
        "<h1>compute — rocprof-compute</h1>",
        f"<p class='sub'>{H.esc(name)} &middot; arch <b>{H.esc(arch)}</b> &middot; "
        f"rocprof-compute roofline / speed-of-light</p>",
    ]

    # verdict + the two driving ratios
    parts.append(
        H.section(
            "Verdict",
            f"<div class='card'><div class='row'><h3>bottleneck</h3>&nbsp;{H.badge(verdict)}</div>"
            f"<div class='grid2'><div>peak compute (max FLOP/IOP): <b>{compute_pct:.2f} %</b></div>"
            f"<div>peak bandwidth (max cache/LDS BW): <b>{bw_pct:.2f} %</b></div></div>"
            "<p class='sub'>Derived from System Speed-of-Light below: high compute % = "
            "compute-bound; high BW % = memory-bound; both low = latency/occupancy-bound.</p></div>",
        )
    )

    # %-of-peak gauges (rows that have a Pct)
    gitems = [
        (f"{r['metric']} ({r['avg']} {r['unit']})", r["pct"])
        for r in sol
        if r["pct"] is not None
    ]
    if gitems:
        parts.append(
            H.section(
                "Speed-of-Light — % of peak",
                f"<div class='card'>{H.gauges(gitems)}</div>",
            )
        )

    # top kernels: bars by pct + table
    tk = _top_kernel_rows(csvdir)
    if tk:
        items = [
            (
                r["kernel"],
                r["pct"],
                f"{_fmt_us(r['mean_us'], '.1f')} µs ({r['pct']:.1f}%)",
            )
            for r in tk
        ]
        trows = [
            [r["kernel"], r["count"], _fmt_us(r["mean_us"], ".2f"), f"{r['pct']:.1f}"]
            for r in tk
        ]
        parts.append(
            H.section(
                "Top kernels (by total time)",
                f"<div class='card'>{H.bars(items[:12], max_value=100.0)}</div>"
                + H.table(
                    ["kernel", "count", "mean µs", "% time"],
                    trows[:12],
                    num_cols=(1, 2, 3),
                ),
            )
        )

    # Measured VGPR/AGPR/SGPR/LDS/wavefronts for the top kernel, next to the
    # hardware ceiling.
    ls_row = top_launch_stats_row(csvdir)
    if ls_row:
        parts.append(
            H.section(
                f"Measured occupancy inputs — {H.esc(ls_row['kernel'])}",
                "<div class='card'><div class='grid2'>"
                f"<div>VGPRs: <b>{sv(ls_row['vgprs'])}</b></div>"
                f"<div>AGPRs: <b>{sv(ls_row['agprs'])}</b></div>"
                f"<div>SGPRs: <b>{sv(ls_row['sgprs'])}</b></div>"
                f"<div>LDS allocation: <b>{sv(ls_row['lds_bytes'], ' B')}</b></div>"
                f"<div>Total wavefronts: <b>{sv(ls_row['wavefronts'])}</b></div>"
                f"<div>max waves/CU (ceiling): <b>{sv(spec['max_waves_cu'] if spec else None)}</b></div>"
                "</div><p class='sub'>Measured, not estimated — pair with the static "
                "report's compile-time ceiling to see if this run actually reached "
                "it. Not a formal limiter classification; compare each value "
                "against the arch's VGPR/AGPR/LDS caps in the static report's "
                "device-spec table to judge which one is tightest.</p></div>",
            )
        )

    # full SoL table
    if sol:
        trows = [
            [
                r["metric"],
                r["avg"],
                r["unit"],
                r["peak"],
                (f"{r['pct']:.2f}" if r["pct"] is not None else ""),
            ]
            for r in sol
        ]
        parts.append(
            H.section(
                "System Speed-of-Light (full)",
                H.table(
                    ["metric", "avg", "unit", "peak", "% of peak"],
                    trows,
                    num_cols=(1, 3, 4),
                ),
            )
        )

    # system info
    rows = read_panel(csvdir, "1.1_System_Info")
    if rows:
        info = [next(iter(v.values())) for v in rows[:8] if v]
        parts.append(
            H.section(
                "System info",
                "<div class='card'><div class='grid2'>"
                + "".join(f"<div>{H.esc(x)}</div>" for x in info)
                + "</div></div>",
            )
        )

    parts.append(
        "<p class='foot'>Rendered from rocprof-compute CSV panels. Full per-panel "
        "CSVs, the text dump, and empirical-roofline PDFs are under raw/. Re-open "
        "interactively with <code>rocprof-compute analyze -p &lt;workload&gt; --gui</code>.</p>"
    )

    html = H.page(f"compute report — {name} ({arch})", "".join(parts))

    # --- markdown twin ---
    md = [
        f"# compute mode — rocprof-compute — {name} ({arch})",
        "",
        "## How to read",
        "",
        "- Open **`{0}_report.html`** for the charted version (gauges + bars, offline). "
        "This `.md` mirrors it; raw per-panel CSVs + the text dump + roofline PDFs are in "
        "`raw/`.".format(name),
        "- **Verdict** below is the one-line read; the **Speed-of-Light** table is the "
        "evidence — the *% of peak* column is the key one. High FLOP % = compute-bound, "
        "high BW % = memory-bound, both low = latency/occupancy-bound.",
        "",
        f"**Verdict: {verdict}**  (peak compute {compute_pct:.2f}%, peak BW {bw_pct:.2f}%)",
        "",
        "## System Speed-of-Light",
        "",
        "| metric | avg | unit | peak | % of peak |",
        "| --- | --- | --- | --- | --- |",
    ]
    for r in sol:
        md.append(
            f"| {r['metric']} | {r['avg']} | {r['unit']} | {r['peak']} | "
            f"{r['pct']:.2f} |"
            if r["pct"] is not None
            else f"| {r['metric']} | {r['avg']} | {r['unit']} | {r['peak']} |  |"
        )
    if tk:
        md += [
            "",
            "## Top kernels",
            "",
            "| kernel | count | mean µs | % time |",
            "| --- | --- | --- | --- |",
        ]
        for r in tk[:12]:
            md.append(
                f"| {r['kernel']} | {r['count']} | {_fmt_us(r['mean_us'], '.2f')} | {r['pct']:.1f} |"
            )
    if ls_row:
        md += [
            "",
            f"## Measured occupancy inputs — {ls_row['kernel']}",
            "",
            "Measured, not estimated — pair with the static report's compile-time "
            "ceiling. Not a formal limiter classification.",
            "",
            "| VGPRs | AGPRs | SGPRs | LDS allocation (B) | total wavefronts | max waves/CU |",
            "| --- | --- | --- | --- | --- | --- |",
            f"| {sv(ls_row['vgprs'])} | {sv(ls_row['agprs'])} | {sv(ls_row['sgprs'])} | "
            f"{sv(ls_row['lds_bytes'])} | {sv(ls_row['wavefronts'])} | "
            f"{sv(spec['max_waves_cu'] if spec else None)} |",
        ]
    return html, "\n".join(md) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True, help="dir of rocprof-compute CSV panels")
    ap.add_argument("--out", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--arch", default="")
    a = ap.parse_args()
    html, md = build(a.csv, a.name, a.arch)
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, f"{a.name}_report.html"), "w") as f:
        f.write(html)
    with open(os.path.join(a.out, f"{a.name}_report.md"), "w") as f:
        f.write(md)
    print(f"wrote {a.name}_report.html and {a.name}_report.md to {a.out}")


if __name__ == "__main__":
    main()
