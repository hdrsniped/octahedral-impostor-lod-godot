# Octahedral Impostor LOD — DOX root

## Purpose
Standalone Godot 4.7 editor plugin + runtime addon that bakes 3D objects into octahedral impostor cards and swaps the real mesh for a card at a distance. Ships with a demo scene and an automated test suite. It is not part of any game project; nothing here touches `D:\Gamedev\Godot\DriftInfinite`.

- Product name: "Octahedral Impostor LOD" by hdrsniped.
- Master tree: `D:\Gamedev\Godot\OctahedralImpostorLOD`. Addon: `addons/octahedral_impostor_lod`. Demo: `demo/`. Tests: `tests/`.
- Owner: hdrsniped (the user). Changes are made in the working tree; the owner decides when anything is committed, tagged or pushed.
- Design notes, measured results and the open issue list are kept in untracked notes at the repo root; the public history is `CHANGELOG.md`.

## Ownership
- Code and tests in this tree: the maintainer.
- `README.md` and `CHANGELOG.md`: one entry per change, edited deliberately.
- Frozen, never modify: `D:\Gamedev\Godot\OctahedralImpostorLOD_v1` (released v1 project) and `C:\Users\somone\Documents\antigravity` (another tool's copy).
- Never commit, tag or push without the owner's explicit go.

## Local Contracts
- Naming: always "Octahedral Impostor LOD" by hdrsniped. Never "Impostor Cards"/"Imposter Cards". No AI credit in code, docs, commits or release notes.
- Code style: no comments except one short `# --- Title ---` per section (`// --- Title ---` in shaders). `##` lines only as inspector tooltips directly above `@export` properties in `octa_bake_settings.gd` and `octa_impostor.gd`.
- Line endings are per file and must be preserved: CRLF for `shaders/octa_core.gdshaderinc`, `octa_atlas.gd`, `octa_baker.gd`, `tests/queue_test.gd`, `tests/visual_test.gd`; LF for everything else. Check with a byte count, not with grep. .NET `WriteAllText`/`WriteAllLines` write CRLF on this machine.
- Modularity: every optional feature is its own switch. With all switches off the addon must render exactly like v2.1 — proved by `tests/compat_test.gd` (0 differing pixels on Forward+, Mobile and Compatibility).
- Gate rule: a theoretical feature or optimization ships only with a measured gain of at least 5% (accuracy, ms, pixels or VRAM), or it stays off by default / is reverted and the number is recorded. "Looks faster" is not a result.
- Atlas format 4 is the current schema. Files with `format_version` 1-3 must keep loading and rendering identically.
- Tests need a window (they hang with `--headless`), run on one Godot process at a time, and run on a scratch copy — see `tests/AGENTS.md`.
- Do not run long `--uncapped` benchmarks; the owner's PC lags.
- The test machine is an AMD Radeon Vega 7 iGPU: GPU timings drift up to ±30% under sustained load. Interleave A/B runs and take the median of at least three.
- Godot is driven either through Godot Super MCP (`super`, default) or the console binary (`standard`); the mode rules, this project's mismatches and the paired workflow are in `GODOT_MCP.md`.

## Work Guidance
- Before changing anything, read `CHANGELOG.md`, `README.md` and the untracked design notes.
- Edit code in the master tree; test on the scratch copy `D:\Gamedev\Projects\navis\oil` (sync `addons/`, `tests/`, `demo/`, `project.godot`, then `--headless --import` once). The owner often has the editor open on the master tree, so never bake there.
- Baselines that must not regress: editor self-test 137/137, `tests/cli_test.sh` 10/10, `run_all.sh` 60/60 RESULT PASS (the six `visual` entries print ACCURACY only), compat 0 differing pixels on 3 renderers, visual accuracy Rock High MAE 8.09 / bad 7.35%, Rock Ultra 7.17 / 6.62%, Rings High 15.05 / 26.14%.
- Every shader or rendering change is verified on Forward+ (`forward_plus`), Mobile (`mobile`) and Compatibility (`gl_compatibility`).
- After a change, record the measured numbers in `CHANGELOG.md` and in the design notes, and update this file or a child when a contract changes.

## Verification
- Full suite: `GODOT="<godot>" bash tests/run_all.sh` (about 20 minutes; 63 entries).
- Editor self-test: `bash tests/run_editor_test.sh "<godot>"` — expect 137 PASS, 0 FAIL.
- CLI: `bash tests/cli_test.sh "<godot>"` — expect `RESULT PASS`.
- Backward compatibility: `godot --path . -s res://tests/compat_test.gd` — 0 differing pixels on each renderer.
- Accuracy: `godot --path . -s res://tests/visual_test.gd` (prints ACCURACY lines, not RESULT).
- GPU: `godot --path . -s res://tests/perf_test.gd -- --mode=high|ultra --shadows=0`.
- Godot binary: `D:\Program Files\Godot\Godot_v4.7.2-stable_mono_win64_console.exe`.

## Child DOX Index
- `addons/octahedral_impostor_lod/AGENTS.md` — the addon: runtime API, atlas/baker/packer/streamer/group modules, editor plugin, format rules.
- `addons/octahedral_impostor_lod/shaders/AGENTS.md` — runtime shader variants, compile-time defines, capture shaders, bake hook.
- `addons/octahedral_impostor_lod/tools/AGENTS.md` — the command line baker and its flags.
- `demo/AGENTS.md` — the showcase scene and its UI rules.
- `tests/AGENTS.md` — every automated test, the runners, the scratch copy and the lock convention.
