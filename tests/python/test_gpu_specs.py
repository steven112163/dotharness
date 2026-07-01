"""Tests for lib/ck-profile/gpu_specs.py — the hardware-spec lookups."""

import gpu_specs


def test_get_spec_known_arch_returns_full_record():
    spec = gpu_specs.get_spec("gfx942")
    assert spec is not None
    assert spec["product"] == "MI300X/MI325X"
    assert spec["cu"] == 304
    assert spec["wave"] == 64
    assert spec["vgpr_per_simd"] == 256


def test_get_spec_unknown_arch_returns_none():
    assert gpu_specs.get_spec("gfx0000") is None


def test_peak_mem_gbs_known_arch():
    assert gpu_specs.peak_mem_gbs("gfx942") == 5300.0


def test_peak_mem_gbs_unknown_arch_returns_none():
    assert gpu_specs.peak_mem_gbs("gfx0000") is None


def test_unreleased_arch_has_none_fields_but_known_wave():
    spec = gpu_specs.get_spec("gfx1250")
    assert spec["cu"] is None
    assert spec["vgpr_per_simd"] is None
    assert spec["wave"] == 64


def test_every_spec_has_the_required_keys():
    required = {
        "product",
        "cu",
        "wave",
        "simd_per_cu",
        "max_waves_cu",
        "vgpr_per_simd",
        "agpr_per_simd",
        "lds_kb_per_cu",
    }
    for arch, spec in gpu_specs.SPECS.items():
        assert required <= set(spec), f"{arch} missing keys: {required - set(spec)}"


def test_rdna_archs_have_no_separate_agpr_file():
    # RDNA (gfx11xx/gfx12xx) has no accumulation file: agpr_per_simd is 0.
    for arch, spec in gpu_specs.SPECS.items():
        if arch.startswith(("gfx11", "gfx12")) and spec["agpr_per_simd"] is not None:
            assert spec["agpr_per_simd"] == 0, f"{arch} should have agpr_per_simd=0"
