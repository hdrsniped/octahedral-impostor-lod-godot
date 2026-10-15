#!/usr/bin/env bash
# --- CLI bake test ---
set -u
cd "$(dirname "$0")/.."
GODOT="${1:-${GODOT:-godot}}"
CLI=res://addons/octahedral_impostor_lod/tools/octa_bake_cli.gd
rm -rf tests/cli_tmp
mkdir -p tests/cli_tmp
cp tests/editor_selftest/scene_template.tscn.txt tests/cli_tmp/scene.tscn
"$GODOT" --headless --path . --import > /dev/null 2>&1
fails=0
"$GODOT" --path . -s $CLI -- --scene=res://tests/cli_tmp/scene.tscn --nodes=Ball,Ring --preset=balanced --out=res://tests/cli_tmp/out/ --save-scene > tests/cli_tmp/log.txt 2>&1
code=$?
if [ $code -eq 0 ] && [ -f tests/cli_tmp/out/scene_ball.res ] && [ "$(grep -c octa_source tests/cli_tmp/scene.tscn)" = "2" ]; then echo "PASS bake and save scene"; else echo "FAIL bake and save scene (exit $code)"; fails=1; fi
"$GODOT" --path . -s $CLI -- --scene=res://tests/cli_tmp/scene.tscn --nodes=Missing > tests/cli_tmp/log2.txt 2>&1
if [ $? -ne 0 ]; then echo "PASS missing node exits non-zero"; else echo "FAIL missing node exits non-zero"; fails=1; fi
"$GODOT" --path . -s $CLI -- --scene=res://tests/cli_tmp/nothing.tscn > tests/cli_tmp/log3.txt 2>&1
if [ $? -ne 0 ]; then echo "PASS missing scene exits non-zero"; else echo "FAIL missing scene exits non-zero"; fails=1; fi
rm -rf tests/cli_tmp
echo "RESULT $([ $fails -eq 0 ] && echo PASS || echo FAIL)"
exit $fails
