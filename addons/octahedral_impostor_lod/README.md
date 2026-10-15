# Octahedral Impostor LOD

Octahedral impostor LOD for Godot 4, by hdrsniped.

Bake 3D objects into lightweight camera-facing cards that replace the real mesh
at a distance.

1. Enable the plugin: *Project > Project Settings > Plugins > Octahedral Impostor LOD*.
2. In a 3D scene, select objects and choose *Octahedral Impostor LOD > Bake Selected...* in the 3D toolbar (or *Bake Scene...* to pick from a checklist).
3. Pick a preset and options in the dialog (hover any option for help) and press **Bake**.

Undo with *Edit > Undo* or *Octahedral Impostor LOD > Remove Impostors from Selected*.
The **Impostors** dock edits selected cards in bulk and holds the debug view dropdown.

From code:

```gdscript
var atlas := await OctaLOD.generate([rock, tree], self)
```

Also included: `OctaBakeQueue` (runtime baking within a frame budget), `OctaDebug` and
`OctaDebugHUD` (debug views and stats), and a command line baker:

```
godot --path <project> -s res://addons/octahedral_impostor_lod/tools/octa_bake_cli.gd -- --scene=res://x.tscn --preset=balanced --save-scene
```

Full documentation (features, renderer support, migration from v1), demo and tests: see the project's main README.
Made by hdrsniped. Free for private and commercial use with credit to hdrsniped (see LICENSE in this folder).
