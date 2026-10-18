# addons/octahedral_impostor_lod/shaders — DOX

## Purpose
The runtime shaders and their capture counterparts.
- `octa_core.gdshaderinc` — the shared fragment/vertex core (CRLF). Everything else is a thin entry that sets `#define` values and includes it: `octa_low.gdshader`, `octa_medium.gdshader`, `octa_high.gdshader`, `octa_ultra.gdshader`.
- Capture passes baked with the rig: `capture_*.gdshader` (albedo, normal+depth, cull-front/back, ORM, emission).
- `octa_bake_hook.gdshaderinc` — the include a custom shader uses to output exact bake data (`OCTA_BAKE_OUTPUT`).

## Ownership
- Maintainer.

## Local Contracts
- `octa_core.gdshaderinc` is CRLF and must stay CRLF; the entry shaders and the hook include are LF.
- `#define` names are the variant ABI: `QUALITY`, `NO_DEPTH_WRITE`, `DEBUG_MODE`, `PRECISE_SEARCH`, `CARD_FADE`, `CARD_WIND`, `VIEW_VISIBILITY`, `PYRAMID_SEARCH`, `PARALLAX_REFINE`. They are appended by `OctaAtlas.shader_for()`; never reorder or reuse a cache-key bit (1000, 2000, 4000, 8000, 16000, 32000, then 64000 for the next one).
- A flag may be normalised away per quality in `shader_for()`; when it is, the fragment code for that quality must be a no-op anyway.
- Godot shader language limits: no `return` inside `fragment()` (the bake hook uses `if/else`), no dynamic loops, `flat` varyings for per-card data.
- Varying budget: `octa_core` already uses about 13 vec4 slots. A measured test (S1, 2026-10-18) showed +9 varying floats per pixel costs 5.0 -> 8.3 ms at Low and 7.8 -> 11.9 ms at High on the Vega 7; pass per-card data through existing varyings or accept a measured regression, do not add varyings casually.
- The shadow pass has its own branch (`IN_SHADOW_PASS`): one view, 2 parallax steps, never the Ultra ray search, `shadow_views` 1-3.
- The bake hook must never `return` and must compile in every quality; `OctaBaker` detects it by `Shader.code.contains("octa_bake_mode"/"octa_bake_hook")`, not by a uniform value.
- All "off" paths must render exactly like v2.1: `tests/compat_test.gd` proves it with 0 differing pixels on Forward+, Mobile and Compatibility.

## Work Guidance
- Change the core include, never the generated variant strings, to add behaviour.
- Keep the mobile-friendly subset in mind: no `textureLod` outside Ultra's precise path, no integer bit tricks, no derivative tricks beyond `dFdx/dFdy` on texture coordinates.
- After a shader change run: `tests/compat_test.gd` (3 renderers), `tests/visual_test.gd` (accuracy must match the recorded baseline unless the change is meant to alter it), `tests/precise_test.gd`, `tests/parallax_test.gd`, and `tests/perf_test.gd --mode=low|high|ultra --shadows=0` for cost.
- GPU data on this machine is noisy: interleave A/B, median of at least 3, and record the range in the design notes.

## Verification
- `godot --path . -s res://tests/compat_test.gd` — 0 differing pixels per renderer.
- `godot --path . -s res://tests/visual_test.gd` — ACCURACY lines, compare with the recorded baseline.
- `godot --path . -s res://tests/wind_test.gd`, `tests/fade_test.gd`, `tests/overdraw_test.gd`, `tests/shadow_test.gd` — the per-feature shader paths.
- `godot --path . -s res://tests/perf_test.gd -- --mode=ultra --shadows=0` — GPU cost.
