#!/usr/bin/env python3
"""Zero-dependency HTML report primitives shared by aggregate.py (dynamic) and
parse_resource_usage.py (static). No matplotlib / plotly / pandas: charts are
plain CSS bars and inline gauges, so the output is one self-contained .html file
that opens offline anywhere (no CDN, no internet).
"""
import html

_CSS = """
:root { --bg:#0f1115; --card:#1a1d24; --ink:#e6e8eb; --mut:#9aa3af;
        --line:#2a2f3a; --accent:#4cc2ff; --track:#2a2f3a; }
* { box-sizing:border-box; }
body { margin:0; padding:32px; background:var(--bg); color:var(--ink);
       font:14px/1.5 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif; }
.wrap { max-width:1040px; margin:0 auto; }
h1 { font-size:22px; margin:0 0 4px; }
h2 { font-size:16px; margin:28px 0 12px; padding-bottom:6px; border-bottom:1px solid var(--line); }
h3 { font-size:14px; margin:18px 0 8px; color:var(--mut); font-weight:600; }
.sub { color:var(--mut); margin:0 0 8px; }
.card { background:var(--card); border:1px solid var(--line); border-radius:10px;
        padding:16px 18px; margin:14px 0; }
table { border-collapse:collapse; width:100%; font-size:13px; }
th,td { text-align:left; padding:6px 10px; border-bottom:1px solid var(--line); }
th { color:var(--mut); font-weight:600; }
td.num,th.num { text-align:right; font-variant-numeric:tabular-nums; }
tr.flag td { background:rgba(255,107,107,0.10); }
.row { display:flex; align-items:center; gap:10px; margin:5px 0; }
.row .lbl { flex:0 0 240px; color:var(--ink); overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.row .track { flex:1; height:16px; background:var(--track); border-radius:8px; position:relative; overflow:hidden; }
.row .fill { height:100%; border-radius:8px; }
.row .val { flex:0 0 130px; text-align:right; color:var(--mut); font-variant-numeric:tabular-nums; }
.tick { position:absolute; top:0; bottom:0; width:2px; background:#ff6b6b; opacity:.8; }
.badge { display:inline-block; padding:2px 10px; border-radius:999px; font-size:12px; font-weight:600; }
.b-compute { background:#3a2a14; color:#ffb454; }
.b-memory  { background:#13263a; color:#4cc2ff; }
.b-latency { background:#2a1c3a; color:#c08cff; }
.b-mixed   { background:#143028; color:#5fd0a0; }
.b-na      { background:#26292f; color:#9aa3af; }
.grid2 { display:grid; grid-template-columns:1fr 1fr; gap:8px 22px; }
.foot { color:var(--mut); font-size:12px; margin-top:24px; }
"""


def esc(s):
    return html.escape(str(s))


def page(title, body):
    return (f"<!doctype html><html lang='en'><head><meta charset='utf-8'>"
            f"<meta name='viewport' content='width=device-width,initial-scale=1'>"
            f"<title>{esc(title)}</title><style>{_CSS}</style></head>"
            f"<body><div class='wrap'>{body}</div></body></html>\n")


def section(title, inner):
    return f"<h2>{esc(title)}</h2>{inner}"


def table(headers, rows, num_cols=(), flag_rows=()):
    """headers: list[str]; rows: list[list]; num_cols: indices right-aligned;
    flag_rows: set of row indices to highlight."""
    head = "".join(f"<th class='num'>{esc(h)}</th>" if i in num_cols
                   else f"<th>{esc(h)}</th>" for i, h in enumerate(headers))
    body = []
    for ri, r in enumerate(rows):
        cells = "".join(f"<td class='num'>{esc(c)}</td>" if i in num_cols
                        else f"<td>{esc(c)}</td>" for i, c in enumerate(r))
        cls = " class='flag'" if ri in flag_rows else ""
        body.append(f"<tr{cls}>{cells}</tr>")
    return f"<table><thead><tr>{head}</tr></thead><tbody>{''.join(body)}</tbody></table>"


def _fill_color(frac):
    # frac in 0..1 — light teal for low, brighter for high (intensity only, no good/bad).
    if frac >= 0.60:
        return "#4cc2ff"
    if frac >= 0.25:
        return "#3a8fbf"
    return "#33566b"


def bars(items, max_value=None, tick_frac=None):
    """items: list of (label, value, display_str). Bar width is value/max_value.
    tick_frac: optional 0..1 position for a red marker line (e.g. occupancy cliff)."""
    mx = max_value if max_value else max((v for _, v, _ in items), default=1) or 1
    out = []
    for label, value, disp in items:
        frac = max(0.0, min(value / mx, 1.0)) if mx else 0.0
        tick = (f"<span class='tick' style='left:{tick_frac*100:.1f}%'></span>"
                if tick_frac is not None else "")
        out.append(
            f"<div class='row'><div class='lbl' title='{esc(label)}'>{esc(label)}</div>"
            f"<div class='track'>{tick}<div class='fill' style='width:{frac*100:.1f}%;"
            f"background:{_fill_color(frac)}'></div></div>"
            f"<div class='val'>{esc(disp)}</div></div>")
    return "".join(out)


def gauges(items):
    """items: list of (label, pct). Each renders as a 0..100% bar."""
    norm = [(label, (0.0 if pct != pct else pct)) for label, pct in items]  # NaN -> 0
    return bars([(label, p, f"{p:.1f} %") for label, p in norm], max_value=100.0)


def badge(verdict):
    v = verdict.lower()
    cls = ("b-compute" if "compute" in v else "b-memory" if "bandwidth" in v or "memory" in v
           else "b-latency" if "latency" in v or "occupancy" in v
           else "b-na" if "n/a" in v else "b-mixed")
    return f"<span class='badge {cls}'>{esc(verdict)}</span>"
