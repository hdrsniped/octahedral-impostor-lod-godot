# Changelog

## 3.0.0

Quality control (2026-10-18, after the features below)
- The bake dialog explains every setting on hover: 38 one-line tooltips ("Views per side. More views, less detail per view.", "Ultra only: smarter search, 2-3x slower.") on the rows and their editors, so no option needs the documentation to be understood.
- Presets are read-only templates. `OctaBakeSettings.preset_values()` returns a fresh dictionary for each preset, `apply_preset()` only copies from it, and the editor test proves a preset table cannot be changed by baking. Changing a setting a preset owns switches the dialog's dropdown to **Custom**; changing placement (mode, LOD distance) keeps the current preset, because presets never own placement.
- Custom is remembered everywhere: the dialog saves its settings after every edit, on preset changes and on bake, restores them when the plugin starts again, and picks the preset that matches the restored values (Custom when none does). You set your own configuration once and keep it across bakes and Godot restarts.
- Presets are a four-step ladder now: **Minimal** (the fastest the addon gets: Low, 8x8 views on a 1024 atlas, VRAM compression, no material maps, flat depth so the card casts no shadow, 1 shadow view), **Fast** (many props: High, 10x10 on 2048, VRAM compression, half-res maps, 1 shadow view), **Quality** (best without trading much performance: High, 16x16 on 4096, lossless, full-res maps, 2 shadow views) and **Max** (maximum quality at every point: Ultra with precise search, split parts, back layer, 24 search steps, 16x16 on a 4096 lossless atlas, full-res maps, 3 shadow views, 8x MSAA capture, hemisphere on). Every preset sets the whole cost/quality surface (including material maps, emission, pyramid and visibility options) and crossfades by default; none of them touches placement, LOD mode/distance or the join settings. Full-sphere baking is the `hemisphere` option now, not a preset. The old Mobile/Balanced/High quality/Complex shapes/Full sphere presets are gone; `--preset=` takes the new names.
- Fixed: saved atlases carried their materials (four `ShaderMaterial`s, and any runtime `Shader` variant, with its code) in every `.res` file; `materials` is runtime-only again and `get_material()` rebuilds it. The same atlas is 59% smaller on disk (`.tres` text 90% smaller) and old files that still contain materials load and render as before (M2).
- Fixed: saving an atlas compressed its textures *after* the materials were built, so the material parameters still pointed at the uncompressed images and a scene saved in the same session embedded them (~12 MB for one card). `save_atlas` now re-applies the parameters after compressing; a scene with one card is 80 bytes instead of ~12 MB (M4).
- The Bake Scene picker estimates an object's radius from the corners of its mesh AABBs instead of collecting every vertex: 200 candidates take 3-4 ms (was 899-921 ms) for ArrayMeshes and 11-12 ms (was 762-886 ms) for primitive meshes, with the same tick state (±2 percentage points on the threshold) (K3).
- The Impostor dock debounces selection changes, caches its group info and calls `_cards()` once per refresh instead of three times (K6).
- `OctaAtlas.shader_variant(quality, depth, debug, flags)` with `V_PRECISE`/`V_FADE`/`V_WIND`/`V_VISIBILITY`/`V_PYRAMID`/`V_PARALLAX` replaces the nine-positional-argument call internally; `shader_for()` keeps its signature (D1).
- `OctaPacker.save_packed()` picks a unique `_N` file name instead of overwriting an existing pack (D4).
- CLI: `--pack` packs the atlases produced by that run into one shared atlas, saves it next to the others and, with `--save-scene`, re-points the cards and group atlases (`--help` lists it; `tests/cli_test.sh` has a case) (E7).
- New `demo/bake_showcase.tscn`: an editable bake sandbox (sun + sky + ground, a red box, green sphere, blue capsule, gold metallic torus, a two-part mushroom for split parts, and an `OctaImpostorGroup` with three boxes and its own 1024/8x8 settings). Select any mesh, run Bake Selected..., and the card swaps in the editor viewport as your camera crosses the LOD distance; the group node bakes all three boxes into one atlas with its inspector button.`n- Demo: the camera can fly, not just orbit. Arrow keys move along the view, `Q`/`E` go down/up, `Shift` flies four times faster and the pivot stops 0.4 m above the ground; orbiting, dragging, the wheel and every key still work, and the fly keys are ignored during the auto-benchmark.`n- Demo: key `C` shows a three-prop `OctaImpostorGroup` with a 24 m chunk card (press again to remove it) (E6).
- Demo camera: arrows move along the view, `Q`/`E` go down and up, `Shift` flies four times faster; orbit, drag, the wheel and every key still work, and the fly keys are ignored during the auto-benchmark.
- Tests: `perf_test` and `visual_test` take `--depth=0|1`; a depth-off card was measured 27.6% (Low), 35.7% (Medium) and 17.9% (High) faster on Forward+ but loses card self-shadowing and cast shadows, so `write_depth` stays on by default.
- Ultra only: `is_inside`/`crossed_slab` take precomputed surface heights and the frame test runs once per sample (bit-identical output; 14.60 -> 14.36 ms median on Forward+).
- New statics `OctaLOD.candidate_radius()` and `OctaLOD.triangle_count()`; `OctaAtlas.refresh_materials()`.
- Fixed: the coverage pyramid (P1) read past the image on every non-square atlas (2, 5, 6, 7 objects...) and built a square map for a rectangular one; it is rectangular now and `layout()` rounds the view size so `grid * frame` is a multiple of the 4 px coverage block (X1, X6). The packer copies the coverage tiles instead of recomputing them, and the baker builds it before the normal map's mipmaps.
- Fixed: packing crashed when a source atlas' tile grid had an empty slot (3 objects in a 2x2 grid); old-format atlases lost the `AO = 1` default (cards rendered dark) and could index past `surface_params`; the packed atlas shared the first source's `BakeSettings`; packing only merged *consecutive* compatible atlases; a single atlas was copied (161 ms) instead of returned; the packing limit came from the dialog's atlas size (the Mobile preset's 1024 produced one atlas per object); the new files were not re-scanned; and every tile did a full `get_image()` readback and conversion of the whole source atlas (now one readback per map, mipmaps dropped before the copy). A 2-atlas, 5-object pack at 2040 px measures 109-122 ms before and after: the cost is the tile blits plus mipmap generation, not the readbacks (A1, A2, A4, B1, B4, B5, B7, B9, C1).
- Fixed: Re-bake Selected on a chunk card (and Re-bake All in a scene that has one) baked the group again as a plain object and repointed every prop's visibility parent to the chunk card, so the real meshes disappeared inside the LOD range. The group lookup now resolves the group itself and walks up from the node (A3, K7).
- Fixed: the chunk card was found by node name (renaming it made re-bake add another one; it uses a meta now) and `detach_chunk` reset every card's `visibility_range_end` instead of restoring user values (B2, B3).
- Fixed: streamed chunks drew instances at the node origin while uploading (instances are now revealed as they are written, so nothing appears at the origin while the chunk streams in), releasing a chunk mid-load drains its threaded load, and `is_pending` / `keep_atlases` behave as documented (X2, X7, R4, B8).
- Fixed: the CLI overwrote an existing `_chunk.res` (now unique) and took its overrides from whichever card it found last, which could be a sub-part's card (X4, X5).
- Faster: the debug HUD no longer walks the whole scene twice every 0.5 s (cards and joined groups register themselves), uses the joined group's atlas instead of comparing `obj_data` across all atlases, and the card-fill mean samples 1/16 of the pixels, cutting its first-call stall about 16x (R3, K4). Cards apply the shared material once per atlas change instead of about 13 parameters per setter (R2); wind and live-atlas bookkeeping use dictionaries (R6); the renderer fade check is cached (R5); the quality check compares byte buffers instead of 2 x 295k `get_pixel` calls (K5); card lookup below a node is one subtree walk instead of one sibling scan per geometry node (K8); `describe`/`cost_text` scan the sources once instead of twice (Q2).
- Memory: the back layer is captured into an R8 image from the start (4x less during the bake, M1) and `vram_bytes()` now counts compressed atlases, the coverage map and `obj_data` (M3).
- Shader: non-Ultra frames whose coarse sample is empty now skip their parallax and colour fetches (S2, accuracy unchanged). Variant flags are normalised per quality (visibility only below Ultra, pyramid only at Ultra, parallax only at Low/Medium), so no needless shader variants are compiled and the Parallax refine tooltip no longer claims a gain on High (C4).
- Tried and reverted: moving the per-pixel frame basis to the vertex stage (S1) cost +9 interpolated floats per pixel and measured 5.0 -> 8.3 ms at Low and 7.8 -> 11.9 ms at High (4,000 cards, Vega 7); filling MultiMeshes through `MultiMesh.buffer` (R1) measured 6.7-7.2 ms against 1.2-2.4 ms for 10,000 `set_instance_transform` calls, because packing the floats in GDScript costs more than the engine calls (the join and the streamer keep the per-instance path, the streamer only adds `visible_instance_count`).
- Not done (needs a cooled-machine A/B first): depth prepass / early-Z defaults (S3), Ultra helper hoisting (S4), picker AABB estimates (K3), dock debounce (K6), material export trimming (M2), shared editor/CLI bake planner (Q1), tighter bounding sphere (Q3).

New
- Smooth LOD crossfade on Mobile and Compatibility (I6). With Fade = Crossfade the card shader dithers itself in across the band (LOD distance +- fade margin, smoothstep, fixed screen-space pattern, shadow pass not dithered) as a compile-time variant (`#define CARD_FADE`, `OctaAtlas.shader_for(..., fade)`, `atlas.card_fade`) that only exists when a card asks for it. Forward+ keeps Godot's native fade and the shipped shaders. Fade None is unchanged.
- `fade_real_mesh` (bake setting and OctaImpostor property, on by default): on Mobile and Compatibility the real mesh also dithers out across the band with shared StandardMaterial3D copies (`OctaMeshFade`); originals are never changed and come back on Remove, re-bake, Fade None and before editor saves. Sources that cannot fade (ShaderMaterial, own distance fade) keep the overlap: the card fades in, then the mesh switches off.
- `OctaLOD.fade_available()` (always true), `fade_kind()` ("native" or "dither"); `fade_supported()` still means native fade. `create_multimesh()` takes `lod_distance` and `fade_margin` so joined groups fade per instance on Mobile and Compatibility.
- Adaptive join (I2, option, off by default): `join_adaptive`, `join_region_size` (20 m) and `join_region_count` (128) in Scene and joining. Each Join Cell is split by a median split on the longest axis until a region holds at most Region Count instances and spans at most Region Size (regions under 16 instances are never split by size), and the instances of every group are ordered along a 3D Z-order (Morton) curve. New `OctaJoin` (`partition`, `subdivide`, `order`, `codes`) and `OctaAtlas.create_multimeshes()`; the editor Join and the demo's J use it when the option is on. Measured on 20,000 cards over 4 x 4 km: 0% to -63% off-screen instances submitted, but 12% to 300% more MultiMeshes and +8% to +195% CPU, GPU unchanged to +24% (under 1.2 ms), so it ships off. With it off, joined groups and instance order are identical to 2.1.
- Far-field wind for foliage cards (I1, option, off by default): `OctaImpostor.wind_strength` (0-1, per card instance uniform `card_wind`), `OctaBakeSettings.wind_strength` (default for new cards), dock row Wind (undoable), `OctaWind.set_wind(direction, speed, gust, frequency)` for the shared direction and speed (written to the materials of the live atlases, so it works for single cards and for MultiMesh groups on every renderer), `create_multimesh(..., wind_strength)`. The top of the object leans downwind by up to 20% of its radius (height squared, so the base row stays fixed) by shifting the sampled position before the view lookup, in texture space: all three views move together, the shadow pass uses the same shift, baked normals are tilted by the lean, nothing is read outside a frame tile, no vertex displacement and no bounds growth. Compile-time variant `#define CARD_WIND` (`OctaAtlas.shader_for(..., wind)`, cache key +4000), selected only while a card above 0 or a wind group exists; otherwise the shipped shaders run unchanged. Demo key [K]. About +4-10% card shader time while on, 0 when off./ Joined groups are `OctaJoinedGroup` nodes that register their wind like cards (no saved flag; the atlas returns to the shipped shader when none is left); the dock Atlas info lists wind.
- Demo memory on Compatibility: the demo bake renders 8 views at a time instead of 64 (`batch_size = 8`), so the four material passes keep 32 SubViewports alive instead of 256. Peak private memory of the demo smoke run drops from 4173 MB to 1784 MB and of a normal demo run from 3124 MB to 1412 MB; the baked atlas is unchanged and the bake takes 2.4 s instead of 1.8 s.

- Custom-shader bake hook (I7/A2): a shader can include `octa_bake_hook.gdshaderinc` and call `OCTA_BAKE_OUTPUT(...)` so the baker captures exact roughness, metallic, AO and emission. The same shiny/emissive test shader drops from 38.45% to 20.27% bad px at High. Shaders without the hook are unchanged (compat_test 0 differing pixels).
- Full sphere high preset (I5): HIGH quality, 17x17 views on a 2896 atlas with hemisphere off, at the same per-view size as the default. Below-view IoU Rock 0.92 -> 0.98, Tree 0.78 -> 0.97, Rings 0.70 -> 0.84; overall bad px -21% / -33% / -6%; about 2x video memory and bake time.
- Parallax refine (P4, option, off by default): `parallax_refine` gives Low and Medium the 3-sample depth parallax loop High uses, as a compile-time variant (`#define PARALLAX_REFINE`, cache key +32000). The 1-sample loop was under-converged: bad pixels at Medium Rock 13.13 -> 7.35%, Tree 10.22 -> 9.23%, Rings 29.29 -> 26.14%, and Low ends up slightly more accurate than High (Rock 6.98% vs 7.35%). Costs +3% GPU at Low and +9% at Medium (4,000 cards, shadows on). Off is the shipped shader. An over-relaxed first guess (1.6x) overshot badly and an early-out convergence test saved taps but cost High 1-3% accuracy, so plain extra samples ship.
- Pack atlases: `OctaPacker.pack(atlases, max_side)` copies the tiles of separately baked atlases into shared ones without re-baking, so cards of different objects share one material per quality and can be joined. The menu item "Pack Selected Atlases..." (and the dock button) packs the atlases of the selected cards, saves them next to the scene as `<scene>_packed.res` and re-points the cards in one undoable action. Atlases must agree on grid size, view size, padding, map presence and atlas options; the result splits into several atlases when the maximum atlas side is exceeded. Pixel copy verified tile-by-tile and by rendering (packed card vs original: 0.000/255).
- Chunk LOD (I3): `OctaImpostorGroup.chunk_lod_distance` (0 = off) adds a second, farther impostor tier. "Bake Group" then also bakes the whole group as one card (`<atlas>_chunk.res`, `group.chunk_atlas`), attaches it as `OctaChunk` with its visibility range starting at the chunk distance, and ends the object cards' ranges there, so real mesh -> object card -> chunk card is one chain with no gap or double draw. `attach_chunk()` / `detach_chunk()` / `chunk_settings()` are public and undoable. Measured on a 3-prop group at the switch distance: IoU 0.881 vs the real meshes (Forward+, Mobile, Compatibility), bad px 11.9%. The command line bakes the chunk card too.
- Chunk streaming (I4): `OctaChunkStreamer` (Node) loads packed chunk atlases on a worker thread (`ResourceLoader.load_threaded_request`) and uploads the instances in slices inside `budget_ms` per frame, so a chunk with thousands of instances never blocks one frame. `release()` frees the node and drops the atlas with its last user (`keep_atlases` shares one atlas between chunks), `loaded` / `failed` / `unloaded` signals, `is_loaded()`, `node_for()`, `release_all()`.

Tried and not shipped (v3, below the 5% gain rule)
- Stochastic view selection (P2): one of the three blended views per pixel, picked with probability equal to its coverage-weighted blend weight from a per-frame noise pattern, for TAA to average. Measured with a 16-frame temporal average on Rock High: bad px 4.20 -> 4.59%, MAE 6.51 -> 6.98 (7-9% worse), and the GPU got 16-22% slower (High 8.37 -> 10.21 ms, Ultra 15.67 -> 18.11 ms at 4,000 cards) because the per-pixel pick makes every warp run all three view bodies anyway. Removed.
- Visibility-aware view weighting (P3): fades non-Ultra views whose reprojected depth disagrees with the frontmost valid view. Off is identical; measured worse (bad px Rock high 7.35 -> 7.62%, Rings high 26.14 -> 30.74% near), so it stays an off-by-default option.
- Normal-buffer roughness capture for custom shaders without the hook (I7/A1): Forward+ only; it produced worse results (plain custom 2.91% -> 49.20% bad px), so it was reverted. Use the bake hook (A2) instead.
- Max-depth pyramid ray search (P1): a max-pooled coverage map skips empty intervals in the Ultra search. Off is identical; accuracy neutral (Rock 6.62 -> 6.61% bad px) and GPU +23%, so it stays off by default and the small-tile caveat is confirmed.

## 2.1.0 (2026-10-17)

New
- `OctaImpostorGroup` node: objects that share bake settings and one atlas, saved in the scene. Precedence: properties changed on a card > group settings > bake dialog. Works with Bake Group / Re-bake Group, Bake Scene (one item per group), Re-bake Selected and the command line baker (`--ignore-groups` treats groups as plain nodes).
- Re-bake now keeps the properties you changed on a card (quality, LOD, fade, tint, depth multiplier).
- Precise search option for Ultra (off by default): a coverage probe per ray search interval finds thin features more reliably. About 2-3x slower on the GPU (Ultra, 4000 cards: Forward+ 43 -> 129 ms, Mobile 25 -> 60 ms); bad pixels e.g. Tree 9.6 -> 6.2%, Rings 20.3 -> 18.0%.
- `shadow_views` setting (1-3, default 1) and a cheaper shadow pass: one view, 2 parallax steps, never the Ultra ray search. Shadow pass GPU (4000 cards, 4 cascades): Forward+ High -18%, Ultra -68%; Mobile Ultra -68%. Ground shadow match with the real mesh is equal or better (Ultra +2..8%).
- Atlas format 4: atlases whose materials are constant skip the ORM map (-33% VRAM on the test objects). Option for half-resolution material and emission maps, on by default (-75% on those maps, colour error about +2%; off in the High quality preset).
- Overdraw debug view (`OctaDebug.Mode.OVERDRAW`) and a card fill readout in `OctaDebugHUD`.
- `OctaCoverage` (also `atlas.card_coverage(index)`): measures how much of a card quad an object really covers.
- `OctaBakeQueue.cache_limit` (default 32): the atlas cache drops the least recently used atlas first.
- Bake dialog notes that roughness and metallic are averaged per object when material maps are off and an object's materials differ.
- Menu: Re-bake All Impostors in Scene (each atlas or group is re-baked with its own settings, overrides kept, undoable), Select Impostors in Scene, and a Help dialog with the menu, dock, options, debug views, CLI and queue. The dock has matching Re-bake All and Select All buttons.
- Impostors dock: the Atlas block shows format version, which maps exist, half-res, write depth, shadow views, precise search and video memory. The Group section explains how to add a group.
- The project setting `octa_lod/reference_fov` (10-120, default 75) is registered when the plugin is enabled, so it appears in Project Settings.
- Presets define every setting: depth write, fade, half-res maps, shadow views (High quality uses 2), search steps and precise search, so a preset gives the same result whatever was set before. Each preset has a tooltip with its choices. Presets still never touch the placement (mode, LOD mode, distances).
- Bake dialog settings are grouped as Placement, Quality, Complex shapes, Scene and joining, Atlas, Shadows, Advanced. Every exported property of the settings, the card, the queue and the HUD has a tooltip and a range.
- `OctaBakeQueue.shared(get_tree())` returns one queue under the root, so no autoload is needed.
- Command line: `--help` lists every option; every bake setting is a flag (`--grid-size=8`, `--precise-search`, `--shadow-views=2`, `--no-dedupe`, ...); unknown flags and invalid values print an error and exit 1.
- Demo (`demo/showcase.gd`): every plugin option is a key on both levels where it makes sense: quality F1-F4 (Ultra added), debug views D (all six), precise search P, write depth W, sun shadows S, shadow views V, sun spin R, auto LOD O (visibility range with crossfade on Forward+), join J (MultiMesh groups, Level 2), textured asset 4 (material maps, same atlas). Hot-swap, tint, UI toggles and the camera work on Level 1 too. A toast shows the result of each key, the analytics panel shows all toggle states, the card fill (`OctaDebugHUD`) and the join effect. HUD text updates at 8 Hz.

Fixed
- Joined (MultiMesh) cards used the tint colour as sRGB, so the colour differed from the single card. The depth multiplier of 0 is clamped for joined cards too.
- Undoing a re-bake no longer prints "Can't find visibility parent" errors or leaves renamed nodes.
- Re-bake of cards from different atlases used the settings of the last card for all of them; each atlas now keeps its own settings.
- Undoing a dock change of write depth, precise search or shadow views saved the atlas before the old value was restored, so the file kept the new value.
- The dock described precise search as 2x slower; it is 2-3x.
- Pressing Check Quality twice no longer starts a second measurement.
- `lod_distance` read before the card enters the scene tree returns the stored value.
- Bake setup is 57% faster for many identical meshes (shared vertex cache: 220 sources, 486 -> 207 ms).
- Demo: changing the asset or the quality on Level 2 rebuilt nothing (freed nodes were still counted as children) and left an empty field; the Level 1 labels came back after the UI had been hidden; the wave monitor printed raw BBCode; the instance uniform buffer overflowed above about 4100 cards (the prop limit is 4000 now).

Tests
- New: `demo_smoke_test` (drives every demo key on both levels on all three renderers, checks the state changes, auto LOD swap, join, benchmark stages, static layout and saves screenshots), `transform_test`, `pole_test`, `joined_depth_test`, `material_maps_test`, `compat_test` (old atlas files in `tests/fixtures`), `shadow_test`, `precise_test`, `overdraw_test`, `coverage_report`. `visual_test` gained far-view and edge metrics; `perf_test` gained shadow options. Editor self-test: 114 checks; `queue_test` covers `OctaBakeQueue.shared`; `cli_test.sh` covers `--help`, unknown flags, invalid values and the generic setting flags.

Notes
- The Compatibility colour difference (about 2x) was caused by shadows: Compatibility ignores `LIGHT_VERTEX`, so a card cannot shadow itself there while the real mesh does. With shadows off the colour error matches Forward+. The visual test turns shadows off on Compatibility.

Tried and not shipped (measured, below the 5% gain rule)
- Edge dilation of the atlas maps: edge colour error +4..9% worse on 2 of 3 objects, near accuracy worse.
- 2x supersampling at capture: bake time +47% to +154%, video memory x2, best accuracy gain 4.4%, some cases 8% worse.
- Edge alpha normalisation for High: 0.0 change in IoU and bad pixels at normal grid sizes.
- Self-shadow offset formulas (constant sweep, slope scaled): none beat the current 0.04 of the radius by 5% on all objects.
- Per-view mip gradients: -0.6..+2.0% colour error, no object better.
- Fitted card mesh: an 8-gon saves more than 25% of the card area only for trees (67%; rock 21%, rings 16%), so it stays a candidate for tall thin objects.
- Adaptive ray search as the default: 17-32% more accurate but +140..340% GPU, so it ships only as the opt-in Precise search.

Compatibility
- Atlases from 1.0 and 2.0 still load and render identically (checked pixel for pixel on Forward+, Mobile and Compatibility).

## 2.0.0 (2026-10-16)

Quality
- Ultra quality: ray search through the baked depth with layer rejection, clean on see-through and interlocking shapes (rings, frames).
- Split parts: bake each mesh of an object as its own card. Experimental back layer for thin parts.
- Per-pixel roughness, metallic and ambient occlusion maps, and emission maps (scaled by intensity), captured from the source materials.
- Up to 1024 objects per atlas (per-object data moved into a data texture).
- Compatibility renderer depth fix.

Workflow
- `OctaImpostor` node class with Inspector fields and tool buttons (Check Quality, Select Source, Edit Shared Look); per-card tint and depth.
- Bake dialog presets (Mobile, Balanced, High quality, Complex shapes), size and shader cost estimates, progress window with Cancel.
- Impostors dock for batch edits of quality, LOD, fade and depth, with undo.
- Bake Scene (checklist by on-screen size), dedupe of identical objects, Join into per-area MultiMeshes, optional Strip source, Re-bake.
- Check Quality: compares card and mesh from 8 angles and suggests a fix.

LOD
- LOD by distance or by on-screen size (reference field of view project setting `octa_lod/reference_fov`).
- Optional crossfade (Forward+ only; Mobile and Compatibility pop).
- Write depth toggle: flat card depth variant without `DEPTH` writes, cheaper on mobile.

Runtime and tools
- `OctaBakeQueue`: time-sliced runtime baking with a frame budget, jobs, cancellation and an atlas cache.
- Debug views (`OctaDebug`): tint by quality, view index, depth, material maps; zero cost when off. Dock dropdown and `OctaDebugHUD` stats overlay.
- Command line baker `tools/octa_bake_cli.gd`.

Fixes
- Check Quality reported 0% match for cards with screen-size LOD or fade: the checked copy re-applied its LOD distance when added to the scene and was culled. Its LOD and fade are now reset after it enters the tree.

Compatibility
- v1 atlases still load and render as before (atlas format version 1). Re-bake them to use the new options.

## 1.0.0

First release.

- Bake any 3D objects into octahedral impostors from the 3D editor toolbar (Octahedral Impostor LOD > Bake Selected...).
- Bake dialog with every option, tooltips and a size/memory estimate; options remembered per project.
- Dynamic LOD, Duplicate and Replace modes; re-baking replaces old cards; fully undoable.
- Low / Medium / High shader quality, per-pixel depth, shadows, MultiMesh support.
- Lossless or VRAM (Basis Universal) atlas compression.
- Demo scene and automated tests.
