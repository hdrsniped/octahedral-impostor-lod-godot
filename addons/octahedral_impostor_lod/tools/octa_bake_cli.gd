extends SceneTree

const USAGE := "Usage: godot --path <project> -s res://addons/octahedral_impostor_lod/tools/octa_bake_cli.gd -- --scene=res://x.tscn [options]  (--help lists every option)"
const OWN_FLAGS := {
	"scene": "=<res://x.tscn>  scene to load (required)",
	"nodes": "=<a,b>  nodes to bake, by path or name (default: everything small on screen, as Bake Scene pre-ticks)",
	"preset": "=<mobile|balanced|high_quality|complex_shapes>  applied first; the options below override it",
	"save-scene": "  write the cards back into the scene file",
	"ignore-groups": "  treat OctaImpostorGroup nodes as plain nodes (default: each group is baked with its own settings)",
	"help": "  print this list and exit",
}
const ALIASES := {"out": "output_dir", "atlas-size": "max_atlas_size"}

var _args := {}
var _flags := {}
var _bad := false


func _initialize() -> void:
	_run.call_deferred()


func _fail(msg: String) -> void:
	printerr("octa_bake_cli: ", msg)
	quit(1)


# --- Arguments ---
func _parse() -> void:
	for p in OctaBakeSettings.new().get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			_flags[String(p.name).replace("_", "-")] = p
	for alias: String in ALIASES:
		_flags[alias] = _flags[ALIASES[alias].replace("_", "-")]
	for a in OS.get_cmdline_user_args():
		var s := a.trim_prefix("--")
		var eq := s.find("=")
		if eq < 0:
			_args[s] = "true"
		else:
			_args[s.substr(0, eq)] = s.substr(eq + 1)


func _unknown() -> String:
	for flag: String in _args:
		if not OWN_FLAGS.has(flag) and not _flags.has(flag) and not (flag.begins_with("no-") and _flags.has(flag.substr(3)) and _flags[flag.substr(3)].type == TYPE_BOOL):
			return flag
	return ""


func _help() -> void:
	print(USAGE)
	for flag: String in OWN_FLAGS:
		print("  --", flag, OWN_FLAGS[flag])
	print("Bake settings (the same options as the bake dialog; booleans also accept --no-<name>):")
	var defaults := OctaBakeSettings.new()
	for flag: String in _flags:
		if ALIASES.has(flag):
			continue
		var info: Dictionary = _flags[flag]
		var aliases := ALIASES.keys().filter(func(a: String) -> bool: return ALIASES[a] == info.name)
		var kind := "[=true|false]"
		var shown: Variant = defaults.get(info.name)
		if info.hint == PROPERTY_HINT_ENUM:
			var names := PackedStringArray()
			for item: String in info.hint_string.split(","):
				names.append(_key(item.get_slice(":", 0)))
				if item.get_slice(":", 1) == str(shown):
					shown = names[-1]
			kind = "=<" + "|".join(names) + ">"
		elif info.type == TYPE_INT or info.type == TYPE_FLOAT:
			var r: PackedStringArray = info.hint_string.split(",") if info.hint == PROPERTY_HINT_RANGE else PackedStringArray()
			kind = "=<%s..%s>" % [r[0].trim_suffix(".0"), r[1].trim_suffix(".0")] if r.size() > 1 else "=<number>"
		elif info.type == TYPE_STRING:
			kind = "=<text>"
		print("  --%s%s  (default %s)%s" % [flag, kind, shown, "  also --" + ", --".join(aliases) if not aliases.is_empty() else ""])


func _key(text: String) -> String:
	return text.strip_edges().to_lower().replace(" ", "_").replace("-", "_")


func _settings() -> OctaBakeSettings:
	var s := OctaBakeSettings.new()
	if _args.has("preset"):
		var names := OctaBakeSettings.PRESET_NAMES.map(_key)
		var i := names.find(_key(_args.preset))
		if i < 1:
			printerr("octa_bake_cli: invalid --preset '%s' (use %s)." % [_args.preset, ", ".join(names.slice(1))])
			return null
		s.apply_preset(i as OctaBakeSettings.Preset)
	for flag: String in _args:
		if OWN_FLAGS.has(flag):
			continue
		var name := flag
		var value: String = _args[flag]
		if not _flags.has(name):
			name = flag.substr(3)
			value = "false"
		if not _apply(s, _flags[name], value):
			printerr("octa_bake_cli: invalid value '%s' for --%s (see --help)." % [value, flag])
			return null
	return s


func _apply(s: OctaBakeSettings, info: Dictionary, value: String) -> bool:
	var v: Variant = null
	if info.type == TYPE_BOOL:
		v = not value.to_lower() in ["false", "0", "off", "no"]
	elif info.hint == PROPERTY_HINT_ENUM:
		for item: String in info.hint_string.split(","):
			if _key(item.get_slice(":", 0)) == _key(value) or item.get_slice(":", 1) == value:
				v = int(item.get_slice(":", 1))
	elif info.type == TYPE_INT and value.is_valid_int():
		v = int(value)
	elif info.type == TYPE_FLOAT and value.is_valid_float():
		v = float(value)
	elif info.type == TYPE_STRING:
		v = value
	if v != null:
		s.set(info.name, v)
	return v != null


func _pick(root: Node, s: OctaBakeSettings, use_groups: bool) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if _args.has("nodes"):
		for n: String in _args.nodes.split(",", false):
			var node := root.get_node_or_null(NodePath(n.strip_edges())) as Node3D
			if node == null:
				node = root.find_child(n.strip_edges(), true, false) as Node3D
			if node == null:
				printerr("octa_bake_cli: node not found: ", n)
				_bad = true
				return []
			if use_groups and node is OctaImpostorGroup:
				continue
			out.append(node)
		return out
	for c: Dictionary in OctaLOD.scene_candidates(root, s.lod_distance, use_groups):
		if c.pct <= s.scene_pick_percent:
			out.append(c.node)
	return out


# --- Bake ---
func _run() -> void:
	_parse()
	if _args.has("help"):
		_help()
		quit(0)
		return
	var unknown := _unknown()
	if unknown != "":
		_fail("unknown option --%s (run with --help to list every option)." % unknown)
		return
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
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	for i in 3:
		await process_frame
	var use_groups := not _args.has("ignore-groups")
	var jobs: Array[Dictionary] = []
	if use_groups:
		for g in OctaImpostorGroup.find_all(scene):
			var members := g.target_nodes()
			if members.is_empty() or (_args.has("nodes") and not _named(scene, g)):
				continue
			var gs := g.effective_settings().duplicate()
			if _args.has("out"):
				gs.output_dir = _args.out
			jobs.append({nodes = members, settings = gs, group = g, label = String(g.name)})
	var nodes := _pick(scene, s, use_groups)
	if _bad:
		quit(1)
		return
	if nodes.is_empty() and jobs.is_empty():
		_fail("no objects to bake (use --nodes=a,b or lower the LOD distance).")
		return
	if not nodes.is_empty():
		jobs.append({nodes = nodes, settings = s, group = null, label = String(nodes[0].name)})

	var t0 := Time.get_ticks_msec()
	var cards := 0
	var atlases: Array[OctaAtlas] = []
	for job in jobs:
		var done := await _bake_job(scene, scene_path, job)
		if done < 0:
			return
		cards += done
		atlases.append(job.atlas)
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
	print("octa_bake_cli: done - %d card(s) in %d atlas%s%s (%.1f s)" % [cards, atlases.size(), "" if atlases.size() == 1 else "es", saved, (Time.get_ticks_msec() - t0) / 1000.0])
	scene.queue_free()
	await process_frame
	quit(0)


func _named(scene: Node, node: Node) -> bool:
	for n: String in _args.nodes.split(",", false):
		var found := scene.get_node_or_null(NodePath(n.strip_edges()))
		if found == null:
			found = scene.find_child(n.strip_edges(), true, false)
		if found == node:
			return true
	return false


func _bake_job(scene: Node, scene_path: String, job: Dictionary) -> int:
	var s: OctaBakeSettings = job.settings
	var nodes: Array[Node3D] = job.nodes
	for n in nodes:
		if not OctaLOD.geometry_below(n).any(func(g: Node) -> bool: return g is MeshInstance3D and g.mesh != null):
			_fail("'%s' has no mesh to bake." % n.name)
			return -1
		if n == scene and not OctaLOD.is_child_card(n, s.mode):
			_fail("'%s' is the scene root; this mode needs a parent." % n.name)
			return -1

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
		return -1

	var out_dir := s.output_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var base := out_dir.path_join("%s_%s" % [scene_path.get_file().get_basename().to_snake_case(), job.label.to_snake_case()])
	var path := base + ".res"
	var suffix := 2
	while FileAccess.file_exists(path):
		path = "%s_%d.res" % [base, suffix]
		suffix += 1

	print("octa_bake_cli: baking %d object(s) from %s -> %s%s" % [bake_list.size(), scene_path, path, " (group %s)" % job.group.name if job.group != null else ""])
	var atlas := await OctaBaker.bake_to_file(bake_list, root, path, s)
	if atlas == null:
		_fail("bake failed.")
		return -1

	var cards := 0
	for k in targets.size():
		var src := targets[k]
		var kept := {}
		for below in [src] + OctaLOD.geometry_below(src):
			for old in OctaLOD.find_cards(below):
				kept = OctaLOD.card_overrides(old)
			OctaLOD.remove_cards(below)
		var card := OctaLOD.attach_card(src, atlas, index[k], s.mode, s.lod_distance, kept.get("quality", s.quality), scene, s)
		OctaLOD.apply_overrides(card, kept)
		cards += 1
		if s.mode == OctaLOD.Mode.REPLACE and s.strip_source and not s.split_parts:
			var parent := src.get_parent()
			parent.remove_child(src)
			src.free()
	if job.group != null:
		job.group.atlas = atlas
	job.atlas = atlas
	print("octa_bake_cli: baked %s - %d card(s), %d atlas entr%s, grid %d, %s" % [job.label, cards, atlas.object_count(), "y" if atlas.object_count() == 1 else "ies", atlas.grid_size, atlas.resource_path])
	return cards
