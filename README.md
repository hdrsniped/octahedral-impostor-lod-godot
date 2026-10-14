# Octahedral Impostor LOD for Godot 4

Turn heavy 3D objects into lightweight **octahedral impostors**: one flat, camera-facing
card per object that looks like the real model from any angle. Up close you see
the real mesh; farther away the card takes over automatically. A whole forest of
30,000-triangle rocks becomes 2 triangles per rock in the distance.

- **One click in the editor**: select objects, *Octahedral Impostor LOD > Bake Selected...*, done.
- **Automatic LOD switching** with Godot's built-in visibility ranges (no script per frame).
- **Looks 3D**: 144 baked views per object, blended, with per-pixel depth and normals,
  so cards are lit by your scene, cast shadows and intersect the ground correctly.
- **Batches well**: every card from one atlas shares a single material; MultiMesh supported.
- **Fully undoable**, works with Forward+ and Mobile renderers.

> Measured on a laptop iGPU: 4,000 rocks as real meshes ~388 ms per frame;
> as High-quality impostors ~6 ms; as Low ~1 ms.

## When to use it

| Good fit | Poor fit |
| --- | --- |
| Rocks, trees, bushes, props, buildings, parked cars, crowds of static things | Anything the camera gets very close to (it looks soft) |
| Things repeated many times | Animated or moving parts (wheels, doors, characters) |
| Distant landmarks and background ships | Long, flat things: roads, terrain, walls, fences |
| Mobile games that need far scenery cheaply | Glass, glowing (emissive) or see-through materials |

## Install

1. Download the latest `octahedral-impostor-lod-godot-vX.Y.Z.zip` from the
   [Releases](https://github.com/hdrsniped/octahedral-impostor-lod-godot/releases) page.
2. Unzip it into your Godot project folder. It contains the
   `addons/octahedral_impostor_lod` folder.
3. *Project > Project Settings > Plugins*: enable **Octahedral Impostor LOD**.
4. An **Octahedral Impostor LOD** menu appears in the 3D editor's toolbar.

Requires Godot **4.7** or newer.

## Use it in the editor

1. Open a 3D scene and select one or more objects (a node that contains
   `MeshInstance3D` nodes, or a `MeshInstance3D` itself).
2. *Octahedral Impostor LOD > Bake Selected...*. A dialog shows every option with a tooltip
   and an estimate of the atlas size and video memory.
3. Press **Bake**. The atlas is saved to `res://octa_impostors/` and each object gets a card:
   - a child named `OctaImpostor` when you selected a parent node,
   - a sibling named `<Object>_OctaImpostor` when you selected a mesh directly.
4. To undo: *Edit > Undo*, or select the object (or its card) and use
   *Octahedral Impostor LOD > Remove Impostors from Selected*.

Baking several objects at once puts them all in one atlas and one material,
which is faster to draw than separate bakes.

### Modes

| Mode | What happens |
| --- | --- |
| **Dynamic LOD** (default) | Real mesh up close, card beyond *LOD Distance*. |
| **Duplicate** | Card added next to the object; the object is untouched. |
| **Replace** | Card added and the object hidden. Ship only the card. |

## Use it from code

```gdscript
# Bake two objects into one atlas and give each a card that takes over beyond 40 m.
var atlas := await OctaLOD.generate([rock, tree], self)

# Or bake once, save, and place many copies later.
var settings := OctaBakeSettings.new()
settings.max_atlas_size = 1024
var atlas := await OctaBaker.bake_to_file([rock], self, "res://octa_impostors/rock.res", settings)
OctaLOD.attach_card(another_rock, atlas, 0, OctaLOD.Mode.DYNAMIC_LOD, 40.0)

# Thousands of copies in one draw call.
add_child(atlas.create_multimesh(0, transforms))

# Undo a card.
OctaLOD.remove_cards(another_rock)
```

Baking needs a real renderer, so it does not run with `--headless`.

## Settings

| Setting | Default | What it does |
| --- | --- | --- |
| Mode | Dynamic LOD | See *Modes* above. |
| LOD Distance | 40 m | Where the card replaces the real mesh. |
| Quality | High | Low = 1 view (fastest), Medium = 3 blended views, High = 3 views + depth parallax. |
| Grid Size | 12 | Views per side (144 views). More = smoother turning, less detail per view. |
| Hemisphere | On | Only views from above and the side: twice the detail. **Turn off** for objects seen from below. |
| Max Atlas Size | 2048 | Atlas width in pixels. Bigger = sharper and more memory. |
| Compression | Lossless | **VRAM** uses ~4x less video memory (good for mobile), slightly softer. |
| Output Dir | `res://octa_impostors` | Where atlases are saved. |

Detail per view = *Max Atlas Size* / (objects per row x *Grid Size*).
One object at 2048 gets about 170 px per view; video memory is about 45 MB
(about 11 MB with VRAM compression).

## Check that it works (no 3D knowledge needed)

1. Open this repository's folder as a project in Godot 4.7 and press **Play** (F5).
   The demo bakes a few objects and fills a field with 400 of them.
2. Fly around: hold the right mouse button to look, `W A S D` to move, `Shift` to go fast.
3. Press **T**: every impostor turns red. Near objects stay normal (real meshes),
   far ones are red (cards). Walk toward a red object: it turns normal at 40 m.
4. Press **F** to turn impostors off and watch *triangles drawn* jump into the
   millions and FPS drop; press **F** again to turn them back on.
5. Press **1**, **2**, **3** to compare Low, Medium and High quality.

Automated tests live in `tests/` (see the comments at the top of each file).

## Limits

- Cards are images: they look soft when they fill a large part of the screen.
- Lighting is approximate: one roughness and metallic value per object, no
  emission, no transparency, no animation.
- Only `MeshInstance3D` nodes are captured (not CSG, MultiMesh or particles);
  skinned meshes are captured in their rest pose.
- A card placed next to a mesh (sibling) does not follow if you move the mesh
  later. Move both, or bake the mesh's parent node instead.
- Up to 256 objects per atlas.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| The menu isn't in the toolbar | Enable the plugin and open a **3D** scene. |
| "has no visible mesh to bake" | Select the node that contains the `MeshInstance3D`, and make sure it is visible. |
| Objects look wrong from below | Re-bake with *Hemisphere* off. |
| Cards look blurry | Raise *Max Atlas Size*, lower *Grid Size*, or bake fewer objects per atlas. |
| Cards pop in too close | Increase *LOD Distance* and re-bake (or set `visibility_range_begin` on the card). |
| Old atlases stopped loading after an update | Re-bake them. |

## License and credit

Free for private and commercial use. **Credit is required**: any game or product
that uses this plugin must credit **hdrsniped** as the author of Octahedral
Impostor LOD (for example in its credits screen or documentation).
Full terms in [LICENSE](LICENSE).

Made by **hdrsniped**.

## Background

*Impostors* are a classic real-time graphics technique: distant geometry is
replaced by a textured image of itself. *Octahedral impostors* store many views
of an object on an octahedron, so the image matches the object from any
direction. This plugin is an independent Godot implementation of that technique
with automatic LOD switching.
