# Octahedral Impostor LOD Addon for Godot 4

Bakes 3D objects into octahedral impostors: one camera-facing card per object, drawn from a grid of pre-rendered views blended with per-pixel depth and normals. Real mesh up close, card beyond a distance or below a screen size. Built for scenes where ordinary LOD fails to hold up, such as fast-moving racing games. Editor plugin and runtime API, Godot 4.7+.

## Quick Features
- Editor baking from a selection, a group or a whole scene, with presets, undo and quality check.
- Lit cards: baked depth, normals, roughness, metallic, AO and emission; cards cast shadows and intersect the ground.
- LOD by distance or screen size, with crossfade on Forward+, Mobile and Compatibility.
- Four quality levels, up to a depth ray search for rings, frames and other see-through shapes.
- Join into MultiMeshes, atlas packing, chunk LOD (one card per group on the horizon) and chunk streaming.
- Time-sliced runtime baking, command-line baker, far-field wind for foliage, debug views.

## Explanation
I made this addon because most other addon are either old or very basic, I think It has potential to be more than what it seems.
Firstly it's basically converting 3d object with many polygons into just one plane but preserving the 3d look from series of 2d images.
| Older addon | Octahedral Impostor LOD |
| --- | --- |
| Colour atlas | Colour, normal, depth, roughness, metallic, AO, emission atlases ( basically looks almost like the real 3d except upclose ) |
| Just black if seeing from below | Virtually full sphere view, the bottom view is not as good as other angle but looks so much better from afar then not having it(make sure to turn it on it's off by default) |
| Nothing affects it | Affected by these: Light, shadow |
| Static | Tree can sways, while keeping all features.(there might be othere use of this) |
| Flat card | Writes per-pixel depth, intersects the ground |
| Single parallax step | Ray search through baked depth with layer rejection |
| Basic crossfade | Smooth crossfade with full compatibility on Forward+, Mobile and Compatibility |


|Spesific Features|
| --- |
| Automatic swap by distance or screen size |
|Bake selection, whole scene (checklist) or group |
| Quick preset: Minimal, Fast, Quality, Max |
| Undoable bakes, re-bake keeps per-card edits |
| Precise search for thin parts |
| Back layer for thin geometry |
 | Split parts (each mesh its own card) |
 | Parallax refine for Low and Medium |
 | Half-resolution material maps |
 | Constant materials skip the material map |
 | Custom-shader material capture |
 | Shadow pass with light-chosen view, 1-3 shadow views |
 | Write-depth toggle |
 | Far-field wind in texture space |
 | Per-card tint and depth multiplier |
 | Join into MultiMesh |
 | Adaptive regional join with Morton ordering |
| Atlas packing without re-baking |
 | Chunk LOD (one card per group on the horizon) |
 | Chunk streaming with frame budget |
 | Time-sliced runtime bake queue with atlas cache |
 | Dedupe of identical objects |
 | Group node with saved settings and precedence |
 | Check Quality: 8-angle comparison against the real mesh |
 | Debug views: quality tint, view index, depth, material, overdraw |
 | On-screen stats HUD with card fill |
 | Coverage measurement tool |
 | Command-line baker |
 | Memory and cost estimates with option warnings |
 | Impostors dock with batch edits |
 | 1024 objects per atlas |
 | Old atlases load and render identically |




## Performance

The addon contains 4 preset included, but all options are fully customizable.

Vega 7 iGPU, Windows, 4,000 rocks:

| | Frame time |
| --- | --- |
| Real meshes | ~388 ms |
| High impostors | ~6 ms |
| Low impostors | ~1 ms |

- Ultra costs about 2x High; precise search 2-3x Ultra.
- Shadow pass: -18% at High, -68% at Ultra.
- Join, 1,000 cards: 1,396 -> 26 draw calls on Mobile, 1,692 -> 47 on Compatibility.
- Constant materials skip the material map: -33% video memory. Half-res maps: -75% on those maps.
- Atlas memory: 1024 ~11 MB, 2048 ~45 MB, 4096 ~180 MB.

## Limits

- Soft when a card fills much of the screen; flat from below unless full sphere is on.
- Poor fit for roads, terrain, walls, animated parts and glass.
- Captures `MeshInstance3D` only. 1,024 objects per atlas.
