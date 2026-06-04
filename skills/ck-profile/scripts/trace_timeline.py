#!/usr/bin/env python3
"""Standalone HTML timeline from rocprofv3 --sys-trace CSVs.

Renders the host (HIP API) and device (kernel dispatch) lanes on a shared time
axis as one offline-standalone .html (no CDN, no JS libs) that opens in Cursor's
Live Preview — the in-editor alternative to dragging the .pftrace into perfetto.
It is NOT a perfetto clone: no flows, counter tracks, SQL, or CPU-scheduling —
just "what ran when, where the gaps are, who dominates wall time, and whether
host launches overlap device work", which is most of what you inspect here.

Reads, per run dir (prefix from rocprofv3 -o, default "trace"):
  <p>_kernel_trace.csv   device lane (Start/End ns, Kernel_Name, Queue_Id)
  <p>_hip_api_trace.csv  host lane   (Function, Start/End ns) — runtime calls only
  <p>_memory_copy_trace.csv  copy lane (Direction, Start/End ns), if present

Kernel_Name carries template commas, so this uses csv.DictReader (never cut -d,).

    trace_timeline.py --run-dir <dir> [--prefix trace] --out <dir>/timeline.html
"""
import argparse
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aggregate import short              # shared short kernel label
from html_report import page, section, esc, bars

PALETTE = ["#5ad1ff", "#ffb454", "#c08cff", "#5fd0a0", "#ff6b6b", "#4cc2ff",
           "#f78fb3", "#9ad34b", "#ffd166", "#8ac6ff", "#b388ff", "#ff9f6b"]
GUT = 74  # px reserved at left for the (non-scrolling) sticky lane label

# Host calls worth showing: the runtime loop (launches, sync bubbles, mem ops),
# not the one-time setup/getters (__hipRegister*, push/pop config, getDevice...).
_HOST_KEEP = ("launch", "memcpy", "memset", "synchron", "event")


def _keep_host(fn):
    l = fn.lower()
    return any(k in l for k in _HOST_KEEP)


def _read(path):
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return list(csv.DictReader(f))


def load_events(run_dir, prefix):
    kt = _read(os.path.join(run_dir, f"{prefix}_kernel_trace.csv"))
    if not kt:
        return None
    kern = [(short(r["Kernel_Name"]), r["Kernel_Name"],
             int(r["Start_Timestamp"]), int(r["End_Timestamp"]))
            for r in kt if r.get("Start_Timestamp")]
    if not kern:
        return None
    g0 = min(e[2] for e in kern)
    g1 = max(e[3] for e in kern)

    def windowed(rows, name_key):
        out = []
        for r in rows:
            if not r.get("Start_Timestamp"):
                continue
            t0, t1 = int(r["Start_Timestamp"]), int(r["End_Timestamp"])
            if t1 < g0 or t0 > g1:           # keep only what overlaps the kernel window
                continue
            out.append((r[name_key], r[name_key], t0, t1))
        return out

    host = [r for r in _read(os.path.join(run_dir, f"{prefix}_hip_api_trace.csv"))
            if _keep_host(r.get("Function", ""))]
    host = windowed(host, "Function")
    copies = _read(os.path.join(run_dir, f"{prefix}_memory_copy_trace.csv"))
    for r in copies:
        r["_lbl"] = r.get("Direction", "COPY").replace("MEMORY_COPY_", "").replace("_", "")
    copy = windowed(copies, "_lbl") if copies else []
    return {"g0": g0, "g1": g1, "kern": kern, "host": host, "copy": copy}


def _host_color(fn):
    l = fn.lower()
    if "synchron" in l:
        return "#c08cff"
    if "memcpy" in l or "memset" in l:
        return "#ffb454"
    if "event" in l:
        return "#5fd0a0"
    return "#2c6f8c"                          # launches: muted accent


def _ev_div(t0us, durus, color, cap, tip, base):
    left = GUT + t0us * base
    w = max(1.5, durus * base)
    return (f"<div class='ev' data-t0='{t0us:.4f}' data-du='{durus:.4f}' "
            f"data-tip='{esc(tip)}' style='left:{left:.2f}px;width:{w:.2f}px;--c:{color}'>"
            f"<span class='cap'>{esc(cap)}</span></div>")


def build_lane(name, events, g0, base, color_of):
    rows = []
    for cap, full, t0, t1 in events:
        t0us, durus = (t0 - g0) / 1e3, (t1 - t0) / 1e3
        startus = (t0 - g0) / 1e3
        tip = f"{full}\n{name} · start {startus:.3f} µs · dur {durus:.3f} µs"
        rows.append(_ev_div(t0us, durus, color_of(cap, full), cap, tip, base))
    return (f"<div class='tl-lane'><span class='lane-lbl'>{esc(name)}</span>"
            f"{''.join(rows)}</div>")


_JS = """
(function(){
  var canvas=document.getElementById('tlcanvas'); if(!canvas) return;
  var scroll=document.getElementById('tlscroll'), axis=document.getElementById('tlaxis');
  var tip=document.getElementById('tltip');
  var lanes=canvas.querySelectorAll('.tl-lane'), evs=canvas.querySelectorAll('.ev');
  var GUT=parseFloat(canvas.dataset.gut), total=parseFloat(canvas.dataset.total)||1;
  var base=parseFloat(canvas.dataset.base)||1, pxus=base;
  function layout(){
    var w=GUT+Math.max(total*pxus,1);
    canvas.style.width=w+'px'; axis.style.width=w+'px';
    lanes.forEach(function(l){l.style.width=w+'px';});
    evs.forEach(function(e){
      e.style.left=(GUT+parseFloat(e.dataset.t0)*pxus)+'px';
      e.style.width=Math.max(1.5,parseFloat(e.dataset.du)*pxus)+'px';
    });
    drawAxis();
  }
  function drawAxis(){
    axis.innerHTML='';
    var target=110/pxus, p=Math.pow(10,Math.floor(Math.log10(target))), step=p;
    [1,2,5,10].forEach(function(s){ if(step<target) step=s*p; });
    for(var t=0;t<=total+step/2;t+=step){
      var d=document.createElement('div'); d.className='tk'; d.style.left=(GUT+t*pxus)+'px';
      var s=document.createElement('span'); s.className='tlab';
      s.textContent=(step<1?t.toFixed(2):step<10?t.toFixed(1):t.toFixed(0))+' µs';
      d.appendChild(s); axis.appendChild(d);
    }
  }
  function zoom(f){ pxus=Math.min(Math.max(pxus*f,base*0.5),base*600); layout(); }
  document.getElementById('zin').onclick=function(){zoom(1.6);};
  document.getElementById('zout').onclick=function(){zoom(1/1.6);};
  document.getElementById('zfit').onclick=function(){pxus=base;layout();scroll.scrollLeft=0;};
  scroll.addEventListener('wheel',function(e){
    if(!e.ctrlKey) return; e.preventDefault();
    var r=scroll.getBoundingClientRect(), cx=e.clientX-r.left+scroll.scrollLeft-GUT, tus=cx/pxus;
    zoom(e.deltaY<0?1.25:0.8);
    scroll.scrollLeft=tus*pxus+GUT-(e.clientX-r.left);
  },{passive:false});
  canvas.addEventListener('mouseover',function(e){
    var el=e.target.closest('.ev'); if(!el) return;
    tip.textContent=el.dataset.tip; tip.style.display='block';
  });
  canvas.addEventListener('mousemove',function(e){
    if(tip.style.display==='block'){ tip.style.left=(e.clientX+14)+'px'; tip.style.top=(e.clientY+16)+'px'; }
  });
  canvas.addEventListener('mouseout',function(e){ if(e.target.closest('.ev')) tip.style.display='none'; });
  var drag=false,sx,sl;
  scroll.addEventListener('mousedown',function(e){ if(e.target.closest('.ev'))return; drag=true;sx=e.clientX;sl=scroll.scrollLeft;scroll.classList.add('drag'); });
  window.addEventListener('mousemove',function(e){ if(drag) scroll.scrollLeft=sl-(e.clientX-sx); });
  window.addEventListener('mouseup',function(){ drag=false; scroll.classList.remove('drag'); });
  layout();
})();
"""

_TL_CSS = """
<style>
.tlctl{display:flex;align-items:center;gap:8px;margin:12px 0;}
.tlctl button{font:600 11px/1 var(--mono);color:var(--accent-ink);background:var(--card);
  border:1px solid var(--line2);border-radius:7px;padding:7px 11px;cursor:pointer;
  text-transform:uppercase;letter-spacing:.6px;}
.tlctl button:hover{border-color:var(--accent-dim);}
.tlctl .hint{color:var(--faint);font:11px/1.7 var(--mono);margin-left:4px;}
.tl{border:1px solid var(--line2);border-radius:var(--radius);overflow:hidden;background:var(--card);
  box-shadow:inset 0 1px 0 rgba(255,255,255,.04);}
.tlscroll{overflow-x:auto;overflow-y:hidden;cursor:grab;}
.tlscroll.drag{cursor:grabbing;}
.tlcanvas{position:relative;min-width:100%;}
.tlaxis{position:relative;height:22px;border-bottom:1px solid var(--line2);background:#10141c;}
.tlaxis .tk{position:absolute;top:0;bottom:0;width:1px;background:var(--line2);}
.tlaxis .tlab{position:absolute;left:4px;top:5px;font:10px/1 var(--mono);color:var(--faint);white-space:nowrap;}
.tl-lane{position:relative;height:26px;border-bottom:1px solid var(--line);}
.tl-lane:last-child{border-bottom:0;}
.lane-lbl{position:sticky;left:0;z-index:4;display:flex;align-items:center;width:74px;height:26px;
  padding:0 8px;font:600 10px/1 var(--mono);color:var(--mut);background:#0f131b;
  border-right:1px solid var(--line2);text-transform:uppercase;letter-spacing:.6px;}
.ev{position:absolute;top:4px;height:18px;border-radius:3px;background:var(--c,#5ad1ff);
  box-shadow:0 0 6px -2px var(--c,#5ad1ff);overflow:hidden;cursor:pointer;}
.ev:hover{outline:1px solid #fff;outline-offset:-1px;}
.ev .cap{display:block;font:10px/18px var(--mono);color:#08111a;padding:0 4px;white-space:nowrap;pointer-events:none;}
#tltip{position:fixed;z-index:50;display:none;pointer-events:none;max-width:520px;
  background:#0d1119;border:1px solid var(--line2);border-radius:8px;padding:8px 10px;
  font:11px/1.5 var(--mono);color:var(--ink);box-shadow:0 12px 30px -10px #000;
  white-space:pre-wrap;word-break:break-all;}
.legend{display:flex;flex-wrap:wrap;gap:7px 16px;font:11px/1.6 var(--mono);color:var(--mut);}
.legend .lk{display:inline-flex;align-items:center;gap:7px;}
.legend .sw{width:11px;height:11px;border-radius:3px;background:var(--c);box-shadow:0 0 6px -1px var(--c);}
</style>
"""


def render(data, name, out):
    # origin spans all kept events, not just kernels: host launches precede their
    # dispatch, so pinning to the first kernel would push them to negative offsets.
    starts = [data["g0"]] + [e[2] for e in data["host"]] + [e[2] for e in data["copy"]]
    ends = [data["g1"]] + [e[3] for e in data["host"]] + [e[3] for e in data["copy"]]
    g0, g1 = min(starts), max(ends)
    total_us = (g1 - g0) / 1e3
    base = 1500.0 / total_us if total_us else 1.0      # px per µs at "fit"

    # stable color per device-kernel short-name, in first-seen order
    kcolor, order = {}, []
    for cap, _f, _t0, _t1 in data["kern"]:
        if cap not in kcolor:
            kcolor[cap] = PALETTE[len(order) % len(PALETTE)]
            order.append(cap)

    lanes = [build_lane("HIP API", data["host"], g0, base,
                        lambda cap, full: _host_color(full))]
    if data["copy"]:
        lanes.append(build_lane("COPY", data["copy"], g0, base,
                                lambda cap, full: "#ffb454"))
    lanes.append(build_lane("GPU", data["kern"], g0, base,
                            lambda cap, full: kcolor.get(cap, "#5ad1ff")))

    canvas = (f"<div class='tl'><div class='tlscroll' id='tlscroll'>"
              f"<div class='tlcanvas' id='tlcanvas' data-gut='{GUT}' "
              f"data-total='{total_us:.4f}' data-base='{base:.6f}'>"
              f"<div class='tlaxis' id='tlaxis'></div>{''.join(lanes)}</div></div></div>")
    ctl = ("<div class='tlctl'><button id='zout'>− zoom</button>"
           "<button id='zin'>+ zoom</button><button id='zfit'>fit</button>"
           "<span class='hint'>ctrl+wheel = zoom at cursor · drag = pan · hover = details</span></div>")

    # per-kernel aggregate (device lane only) for the top-kernels bars
    agg = {}
    for cap, _f, t0, t1 in data["kern"]:
        e = agg.setdefault(cap, [0, 0.0])
        e[0] += 1
        e[1] += (t1 - t0) / 1e3
    top = sorted(agg.items(), key=lambda kv: -kv[1][1])[:15]
    topbars = bars([(f"{k}  (x{v[0]})", v[1], f"{v[1]:.1f} µs") for k, v in top])

    legend = "".join(
        f"<span class='lk'><span class='sw' style='--c:{kcolor[k]}'></span>{esc(k)}</span>"
        for k in order[:12])

    sub = (f"<p class='sub'>workload <b>{esc(name)}</b> · span <b>{total_us:.1f} µs</b> · "
           f"<b>{len(data['kern'])}</b> dispatches · <b>{len(data['host'])}</b> host calls · "
           f"<b>{len(data['copy'])}</b> copies</p>")
    body = (f"<h1>trace timeline · {esc(name)}</h1>{sub}{_TL_CSS}"
            + section("Host + device timeline", ctl + canvas)
            + "<div id='tltip'></div>"
            + section("Legend (device kernels)", f"<div class='legend'>{legend}</div>")
            + section("Top kernels by total GPU time", topbars)
            + "<p class='foot'>built from rocprofv3 --sys-trace CSVs · "
              "open the .pftrace in ui.perfetto.dev for flows / counters / full zoom</p>"
            + f"<script>{_JS}</script>")
    with open(out, "w") as f:
        f.write(page(f"trace timeline · {name}", body))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--prefix", default="trace")
    ap.add_argument("--name", default="")
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    data = load_events(a.run_dir, a.prefix)
    if not data:
        print(f"trace_timeline: no kernel trace under {a.run_dir} (prefix {a.prefix})",
              file=sys.stderr)
        sys.exit(2)
    out = a.out or os.path.join(a.run_dir, "timeline.html")
    name = a.name or os.path.basename(os.path.normpath(a.run_dir))
    render(data, name, out)
    print("wrote", out)


if __name__ == "__main__":
    main()
