# Octahedral Impostor LOD for Godot 4

Bakes 3D objects into octahedral impostors: one camera-facing card per object, drawn from a grid of pre-rendered views blended with per-pixel depth and normals. Real mesh up close, card beyond a distance or below a screen size. Built for scenes where ordinary LOD fails to hold up, such as fast-moving racing games. Editor plugin and runtime API, Godot 4.7+.

## Features

- Editor baking from a selection, a group or a whole scene, with presets, undo and quality check.
- Lit cards: baked depth, normals, roughness, metallic, AO and emission; cards cast shadows and intersect the ground.
- LOD by distance or screen size, with crossfade on Forward+, Mobile and Compatibility.
- Four quality levels, up to a depth ray search for rings, frames and other see-through shapes.
- Join into MultiMeshes, atlas packing, chunk LOD (one card per group on the horizon) and chunk streaming.
- Time-sliced runtime baking, command-line baker, far-field wind for foliage, debug views.

## Data

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
