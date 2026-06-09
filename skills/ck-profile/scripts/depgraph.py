#!/usr/bin/env python3
"""Dependency graphs for the SSD forward pipeline, emitted as Graphviz DOT.

Two views (`--mode data|runtime|both`):

* data    — the logical data-dependency DAG: which workspace buffer each kernel
            reads/writes, wired producer -> consumer with program-order
            last-writer resolution (so the reused `pa`/`pb` scratch buffers link
            each pack to the GEMM that immediately consumes it). Encoded from
            example/ck_tile/53_ssd/ssd_fwd.hpp.
* runtime — the as-executed graph from a rocprofv3 kernel trace: kernels ordered
            by dispatch time, transitions aggregated (the recurring pipeline
            shows up as a cycle), nodes annotated with call count and time.

DOT only — preview .dot in VS Code's Graphviz extension.

    depgraph.py --mode both --raw ck_profile_out/dynamic/raw --out ck_profile_out/depgraph
"""

import argparse
import csv
import glob
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aggregate import short  # short kernel label, shared with the dynamic report

# SSD forward pipeline as launched in ssd_fwd.hpp (step order preserved).
# Each stage: (id, label, reads, writes). Names p_* are external tensors;
# everything else is a workspace buffer. Scratch buffers pa/pb are reused, so
# last-writer-wins over program order gives the correct producer for each read.
SSD_PIPELINE = [
    ("cumsum", "ssd_cumsum", ["p_da"], ["cum"]),
    ("packC1", "pack_Cmat (IntraBMM1)", ["p_cm"], ["pa"]),
    ("packB1", "pack_Bmat (IntraBMM1)", ["p_bm"], ["pb"]),
    ("gemm_intra1", "GEMM IntraBMM1", ["pa", "pb"], ["ibmm1"]),
    ("segsum", "ssd_segsum_pre_intra2", ["cum", "p_dlt", "ibmm1"], ["pi2"]),
    ("packX1", "pack_X (IntraBMM2)", ["p_x"], ["pa"]),
    ("gemm_intra2", "GEMM IntraBMM2", ["pi2", "pa"], ["abmm2"]),
    ("pre_inter1", "ssd_pre_inter1", ["cum", "p_dlt", "p_bm"], ["pi1", "ce", "lv"]),
    ("packX2", "pack_X (InterBMM1)", ["p_x"], ["pa"]),
    ("gemm_inter1", "GEMM InterBMM1", ["pi1", "pa"], ["rbmm1"]),
    ("state_prop", "ssd_state_propagation", ["rbmm1", "lv"], ["st"]),
    ("packC2", "pack_Cmat (InterBMM2)", ["p_cm"], ["pa"]),
    ("packState", "pack_state (InterBMM2)", ["st"], ["pb"]),
    ("gemm_inter2", "GEMM InterBMM2", ["pa", "pb"], ["rbmm2"]),
    (
        "epilogue",
        "ssd_epilogue",
        ["rbmm2", "abmm2", "ce", "p_x", "p_dp", "p_z"],
        ["p_y"],
    ),
    ("final_state", "ssd_final_state", ["rbmm1", "st", "lv"], ["p_fs"]),
]

INPUT_TENSORS = {
    "p_x": "X",
    "p_da": "DeltaA",
    "p_dlt": "Delta",
    "p_bm": "B_mat",
    "p_cm": "C_mat",
    "p_dp": "D_param",
    "p_z": "Z",
}
OUTPUT_TENSORS = {"p_y": "Y", "p_fs": "Fstate"}

_HEAD = [
    "digraph {0} {{",
    "  rankdir=TB;",
    '  graph [bgcolor="#0a0c10", fontname="monospace", fontcolor="#9aa3af"];',
    '  node [shape=box, style="filled,rounded", fillcolor="#12151d", color="#283042",'
    ' fontname="monospace", fontsize=10, fontcolor="#e9eef4"];',
    '  edge [color="#5ad1ff", fontname="monospace", fontsize=9, fontcolor="#828d9e"];',
]


def emit_data(out):
    lines = [s.format('"ssd_data_dependency"') for s in _HEAD]
    lines.append(
        '  labelloc="t"; fontsize=13; label="SSD forward — data-dependency DAG";'
    )
    for t, lbl in INPUT_TENSORS.items():
        lines.append(
            f'  "{t}" [shape=ellipse, fillcolor="#13263a", color="#2c6f8c", label="{lbl}"];'
        )
    for t, lbl in OUTPUT_TENSORS.items():
        lines.append(
            f'  "{t}" [shape=ellipse, fillcolor="#143028", color="#2f6b4f", label="{lbl}"];'
        )
    for sid, label, _r, _w in SSD_PIPELINE:
        lines.append(f'  "{sid}" [label="{label}"];')
    last_writer = {}
    for sid, _label, reads, writes in SSD_PIPELINE:
        for b in reads:
            if b in last_writer:
                lines.append(f'  "{last_writer[b]}" -> "{sid}" [label="{b}"];')
            elif b in INPUT_TENSORS:
                lines.append(f'  "{b}" -> "{sid}";')
        for b in writes:
            if b in OUTPUT_TENSORS:
                lines.append(f'  "{sid}" -> "{b}";')
            last_writer[b] = sid
    lines.append("}")
    path = os.path.join(out, "data_dependency.dot")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return path


def find_trace_csv(raw, explicit):
    if explicit:
        return explicit if os.path.exists(explicit) else None
    if not raw:
        return None
    hits = sorted(
        glob.glob(os.path.join(raw, "**", "*kernel_trace.csv"), recursive=True)
    )
    return hits[0] if hits else None


def emit_runtime(csv_path, out):
    with open(csv_path) as f:
        rows = list(csv.DictReader(f))
    rows = [r for r in rows if r.get("Start_Timestamp")]
    rows.sort(key=lambda r: int(r["Start_Timestamp"]))
    seq, node = [], {}
    for r in rows:
        name = short(r["Kernel_Name"])
        dur = (int(r["End_Timestamp"]) - int(r["Start_Timestamp"])) / 1e3  # us
        e = node.setdefault(name, {"calls": 0, "us": 0.0})
        e["calls"] += 1
        e["us"] += dur
        seq.append(name)
    trans = {}
    for a, b in zip(seq, seq[1:]):
        trans[(a, b)] = trans.get((a, b), 0) + 1

    def nid(n):
        return '"' + n.replace('"', "'") + '"'

    lines = [s.format('"ssd_runtime_trace"') for s in _HEAD]
    lines.append(
        '  labelloc="t"; fontsize=13; label="SSD forward — runtime dispatch graph '
        f'({len(rows)} dispatches, transitions aggregated)";'
    )
    for n, e in node.items():
        avg = e["us"] / e["calls"] if e["calls"] else 0.0
        lines.append(
            f'  {nid(n)} [label="{n}\\l{e["calls"]}x  ·  {e["us"]:.1f} us tot  ·  {avg:.1f} us avg\\l"];'
        )
    for (a, b), w in sorted(trans.items(), key=lambda x: -x[1]):
        lbl = f' [label="x{w}"]' if w > 1 else ""
        lines.append(f"  {nid(a)} -> {nid(b)}{lbl};")
    lines.append("}")
    path = os.path.join(out, "runtime_trace.dot")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return path, len(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["data", "runtime", "both"], default="both")
    ap.add_argument(
        "--raw", default="", help="dir to search for t_kernel_trace.csv (runtime)"
    )
    ap.add_argument(
        "--trace-csv", default="", help="explicit rocprofv3 kernel-trace CSV (runtime)"
    )
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    dotdir = os.path.join(a.out, "dot")
    os.makedirs(dotdir, exist_ok=True)

    have_data = have_runtime = False
    wrote = []
    if a.mode in ("data", "both"):
        wrote.append(emit_data(dotdir))
        have_data = True
    if a.mode in ("runtime", "both"):
        csv_path = find_trace_csv(a.raw, a.trace_csv)
        if not csv_path:
            msg = (
                "no rocprofv3 kernel-trace CSV found (need *kernel_trace.csv from "
                "trace/dynamic mode); pass --trace-csv or --raw"
            )
            if a.mode == "runtime":
                print("ERROR:", msg, file=sys.stderr)
                sys.exit(2)
            print("runtime graph skipped:", msg, file=sys.stderr)
        else:
            path, ndisp = emit_runtime(csv_path, dotdir)
            wrote.append(f"{path}  (from {ndisp} dispatches in {csv_path})")
            have_runtime = True

    md = ["# depgraph mode — kernel dependency graphs", "", "## How to read", ""]
    if have_data:
        md += [
            "- **`dot/data_dependency.dot`** — the *logical* DAG. Ellipses are "
            "input/output tensors, boxes are kernels, each edge is labelled with the "
            "workspace buffer that connects a producer to its consumer (resolved by "
            "program order, so the reused `pa`/`pb` scratch links each pack to the GEMM "
            "that consumes it). Read top-to-bottom = the algorithm's data flow; this is "
            "what *must* be serialized for correctness."
        ]
    if have_runtime:
        md += [
            "- **`dot/runtime_trace.dot`** — the *as-executed* graph from the kernel "
            "trace. Boxes are kernels (with call count and total/avg µs); edges are "
            "consecutive dispatches with `xN` = how often that transition occurred, so "
            "the repeating pipeline appears as a cycle. Read it to see real ordering and "
            "which kernel dominates wall time."
        ]
    md += [
        "- Preview `.dot` in VS Code's Graphviz extension, or `dot -Tsvg`.",
        "- Compare the two: edges in the runtime graph that are **not** forced by the "
        "data DAG are pure serialization overhead — candidates for fusion or overlap.",
        "",
    ]
    with open(os.path.join(a.out, "index.md"), "w") as f:
        f.write("\n".join(md) + "\n")
    try:
        here = os.path.dirname(os.path.abspath(__file__))
        parent = os.path.dirname(os.path.abspath(a.out.rstrip("/"))) or "."
        shutil.copy(
            os.path.join(here, "profile_readme.md"), os.path.join(parent, "README.md")
        )
        # ignore the output dir via .git/info/exclude (not the tracked .gitignore)
        subprocess.run(
            ["bash", os.path.join(here, "git_exclude_outdir.sh"), parent],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        pass
    for w in wrote:
        print("wrote", w)
    print("wrote", os.path.join(a.out, "index.md"))


if __name__ == "__main__":
    main()
