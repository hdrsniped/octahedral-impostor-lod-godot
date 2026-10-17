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
cat > tests/cli_tmp/group.tscn <<'SCENE'
[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://addons/octahedral_impostor_lod/octa_impostor_group.gd" id="1"]
[ext_resource type="Script" path="res://addons/octahedral_impostor_lod/octa_bake_settings.gd" id="2"]

[sub_resource type="Resource" id="settings"]
script = ExtResource("2")
grid_size = 6
max_atlas_size = 512

[sub_resource type="SphereMesh" id="sphere"]

[sub_resource type="BoxMesh" id="box"]

[node name="Root" type="Node3D"]

[node name="Props" type="Node3D" parent="."]
script = ExtResource("1")
settings = SubResource("settings")

[node name="A" type="MeshInstance3D" parent="Props"]
mesh = SubResource("box")

[node name="B" type="MeshInstance3D" parent="Props"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 2, 0, 0)
mesh = SubResource("sphere")

[node name="Ball" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -3, 0, 0)
mesh = SubResource("sphere")
SCENE
cp tests/cli_tmp/group.tscn tests/cli_tmp/ungrouped.tscn
"$GODOT" --path . -s $CLI -- --scene=res://tests/cli_tmp/group.tscn --atlas-size=1024 --out=res://tests/cli_tmp/gout/ --save-scene > tests/cli_tmp/log4.txt 2>&1
code=$?
if [ $code -eq 0 ] && grep -q "baked Props - 2 card(s), 2 atlas entries, grid 6" tests/cli_tmp/log4.txt && grep -q "baked Ball - 1 card(s), 1 atlas entry, grid 12" tests/cli_tmp/log4.txt && [ -f tests/cli_tmp/gout/group_props.res ] && [ -f tests/cli_tmp/gout/group_ball.res ] && [ "$(grep -c octa_source tests/cli_tmp/group.tscn)" = "3" ]; then echo "PASS group baked with its own settings, other objects with the CLI settings"; else echo "FAIL group bake (exit $code)"; fails=1; fi
"$GODOT" --path . -s $CLI -- --scene=res://tests/cli_tmp/ungrouped.tscn --ignore-groups --atlas-size=1024 --out=res://tests/cli_tmp/iout/ > tests/cli_tmp/log5.txt 2>&1
code=$?
if [ $code -eq 0 ] && grep -q "grid 12" tests/cli_tmp/log5.txt && ! grep -q "grid 6" tests/cli_tmp/log5.txt && [ ! -f tests/cli_tmp/iout/ungrouped_ball.res ]; then echo "PASS --ignore-groups bakes with the old single-settings behaviour"; else echo "FAIL --ignore-groups (exit $code)"; fails=1; fi
"$GODOT" --path . -s $CLI -- --help > tests/cli_tmp/log6.txt 2>&1
code=$?
missing=""
for opt in scene nodes preset save-scene ignore-groups mode strip-source lod-mode lod-distance lod-screen-percent fade fade-margin quality write-depth split-parts back-layer search-steps precise-search layer-tolerance dedupe scene-pick-percent join-cell grid-size hemisphere max-atlas-size atlas-size material-maps emission half-res-material-maps compression output-dir out shadow-views frame-resolution msaa padding-px batch-size help; do
	grep -q -- "--$opt" tests/cli_tmp/log6.txt || missing="$missing $opt"
done
if [ $code -eq 0 ] && [ -z "$missing" ]; then echo "PASS --help exits 0 and lists every option"; else echo "FAIL --help (exit $code, missing:$missing)"; fails=1; fi
"$GODOT" --path . -s $CLI -- --scene=res://tests/cli_tmp/scene.tscn --bogus-flag=1 > tests/cli_tmp/log7.txt 2>&1
code=$?
if [ $code -ne 0 ] && grep -q "unknown option --bogus-flag" tests/cli_tmp/log7.txt; then echo "PASS unknown option exits 1 with a clear message"; else echo "FAIL unknown option (exit $code)"; fails=1; fi
"$GODOT" --path . -s $CLI -- --scene=res://tests/cli_tmp/scene.tscn --nodes=Ball --quality=bogus > tests/cli_tmp/log8.txt 2>&1
code=$?
if [ $code -ne 0 ] && grep -q "invalid value 'bogus' for --quality" tests/cli_tmp/log8.txt; then echo "PASS invalid value exits 1 with a clear message"; else echo "FAIL invalid value (exit $code)"; fails=1; fi
cp tests/editor_selftest/scene_template.tscn.txt tests/cli_tmp/flags.tscn
"$GODOT" --path . -s $CLI -- --scene=res://tests/cli_tmp/flags.tscn --nodes=Ball --grid-size=4 --max-atlas-size=512 --shadow-views=2 --quality=ultra --precise-search --no-dedupe --no-half-res-material-maps --out=res://tests/cli_tmp/fout/ > tests/cli_tmp/log9.txt 2>&1
code=$?
if [ $code -eq 0 ] && grep -q "grid 4" tests/cli_tmp/log9.txt && [ -f tests/cli_tmp/fout/flags_ball.res ]; then echo "PASS generic setting flags reach the bake"; else echo "FAIL generic setting flags (exit $code)"; fails=1; fi
rm -rf tests/cli_tmp
echo "RESULT $([ $fails -eq 0 ] && echo PASS || echo FAIL)"
exit $fails
