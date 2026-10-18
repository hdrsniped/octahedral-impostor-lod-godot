extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _arg(key: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.split("=", true, 1)[1]
	return def


# --- Reference renders for fade_test, made with the code before the fade work ---
func _run() -> void:
	var out := _arg("out", "res://tests/fixtures/fade_refs")
	var atlas := ResourceLoader.load("res://tests/fixtures/v2_plain.res", "", ResourceLoader.CACHE_MODE_IGNORE) as OctaAtlas
	var dir := "%s/%s" % [out, RenderingServer.get_current_rendering_method()]
	DirAccess.make_dir_recursive_absolute(dir)
	for case_name: String in FadeRender.CASES:
		if case_name == "native" and RenderingServer.get_current_rendering_method() != "forward_plus":
			continue
		var im: Image = await FadeRender.sheet(atlas, root, case_name)
		im.save_png("%s/%s.png" % [dir, case_name])
		print("RENDERED %s/%s.png" % [dir, case_name])
	for c in root.get_children():
		c.queue_free()
	await process_frame
	quit()
