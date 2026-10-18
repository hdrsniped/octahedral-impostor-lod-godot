# addons/octahedral_impostor_lod/tools — DOX

## Purpose
`octa_bake_cli.gd` — the headless baker. Loads a scene, picks nodes, bakes atlases (one per group with the group's settings, the rest with the CLI settings), attaches cards and optionally saves the scene. It is the only supported way to bake outside the editor.

## Ownership
- Maintainer.

## Local Contracts
- Arguments come after `--`: `godot --path <project> -s res://addons/octahedral_impostor_lod/tools/octa_bake_cli.gd -- --scene=res://x.tscn [options]`.
- Every `OctaBakeSettings` property is a flag generated from `get_property_list()` (hyphenated, `--no-<bool>` for booleans, enums by name or number), plus `--out` / `--atlas-size` aliases and `--nodes`, `--preset`, `--save-scene`, `--ignore-groups`, `--pack`, `--help`.
- Unknown flags and invalid values print an error and exit 1. A failed bake exits 1. `--help` exits 0 and lists every option, including the generated ones.
- Output paths are unique (a `_N` suffix while the file exists), including the chunk atlas (`<atlas>_chunk.res`).
- Groups are baked with their own settings and their own atlas; `--ignore-groups` restores the flat behaviour. A group with `chunk_lod_distance > 0` also bakes its chunk card.
- `--pack` merges the atlases produced by that run with `OctaPacker.pack()` into `<out>/<scene>_packed.res` (unique `_N` suffix), prints what was packed and, with `--save-scene`, re-points the cards plus `group.atlas` / `group.chunk_atlas` to the packed atlas. The chunk atlas is included; incompatible atlases stay separate.
- Card overrides are taken from the source's own card only, never from a sub-part's card.
- The CLI never joins.

## Work Guidance
- Add a flag by adding it to the settings (it is then generated) or to `OWN_FLAGS` for CLI-only behaviour, and cover it in `tests/cli_test.sh`.
- Keep the script free of editor-only APIs; it runs with `--headless` on exported projects too.
- Do not add interactive prompts; every decision must come from a flag or a documented default.

## Verification
- `bash tests/cli_test.sh "<godot>"` — expects `RESULT PASS`; 10 cases now: bake + save scene, missing node, missing scene, group settings, `--ignore-groups`, `--help`, unknown option, invalid value, a generic setting flag, and `--pack` (merges the run's atlases and the saved scene uses them).
