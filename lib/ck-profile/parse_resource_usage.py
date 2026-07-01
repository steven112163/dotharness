#!/usr/bin/env python3
"""Extract kernel resource usage from a CK build log.

The log must come from a build compiled with
`-Rpass-analysis=kernel-resource-usage`. The compiler emits one block of
remarks per device function; each remark line looks like

    <file>:<line>:<col>: remark:     VGPRs: 256 [-Rpass-analysis=kernel-resource-usage]

(possibly wrapped in ANSI color codes). This script collects the blocks, names
them (demangled with c++filt when available), computes effective VGPRs and the
occupancy implication, and writes a CSV plus a short markdown report.

    parse_resource_usage.py <build_log> [--arch gfx942] [--target NAME] [--out DIR]
"""

import argparse
import csv
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gpu_specs import (
    get_spec,
    peak_mem_gbs,
)  # per-arch hardware specs (shared with aggregate.py)
import html_report as H  # zero-dependency self-contained HTML report

TAG = "[-Rpass-analysis=kernel-resource-usage]"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")


# remark label -> (record field, parser)
def _INT(s):
    return int(s.strip())


def _BOOL(s):
    return s.strip().lower() == "true"


LABELS = {
    "Function Name": ("kernel", str.strip),
    "TotalSGPRs": ("total_sgprs", _INT),
    "VGPRs": ("vgprs", _INT),
    "AGPRs": ("agprs", _INT),
    "ScratchSize [bytes/lane]": ("scratch_size", _INT),
    "Dynamic Stack": ("dynamic_stack", _BOOL),
    "Occupancy [waves/SIMD]": ("occupancy", _INT),
    "SGPRs Spill": ("sgpr_spill", _INT),
    "VGPRs Spill": ("vgpr_spill", _INT),
    "LDS Size [bytes/block]": ("lds_size", _INT),
}
NUMERIC_FIELDS = [
    "total_sgprs",
    "vgprs",
    "agprs",
    "scratch_size",
    "occupancy",
    "sgpr_spill",
    "vgpr_spill",
    "lds_size",
]


def _new_record(source, kernel):
    rec = {"source": source, "kernel": kernel, "dynamic_stack": False}
    rec.update({f: 0 for f in NUMERIC_FIELDS})
    return rec


def parse_log(path):
    """Return a list of per-kernel records parsed from the build log."""
    records, cur = [], None
    for line in Path(path).read_text(errors="replace").splitlines():
        if TAG not in line:
            continue
        line = _ANSI.sub("", line)
        location, _, rest = line.partition(": remark:")
        if not rest:
            continue
        body = rest.replace(TAG, "").strip()
        label, sep, value = body.partition(":")
        label = label.strip()
        if not sep or label not in LABELS:
            continue
        field, conv = LABELS[label]
        if field == "kernel":
            if cur:
                records.append(cur)
            cur = _new_record(location.strip(), conv(value))
        elif cur is not None:
            try:
                cur[field] = conv(value)
            except ValueError:
                pass
    if cur:
        records.append(cur)
    return records


def demangle_names(names):
    """Map mangled -> demangled using one c++filt call; identity on failure."""
    result = {n: n for n in names}
    mangled = sorted({n for n in names if n.startswith("_Z")})
    if not mangled or not shutil.which("c++filt"):
        return result
    proc = subprocess.run(
        ["c++filt"], input="\n".join(mangled), capture_output=True, text=True
    )
    if proc.returncode == 0:
        for mangled_name, readable in zip(mangled, proc.stdout.splitlines()):
            result[mangled_name] = readable.strip()
    return result


def effective_vgprs(rec, arch):
    """CDNA4 (gfx95x) sums VGPR+AGPR (unified file); CDNA3 takes the max."""
    if arch.startswith("gfx95"):
        return rec["vgprs"] + rec["agprs"]
    return max(rec["vgprs"], rec["agprs"])


def has_spill(rec):
    return rec["scratch_size"] > 0 or rec["sgpr_spill"] > 0 or rec["vgpr_spill"] > 0


def write_csv(records, arch, path):
    cols = [
        "source",
        "kernel",
        "vgprs",
        "agprs",
        "effective_vgprs",
        "total_sgprs",
        "scratch_size",
        "occupancy",
        "sgpr_spill",
        "vgpr_spill",
        "lds_size",
        "dynamic_stack",
    ]
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(cols)
        for r in sorted(
            records, key=lambda r: (r["scratch_size"], r["vgprs"]), reverse=True
        ):
            w.writerow(
                [
                    r["source"],
                    r["readable"],
                    r["vgprs"],
                    r["agprs"],
                    r["effective_vgprs"],
                    r["total_sgprs"],
                    r["scratch_size"],
                    r["occupancy"],
                    r["sgpr_spill"],
                    r["vgpr_spill"],
                    r["lds_size"],
                    r["dynamic_stack"],
                ]
            )


def write_report(records, arch, target, path):
    spilled = [r for r in records if has_spill(r)]
    dynstack = [r for r in records if r["dynamic_stack"]]
    worst = sorted(
        records,
        key=lambda r: (r["scratch_size"], r["vgpr_spill"], r["effective_vgprs"]),
        reverse=True,
    )[:15]
    occ_hist = {}
    for r in records:
        occ_hist[r["occupancy"]] = occ_hist.get(r["occupancy"], 0) + 1

    lines = [
        f"# static mode — kernel resource report — {target or '(target)'} ({arch})",
        "",
    ]
    lines += [
        f"- Kernels analyzed: **{len(records)}**",
        f"- With spills or scratch: **{len(spilled)}**",
        f"- With dynamic stack: **{len(dynstack)}**",
        "",
        "## How to read",
        "",
        "- Compile-time only (no GPU run). Open **`build_report.html`** for charts; "
        "this `.md` mirrors it; `build_report.csv` is for scripts; `build/` is the "
        "throwaway instrumented build tree.",
        "- **Occupancy (waves/SIMD)** is the *ceiling* each kernel allows; the "
        "dynamic report's *occ util %* is what was actually achieved against it.",
        "- **Effective VGPR** drives the ceiling: cliff at **129** (128 → 4 waves, "
        "129 → 3). Non-zero **scratch / spill** or **dynamic stack** = per-lane "
        "global-memory traffic — a red flag (highlighted rows).",
        "- The top table is sorted worst-first (scratch, then spill, then eff-VGPR). "
        "A heavy kernel here that is also hot in the dynamic report is the one to "
        "attack first.",
        "",
    ]
    spec = get_spec(arch)
    if spec:

        def sv(x, s=""):
            return f"{x}{s}" if x is not None else "n/a"

        lines += [
            f"## Device spec — {arch} ({spec['product']})",
            "",
            "| CUs | wave | SIMD/CU | max waves/CU | VGPR/SIMD | AGPR/SIMD | LDS/CU | peak mem BW |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |",
            f"| {sv(spec['cu'])} | {sv(spec['wave'])} | {sv(spec['simd_per_cu'])} | "
            f"{sv(spec['max_waves_cu'])} | {sv(spec['vgpr_per_simd'])} | {sv(spec['agpr_per_simd'])} | "
            f"{sv(spec['lds_kb_per_cu'], ' KB')} | {sv(peak_mem_gbs(arch), ' GB/s')} |",
            "",
            "Per-kernel VGPR/AGPR/LDS below are reserved out of the per-SIMD VGPR file "
            "and per-CU LDS shown here; the closer a kernel gets to those, the fewer waves "
            "fit. n/a = value not published for this arch.",
            "",
        ]
    lines += [
        "## Occupancy (waves/SIMD) distribution",
        "",
        "| waves/SIMD | kernels |",
        "| --- | --- |",
    ]
    for occ in sorted(occ_hist):
        lines.append(f"| {occ} | {occ_hist[occ]} |")
    lines += [
        "",
        "## Highest resource usage (top 15 by scratch, then spill, then eff-VGPR)",
        "",
        "| kernel | eff VGPR | VGPR | AGPR | SGPR | scratch | vgpr_spill | sgpr_spill | LDS | occ | dyn-stack |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for r in worst:
        name = r["readable"]
        name = name if len(name) <= 70 else name[:67] + "..."
        lines.append(
            f"| {name} | {r['effective_vgprs']} | {r['vgprs']} | {r['agprs']} | "
            f"{r['total_sgprs']} | {r['scratch_size']} | {r['vgpr_spill']} | "
            f"{r['sgpr_spill']} | {r['lds_size']} | {r['occupancy']} | "
            f"{'yes' if r['dynamic_stack'] else 'no'} |"
        )
    lines += [
        "",
        "Occupancy cliff: 128 eff VGPR -> 4 waves, 129 -> 3 waves. "
        "Non-zero scratch/spill or dynamic stack means per-lane global-memory traffic.",
        "",
    ]
    Path(path).write_text("\n".join(lines))


def write_html(records, arch, target, path):
    spilled = [r for r in records if has_spill(r)]
    dynstack = [r for r in records if r["dynamic_stack"]]
    occ_hist = {}
    for r in records:
        occ_hist[r["occupancy"]] = occ_hist.get(r["occupancy"], 0) + 1
    worst = sorted(
        records,
        key=lambda r: (r["scratch_size"], r["vgpr_spill"], r["effective_vgprs"]),
        reverse=True,
    )[:15]

    parts = [
        "<h1>CK static kernel resource report</h1>",
        f"<p class='sub'>{H.esc(target or '(target)')} &middot; arch <b>{H.esc(arch)}</b> "
        f"&middot; {len(records)} kernels &middot; "
        f"<b>{len(spilled)}</b> with spills/scratch &middot; "
        f"<b>{len(dynstack)}</b> with dynamic stack</p>",
    ]

    spec = get_spec(arch)

    def sv(x, s=""):
        return f"{x}{s}" if x is not None else "n/a"

    if spec:
        rows = [
            [
                sv(spec["cu"]),
                sv(spec["wave"]),
                sv(spec["simd_per_cu"]),
                sv(spec["max_waves_cu"]),
                sv(spec["vgpr_per_simd"]),
                sv(spec["agpr_per_simd"]),
                sv(spec["lds_kb_per_cu"], " KB"),
                sv(peak_mem_gbs(arch), " GB/s"),
            ]
        ]
        parts.append(
            H.section(
                f"Device spec — {arch} ({spec['product']})",
                H.table(
                    [
                        "CUs",
                        "wave",
                        "SIMD/CU",
                        "max waves/CU",
                        "VGPR/SIMD",
                        "AGPR/SIMD",
                        "LDS/CU",
                        "peak mem BW",
                    ],
                    rows,
                    num_cols=range(8),
                ),
            )
        )

    hist = [
        (f"{occ} waves/SIMD", occ_hist[occ], str(occ_hist[occ]))
        for occ in sorted(occ_hist)
    ]
    parts.append(
        H.section(
            "Occupancy ceiling distribution (waves/SIMD)",
            f"<div class='card'>{H.bars(hist)}</div>",
        )
    )

    # Effective-VGPR bars with the CDNA 128/129 occupancy cliff marked.
    max_eff = max((r["effective_vgprs"] for r in worst), default=1)
    cdna_cliff = 128
    mx = max(max_eff, cdna_cliff + 1)
    tick = cdna_cliff / mx if arch.startswith("gfx9") else None
    vbars = [
        (r["readable"][:60], r["effective_vgprs"], str(r["effective_vgprs"]))
        for r in worst[:12]
    ]
    note = (
        " Red line = 128 eff-VGPR cliff (129 drops a wave/SIMD)."
        if tick is not None
        else ""
    )
    parts.append(
        H.section(
            "Effective VGPR per kernel (top 12)",
            f"<div class='card'>{H.bars(vbars, max_value=mx, tick_frac=tick)}</div>"
            f"<p class='sub'>{note}</p>",
        )
    )

    headers = [
        "kernel",
        "eff VGPR",
        "VGPR",
        "AGPR",
        "SGPR",
        "scratch",
        "vgpr_spill",
        "sgpr_spill",
        "LDS",
        "occ",
        "dyn-stack",
    ]
    rows, flags = [], set()
    for i, r in enumerate(worst):
        if has_spill(r) or r["dynamic_stack"]:
            flags.add(i)
        rows.append(
            [
                r["readable"][:70],
                r["effective_vgprs"],
                r["vgprs"],
                r["agprs"],
                r["total_sgprs"],
                r["scratch_size"],
                r["vgpr_spill"],
                r["sgpr_spill"],
                r["lds_size"],
                r["occupancy"],
                "yes" if r["dynamic_stack"] else "no",
            ]
        )
    parts.append(
        H.section(
            "Highest resource usage (top 15)",
            H.table(headers, rows, num_cols=range(1, 10), flag_rows=flags),
        )
    )

    parts.append(
        "<p class='foot'>Self-contained report — CSS/SVG bars, no external "
        "dependencies. Highlighted rows spill or use a dynamic stack "
        "(per-lane global-memory traffic). Companion files: same-stem .md and .csv.</p>"
    )
    Path(path).write_text(H.page(f"CK static resource report — {arch}", "".join(parts)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log_file")
    ap.add_argument("--arch", default="gfx942")
    ap.add_argument("--target", default="")
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    records = parse_log(a.log_file)
    if not records:
        print(
            "No kernel-resource-usage remarks found. Was the build compiled "
            "with -Rpass-analysis=kernel-resource-usage?"
        )
        return

    readable = demangle_names([r["kernel"] for r in records])
    for r in records:
        r["readable"] = readable.get(r["kernel"], r["kernel"])
        r["effective_vgprs"] = effective_vgprs(r, a.arch)

    stem = Path(a.out or Path(a.log_file).parent) / (Path(a.log_file).stem + "_report")
    csv_path, md_path, html_path = f"{stem}.csv", f"{stem}.md", f"{stem}.html"
    write_csv(records, a.arch, csv_path)
    write_report(records, a.arch, a.target, md_path)
    write_html(records, a.arch, a.target, html_path)

    spilled = sum(1 for r in records if has_spill(r))
    dynstack = sum(1 for r in records if r["dynamic_stack"])
    print(
        f"Parsed {len(records)} kernels  (spills/scratch: {spilled}, dynamic stack: {dynstack})"
    )
    print(f"  CSV:    {csv_path}")
    print(f"  Report: {md_path}")
    print(f"  HTML:   {html_path}")


if __name__ == "__main__":
    main()
