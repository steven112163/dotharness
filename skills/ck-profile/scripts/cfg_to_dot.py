#!/usr/bin/env python3
"""Build per-kernel ISA control-flow graphs (DOT) from GCN disassembly.

Reads `llvm-objdump -d` output of an extracted amdgcn code object on stdin and
writes one Graphviz `.dot` per device kernel plus an `index.md`. DOT only — no
graphviz/SVG (the user previews .dot in VS Code's Graphviz extension).

llvm-objdump emits, per instruction:
    <tab>MNEMONIC operands     // <hexaddr>: <encoding> [<symbol+0xoff>]
The trailing `<symbol+0xoff>` on branch instructions already resolves the target,
so basic blocks are built from those resolved addresses without decoding offsets.

    cfg_to_dot.py --out DIR [--arch gfx942] < disasm.txt
"""

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_resource_usage import (
    demangle_names,
)  # one c++filt batch, identity on failure

HEADER = re.compile(r"^([0-9a-fA-F]+)\s+<(.+)>:\s*$")
# instruction line: "<ws>MNEMONIC ops   // <addr>: <enc> [<sym+0xoff>]"
INSN = re.compile(
    r"^\s+(\S+)\s*(.*?)\s*//\s*([0-9a-fA-F]+):\s*[0-9a-fA-F ]+(?:<([^>]+)>)?\s*$"
)
TARGET = re.compile(r"^(.*)\+0x([0-9a-fA-F]+)$")


def is_cond(m):
    return m.startswith("s_cbranch")


def is_uncond(m):
    return m == "s_branch"


def is_term(m):
    # ends a path with no static successor
    return m in ("s_endpgm",) or m.startswith("s_setpc")


def parse(stream):
    """Return {kernel_name: {"base": int, "insns": [(addr, mnem, target_or_None)]}}."""
    kernels, cur, bases = {}, None, {}
    for line in stream:
        h = HEADER.match(line)
        if h:
            base = int(h.group(1), 16)
            name = h.group(2)
            bases[name] = base
            cur = {"base": base, "insns": []}
            kernels[name] = cur
            continue
        if cur is None:
            continue
        m = INSN.match(line)
        if not m:
            continue
        mnem, _ops, addr_hex, symoff = m.group(1), m.group(2), m.group(3), m.group(4)
        addr = int(addr_hex, 16)
        target = None
        if (is_cond(mnem) or is_uncond(mnem)) and symoff:
            t = TARGET.match(symoff)
            if t:
                sym, off = t.group(1), int(t.group(2), 16)
                target = bases.get(sym, cur["base"]) + off
        cur["insns"].append((addr, mnem, target))
    return kernels


def build_blocks(insns):
    """Split a kernel's instruction list into basic blocks; return (blocks, edges).
    blocks: {start_addr: [(addr,mnem,target)]}; edges: list of (src_start, dst_start, kind)."""
    if not insns:
        return {}, []
    # Drop trailing inter-kernel alignment padding (s_nop / s_code_end) that the
    # disassembler lists after the kernel's final s_endpgm.
    last_end = max(
        (i for i, (_, m, _) in enumerate(insns) if m == "s_endpgm"), default=None
    )
    if last_end is not None:
        insns = insns[: last_end + 1]
    addrs = [a for a, _, _ in insns]
    addr_set = set(addrs)
    leaders = {insns[0][0]}
    for i, (addr, mnem, target) in enumerate(insns):
        if is_cond(mnem) or is_uncond(mnem) or is_term(mnem):
            if i + 1 < len(insns):
                leaders.add(insns[i + 1][0])  # fall-through point starts a block
            if target is not None and target in addr_set:
                leaders.add(target)  # branch target starts a block
    leaders = sorted(leaders)
    # map each instruction index to its block start
    blocks, cur_start = {}, None
    for addr, mnem, target in insns:
        if addr in leaders:
            cur_start = addr
            blocks[cur_start] = []
        blocks[cur_start].append((addr, mnem, target))
    edges = []
    for start, blk in blocks.items():
        last_addr, last_mnem, last_target = blk[-1]
        # index of last instruction to find the textual successor
        nxt = None
        idx = addrs.index(last_addr)
        if idx + 1 < len(addrs):
            nxt = addrs[idx + 1]
        if is_uncond(last_mnem):
            if last_target is not None:
                edges.append((start, last_target, "jmp"))
        elif is_cond(last_mnem):
            if last_target is not None:
                edges.append((start, last_target, "taken"))
            if nxt is not None:
                edges.append((start, nxt, "fall"))
        elif is_term(last_mnem):
            pass  # terminal
        else:
            if nxt is not None and nxt in blocks:
                edges.append((start, nxt, "fall"))
    return blocks, edges


def slug(demangled, used):
    s = demangled.split("(")[0]
    s = s.split("<")[0]
    s = s.split("::")[-1].strip() or "kernel"
    s = re.sub(r"[^0-9A-Za-z_]+", "_", s)
    base, n = s, 1
    while s in used:
        n += 1
        s = f"{base}_{n}"
    used.add(s)
    return s


def emit_dot(name, short, blocks, edges):
    lines = [
        f'digraph "{short}" {{',
        "  rankdir=TB;",
        '  graph [bgcolor="#0a0c10", fontname="monospace", fontcolor="#9aa3af"];',
        '  node [shape=box, style="filled,rounded", fillcolor="#12151d", '
        'color="#283042", fontname="monospace", fontsize=10, fontcolor="#e9eef4"];',
        '  edge [color="#5ad1ff", fontname="monospace", fontsize=9, fontcolor="#828d9e"];',
        f'  labelloc="t"; fontsize=12; label="{short}\\n{name}";',
    ]
    for start, blk in blocks.items():
        term = blk[-1][1]
        end = blk[-1][0]
        label = f"0x{start:x} – 0x{end:x}\\l{len(blk)} insn  ·  {term}\\l"
        lines.append(f'  "0x{start:x}" [label="{label}"];')
    style = {
        "taken": ' [label="T",color="#5fd0a0"]',
        "fall": ' [label="·",color="#5b6473"]',
        "jmp": ' [color="#c08cff"]',
    }
    for src, dst, kind in edges:
        lines.append(f'  "0x{src:x}" -> "0x{dst:x}"{style.get(kind, "")};')
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--arch", default="")
    a = ap.parse_args()
    dotdir = os.path.join(a.out, "dot")
    os.makedirs(dotdir, exist_ok=True)

    kernels = parse(sys.stdin)
    if not kernels:
        print(
            "No kernels parsed from disassembly (empty or unexpected format).",
            file=sys.stderr,
        )
        sys.exit(1)

    readable = demangle_names(list(kernels))
    used, rows = set(), []
    for name, k in kernels.items():
        blocks, edges = build_blocks(k["insns"])
        if not blocks:
            continue
        dem = readable.get(name, name)
        short = slug(dem, used)
        with open(os.path.join(dotdir, f"{short}.dot"), "w") as f:
            f.write(emit_dot(dem, short, blocks, edges))
        ninsn = sum(len(b) for b in blocks.values())
        rows.append((short, len(blocks), len(edges), ninsn, dem))

    rows.sort(key=lambda r: -r[3])
    md = [
        f"# cfg mode — ISA control-flow graphs ({a.arch or 'amdgcn'})",
        "",
        "## How to read",
        "",
        "- One `dot/<kernel>.dot` per device kernel. Preview in VS Code's Graphviz "
        "extension (open the `.dot`, right-click → Open Preview), or render with "
        "`dot -Tsvg dot/x.dot -o x.svg` where graphviz is installed.",
        "- **Nodes** are basic blocks labelled `start–end addr / N instructions / "
        "terminator`. **Edges**: green = branch taken, grey = fall-through, "
        "violet = unconditional jump. A back-edge to an earlier block is a loop.",
        "- **What to look for:** loop nests (hot inner loops), highly-branchy kernels "
        "(many small blocks = divergence risk), and the longest straight-line block "
        "(scheduling unit). Cross-reference block counts with the static report's "
        "VGPR/occupancy for the same kernel.",
        "- Rows below are sorted by instruction count (largest kernels first).",
        "",
        "| file | blocks | edges | insns | kernel |",
        "| --- | --- | --- | --- | --- |",
    ]
    for short, nb, ne, ni, dem in rows:
        d = dem if len(dem) <= 80 else dem[:77] + "..."
        md.append(f"| dot/{short}.dot | {nb} | {ne} | {ni} | {d} |")
    with open(os.path.join(a.out, "index.md"), "w") as f:
        f.write("\n".join(md) + "\n")
    print(f"wrote {len(rows)} CFG .dot files + index.md to {a.out}")


if __name__ == "__main__":
    main()
