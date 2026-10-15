# Changelog

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
