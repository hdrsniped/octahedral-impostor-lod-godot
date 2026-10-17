extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _arg(key: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.split("=", true, 1)[1]
	return def


# --- Old-version fixtures ---
func _run() -> void:
	var out := _arg("out")
	var set_name := _arg("set")
	var path := "%s/%s.res" % [out, set_name]
	if _arg("mode") == "bake":
		var objs: Array = DemoObjects.all()
		if set_name == "v2_all":
			objs.append(load("res://demo/demo_objects.gd").textured())
		for o: Node3D in objs:
			root.add_child(o)
		var s := OctaBakeSettings.new()
		s.grid_size = 8
		s.max_atlas_size = 512
		if set_name == "v2_plain" or set_name == "v2_fmt2":
			s.material_maps = false
			s.emission = false
		var atlas: OctaAtlas = await OctaBaker.bake_to_file(objs, root, path, s)
		print("BAKED %s: %d objects, format %s" % [path, atlas.object_count(), atlas.get("format_version")])
		if set_name == "v2_fmt2":
			atlas.format_version = 2
			atlas.material_params = PackedVector4Array()
			ResourceSaver.save(atlas, path, ResourceSaver.FLAG_COMPRESS)
	else:
		if not FileAccess.file_exists(path):
			path = "%s/%s.tres" % [out, set_name]
		var atlas: OctaAtlas = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var sheet: Image = await CompatRender.sheet(atlas, root, set_name)
		var dir := "%s/refs/%s" % [out, RenderingServer.get_current_rendering_method()]
		DirAccess.make_dir_recursive_absolute(dir)
		sheet.save_png("%s/%s.png" % [dir, set_name])
		print("RENDERED %s/%s.png" % [dir, set_name])
	for c in root.get_children():
		c.queue_free()
	await process_frame
	quit()
