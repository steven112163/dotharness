#!/usr/bin/env python3
"""Single source of truth for AMD GPU hardware specs, keyed by gfx (LLVM target)
ID. Imported by both aggregate.py (dynamic report) and parse_resource_usage.py
(static report) so the two can never disagree on a hardware number.

Two tables:
  PEAK_MEM_GBS  theoretical peak device-memory bandwidth (GB/s)
  SPECS         CU count, wave size, SIMDs/CU, max resident waves/CU,
                VGPR/AGPR file per SIMD, LDS per CU (KB)

All values are from AMD specs / whitepapers, not host-measured, so no matching
hardware is needed. Caveats (see REFERENCE.md for full detail and sources):

- max_waves_cu is DERIVED, not quoted verbatim: CDNA = 8 waves/SIMD x 4 SIMD;
  RDNA = 16 waves/SIMD x 2 SIMD. Both land at 32. The legacy "10 waves/SIMD ->
  40/CU" is GCN-era and does NOT apply to CDNA3/RDNA3+.
- RDNA: one gfx ID spans many SKUs with different CU counts, so the SPECS entry
  is the FLAGSHIP of that family (matches the PEAK_MEM_GBS convention).
- gfx950 (CDNA4): whether the VGPR/AGPR files are unified is unverified, so the
  CDNA3 "separate files" model is kept.
- gfx1250/gfx1251 (MI450/MI455X/MI430X) are unreleased: only HBM4 bandwidth is
  public, so their SPECS fields are None and print as n/a.

Sources: ROCm GPU hardware specs page; AMD CDNA3 ISA guide + CDNA3/CDNA4
whitepapers; TechPowerUp GPU database (RDNA SKUs); GPUOpen "Occupancy explained".
"""

# Theoretical peak device-memory bandwidth (GB/s).
# CDNA (Instinct, HBM) — one product family per gfx ID, exact:
#   gfx942 = MI300X/MI325X (CDNA3, HBM3); gfx950 = MI350X/MI355X (CDNA4, HBM3E)
#   gfx1250 = MI450/MI455X, gfx1251 = MI430X (CDNA-next, HBM4)
# RDNA (Radeon, GDDR) — one gfx ID spans many SKUs, so FLAGSHIP of each family;
# pass --peak-gbs for an exact per-card value.
PEAK_MEM_GBS = {
    "gfx942": 5300.0,
    "gfx950": 8000.0,
    "gfx1250": 19600.0,
    "gfx1251": 19600.0,
    "gfx1201": 640.0,
    "gfx1200": 320.0,
    "gfx1100": 960.0,
    "gfx1101": 624.0,
    "gfx1102": 288.0,
}

# Per-arch hardware resources. None = unverified/unreleased (prints as n/a).
# Keys: product, cu, wave, simd_per_cu, max_waves_cu, vgpr_per_simd,
#       agpr_per_simd (0 on RDNA — no separate accumulation file), lds_kb_per_cu.
SPECS = {
    # CDNA3 — separate 256 VGPR + 256 AGPR files per SIMD; 64 KB LDS/CU.
    "gfx942": {
        "product": "MI300X/MI325X",
        "cu": 304,
        "wave": 64,
        "simd_per_cu": 4,
        "max_waves_cu": 32,
        "vgpr_per_simd": 256,
        "agpr_per_simd": 256,
        "lds_kb_per_cu": 64,
    },
    # CDNA4 — 256 CU, 160 KB LDS/CU; VGPR/AGPR unification unverified, keep CDNA3 model.
    "gfx950": {
        "product": "MI350X/MI355X",
        "cu": 256,
        "wave": 64,
        "simd_per_cu": 4,
        "max_waves_cu": 32,
        "vgpr_per_simd": 256,
        "agpr_per_simd": 256,
        "lds_kb_per_cu": 160,
    },
    # CDNA-next (MI4xx) — unreleased; only HBM4 bandwidth is public.
    "gfx1250": {
        "product": "MI450/MI455X",
        "cu": None,
        "wave": 64,
        "simd_per_cu": None,
        "max_waves_cu": None,
        "vgpr_per_simd": None,
        "agpr_per_simd": None,
        "lds_kb_per_cu": None,
    },
    "gfx1251": {
        "product": "MI430X",
        "cu": None,
        "wave": 64,
        "simd_per_cu": None,
        "max_waves_cu": None,
        "vgpr_per_simd": None,
        "agpr_per_simd": None,
        "lds_kb_per_cu": None,
    },
    # RDNA4 — wave32, 2 SIMD/CU, 1536 VGPR/SIMD, 128 KB LDS/CU. Flagship CU counts.
    "gfx1201": {
        "product": "RX 9070 XT",
        "cu": 64,
        "wave": 32,
        "simd_per_cu": 2,
        "max_waves_cu": 32,
        "vgpr_per_simd": 1536,
        "agpr_per_simd": 0,
        "lds_kb_per_cu": 128,
    },
    "gfx1200": {
        "product": "RX 9060 XT",
        "cu": 32,
        "wave": 32,
        "simd_per_cu": 2,
        "max_waves_cu": 32,
        "vgpr_per_simd": 1536,
        "agpr_per_simd": 0,
        "lds_kb_per_cu": 128,
    },
    # RDNA3 — wave32, 2 SIMD/CU, 128 KB LDS/CU. Navi33 (gfx1102) has a smaller VGPR file.
    "gfx1100": {
        "product": "RX 7900 XTX",
        "cu": 96,
        "wave": 32,
        "simd_per_cu": 2,
        "max_waves_cu": 32,
        "vgpr_per_simd": 1536,
        "agpr_per_simd": 0,
        "lds_kb_per_cu": 128,
    },
    "gfx1101": {
        "product": "RX 7800 XT",
        "cu": 60,
        "wave": 32,
        "simd_per_cu": 2,
        "max_waves_cu": 32,
        "vgpr_per_simd": 1536,
        "agpr_per_simd": 0,
        "lds_kb_per_cu": 128,
    },
    "gfx1102": {
        "product": "RX 7600",
        "cu": 32,
        "wave": 32,
        "simd_per_cu": 2,
        "max_waves_cu": 32,
        "vgpr_per_simd": 1024,
        "agpr_per_simd": 0,
        "lds_kb_per_cu": 128,
    },
}


def get_spec(arch):
    """Return the spec dict for an arch, or None if unknown."""
    return SPECS.get(arch)


def peak_mem_gbs(arch):
    """Return peak device-memory bandwidth (GB/s) for an arch, or None."""
    return PEAK_MEM_GBS.get(arch)
