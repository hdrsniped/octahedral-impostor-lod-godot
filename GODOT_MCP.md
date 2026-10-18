# Godot MCP — operating modes for this project

How an agent should drive Godot while working on Octahedral Impostor LOD. The canonical, machine-wide contract is `D:\Gamedev\GodotSuperMCP\AGENT.md`; this file is the project-local summary and the rules that actually apply here.

## Modes

| Mode | What you do | Use when |
|---|---|---|
| **`super`** (default) | Drive the open Godot editor through Godot Super MCP: read the scene tree, edit nodes, open the bake dialog, take screenshots, run the game and inspect it live. | An editor is open on `D:\Gamedev\Godot\OctahedralImpostorLOD` with the `godot_super_mcp` addon enabled, and the task is UI, scene authoring, visual review or live runtime checks. |
| **`standard`** | Ignore the MCP. Drive the console build directly: `Godot_v4.7.2-stable_mono_win64_console.exe --path . -s res://tests/<name>.gd -- <args>`, `--headless --import`, shell scripts, log parsing. | Test suites, renderer matrices, repeated bakes and benchmarks, projects without the addon, no editor open, or the editor is busy. |

Rules: `super` is the default; announce the mode in one line; switch to `standard` when a trigger below applies instead of retrying a dead connection; the mode is per task; the user can force either ("mode: standard", "raw dog it"). The `standard` **operating mode** is not the `standard` **safety mode** in the MCP Project Settings.

## This project's reality

- **The addon is not installed here.** `addons/godot_super_mcp` does not exist, so `super` needs it copied in and enabled first. Until then, this project is `standard`-only.
- **Binary**: use `D:\Program Files\Godot\Godot_v4.7.2-stable_mono_win64_console.exe` (the mono build); the non-mono path in the MCP doc does not match this project.
- **Tests need a window.** The suite hangs headless, and the editor self-test spawns a real editor. Run them through the CLI with a timeout, as `tests/run_all.sh` and `tests/run_editor_test.sh` do.
- **Tests run on a scratch copy** (`D:\Gamedev\Projects\navis\oil`) because the owner may have the editor open on this tree. MCP tools mutate the editor's open project, so either open the copy in the editor or use `standard` against the copy.
- **One Godot process at a time** (see `tests/AGENTS.md` for the lock file).

## Paired workflow

MCP for seeing and touching, CLI for grinding:

1. Change something through MCP (or in the tree for code).
2. Sync + import and run the project's own runner from the shell.
3. Verify visually with `get_editor_screenshot` / `get_game_screenshot`, and read the property back before calling it done.

## When not to use the MCP

- A whole suite, a 3-renderer matrix, a benchmark loop or dozens of bakes.
- Anything outside the project: shell, git, robocopy, process and log handling.
- No editor open, or the addon not enabled.
- Another tool or agent owns the editor (one editor, one server, one client).
- You only need `--headless --import` or one script run.

## Coverage

| Need | MCP | CLI |
|---|---|---|
| Read/edit the open scene, nodes, properties | yes | no |
| Screenshots, run the game, simulate input | yes | no |
| One-off headless script or scene | yes | yes |
| `--headless --import` | no | yes |
| Suites, renderer matrices, repeated bakes | no | yes |
| Shell, git, robocopy, logs | no | yes |
