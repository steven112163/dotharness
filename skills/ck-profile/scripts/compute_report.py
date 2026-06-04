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
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import html_report as H

COMPUTE_BOUND_PCT = 60.0
BW_BOUND_PCT = 60.0


def read_panel(csvdir, stem):
    """Find <stem>*.csv (panels are prefixed by id) and return (headers, rows)."""
    hits = glob.glob(os.path.join(csvdir, f"{stem}*.csv"))
    if not hits:
        return [], []
    with open(hits[0], newline="") as f:
        r = list(csv.reader(f))
    return (r[0], r[1:]) if r else ([], [])


def fnum(s):
    try:
        return float(str(s).replace(",", "").strip())
    except (ValueError, AttributeError):
        return None


def short_kernel(name):
    s = " ".join(str(name).split())          # collapse the wrapped multi-line cell
    s = re.sub(r"^void\s+", "", s)
    s = s.split("(")[0].split("<")[0]
    s = s.split("::")[-1].strip()
    return s[:34] if s else "kernel"


def classify(compute_pct, bw_pct):
    if compute_pct >= COMPUTE_BOUND_PCT:
        return "compute-bound (VALU/MFMA)"
    if bw_pct >= BW_BOUND_PCT:
        return "memory-bandwidth-bound"
    if compute_pct < 25 and bw_pct < 25:
        return "latency/occupancy-bound"
    return "mixed / partially bound"


def sol_rows(csvdir):
    """System Speed-of-Light as list of dicts: metric, avg, unit, peak, pct."""
    hdr, rows = read_panel(csvdir, "2.1_System_Speed-of-Light")
    out = []
    for r in rows:
        if len(r) < 5:
            continue
        out.append({"metric": r[0], "avg": r[1], "unit": r[2], "peak": r[3], "pct": fnum(r[4])})
    return out


def build(csvdir, name, arch):
    sol = sol_rows(csvdir)
    flops = [r["pct"] for r in sol if r["pct"] is not None and ("FLOP" in r["metric"] or "IOP" in r["metric"])]
    bw = [r["pct"] for r in sol if r["pct"] is not None and ("BW" in r["metric"] or "Bandwidth" in r["metric"])]
    compute_pct = max(flops) if flops else 0.0
    bw_pct = max(bw) if bw else 0.0
    verdict = classify(compute_pct, bw_pct)

    parts = [f"<h1>compute — rocprof-compute</h1>",
             f"<p class='sub'>{H.esc(name)} &middot; arch <b>{H.esc(arch)}</b> &middot; "
             f"rocprof-compute roofline / speed-of-light</p>"]

    # verdict + the two driving ratios
    parts.append(H.section("Verdict",
        f"<div class='card'><div class='row'><h3>bottleneck</h3>&nbsp;{H.badge(verdict)}</div>"
        f"<div class='grid2'><div>peak compute (max FLOP/IOP): <b>{compute_pct:.2f} %</b></div>"
        f"<div>peak bandwidth (max cache/LDS BW): <b>{bw_pct:.2f} %</b></div></div>"
        "<p class='sub'>Derived from System Speed-of-Light below: high compute % = "
        "compute-bound; high BW % = memory-bound; both low = latency/occupancy-bound.</p></div>"))

    # %-of-peak gauges (rows that have a Pct)
    gitems = [(f"{r['metric']} ({r['avg']} {r['unit']})", r["pct"]) for r in sol if r["pct"] is not None]
    if gitems:
        parts.append(H.section("Speed-of-Light — % of peak",
                     f"<div class='card'>{H.gauges(gitems)}</div>"))

    # top kernels: bars by pct + table
    hdr, rows = read_panel(csvdir, "0.1_Top_Kernels")
    if rows:
        items, trows = [], []
        for r in rows:
            if len(r) < 6:
                continue
            k = short_kernel(r[0]); pct = fnum(r[5]) or 0.0
            mean_us = (fnum(r[3]) or 0.0) / 1e3
            items.append((k, pct, f"{mean_us:.1f} µs ({pct:.1f}%)"))
            trows.append([k, r[1], f"{mean_us:.2f}", f"{pct:.1f}"])
        parts.append(H.section("Top kernels (by total time)",
                     f"<div class='card'>{H.bars(items[:12], max_value=100.0)}</div>"
                     + H.table(["kernel", "count", "mean µs", "% time"], trows[:12], num_cols=(1, 2, 3))))

    # full SoL table
    if sol:
        trows = [[r["metric"], r["avg"], r["unit"], r["peak"],
                  (f"{r['pct']:.2f}" if r["pct"] is not None else "")] for r in sol]
        parts.append(H.section("System Speed-of-Light (full)",
                     H.table(["metric", "avg", "unit", "peak", "% of peak"], trows, num_cols=(1, 3, 4))))

    # system info
    hdr, rows = read_panel(csvdir, "1.1_System_Info")
    if rows:
        info = [v[0] for v in rows[:8] if v]
        parts.append(H.section("System info",
                     "<div class='card'><div class='grid2'>"
                     + "".join(f"<div>{H.esc(x)}</div>" for x in info) + "</div></div>"))

    parts.append("<p class='foot'>Rendered from rocprof-compute CSV panels. Full per-panel "
                 "CSVs, the text dump, and empirical-roofline PDFs are under raw/. Re-open "
                 "interactively with <code>rocprof-compute analyze -p &lt;workload&gt; --gui</code>.</p>")

    html = H.page(f"compute report — {name} ({arch})", "".join(parts))

    # --- markdown twin ---
    md = [f"# compute mode — rocprof-compute — {name} ({arch})", "",
          "## How to read", "",
          "- Open **`{0}_report.html`** for the charted version (gauges + bars, offline). "
          "This `.md` mirrors it; raw per-panel CSVs + the text dump + roofline PDFs are in "
          "`raw/`.".format(name),
          "- **Verdict** below is the one-line read; the **Speed-of-Light** table is the "
          "evidence — the *% of peak* column is the key one. High FLOP % = compute-bound, "
          "high BW % = memory-bound, both low = latency/occupancy-bound.", "",
          f"**Verdict: {verdict}**  (peak compute {compute_pct:.2f}%, peak BW {bw_pct:.2f}%)", "",
          "## System Speed-of-Light", "",
          "| metric | avg | unit | peak | % of peak |", "| --- | --- | --- | --- | --- |"]
    for r in sol:
        md.append(f"| {r['metric']} | {r['avg']} | {r['unit']} | {r['peak']} | "
                  f"{r['pct']:.2f} |" if r["pct"] is not None else
                  f"| {r['metric']} | {r['avg']} | {r['unit']} | {r['peak']} |  |")
    hdr, rows = read_panel(csvdir, "0.1_Top_Kernels")
    if rows:
        md += ["", "## Top kernels", "", "| kernel | count | mean µs | % time |",
               "| --- | --- | --- | --- |"]
        for r in rows[:12]:
            if len(r) < 6:
                continue
            md.append(f"| {short_kernel(r[0])} | {r[1]} | {(fnum(r[3]) or 0)/1e3:.2f} | {r[5]} |")
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
