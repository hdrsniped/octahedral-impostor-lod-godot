# Changelog

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
