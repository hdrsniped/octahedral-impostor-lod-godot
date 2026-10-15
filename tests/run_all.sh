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
	result=$(grep -E "^RESULT|IoU avg|^BAKE" "tests/out/log_$name.txt" | tail -10)
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
run debug          -s res://tests/debug_test.gd
run quality_flat   -s res://tests/quality_flat_test.gd
echo "== cli"
bash tests/cli_test.sh "$GODOT"
echo "== editor"
bash tests/run_editor_test.sh "$GODOT"
