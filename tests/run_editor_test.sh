#!/usr/bin/env bash
# --- Editor self-test runner ---
set -u
cd "$(dirname "$0")/.."
GODOT="${1:-${GODOT:-godot}}"
mkdir -p tests/editor_tmp
cp tests/editor_selftest/scene_template.tscn.txt tests/editor_tmp/scene.tscn
cp project.godot tests/editor_tmp/project.godot.bak
sed -i 's|enabled=PackedStringArray("res://addons/octahedral_impostor_lod/plugin.cfg")|enabled=PackedStringArray("res://addons/octahedral_impostor_lod/plugin.cfg", "res://tests/editor_selftest/plugin.cfg")|' project.godot
timeout 240 "$GODOT" --editor --path . > tests/editor_tmp/log.txt 2>&1; grep -E "SELFTEST|SCRIPT ERROR|ERROR:|Cycle" tests/editor_tmp/log.txt | grep -v ".NET"; cp tests/editor_tmp/log.txt "${EDITOR_LOG:-/dev/null}"
cp tests/editor_tmp/project.godot.bak project.godot
rm -rf tests/editor_tmp octa_impostors/scene_*.res
rmdir octa_impostors 2>/dev/null
true
