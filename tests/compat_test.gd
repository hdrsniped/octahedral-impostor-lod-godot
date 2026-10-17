extends SceneTree

const MAX_MEAN_DIFF := 0.05
const MAX_DIFF_PIXELS := 0.0005
const MIN_COVERED := 0.02
const FORMATS := {"v1_all": 1, "v2_fmt2": 2, "v2_plain": 3, "v2_all": 3}

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.split("=", true, 1)[1]
	return def


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


# --- Old atlas files render as they did before ---
func _run() -> void:
	var dir := _arg("fixtures", "res://tests/fixtures")
	var renderer := RenderingServer.get_current_rendering_method()
	print("RENDERER %s, fixtures %s" % [renderer, dir])
	var names := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".res") or f.ends_with(".tres"):
			names.append(f.get_basename())
	names.sort()
	_check(not names.is_empty(), "found %d old atlas files" % names.size())
	for set_name: String in names:
		var file := "%s/%s.res" % [dir, set_name]
		if not FileAccess.file_exists(file):
			file = "%s/%s.tres" % [dir, set_name]
		var atlas := ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE) as OctaAtlas
		if atlas == null:
			_check(false, "%s loads as an OctaAtlas" % set_name)
			continue
		var expected: int = FORMATS.get(set_name, 1)
		_check(atlas.format_version == expected and atlas.format_version < OctaAtlas.FORMAT_VERSION, "%s: old file keeps format_version %d (current code writes %d)" % [set_name, atlas.format_version, OctaAtlas.FORMAT_VERSION])
		var ref := Image.load_from_file("%s/refs/%s/%s.png" % [dir, renderer, CompatRender.ref_name(set_name)])
		if ref == null:
			_check(false, "%s: reference image for %s exists" % [set_name, renderer])
			continue
		var now := await CompatRender.sheet(atlas, root, set_name)
		ref.convert(Image.FORMAT_RGBA8)
		var r := _compare(ref, now)
		print("COMPAT %s (%s): %d objects, %d renders, covered %.1f%%, mean difference %.4f/255, differing pixels %.4f%%, max channel difference %d" % [
				set_name, renderer, atlas.object_count(), now.get_height() / CompatRender.SIZE, r.covered * 100.0, r.mean, r.fraction * 100.0, r.max])
		_check(now.get_size() == ref.get_size() and r.covered > MIN_COVERED and r.mean < MAX_MEAN_DIFF and r.fraction < MAX_DIFF_PIXELS,
				"%s renders like the reference made with the old code" % set_name)
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	for c in root.get_children():
		c.queue_free()
	await process_frame
	await process_frame
	quit(1 if _fails else 0)


func _compare(a: Image, b: Image) -> Dictionary:
	var sum := 0.0
	var diff := 0
	var covered := 0
	var worst := 0
	var total := a.get_width() * a.get_height()
	if a.get_size() != b.get_size():
		return {mean = 255.0, fraction = 1.0, covered = 0.0, max = 255}
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if ca.a8 > 128:
				covered += 1
			var d := maxi(maxi(absi(ca.r8 - cb.r8), absi(ca.g8 - cb.g8)), maxi(absi(ca.b8 - cb.b8), absi(ca.a8 - cb.a8)))
			sum += d
			worst = maxi(worst, d)
			if d > 0:
				diff += 1
	return {mean = sum / total, fraction = float(diff) / total, covered = float(covered) / total, max = worst}
