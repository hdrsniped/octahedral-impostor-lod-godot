# Octahedral Impostor LOD for Godot 4 ( for now )

Bakes 3D objects into octahedral impostors: one camera-facing card per object, built from a grid of pre-rendered views blended with per-pixel depth and normals. Real mesh up close, card beyond a distance or below a screen size. Editor plugin plus a runtime API. Godot 4.7+.

What makes this different: on fast-moving games normal LOD fails to give good visuals. With this, racing games can enjoy it too. Long live optimization!

> Measured on a vega 7 windows system: 4,000 rocks as real meshes ~388 ms per frame; as High-quality impostors ~6 ms; as Low ~1 ms.

- Bake from the editor (selection or whole scene), undoable. Re-bake keeps the edits you made on a card.
- Cards are lit by your scene, cast shadows and intersect the ground (baked depth, normals, roughness, metallic, AO, emission).
- LOD by distance or on-screen size, optional crossfade on every renderer.
- Ultra quality and split parts for rings, frames and other see-through shapes.
- Join cards into MultiMeshes, time-sliced runtime baking, command line baker, debug views.
- Chunk LOD: one card for a whole group beyond a distance, and a streaming helper for packed chunk atlases. Pack separately baked atlases into shared ones without re-baking.

## Install

1. Download `octahedral-impostor-lod-godot-vX.Y.Z.zip` from [Releases](https://github.com/hdrsniped/octahedral-impostor-lod-godot/releases) and unzip it into your project (it holds `addons/octahedral_impostor_lod`).
2. Project > Project Settings > Plugins: enable **Octahedral Impostor LOD**.
3. A menu appears in the 3D toolbar and an **Impostors** dock on the right.

## Quick start

1. Open a 3D scene, select a node that contains a `MeshInstance3D` (or the mesh itself).
2. Octahedral Impostor LOD > **Bake Selected...**, pick a preset, press Bake.
3. The atlas lands in `res://octa_impostors/` and each object gets an `OctaImpostor` card. Undo works, or use **Remove Impostors from Selected**.

Other menu items: Bake Scene (checklist, small objects pre-ticked), Bake Group, Re-bake Selected / Re-bake All, Join Selected Impostors, Check Quality of Selected, Select Impostors in Scene, Help. Baking needs a real window, not `--headless`.

## Code

```gdscript
# Bake two objects into one atlas; each gets a card that takes over beyond 40 m.
var atlas := await OctaLOD.generate([rock, tree], self)

# Bake once, save, place copies later.
var settings := OctaBakeSettings.new()
settings.apply_preset(OctaBakeSettings.Preset.FAST)
var saved := await OctaBaker.bake_to_file([rock], self, "res://octa_impostors/rock.res", settings)
OctaLOD.attach_card(another_rock, saved, 0, OctaLOD.Mode.DYNAMIC_LOD, 40.0)
add_child(saved.create_multimesh(0, transforms))  # many copies, one draw call

# Merge separately baked atlases into shared ones (same grid and view size) so
# their cards share one material per quality and can be joined.
var shared := OctaPacker.pack([saved, other_saved], 4096)
```

Runtime baking within a frame budget, no autoload needed:

```gdscript
var job := OctaBakeQueue.shared(get_tree()).enqueue(generated_rock)
job.completed.connect(func(ok: bool) -> void: print(job.card))
```

Identical sources share a cached atlas (`cache_limit`, default 32, least recently used dropped first). Runtime atlases fall back from VRAM to lossless compression.

## Options that matter

| Option | What it does |
| --- | --- |
| Preset | Minimal (Low, 1024, no material maps, flat depth), Fast (High, 2048, half-res maps), Quality (High, 4096, full-res maps, 2 shadow views), Max (Ultra, precise search, split parts, back layer, 24 search steps, 3 shadow views, 8x MSAA). Sets everything except placement and hemisphere (Max pins hemisphere on). |
| Quality | Low: 1 view. Medium: 3 blended views. High: 3 views + depth parallax. Ultra: ray search through the baked depth, about 2x High. |
| Hemisphere | On (default): views from above and the side, twice the detail. Turn off for objects seen from below. |
| LOD mode | Distance (40 m default) or screen size (% of screen height, converted with `octa_lod/reference_fov`, default 75). |
| Fade | Crossfade works on all renderers: Godot's own dithered fade on Forward+, a stable screen-space dither in the card shader on Mobile and Compatibility. The band runs from LOD distance minus Fade Margin to LOD distance plus Fade Margin. |
| Fade real mesh | Mobile and Compatibility with Crossfade (on by default): the real mesh dithers out across the same band using shared material copies (your materials stay untouched, restored on Remove, re-bake, Fade None and before scene saves). Shader materials and materials with their own distance fade are skipped: the card fades in over them and the mesh switches off behind it. Joined MultiMesh groups can fade too (`create_multimesh(..., lod_distance, fade_margin)`) on Mobile and Compatibility. |
| Split parts / Back layer / Precise search | For complex shapes. Split bakes each mesh as its own card. Back layer (experimental) helps thin parts, +25% memory. Precise search is Ultra only and off by default. |
| Parallax refine | Off by default. Low and Medium get the same 3-sample depth parallax High uses (one depth sample per view is under-converged: at Medium up to 48% fewer wrong pixels, +3% GPU at Low, +9% at Medium). |
| Material maps / Half-res | Per-pixel roughness, metallic, AO, emission. Skipped when materials are constant. Half-res on by default. |
| Shadow views | 1 (default) to 3. More views = smoother shadow silhouette when the light moves, higher cost. |
| Wind | Off by default. A card's `wind_strength` (0-1, per card, dock row Wind, bake setting for new cards) sways the top of foliage downwind by up to 20% of the object radius while the base stays fixed. Done in texture space: no vertex displacement, no bigger bounds. Set the global direction and speed with `OctaWind.set_wind(direction, speed, gust, frequency)`. Atlases without a wind card keep the normal shader. Demo: [K]. |
| Write depth | On: real surface depth. Off: flat, cheaper on mobile, cards can clip into geometry. |
| Join | Merges nearby cards of one object into a MultiMesh, grouped by Join Cell (50 m default). Adaptive Join (off by default) also splits every cell into regions of at most Region Count instances and Region Size meters (median split) and orders the instances of each group along a Z-order (Morton) curve, so a group has a small bounding box and off-screen regions are skipped as a whole. It submits fewer off-screen instances but makes more MultiMeshes, which costs CPU (see Numbers). Every MultiMesh also uses a slot of Godot's instance-uniform buffer, so thousands of groups need a larger `rendering/limits/global_shader_variables/buffer_size` (the log says 'Too many instances using shader instance variables'). From code: `OctaAtlas.create_multimeshes(...)`, `OctaJoin.partition(...)`. Joined groups have no LOD distance: joining hides the real meshes and the impostors stay on at every distance (undo restores the meshes). |
| Groups | `OctaImpostorGroup` node: shared settings and one atlas for its targets. Priority: card edits > group > dialog. |
| Chunk LOD | On a group: set Chunk LOD Distance (0 = off). Bake/Re-bake Group then bakes one extra card of the whole group, saved as `<atlas>_chunk.res`, and the object cards stop at that distance, so a whole city block or prop cluster costs one card on the horizon (`group.chunk_card()`). Command line bakes it too. |
| Streaming | `OctaChunkStreamer` (Node, add it yourself): `request(key, atlas_path, transforms, object_index, quality)` loads the atlas on a worker thread and fills one instance buffer in slices inside `budget_ms` per frame (nothing is drawn until the chunk is complete), `release(key)` frees the chunk and drops the atlas with its last user, `keep_atlases` (default on) keeps a loaded atlas until `drop_atlases()`. Signals `loaded`, `failed`, `unloaded`. |
| Pack atlases | Menu "Pack Selected Atlases...", dock button or `OctaPacker.pack(atlases, max_side)`: merges separately baked atlases into shared ones without re-baking, so their cards share one material per quality (and can be joined). Atlases must agree on atlas format, grid size, view size, padding, maps and atlas options; the result splits into several atlases when the maximum side is exceeded. Cards are re-pointed in one undoable step. |
| Grid / Atlas size / Compression | Grid 12 (144 views), atlas 2048, Lossless or VRAM (about 4x smaller). |

Memory per atlas, colour + normal/depth: 1024 about 11 MB, 2048 about 45 MB, 4096 about 180 MB. A material map adds about 50% per full-res texture, 25% half-res, nothing for constant materials.

## Numbers

Measured on an AMD Radeon iGPU, 4,000 cards, no shadows unless stated.

- Ultra costs about 2x High. Precise search on top: 2-3x on Ultra (Forward+ 43 -> 129 ms, Mobile 25 -> 60 ms). Bad pixels vs the real mesh: Tree 9.6 -> 6.2%, Rings 20.3 -> 18.0%.
- Parallax refine (on, Low/Medium): GPU +3% at Low, +9% at Medium. Bad pixels Rock Medium 13.1 -> 7.4%, Tree 10.2 -> 9.2%, Rings 29.3 -> 26.1%; Low becomes slightly more accurate than High (Rock 6.98% vs 7.35%).
- Shadow pass (4 cascades): Forward+ High -18%, Ultra -68%; Mobile Ultra -68%.
- Constant materials skip the ORM map: -33% VRAM. Half-res maps on a fully textured object: -75% on those maps, colour error about +2%.
- Join, 1000 cards: Mobile 1396 -> 26 draw calls, Compatibility 1692 -> 47. Forward+ already batches identical cards, so only CPU time (1.3 -> 0.6 ms) and object count drop.
- Adaptive join, 20,000 cards over 4 x 4 km (3 objects, clustered, camera looking along the field): off-screen instances submitted 0% to -63% (e.g. 549 -> 300 of 8,311, Join Cell 100), MultiMeshes +12% to +300%, CPU +8% to +195% (Forward+ 1.28 -> 1.93 ms, Mobile 1.16 -> 1.57 ms), GPU unchanged to +24% (under 1.2 ms). That is why it is an option, off by default.
- Runtime queue, 1024 atlases: median frame cost 2-3 ms, worst 10-37 ms (the first atlas of a session builds its shaders).

## Renderers

| | Forward+ | Mobile | Compatibility |
| --- | --- | --- | --- |
| Low to Ultra, depth, shadows, material maps | Yes | Yes | Yes |
| Crossfade | Yes (native) | Yes (dither) | Yes (dither) |
| Card self-shadowing | Yes | Yes | No |

Compatibility ignores `LIGHT_VERTEX`, so cards cannot shadow themselves there (the real mesh does). They still cast and receive shadows. With shadows off, colours match Forward+.

## Limits

- Cards are images: soft when they fill much of the screen, flat from below with Hemisphere on.
- Bad fit: roads, terrain, walls, fences, animated parts (wheels, doors, characters), glass.
- Only `MeshInstance3D` is captured (no CSG, MultiMesh, particles). Skinned meshes bake in rest pose.
- A card next to a mesh (sibling) does not follow if you move the mesh later. Move both, or bake the parent.
- 1024 objects per atlas.

## Tools

- Check Quality of Selected renders mesh and card from 8 angles and reports shape match, worst view and wrong pixels.
- Debug views (`OctaDebug`, Impostors dock dropdown): tint by quality, view index, depth, material maps, overdraw. `OctaDebugHUD` shows stats on screen.
- CLI baker (needs a window), `--help` lists every flag:

```
godot --path <project> -s res://addons/octahedral_impostor_lod/tools/octa_bake_cli.gd -- --scene=res://x.tscn --nodes=Rock,Tree --preset=balanced --save-scene
```

- Demo: open this repo as a project and press Play. Level 2 is a field of props with real/impostor hot-swap (F), quality (F1-F4), debug views (D), join (J), auto LOD (O), wind on the tree (K) and a benchmark (B). A toggles the analytics panel.
- Tests: `bash tests/run_all.sh <godot>` (each test needs a window).

## Upgrading from 1.0 or 2.0

Existing atlases still load and render identically. Nothing to do. Re-bake old v1 cards to get `OctaImpostor` nodes and the new options.

## License

Free for personal and commercial use, credit required. Details in [LICENSE](LICENSE). Made by hdrsniped.
