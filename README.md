# Octahedral Impostor LOD for Godot 4 ( for now )

Turn heavy 3D objects into lightweight **octahedral impostors**: one flat, camera-facing
card per object that looks like the real model from any angle. Up close you see
the real mesh; farther away the card takes over automatically. A whole forest of
30,000-triangle rocks becomes 2 triangles per rock in the distance.

- **One click in the editor**: select objects, *Octahedral Impostor LOD > Bake Selected...*, done. Or bake a whole scene with a checklist.
- **Automatic LOD switching** with Godot's built-in visibility ranges, by distance or by on-screen size, with optional crossfade.
- **Looks 3D**: baked views blended with per-pixel depth, normals, roughness, metallic, ambient occlusion and emission, so cards are lit by your scene, cast shadows and intersect the ground correctly.
- **Ultra quality** for rings, frames, gyroscopes and other see-through or interlocking shapes.
- **Batches well**: every card from one atlas shares a single material; join nearby cards into a MultiMesh.
- **Runtime baking** without hitches (time-sliced queue), a **command line baker** for build pipelines, and a **debug overlay**.
- **Fully undoable**, works with Forward+, Mobile and Compatibility renderers.

> Measured on a vega 7 windows system: 4,000 rocks as real meshes ~388 ms per frame;
> as High-quality impostors ~6 ms; as Low ~1 ms.

## When to use it

what makes this different?: normally, on a fast moving games the LOD failed to deliver a good visual; with this racing games can enjoy it too, long live optimization!

| Good fit | Poor fit |
| --- | --- |
| Rocks, trees, bushes, props, buildings, parked cars, crowds of static things | Anything the camera gets very close to (it looks soft) |
| Things repeated many times | Animated or moving parts (wheels, doors, characters) |
| Distant landmarks and background ships | Long, flat things: roads, terrain, walls, fences |
| Mobile games that need far scenery cheaply | Glass or see-through materials |

## Install

1. Download the latest `octahedral-impostor-lod-godot-vX.Y.Z.zip` from the
   [Releases](https://github.com/hdrsniped/octahedral-impostor-lod-godot/releases) page.
2. Unzip it into your Godot project folder. It contains the
   `addons/octahedral_impostor_lod` folder.
3. *Project > Project Settings > Plugins*: enable **Octahedral Impostor LOD**.
4. An **Octahedral Impostor LOD** menu appears in the 3D editor's toolbar, and an **Impostors** dock on the right.

Requires Godot **4.7** or newer.

## Use it in the editor

1. Open a 3D scene and select one or more objects (a node that contains
   `MeshInstance3D` nodes, or a `MeshInstance3D` itself).
2. *Octahedral Impostor LOD > Bake Selected...*. Pick a **Preset**, adjust anything you like (every option has a tooltip), and read the size / shader cost estimate.
3. Press **Bake**. A progress window with **Cancel** appears. The atlas is saved to `res://octa_impostors/` and each object gets an `OctaImpostor` card:
   - a child named `OctaImpostor` when you selected a parent node,
   - a sibling named `<Object>_OctaImpostor` when you selected a mesh directly.
4. To undo: *Edit > Undo*, or select the object (or its card) and use
   *Octahedral Impostor LOD > Remove Impostors from Selected*.

Baking several objects at once puts them all in one atlas and one material,
which is faster to draw than separate bakes.

### Menu and dock

| Action | What it does |
| --- | --- |
| **Bake Selected...** | Bakes the selected objects with the dialog settings. |
| **Bake Scene...** | Lists every object in the scene with its on-screen size at the LOD distance; small ones are pre-ticked. Tick what to bake. |
| **Remove Impostors from Selected** | Deletes cards and restores links / visibility. |
| **Join Selected Impostors** | Merges nearby cards of the same object into one MultiMesh (one draw call), grouped in squares of *Join Cell* meters so off-screen groups can be skipped. The real objects are hidden. Undoable. |
| **Re-bake Selected Impostors** | Bakes again with the settings stored in the atlas. |
| **Check Quality of Selected** | Renders the real mesh and the card from 8 angles and reports shape match, worst view and wrong pixels with a suggestion. |
| **Impostors dock** | Batch-edit selected cards (quality, LOD, fade, write depth), edit the shared look, see atlas info and VRAM, pick the debug view. |

`OctaImpostor` is a node class: select a card to edit atlas, quality, LOD distance or screen size, fade, per-card tint and depth in the Inspector.

### Presets

| Preset | Quality | Atlas | Compression | Notes |
| --- | --- | --- | --- | --- |
| Mobile | Low | 1024 | VRAM | Flat depth (no depth write), 10x10 views |
| Balanced | Medium | 2048 | VRAM | 12x12 views |
| High quality | High | 4096 | Lossless | 16x16 views, crossfade |
| Complex shapes | Ultra | 2048 | Lossless | Split parts + back layer |

### Modes

| Mode | What happens |
| --- | --- |
| **Dynamic LOD** (default) | Real mesh up close, card beyond the LOD distance. |
| **Duplicate** | Card added next to the object; the object is untouched. |
| **Replace** | Card added and the object hidden. Optionally **Strip source** deletes the real object (undo brings it back). Ship only the card. |

### Features

- **Quality**: Low = 1 view, Medium = 3 blended views, High = 3 views + depth parallax, **Ultra** = ray search through the baked depth with layer rejection (about 2x the cost of High).
- **Split parts**: bake every mesh of an object as its own card, in the parent's orientation. Fixes most see-through and interlocking shapes.
- **Back layer** (experimental): also stores where each surface ends so Ultra can see through gaps behind thin parts. +25% memory.
- **Material and emission maps**: roughness, metallic and ambient occlusion are captured per pixel; emission is captured (times its intensity) when something glows.
- **LOD by distance or screen size**: *Screen size* converts a share of the screen height into a distance for each object using the reference field of view (project setting `octa_lod/reference_fov`, default 75).
- **Fade** (Forward+ only): dithered crossfade between mesh and card over *Fade Margin* meters. Mobile and Compatibility pop, because Godot does not fade there. Ignored in Replace mode.
- **Write depth**: cards write their real surface depth by default. Turn it off for flat card depth (cheaper on mobile); cards can then intersect their surroundings.
- **Dedupe**: identical objects (same meshes, materials, relative transforms) share one atlas entry.
- **Per-card look**: tint and depth multiplier per card; the shared tint, normal strength and depth are on the material.

## Use it from code

```gdscript
# Bake two objects into one atlas and give each a card that takes over beyond 40 m.
var atlas := await OctaLOD.generate([rock, tree], self)

# Or bake once, save, and place many copies later.
var settings := OctaBakeSettings.new()
settings.apply_preset(OctaBakeSettings.Preset.BALANCED)
var atlas := await OctaBaker.bake_to_file([rock], self, "res://octa_impostors/rock.res", settings)
OctaLOD.attach_card(another_rock, atlas, 0, OctaLOD.Mode.DYNAMIC_LOD, 40.0)

# Thousands of copies in one draw call.
add_child(atlas.create_multimesh(0, transforms))

# Undo a card.
OctaLOD.remove_cards(another_rock)
```

Baking needs a real renderer, so it does not run with `--headless`.

### Runtime bake queue

`OctaBakeQueue` is a `Node` (add it as an autoload or child) that bakes at runtime within a time budget so the game does not hitch:

```gdscript
var queue := OctaBakeQueue.new()
queue.budget_ms = 2.0
queue.max_views_per_frame = 8
add_child(queue)
var job := queue.enqueue(generated_rock)
job.completed.connect(func(ok: bool) -> void: print(job.card))
```

`enqueue(source, settings = null, save_path = "")` returns an `OctaBakeJob` (`completed(success)`, `atlas`, `card`, `cancel()`). Identical sources share a cached atlas (`clear_cache()` to drop it). Signals `baked` and `finished`. Runtime atlases cannot use VRAM compression (they fall back to lossless). Measured with 1024 atlases: median frame cost about 2-3 ms, worst frames 10-37 ms (one texture upload or shader compile per atlas).

### Debug view and HUD

```gdscript
OctaDebug.set_mode(OctaDebug.Mode.TINT_BY_LOD)
```

| Mode | Shows |
| --- | --- |
| `OFF` | Normal rendering. No extra shader cost: the normal shaders are used. |
| `TINT_BY_LOD` | Cards tinted by quality (Low red, Medium orange, High green, Ultra cyan); real meshes stay normal. |
| `VIEW_INDEX` | A colour per baked view, to see which tile is used and where views change. |
| `DEPTH` | The baked depth as grey (white = toward the camera). |
| `ORM` | Roughness (green) and metallic (blue) / ambient occlusion (red) maps, unlit. |

Each mode is a shader variant (a compile-time define), so the switch affects every atlas at once. The same dropdown is in the Impostors dock. Add an `OctaDebugHUD` node (a `Control`) to your UI for on-screen stats: card count, impostors drawn versus real meshes, atlases and estimated video memory. Set its `cycle_key` to step through the debug views while running; `scan()` returns the numbers as a Dictionary.

## Command line baking

Bake a scene in a build pipeline or without opening the editor (needs a window, not `--headless`):

```
godot --path <project> -s res://addons/octahedral_impostor_lod/tools/octa_bake_cli.gd -- --scene=res://x.tscn --nodes=Rock,Tree --preset=balanced --out=res://impostors/ --save-scene
```

| Option | Meaning |
| --- | --- |
| `--scene=` | Scene to load (required). |
| `--nodes=a,b` | Nodes to bake, by path or name. Omit it to bake everything small on screen (as Bake Scene pre-ticks). |
| `--preset=` | `mobile`, `balanced`, `high_quality` or `complex_shapes`. |
| `--out=` | Atlas folder. |
| `--save-scene` | Write the cards back into the scene file. |
| `--mode=`, `--quality=`, `--atlas-size=`, `--lod-distance=` | Override single settings. |
| `--split-parts`, `--no-dedupe`, `--strip-source` | Switches. |

It prints a summary and exits with a non-zero code on any failure (missing scene or node, bake error, save error).

## Settings

| Setting | Default | What it does |
| --- | --- | --- |
| Mode | Dynamic LOD | See *Modes* above. |
| LOD Mode / Distance / Screen % | Distance, 40 m, 5% | Where the card replaces the real mesh. |
| Fade / Fade Margin | None, 5 m | Crossfade (Forward+ only). |
| Write Depth | On | Real surface depth; off = flat, cheaper. |
| Quality | High | Low, Medium, High, Ultra. |
| Split Parts / Back Layer | Off | Complex shapes. |
| Grid Size | 12 | Views per side (144 views). More = smoother turning, less detail per view. |
| Hemisphere | On | Only views from above and the side: twice the detail. **Turn off** for objects seen from below. |
| Max Atlas Size | 2048 | Atlas width in pixels. Bigger = sharper and more memory. |
| Material Maps / Emission | On | Per-pixel roughness, metallic, AO and emission. |
| Compression | Lossless | **VRAM** uses ~4x less video memory (good for mobile), slightly softer. |
| Dedupe | On | Share one atlas entry between identical objects. |
| Output Dir | `res://octa_impostors` | Where atlases are saved. |

Detail per view = *Max Atlas Size* / (objects per row x *Grid Size*).
Memory per atlas (colour + normal/depth): 1024 about 11 MB, 2048 about 45 MB, 4096 about 180 MB; material maps add about 50% per extra texture, VRAM compression divides by about 4.

## Renderer support

| Feature | Forward+ | Mobile | Compatibility |
| --- | --- | --- | --- |
| Low / Medium / High / Ultra | Yes | Yes | Yes |
| Per-pixel depth, shadows | Yes | Yes | Yes |
| Material and emission maps | Yes | Yes | Yes |
| Crossfade fade | Yes | No (pops) | No (pops) |
| Write depth off | Yes | Yes | Yes |
| Debug views, runtime queue, CLI | Yes | Yes | Yes |

Known: the Compatibility renderer shows a lighting offset against Forward+ (also in v1.0).

## Migrating from v1

- v1 atlases (`.res` files) still load and render exactly as before. Their cards are plain `MeshInstance3D` nodes; the dock says "re-bake them to edit them here". Re-bake to get `OctaImpostor` nodes, Ultra, material maps and the new options.
- The API is unchanged: `OctaLOD.generate`, `attach_card`, `remove_cards`, `OctaBaker.bake`, `bake_to_file`, `atlas.create_multimesh` still work. `create_card` now returns an `OctaImpostor`.
- Limits grew from 256 to 1024 objects per atlas.
- *Strip source* is off by default; Replace mode only hides the real object unless you ask.

## Check that it works (no 3D knowledge needed)

1. Open this repository's folder as a project in Godot 4.7 and press **Play** (F5).
   The demo bakes a few objects and fills a field with 400 of them.
2. Fly around: hold the right mouse button to look, `W A S D` to move, `Shift` to go fast.
3. Press **T**: every impostor turns red. Near objects stay normal (real meshes),
   far ones are red (cards). Walk toward a red object: it turns normal at 40 m.
4. Press **F** to turn impostors off and watch *triangles drawn* jump into the
   millions and FPS drop; press **F** again to turn them back on.
5. Press **1**, **2**, **3** to compare Low, Medium and High quality.

Automated tests live in `tests/`: `bash tests/run_all.sh <godot>` runs them all; each needs a window.

## Limits

- Cards are images: they look soft when they fill a large part of the screen.
- No transparency or animation; glass is not captured. Skinned meshes are captured in their rest pose.
- Only `MeshInstance3D` nodes are captured (not CSG, MultiMesh or particles).
- A card placed next to a mesh (sibling) does not follow if you move the mesh
  later. Move both, or bake the mesh's parent node instead.
- Up to 1024 objects per atlas.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| The menu isn't in the toolbar | Enable the plugin and open a **3D** scene. |
| "has no visible mesh to bake" | Select the node that contains the `MeshInstance3D`, and make sure it is visible. |
| Objects look wrong from below | Re-bake with *Hemisphere* off. |
| See-through shapes look wrong | Use the *Complex shapes* preset (Ultra + split parts). |
| Cards look blurry | Raise *Max Atlas Size*, lower *Grid Size*, or bake fewer objects per atlas. |
| Cards pop in too close | Increase the LOD distance, or use fade on Forward+. |
| Cards intersect other geometry | Turn *Write Depth* on. |

## License and credit

Free for private and commercial use. **Credit is required** Full terms in [LICENSE](LICENSE).

Made by **hdrsniped**.

## Background

*Impostors* are a classic real-time graphics technique: distant geometry is
replaced by a textured image of itself. *Octahedral impostors* store many views
of an object on an octahedron, so the image matches the object from any
direction. This plugin is an independent Godot implementation of that technique
with automatic LOD switching.
