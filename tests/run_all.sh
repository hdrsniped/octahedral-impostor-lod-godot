#!/usr/bin/env bash
# --- Runs every automated test ---
set -u
cd "$(dirname "$0")/.."
GODOT="${1:-${GODOT:-godot}}"
mkdir -p tests/out
"$GODOT" --headless --path . --import > /dev/null 2>&1

run() {
	local name=$1; shift
	timeout 600 "$GODOT" --path . "$@" > "tests/out/log_$name.txt" 2>&1
	local result
	result=$(grep -E "^RESULT|IoU avg|^BAKE|^SHADOWS|^QUEUE|^VRAM|^ACCURACY|^COMPAT|^SHADOW " "tests/out/log_$name.txt" | tail -30)
	local errors
	errors=$(grep -E "SCRIPT ERROR|^ERROR" "tests/out/log_$name.txt" | grep -v "\.NET" | head -3)
	echo "== $name"
	echo "${result:-no result (see tests/out/log_$name.txt)}"
	[ -n "$errors" ] && echo "errors:" && echo "$errors"
}

run lod_forward    -s res://tests/lod_test.gd
run lod_mobile     --rendering-method mobile -s res://tests/lod_test.gd
run lod_compat     --rendering-method gl_compatibility -s res://tests/lod_test.gd
run visual         -s res://tests/visual_test.gd
run visual_mobile  --rendering-method mobile -s res://tests/visual_test.gd
run visual_compat  --rendering-method gl_compatibility -s res://tests/visual_test.gd
run visual_far    -s res://tests/visual_test.gd -- --far=1
run visual_far_mobile --rendering-method mobile -s res://tests/visual_test.gd -- --far=1
run visual_far_compat --rendering-method gl_compatibility -s res://tests/visual_test.gd -- --far=1
run queue_forward  -s res://tests/queue_test.gd
run queue_mobile   --rendering-method mobile -s res://tests/queue_test.gd
run queue_compat   --rendering-method gl_compatibility -s res://tests/queue_test.gd
run debug          -s res://tests/debug_test.gd
run quality_flat   -s res://tests/quality_flat_test.gd
run transform      -s res://tests/transform_test.gd
run transform_mobile --rendering-method mobile -s res://tests/transform_test.gd
run transform_compat --rendering-method gl_compatibility -s res://tests/transform_test.gd
run pole           -s res://tests/pole_test.gd
run pole_mobile    --rendering-method mobile -s res://tests/pole_test.gd
run pole_compat    --rendering-method gl_compatibility -s res://tests/pole_test.gd
run joined_depth   -s res://tests/joined_depth_test.gd
run joined_mobile  --rendering-method mobile -s res://tests/joined_depth_test.gd
run joined_compat  --rendering-method gl_compatibility -s res://tests/joined_depth_test.gd
run materials      -s res://tests/material_maps_test.gd
run materials_mobile --rendering-method mobile -s res://tests/material_maps_test.gd
run materials_compat --rendering-method gl_compatibility -s res://tests/material_maps_test.gd
run compat         -s res://tests/compat_test.gd
run compat_mobile  --rendering-method mobile -s res://tests/compat_test.gd
run compat_compat  --rendering-method gl_compatibility -s res://tests/compat_test.gd
run shadow         -s res://tests/shadow_test.gd
run shadow_mobile  --rendering-method mobile -s res://tests/shadow_test.gd
run shadow_compat  --rendering-method gl_compatibility -s res://tests/shadow_test.gd
run precise        -s res://tests/precise_test.gd
run precise_mobile --rendering-method mobile -s res://tests/precise_test.gd
run precise_compat --rendering-method gl_compatibility -s res://tests/precise_test.gd
run overdraw       -s res://tests/overdraw_test.gd
run overdraw_mobile --rendering-method mobile -s res://tests/overdraw_test.gd
run overdraw_compat --rendering-method gl_compatibility -s res://tests/overdraw_test.gd
run demo_forward   --resolution 1920x1080 -s res://tests/demo_smoke_test.gd -- --shots="$PWD/tests/out/demo_forward"
run demo_mobile    --rendering-method mobile --resolution 1920x1080 -s res://tests/demo_smoke_test.gd -- --shots="$PWD/tests/out/demo_mobile"
run demo_compat    --rendering-method gl_compatibility --resolution 1920x1080 -s res://tests/demo_smoke_test.gd -- --shots="$PWD/tests/out/demo_compat"
echo "== cli"
bash tests/cli_test.sh "$GODOT"
echo "== editor"
bash tests/run_editor_test.sh "$GODOT"
