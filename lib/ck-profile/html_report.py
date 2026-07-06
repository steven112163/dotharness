#!/usr/bin/env python3
"""Zero-dependency HTML report primitives shared by aggregate.py (dynamic) and
parse_resource_usage.py (static). No matplotlib / plotly / pandas: charts are
plain CSS bars and inline gauges, so the output is one self-contained .html file
that opens offline anywhere (no CDN, no internet).
"""

import html

from ck_profile_utils import COMPUTE_BOUND_PCT, LATENCY_BOUND_PCT

_CSS = """
:root {
  --bg:#0a0c10; --card:#12151d; --card2:#161b25;
  --ink:#e9eef4; --mut:#828d9e; --faint:#5b6473;
  --line:#1d2330; --line2:#283042; --track:#161b24;
  --accent:#5ad1ff; --accent-dim:#2c6f8c; --accent-ink:#bfecff;
  --amber:#ffb454; --violet:#c08cff; --green:#5fd0a0; --red:#ff6b6b;
  --radius:12px;
  --mono:ui-monospace,"JetBrains Mono","Cascadia Code","SF Mono","Fira Code",Menlo,Consolas,"Liberation Mono",monospace;
  --sans:ui-sans-serif,system-ui,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
}
* { box-sizing:border-box; }
html { color-scheme:dark; }
body {
  margin:0; padding:48px 28px; color:var(--ink);
  font:14px/1.55 var(--sans);
  background:
    radial-gradient(1100px 560px at 82% -8%, rgba(90,209,255,.10), transparent 58%),
    radial-gradient(820px 480px at -8% 112%, rgba(192,140,255,.07), transparent 60%),
    var(--bg);
  -webkit-font-smoothing:antialiased;
}
/* scanline grid only — cheap to paint, no SVG turbulence (kept first paint fast
   and reliable in embedded webviews like the Cursor "Live Preview" iframe). */
body::before {
  content:""; position:fixed; inset:0; pointer-events:none; z-index:0; opacity:.5;
  background-image:
    linear-gradient(transparent 95%, rgba(255,255,255,.020) 0),
    linear-gradient(90deg, transparent 95%, rgba(255,255,255,.020) 0);
  background-size:38px 38px,38px 38px;
}
.wrap { position:relative; z-index:1; max-width:1120px; margin:0 auto; }

/* masthead */
h1 {
  font:600 26px/1.15 var(--mono); letter-spacing:-.5px; margin:0 0 8px;
  display:flex; align-items:center; gap:14px;
}
h1::before {
  content:""; flex:0 0 auto; width:11px; height:11px; border-radius:50%;
  background:var(--accent);
  box-shadow:0 0 0 4px rgba(90,209,255,.14), 0 0 14px 2px var(--accent);
}
.sub { font:13px/1.5 var(--mono); color:var(--mut); margin:0 0 6px; letter-spacing:.2px; }
.sub b { color:var(--accent-ink); font-weight:600; }
.wrap > p.sub:first-of-type {
  position:relative; padding-bottom:22px; margin-bottom:6px;
  border-bottom:1px solid var(--line2);
}
.wrap > p.sub:first-of-type::after {
  content:""; position:absolute; left:0; bottom:-1px; width:180px; height:2px;
  background:linear-gradient(90deg, var(--accent), transparent);
}

/* section headers — instrument labels */
h2 {
  font:600 12px/1 var(--mono); text-transform:uppercase; letter-spacing:2.4px;
  color:var(--mut); margin:34px 0 14px; padding:0 0 10px;
  display:flex; align-items:center; gap:11px; border-bottom:1px solid var(--line);
}
h2::before {
  content:""; width:7px; height:7px; background:var(--accent);
  box-shadow:0 0 8px var(--accent); transform:rotate(45deg);
}
h3 { font:600 13px/1.3 var(--mono); margin:0; color:var(--ink); letter-spacing:.2px; }

/* cards */
.card {
  background:linear-gradient(180deg, var(--card2), var(--card));
  border:1px solid var(--line2); border-radius:var(--radius);
  padding:18px 20px; margin:14px 0;
  box-shadow:inset 0 1px 0 rgba(255,255,255,.04), 0 12px 30px -20px rgba(0,0,0,.85);
  animation:rise .5s cubic-bezier(.2,.7,.2,1) both;
}
.card:hover { border-color:#33405a; }

/* tables */
.tablewrap {
  overflow-x:auto; border:1px solid var(--line2); border-radius:var(--radius);
  box-shadow:inset 0 1px 0 rgba(255,255,255,.04); margin:14px 0;
  animation:rise .5s cubic-bezier(.2,.7,.2,1) both;
}
table { border-collapse:collapse; width:100%; font:13px/1.45 var(--mono); }
thead th {
  position:sticky; top:0; background:#10141c; color:var(--mut); font-weight:600;
  text-transform:uppercase; letter-spacing:1px; font-size:11px;
  text-align:left; padding:10px 12px; border-bottom:1px solid var(--line2); white-space:nowrap;
}
tbody td { padding:8px 12px; border-bottom:1px solid var(--line); }
tbody tr:last-child td { border-bottom:0; }
tbody tr:hover td { background:rgba(90,209,255,.05); }
td.num,th.num { text-align:right; font-variant-numeric:tabular-nums; }
tr.flag td { background:rgba(255,107,107,.09); }
tr.flag td:first-child { box-shadow:inset 3px 0 0 var(--red); }

/* data bars */
.row { display:flex; align-items:center; gap:12px; margin:7px 0; }
.row .lbl {
  flex:0 0 248px; color:var(--ink); font:12px/1.4 var(--mono);
  overflow:hidden; text-overflow:ellipsis; white-space:nowrap;
}
.row .track {
  flex:1; height:18px; background:var(--track); border-radius:7px;
  position:relative; overflow:hidden;
  box-shadow:inset 0 0 0 1px var(--line2), inset 0 1px 3px rgba(0,0,0,.5);
}
.row .fill {
  height:100%; border-radius:7px;
  background:var(--c,#5ad1ff);
  background:linear-gradient(90deg, color-mix(in srgb, var(--c,#5ad1ff) 35%, transparent), var(--c,#5ad1ff));
  box-shadow:0 0 12px -2px var(--c,#5ad1ff);
}
.row .val {
  flex:0 0 140px; text-align:right; color:var(--mut);
  font:12px/1.4 var(--mono); font-variant-numeric:tabular-nums;
}
.tick {
  position:absolute; top:-2px; bottom:-2px; width:2px; background:var(--red);
  box-shadow:0 0 8px var(--red); opacity:.85; z-index:2;
}

/* verdict pills — status LEDs */
.badge {
  display:inline-flex; align-items:center; gap:7px; padding:3px 11px 3px 9px;
  border-radius:999px; font:600 11px/1 var(--mono);
  text-transform:uppercase; letter-spacing:.6px; border:1px solid currentColor;
}
.badge::before {
  content:""; width:6px; height:6px; border-radius:50%;
  background:currentColor; box-shadow:0 0 7px currentColor;
}
.b-compute { color:var(--amber);  background:rgba(255,180,84,.10); }
.b-memory  { color:var(--accent); background:rgba(90,209,255,.10); }
.b-latency { color:var(--violet); background:rgba(192,140,255,.10); }
.b-mixed   { color:var(--green);  background:rgba(95,208,160,.10); }
.b-na      { color:var(--mut);    background:rgba(154,163,175,.08); }

.grid2 {
  display:grid; grid-template-columns:1fr 1fr; gap:9px 24px; margin-top:12px;
  font:12.5px/1.5 var(--mono); color:var(--mut);
}
.grid2 b { color:var(--ink); font-weight:600; }

.foot {
  color:var(--faint); font:11px/1.6 var(--mono); margin-top:30px;
  padding-top:14px; border-top:1px solid var(--line);
  display:flex; align-items:center; gap:8px;
}
.foot::before { content:""; width:6px; height:6px; border-radius:50%; background:var(--accent-dim); }

/* Transform-only entrance: even if a webview throttles/pauses the animation
   before the iframe is "visible", the element stays fully opaque and readable
   (just briefly offset), so content never gets stuck invisible. */
@keyframes rise { from { transform:translateY(10px); } to { transform:none; } }
@media (prefers-reduced-motion:reduce) { * { animation:none !important; } }
"""


def esc(s):
    return html.escape(str(s))


def page(title, body):
    return (
        f"<!doctype html><html lang='en'><head><meta charset='utf-8'>"
        f"<meta name='viewport' content='width=device-width,initial-scale=1'>"
        f"<meta name='color-scheme' content='dark'>"
        f"<title>{esc(title)}</title><style>{_CSS}</style></head>"
        f"<body><div class='wrap'>{body}</div></body></html>\n"
    )


def section(title, inner):
    return f"<h2>{esc(title)}</h2>{inner}"


def table(headers, rows, num_cols=(), flag_rows=()):
    """headers: list[str]; rows: list[list]; num_cols: indices right-aligned;
    flag_rows: set of row indices to highlight."""
    head = "".join(
        f"<th class='num'>{esc(h)}</th>" if i in num_cols else f"<th>{esc(h)}</th>"
        for i, h in enumerate(headers)
    )
    body = []
    for ri, r in enumerate(rows):
        cells = "".join(
            f"<td class='num'>{esc(c)}</td>" if i in num_cols else f"<td>{esc(c)}</td>"
            for i, c in enumerate(r)
        )
        cls = " class='flag'" if ri in flag_rows else ""
        body.append(f"<tr{cls}>{cells}</tr>")
    return (
        f"<div class='tablewrap'><table><thead><tr>{head}</tr></thead>"
        f"<tbody>{''.join(body)}</tbody></table></div>"
    )


def _fill_color(frac):
    # frac in 0..1 — light teal for low, brighter for high (intensity only, no good/bad).
    # Thresholds mirror ck_profile_utils' bound-verdict percentages.
    if frac >= COMPUTE_BOUND_PCT / 100:
        return "#4cc2ff"
    if frac >= LATENCY_BOUND_PCT / 100:
        return "#3a8fbf"
    return "#33566b"


def bars(items, max_value=None, tick_frac=None):
    """items: list of (label, value, display_str). Bar width is value/max_value.
    tick_frac: optional 0..1 position for a red marker line (e.g. occupancy cliff)."""
    mx = max_value if max_value else max((v for _, v, _ in items), default=1) or 1
    out = []
    for label, value, disp in items:
        frac = max(0.0, min(value / mx, 1.0)) if mx else 0.0
        tick = (
            f"<span class='tick' style='left:{tick_frac * 100:.1f}%'></span>"
            if tick_frac is not None
            else ""
        )
        out.append(
            f"<div class='row'><div class='lbl' title='{esc(label)}'>{esc(label)}</div>"
            f"<div class='track'>{tick}<div class='fill' style='width:{frac * 100:.1f}%;"
            f"--c:{_fill_color(frac)}'></div></div>"
            f"<div class='val'>{esc(disp)}</div></div>"
        )
    return "".join(out)


def gauges(items):
    """items: list of (label, pct). Each renders as a 0..100% bar."""
    norm = [(label, (0.0 if pct != pct else pct)) for label, pct in items]  # NaN -> 0
    return bars([(label, p, f"{p:.1f} %") for label, p in norm], max_value=100.0)


def badge(verdict):
    v = verdict.lower()
    cls = (
        "b-compute"
        if "compute" in v
        else "b-memory"
        if "bandwidth" in v or "memory" in v
        else "b-latency"
        if "latency" in v or "occupancy" in v
        else "b-na"
        if "n/a" in v
        else "b-mixed"
    )
    return f"<span class='badge {cls}'>{esc(verdict)}</span>"
