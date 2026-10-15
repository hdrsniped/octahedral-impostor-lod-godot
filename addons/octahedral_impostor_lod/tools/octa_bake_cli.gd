extends SceneTree

const USAGE := "Usage: godot --path <project> -s res://addons/octahedral_impostor_lod/tools/octa_bake_cli.gd -- --scene=res://x.tscn [--nodes=a,b] [--preset=mobile|balanced|high_quality|complex_shapes] [--out=res://impostors/] [--save-scene] [--mode=dynamic_lod|duplicate|replace] [--quality=low|medium|high|ultra] [--atlas-size=2048] [--lod-distance=40] [--split-parts] [--no-dedupe] [--strip-source]"

var _args := {}


func _initialize() -> void:
	_run.call_deferred()


func _fail(msg: String) -> void:
	printerr("octa_bake_cli: ", msg)
	quit(1)


# --- Arguments ---
func _parse() -> void:
	for a in OS.get_cmdline_user_args():
		var s := a.trim_prefix("--")
		var eq := s.find("=")
		if eq < 0:
			_args[s] = "true"
		else:
			_args[s.substr(0, eq)] = s.substr(eq + 1)


func _settings() -> OctaBakeSettings:
	var s := OctaBakeSettings.new()
	if _args.has("preset"):
		var key: String = _args.preset.to_lower().replace("-", "_").replace(" ", "_")
		var names := OctaBakeSettings.PRESET_NAMES.map(func(n: String) -> String: return n.to_lower().replace(" ", "_"))
		var i := names.find(key)
		if i < 1:
			return null
		s.apply_preset(i as OctaBakeSettings.Preset)
	if _args.has("mode"):
		var m := ["dynamic_lod", "duplicate", "replace"].find(_args.mode.to_lower())
		if m < 0:
			return null
		s.mode = m as OctaLOD.Mode
	if _args.has("quality"):
		var q := ["low", "medium", "high", "ultra"].find(_args.quality.to_lower())
		if q < 0:
			return null
		s.quality = q as OctaAtlas.Quality
	if _args.has("atlas-size"):
		s.max_atlas_size = int(_args["atlas-size"])
	if _args.has("lod-distance"):
		s.lod_distance = float(_args["lod-distance"])
	if _args.has("out"):
		s.output_dir = _args.out
	if _args.has("split-parts"):
		s.split_parts = true
	if _args.has("no-dedupe"):
		s.dedupe = false
	if _args.has("strip-source"):
		s.strip_source = true
	return s


func _pick(root: Node, s: OctaBakeSettings) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if _args.has("nodes"):
		for n: String in _args.nodes.split(",", false):
			var node := root.get_node_or_null(NodePath(n.strip_edges())) as Node3D
			if node == null:
				node = root.find_child(n.strip_edges(), true, false) as Node3D
			if node == null:
				printerr("octa_bake_cli: node not found: ", n)
				return []
			out.append(node)
		return out
	for c: Dictionary in OctaLOD.scene_candidates(root, s.lod_distance):
		if c.pct <= s.scene_pick_percent:
			out.append(c.node)
	return out


# --- Bake ---
func _run() -> void:
	_parse()
	if not _args.has("scene"):
		print(USAGE)
		_fail("--scene is required.")
		return
	var scene_path: String = _args.scene
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_fail("cannot load scene %s" % scene_path)
		return
	var s := _settings()
	if s == null:
		_fail("invalid --preset, --mode or --quality value.\n" + USAGE)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	for i in 3:
		await process_frame
	var nodes := _pick(scene, s)
	if nodes.is_empty():
		_fail("no objects to bake (use --nodes=a,b or lower the LOD distance).")
		return
	for n in nodes:
		if not OctaLOD.geometry_below(n).any(func(g: Node) -> bool: return g is MeshInstance3D and g.mesh != null):
			_fail("'%s' has no mesh to bake." % n.name)
			return
		if n == scene and not OctaLOD.is_child_card(n, s.mode):
			_fail("'%s' is the scene root; this mode needs a parent." % n.name)
			return

	var targets: Array[Node3D] = []
	var bake_list: Array[Node3D] = []
	var index: Array[int] = []
	if s.split_parts:
		targets = OctaLOD.split_parts(nodes)
		bake_list = targets.duplicate()
		for k in targets.size():
			index.append(k)
	else:
		targets = nodes.duplicate()
		var seen := {}
		for n in nodes:
			var key := OctaLOD.signature(n) if s.dedupe else str(n.get_instance_id())
			if not seen.has(key):
				seen[key] = bake_list.size()
				bake_list.append(n)
			index.append(seen[key])
	if bake_list.is_empty() or bake_list.size() > OctaAtlas.MAX_OBJECTS:
		_fail("%d different objects to bake; the limit is %d." % [bake_list.size(), OctaAtlas.MAX_OBJECTS])
		return

	var out_dir := s.output_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var base := out_dir.path_join("%s_%s" % [scene_path.get_file().get_basename().to_snake_case(), String(nodes[0].name).to_snake_case()])
	var path := base + ".res"
	var suffix := 2
	while FileAccess.file_exists(path):
		path = "%s_%d.res" % [base, suffix]
		suffix += 1

	var t0 := Time.get_ticks_msec()
	print("octa_bake_cli: baking %d object(s) from %s -> %s" % [bake_list.size(), scene_path, path])
	var atlas := await OctaBaker.bake_to_file(bake_list, root, path, s)
	if atlas == null:
		_fail("bake failed.")
		return

	var cards := 0
	for k in targets.size():
		var src := targets[k]
		for below in [src] + OctaLOD.geometry_below(src):
			OctaLOD.remove_cards(below)
		var card := OctaLOD.attach_card(src, atlas, index[k], s.mode, s.lod_distance, s.quality, scene, s)
		cards += 1
		if s.mode == OctaLOD.Mode.REPLACE and s.strip_source and not s.split_parts:
			var parent := src.get_parent()
			parent.remove_child(src)
			src.free()
	var saved := ""
	if _args.has("save-scene"):
		var ps := PackedScene.new()
		var err := ps.pack(scene)
		if err == OK:
			err = ResourceSaver.save(ps, scene_path)
		if err != OK:
			_fail("could not save %s (error %d)." % [scene_path, err])
			return
		saved = ", scene saved"
	print("octa_bake_cli: done - %d card(s), %d atlas entr%s, %s%s (%.1f s)" % [cards, atlas.object_count(), "y" if atlas.object_count() == 1 else "ies", atlas.resource_path, saved, (Time.get_ticks_msec() - t0) / 1000.0])
	scene.queue_free()
	await process_frame
	quit(0)
