# addons/octahedral_impostor_lod — DOX

## Purpose
The addon itself: the saved atlas resource, the baker and its time-sliced job, bake settings and presets, the card node and LOD helpers, groups, join, atlas packing, chunk streaming, the runtime bake queue, coverage/quality measurement, wind and mesh fade, the debug view and HUD, the dock, the scene picker and the editor plugin. Its two subfolders (`shaders/`, `tools/`) have their own contracts.

File map (runtime unless noted):
- `octa_atlas.gd` — the Resource: textures, per-object `obj_data`, shader variant cache (`shader_variant()` + `V_*` flags; `shader_for()` is the compatibility wrapper), `create_card`, `create_multimesh(es)`, VRAM estimate.
- `octa_baker.gd` — `bake()` / `bake_to_file()` / `save_atlas()`; capture rig, per-view readback, ORM/emission/back passes, mipmaps, coverage pyramid.
- `octa_bake_settings.gd` — every option, `layout()`, `describe()`, `cost_text()`, presets.
- `octa_impostor.gd` — the card node (`MeshInstance3D`), LOD/fade/wind configuration, per-card overrides.
- `octa_lod.gd` — attach/remove/find cards, modes (DYNAMIC_LOD, DUPLICATE, REPLACE), FOV helpers, fade helpers, scene candidates and the picker estimate (`candidate_radius`, `triangle_count`).
- `octa_impostor_group.gd` — group node (shared settings/atlas) + chunk tier (`attach_chunk`, `detach_chunk`, `group_in`, `claimed_nodes`).
- `octa_join.gd` / `octa_joined_group.gd` — Morton/adaptive partition and the MultiMesh node.
- `octa_packer.gd` — merges compatible atlases without re-baking.
- `octa_chunk_streamer.gd` — threaded chunk load, sliced instance upload, unload.
- `octa_bake_queue.gd` + `octa_bake_job.gd` — runtime queue, frame budget, LRU atlas cache, cancel.
- `octa_coverage.gd`, `octa_quality.gd` — card coverage (hull/polygons/mean) and the Check Quality measurement.
- `octa_wind.gd`, `octa_mesh_fade.gd` — global wind parameters and dithered real-mesh fade.
- `octa_debug.gd`, `octa_debug_hud.gd` — debug modes and the on-screen stats.
- `octa_dock.gd` (editor), `octa_scene_picker.gd` (editor), `plugin.gd` (editor plugin entry), `plugin.cfg`.

## Ownership
- The maintainer owns this tree; a contributor working on one task stays inside the files that task names.
- `plugin.cfg` version and `README.md`: edited deliberately.

## Local Contracts
- Public API stays usable from exported games: runtime scripts must not reference `EditorInterface` directly at parse time (use `Engine.get_singleton("EditorInterface")` / `Engine.get_meta("octa_lod_plugin")`); `plugin.gd` and the dock are the only editor-only scripts.
- Atlas format 4: `format_version` 1-3 files must load and render exactly as before; `object_data()` applies the back-compat defaults. Never write a variant `Shader` or a `BakeSettings` by reference into a saved atlas — duplicate settings, keep materials runtime-only.
- All shader swaps go through `OctaAtlas._update_shaders()`; the variant cache key is `quality * 100 + depth + debug + flags * 1000`. New code builds flags with `OctaAtlas.shader_variant(quality, depth, debug, flags)` and the `V_PRECISE/V_FADE/V_WIND/V_VISIBILITY/V_PYRAMID/V_PARALLAX` constants; `shader_for()` keeps its old signature as a wrapper. Flags are normalised per quality (precise/pyramid Ultra-only, visibility below Ultra, parallax below High).
- `OctaAtlas.materials` is runtime-only (not exported) and rebuilt on demand by `get_material()`; saved atlases embed textures and data only. Old files that still contain materials load and render as before.
- Material parameters are applied once per atlas stamp (`_stamp` / `_param_stamp`), not per card setter; `OctaImpostor._refresh()` only runs inside the tree.
- Optional features carry a bake setting and/or a card property and default to off unless their measured gain cleared the 5% gate. Off means the shipped shaders and no extra atlas data.
- Presets are a four-step ladder: `Minimal` (fastest: Low, 8x8 on 1024, VRAM, no material/emission maps, flat depth), `Fast` (many props: High, 10x10 on 2048, VRAM, half-res maps), `Quality` (High, 16x16 on 4096, lossless, full-res maps, 2 shadow views) and `Max` (the measured ceiling: Ultra, precise search, split parts, back layer, 24 steps, 16x16 on 4096, full-res maps, 3 shadow views, 8x MSAA, hemisphere on). A preset fills the whole cost/quality surface and never touches placement, LOD mode/distance, fade margin, dedupe, join, wind or batch size. `PRESET_NAMES` and `PRESET_TIPS` must stay in enum order; the CLI takes the same names. Presets are read-only: `preset_values()` returns a fresh dictionary and nothing may write into it. The dialog switches to Custom only when a property the selected preset owns changes (`_preset_owns`), and a saved Custom configuration is restored by `_load_settings()` with `_matching_preset()` re-selecting the preset it matches. `SHORT_HINTS` carries the one-line hover text for every setting (applied by `_apply_hints()` to each `EditorProperty` row and its child controls); add an entry when adding a setting.
- Legacy and format rules: never rename the class names; `OctaAtlas.shader_for(...)` keeps its current signature (add flags helpers beside it instead of changing it).
- Editor actions are one undoable action each and must restore the previous state on undo (cards, real-mesh visibility, fades, chunk card, packed atlas references).

## Work Guidance
- New option checklist: bake setting (with tooltip), copy in `OctaBaker`, shader variant key if needed, `KEY_PROPERTIES` in the bake queue, `describe()`/`cost_text()`, dock row if it is per-card, README row, CHANGELOG entry, a test that proves the off path is identical, and the measured number in the design notes.
- Editor performance: avoid per-selection full-tree walks and per-call `get_image()` readbacks; cache by `instance_id` and drop entries when the object is freed.
- Memory: atlases are large (2048 ≈ 45 MB). Prefer R8 for single-channel maps, half-res for material maps, and do not keep full-image copies alive unless they are the atlas itself.
- When touching the atlas/baker, re-run `tests/material_maps_test.gd`, `tests/compat_test.gd` and `tests/lod_test.gd` at minimum.
- The Bake Scene picker estimate is an AABB-corner sphere, deliberately looser than the exact bake radius (about ±2 percentage points on the tick threshold); never use it for anything that needs the true bounds.

## Verification
- `tests/lod_test.gd` — save/reload, LOD switching, MultiMesh, DUPLICATE.
- `tests/material_maps_test.gd` — ORM skip for constant materials, half-res maps, VRAM.
- `tests/compat_test.gd` — old atlases, 0 differing pixels on 3 renderers.
- `tests/precise_test.gd`, `tests/parallax_test.gd` — variant plumbing and per-quality normalisation.
- `tests/queue_test.gd` — runtime queue budget, cache, paced bake.
- `tests/coverage_report.gd` / `tests/overdraw_test.gd` — coverage numbers and the overdraw view.
- `tests/quality_flat_test.gd` — Check Quality on a flat card.
- `bash tests/run_editor_test.sh` — the editor paths (bake dialog, groups, chunk card, pack, undo).

## Child DOX Index
- `shaders/AGENTS.md` — shader variants, compile-time defines, capture shaders, bake hook.
- `tools/AGENTS.md` — the command line baker.
