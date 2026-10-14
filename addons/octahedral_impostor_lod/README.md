# Octahedral Impostor LOD

Bake 3D objects into lightweight camera-facing cards that replace the real mesh
at a distance.

1. Enable the plugin: *Project > Project Settings > Plugins > Octahedral Impostor LOD*.
2. In a 3D scene, select objects and choose *Octahedral Impostor LOD > Bake Selected...* in the 3D toolbar.
3. Pick options in the dialog (hover any option for help) and press **Bake**.

Undo with *Edit > Undo* or *Octahedral Impostor LOD > Remove Impostors from Selected*.

From code:

```gdscript
var atlas := await OctaLOD.generate([rock, tree], self)
```

Full documentation, demo and tests: see the project's main README.
Made by hdrsniped. Free for private and commercial use with credit to hdrsniped (see LICENSE in this folder).
