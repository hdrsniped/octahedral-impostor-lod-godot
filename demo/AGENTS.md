# demo — DOX

## Purpose
`showcase.gd` (the playable demo, main scene of the project), `bake_showcase.tscn` (the editor bake sandbox: primitives, a two-part mushroom, a torus and an `OctaImpostorGroup`, all with materials and a camera) and `demo_objects.gd` (the procedural test objects: rock, tree, rings, textured, custom, custom_shiny, custom_hooked). The demo exists to demonstrate every plugin option on screen and it is the subject of `tests/demo_smoke_test.gd`.

## Ownership
- Maintainer.

## Local Contracts
- UI is rectangular only (no rounded corners), with fixed-width stats columns. The Difference column colours: green is good, red is bad; FPS and props are "higher is better", GPU/CPU/triangles/draw calls/VRAM are "lower is better". The bottom bar is static. No comments in demo files.
- Hemisphere is ON by default (plugin and demo). Impostors are not captured from below unless the user turns it off (`hemisphere = false`).
- Key map (both levels where it makes sense): `F1-F4` quality, `D` debug view, `P` precise search, `W` write depth, `S` sun shadows, `V` shadow views, `R` sun spin, `O` auto LOD, `J` join, `K` wind, `C` chunk LOD demo (an `OctaImpostorGroup` with three props and a 24 m chunk card; pressing `C` again removes it), `T` tint, `A` auto-rotate, `H` hide UI, `G` grid/stats, `Space` pause, wheel camera. Every key shows a toast; the analytics panel shows the toggle states and the card fill. There is no pack-atlas key: the demo's main atlas and a chunk atlas are deliberately incompatible (different settings/maps), so the packer cannot be shown cheaply.
- Prop limit is 4000 (Godot's default instance-uniform buffer holds about 4100 cards; 5000 spams errors). Do not raise it without raising `rendering/limits/global_shader_variables/buffer_size`, which made card creation 3x slower when tested.
- The demo bakes at startup with `batch_size = 8` (Compatibility peak memory 4173 -> 1784 MB); keep it.
- `demo_objects.gd` objects are shared with the tests; changing a mesh or material changes every recorded accuracy number in the design notes. Prefer adding a new object over changing an existing one.

## Work Guidance
- New feature: add a key + toast + HUD row + help-bar entry, then extend `tests/demo_smoke_test.gd` with a check for the key (state change and, where it is visual, a screenshot assertion).
- HUD text updates at 8 Hz, the wave monitor at 25 Hz, the debug scan every 1 s (amortised by prop count). No per-frame allocations in `_process`.
- The benchmark (key `B`) turns join and auto LOD off first and ignores the keys that would change the scene while it runs.
- Do not hide the loading layer before the atlas is non-null; a failed bake shows "The impostor atlas could not be baked." and retries once.

## Verification
- `godot --path . --resolution 1920x1080 -s res://tests/demo_smoke_test.gd -- --shots=<dir>` (add `--rendering-method mobile|gl_compatibility` for the others). Expect `RESULT PASS`; it drives every key on both levels, checks the state changes, the auto-LOD swap on screen, the join MultiMesh, the benchmark stages, the static layout and saves 4 screenshots.
- The Compatibility run is the flakiest: it can hit a draw stall at startup (environmental). Re-run once before reporting a failure as a regression.
