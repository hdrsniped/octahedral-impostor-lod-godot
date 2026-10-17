# Octahedral Impostor LOD for Godot 4

Bakes 3D objects into camera-facing octahedral impostor cards that replace the real mesh at a distance. Godot 4.7+. Made by hdrsniped.

## Quick start

1. Enable the plugin: Project > Project Settings > Plugins > Octahedral Impostor LOD.
2. In a 3D scene, select objects and choose Octahedral Impostor LOD > Bake Selected... in the 3D toolbar (Bake Scene... gives a checklist).
3. Pick a preset and press Bake. Undo with Edit > Undo or Remove Impostors from Selected.

The Impostors dock edits selected cards in bulk and holds the debug view dropdown. An `OctaImpostorGroup` node bakes several objects with settings saved in the scene.

## Code

```gdscript
var atlas := await OctaLOD.generate([rock, tree], self)
var job := OctaBakeQueue.shared(get_tree()).enqueue(generated_rock)
```

## Command line

```
godot --path <project> -s res://addons/octahedral_impostor_lod/tools/octa_bake_cli.gd -- --scene=res://x.tscn --preset=balanced --save-scene
```

`--help` lists every option. Baking needs a window, not `--headless`.

Full documentation, renderer support, numbers and the demo: https://github.com/hdrsniped/octahedral-impostor-lod-godot

Free for personal and commercial use, credit required (see LICENSE in this folder).
