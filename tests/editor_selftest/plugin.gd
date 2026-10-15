@tool
extends EditorPlugin

var _menu: MenuButton
var _root: Node


func _ready() -> void:
	_run.call_deferred()


# --- Helpers ---
func _find(n: Node, match_fn: Callable) -> Node:
	if match_fn.call(n):
		return n
	for c in n.get_children():
		var r := _find(c, match_fn)
		if r:
			return r
	return null


func _check(ok: bool, what: String) -> void:
	print("SELFTEST %s %s" % ["PASS" if ok else "FAIL", what])


func _select(names: Array) -> void:
	var sel := EditorInterface.get_selection()
	sel.clear()
	for n in names:
		sel.add_node(_root.get_node(n))
	for i in 5:
		await get_tree().process_frame


func _bake(dialog: ConfirmationDialog, expect: Array) -> bool:
	_menu.get_popup().id_pressed.emit(0)
	await get_tree().process_frame
	var shown := dialog.visible
	dialog.confirmed.emit()
	dialog.hide()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		if expect.all(func(p: String) -> bool: return _root.get_node_or_null(p) != null) and not _busy_plugin():
			return shown
	return false


func _busy_plugin() -> bool:
	return _root.get_tree().root.find_child("_OctaBakeRig", true, false) != null


func _undo() -> void:
	var urm := EditorInterface.get_editor_undo_redo()
	urm.get_history_undo_redo(urm.get_object_history_id(_root)).undo()
	await get_tree().process_frame


func _preset_flat(p: OctaBakeSettings.Preset) -> bool:
	var s := OctaBakeSettings.new()
	s.apply_preset(p)
	return not s.write_depth and s.fade == OctaLOD.Fade.NONE


func _cards(n: String) -> int:
	return OctaLOD.find_cards(_root.get_node(n)).size()


# --- Editor self-test ---
func _run() -> void:
	for i in 30:
		await get_tree().process_frame
	EditorInterface.open_scene_from_path("res://tests/editor_tmp/scene.tscn")
	EditorInterface.set_main_screen_editor("3D")
	for i in 10:
		await get_tree().process_frame
	_root = EditorInterface.get_edited_scene_root()
	_menu = _find(EditorInterface.get_base_control(), func(n: Node) -> bool: return n is MenuButton and n.text == "Octahedral Impostor LOD")
	var dialog: ConfirmationDialog = _find(EditorInterface.get_base_control(), func(n: Node) -> bool: return n is ConfirmationDialog and n.title == "Bake Octahedral Impostors")
	var inspector: EditorInspector = _find(dialog, func(n: Node) -> bool: return n is EditorInspector)
	_check(_menu != null and dialog != null and inspector != null, "menu, dialog and inspector exist")
	var settings: OctaBakeSettings = inspector.get_edited_object()
	settings.mode = OctaLOD.Mode.DYNAMIC_LOD
	settings.strip_source = false
	settings.max_atlas_size = 1024
	settings.quality = OctaAtlas.Quality.HIGH
	settings.lod_mode = OctaLOD.LodMode.DISTANCE
	settings.fade = OctaLOD.Fade.NONE
	settings.write_depth = true
	settings.split_parts = false
	settings.dedupe = false

	await _select(["Ball", "Ring"])
	_check(await _bake(dialog, ["Ball/OctaImpostor", "Ring_OctaImpostor"]), "bake dialog opens and cards are added")
	var mesh: GeometryInstance3D = _root.get_node("Ball/Mesh")
	var ring: GeometryInstance3D = _root.get_node("Ring")
	var card := _root.get_node("Ball/OctaImpostor")
	var ring_card: Node3D = _root.get_node("Ring_OctaImpostor")
	_check(mesh.get_node_or_null(mesh.visibility_parent) == card and card.owner == _root, "Ball mesh linked to its child card, owner set")
	_check(ring.get_node_or_null(ring.visibility_parent) == ring_card and ring_card.transform.is_equal_approx(ring.transform), "Ring linked to a sibling card with the same transform")
	_check(card is OctaImpostor and card.atlas != null and card.atlas.bake_settings != null, "cards are OctaImpostor nodes that remember their atlas and settings")
	var dock: Control = _find(EditorInterface.get_base_control(), func(n: Node) -> bool: return n.name == "Impostors" and n.has_method("refresh"))
	await _select(["Ball"])
	dock.refresh()
	dock._quality.select(OctaAtlas.Quality.ULTRA)
	dock._apply_quality()
	_check(card.quality == OctaAtlas.Quality.ULTRA and card.material_override.shader == OctaAtlas.SHADERS[OctaAtlas.Quality.ULTRA], "dock sets the quality of selected cards")
	await _undo()
	_check(card.quality == OctaAtlas.Quality.HIGH and card.material_override.shader == OctaAtlas.SHADERS[OctaAtlas.Quality.HIGH], "undo restores the quality")
	var ps := OctaBakeSettings.new()
	ps.apply_preset(OctaBakeSettings.Preset.COMPLEX_SHAPES)
	var preset_ui: OptionButton = _find(dialog, func(n: Node) -> bool: return n is OptionButton)
	_check(preset_ui != null and ps.quality == OctaAtlas.Quality.ULTRA and ps.split_parts and ps.back_layer, "presets exist in the dialog and fill the settings")
	_check(DirAccess.get_files_at("res://octa_impostors").size() == 1, "one atlas file saved: %s" % [DirAccess.get_files_at("res://octa_impostors")])

	_check(await _bake(dialog, ["Ball/OctaImpostor"]) and _cards("Ball") == 1 and _cards("Ring") == 1, "re-bake keeps one card per object")
	_check(mesh.get_node_or_null(mesh.visibility_parent) == _root.get_node("Ball/OctaImpostor"), "re-bake re-links the mesh to the new card")

	EditorInterface.save_scene()
	var txt := FileAccess.get_file_as_string("res://tests/editor_tmp/scene.tscn")
	_check(txt.count("octa_source") >= 2 and "instance_shader_parameters/octa_index" in txt, "saved scene has cards with metadata")

	await _select(["Ball", "Ring"])
	_menu.get_popup().id_pressed.emit(1)
	await get_tree().process_frame
	_check(_cards("Ball") == 0 and _cards("Ring") == 0 and mesh.visibility_parent.is_empty() and ring.visibility_parent.is_empty(), "remove deletes cards and clears links")
	await _undo()
	_check(_cards("Ball") == 1 and _cards("Ring") == 1 and mesh.get_node_or_null(mesh.visibility_parent) == _root.get_node("Ball/OctaImpostor"), "undo of remove restores cards and links")
	_check(_root.get_node("Ball/OctaImpostor").owner == _root, "restored card keeps its owner")
	var q: Dictionary = await OctaQuality.measure(_root.get_node("Ball"), EditorInterface.get_base_control())
	_check(not q.has("error") and q.iou > 0.8, "quality check measures the Ball card (match %.2f, wrong %.1f%%)" % [q.get("iou", 0.0), q.get("bad_pct", 100.0)])

	settings.split_parts = true
	await _select(["Ball"])
	_check(await _bake(dialog, ["Ball/Mesh_OctaImpostor"]) and _root.get_node_or_null("Ball/OctaImpostor") == null, "split parts bakes each mesh and replaces the old card")
	_check(mesh.get_node_or_null(mesh.visibility_parent) == _root.get_node("Ball/Mesh_OctaImpostor"), "split part links to its own card")
	settings.split_parts = false

	await _select(["Box"])
	settings.mode = OctaLOD.Mode.REPLACE
	var box: Node3D = _root.get_node("Box")
	_check(await _bake(dialog, ["Box_OctaImpostor"]) and not box.visible, "replace mode hides the source")
	await _select(["Box_OctaImpostor"])
	_menu.get_popup().id_pressed.emit(1)
	await get_tree().process_frame
	_check(box.visible and _root.get_node_or_null("Box_OctaImpostor") == null, "removing a replace card (selected directly) shows the source again")
	await _undo()
	_check(not box.visible and _root.get_node_or_null("Box_OctaImpostor") != null, "undo hides the source again")

	settings.mode = OctaLOD.Mode.DYNAMIC_LOD
	var progress: AcceptDialog = _find(EditorInterface.get_base_control(), func(n: Node) -> bool: return n is AcceptDialog and n.title == "Baking Octahedral Impostors")
	var files_before := DirAccess.get_files_at("res://octa_impostors").size()
	var ring_card_before := _root.get_node_or_null("Ring_OctaImpostor")
	await _select(["Ring"])
	_menu.get_popup().id_pressed.emit(0)
	await get_tree().process_frame
	dialog.confirmed.emit()
	dialog.hide()
	await get_tree().process_frame
	var shown := progress != null and progress.visible
	if progress != null:
		progress.confirmed.emit()
	for i in 300:
		await get_tree().process_frame
		if not _busy_plugin():
			break
	for i in 5:
		await get_tree().process_frame
	_check(shown and not progress.visible and DirAccess.get_files_at("res://octa_impostors").size() == files_before and _root.get_node_or_null("Ring_OctaImpostor") == ring_card_before, "progress window shows and Cancel stops the bake without changes")
	var plug = dock._plugin
	var ring_node: Node3D = _root.get_node("Ring")
	var ring2: Node3D = ring_node.duplicate()
	ring2.name = "Ring2"
	ring2.position = ring_node.position + Vector3(2, 0, 0)
	_root.add_child(ring2)
	ring2.owner = _root
	settings.mode = OctaLOD.Mode.DYNAMIC_LOD
	settings.dedupe = true
	await _select(["Ring", "Ring2"])
	_check(await _bake(dialog, ["Ring_OctaImpostor", "Ring2_OctaImpostor"]) and _root.get_node("Ring2_OctaImpostor").object_index == _root.get_node("Ring_OctaImpostor").object_index and _root.get_node("Ring_OctaImpostor").atlas.object_count() == 1, "dedupe: identical objects share one atlas entry")

	var old_id: int = _root.get_node("Ring2_OctaImpostor").get_instance_id()
	plug.rebake([_root.get_node("Ring2_OctaImpostor")])
	for i in 900:
		await get_tree().process_frame
		var now := _root.get_node_or_null("Ring2_OctaImpostor")
		if now != null and now.get_instance_id() != old_id and not _busy_plugin():
			break
	_check(_root.get_node_or_null("Ring2_OctaImpostor") != null and _root.get_node("Ring2_OctaImpostor").get_instance_id() != old_id and _cards("Ring2") == 1, "re-bake replaces the card with its saved settings")

	var base_card: OctaImpostor = _root.get_node("Ring_OctaImpostor")
	var extra := base_card.atlas.create_card(base_card.object_index, base_card.quality)
	extra.name = "RingExtra_OctaImpostor"
	extra.transform = base_card.transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, 1.5))
	_root.add_child(extra)
	extra.owner = _root
	plug.join_cards([base_card, extra])
	await get_tree().process_frame
	var mmi: MultiMeshInstance3D = _root.get_node_or_null("OctaJoined_1")
	_check(mmi != null and mmi.multimesh.instance_count == 2 and _root.get_node_or_null("Ring_OctaImpostor") == null and not ring_node.visible, "join merges two cards into one MultiMesh and hides the real objects")
	await _undo()
	_check(_root.get_node_or_null("OctaJoined_1") == null and _root.get_node_or_null("Ring_OctaImpostor") != null and ring_node.visible, "undo of join restores the cards and the real objects")

	var crate := MeshInstance3D.new()
	crate.name = "Crate"
	crate.mesh = BoxMesh.new()
	crate.position = Vector3(-3, 0, 0)
	_root.add_child(crate)
	crate.owner = _root
	settings.mode = OctaLOD.Mode.REPLACE
	settings.strip_source = true
	await _select(["Crate"])
	_check(await _bake(dialog, ["Crate_OctaImpostor"]) and _root.get_node_or_null("Crate") == null, "strip source deletes the real object in replace mode")
	await _undo()
	_check(_root.get_node_or_null("Crate") != null and _root.get_node_or_null("Crate_OctaImpostor") == null, "undo brings the stripped object back")
	settings.strip_source = false
	settings.mode = OctaLOD.Mode.DYNAMIC_LOD
	_check(OctaLOD.scene_candidates(_root, 40.0).size() >= 3, "bake scene lists the objects of the scene")

	var rt := OctaLOD.screen_size_for_distance(1.7, OctaLOD.distance_for_screen_size(1.7, 7.5, 60.0), 60.0)
	_check(absf(rt - 7.5) < 0.001 and absf(OctaLOD.distance_for_screen_size(1.0, 100.0, 90.0) - 1.0) < 0.001 and absf(OctaLOD.distance_for_screen_size(2.0, 10.0) - OctaLOD.distance_for_screen_size(1.0, 5.0)) < 0.001, "screen size and distance conversions round-trip")
	settings.lod_mode = OctaLOD.LodMode.SCREEN_SIZE
	settings.lod_screen_percent = 10.0
	settings.fade = OctaLOD.Fade.CROSSFADE
	settings.fade_margin = 4.0
	settings.write_depth = false
	await _select(["Ball"])
	_check(await _bake(dialog, ["Ball/OctaImpostor"]), "bake with screen size LOD, fade and flat depth")
	var lc: OctaImpostor = _root.get_node("Ball/OctaImpostor")
	var want_dist := OctaLOD.distance_for_screen_size(lc.atlas.bounds[lc.object_index].w * OctaLOD.world_scale(lc), 10.0)
	_check(lc.lod_mode == OctaLOD.LodMode.SCREEN_SIZE and absf(lc.visibility_range_begin - want_dist) < 0.01 and absf(lc.screen_percent - 10.0) < 0.001, "screen size card gets its distance from the object radius (%.2f m)" % lc.visibility_range_begin)
	_check(lc.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF and absf(lc.visibility_range_begin_margin - 4.0) < 0.001 and lc.fade == OctaLOD.Fade.CROSSFADE, "fade sets the card fade mode and margin")
	_check(mesh.get_node_or_null(mesh.visibility_parent) == lc and mesh.visibility_range_end == 0.0, "source stays linked to the fading card")
	var flat := lc.atlas.get_material(lc.quality)
	_check(not lc.atlas.write_depth and flat.shader.code.contains("NO_DEPTH_WRITE") and flat.shader != OctaAtlas.SHADERS[lc.quality] and lc.material_override == flat, "flat depth card uses the variant without DEPTH write")
	var core := FileAccess.get_file_as_string(OctaAtlas.SHADER_INCLUDE)
	_check(core.find("#ifndef NO_DEPTH_WRITE") < core.find("DEPTH = clip.z") and core.find("DEPTH = clip.z") > 0, "DEPTH is only written inside the depth define")
	await _select(["Ball"])
	dock.refresh()
	_check(dock._lod_mode.selected == OctaLOD.LodMode.SCREEN_SIZE and absf(dock._lod.value - 10.0) < 0.01 and dock._fade.selected == OctaLOD.Fade.CROSSFADE and not dock._depth.button_pressed, "dock shows the LOD mode, fade and depth of the card")
	dock._lod_mode.select(OctaLOD.LodMode.DISTANCE)
	dock._on_lod_mode(OctaLOD.LodMode.DISTANCE)
	dock._lod.value = 33.0
	dock._apply_lod()
	_check(lc.lod_mode == OctaLOD.LodMode.DISTANCE and absf(lc.visibility_range_begin - 33.0) < 0.001, "dock sets a distance LOD")
	await _undo()
	_check(lc.lod_mode == OctaLOD.LodMode.SCREEN_SIZE and absf(lc.visibility_range_begin - want_dist) < 0.01, "undo restores the screen size LOD")
	dock._fade.select(OctaLOD.Fade.NONE)
	dock._apply_fade()
	_check(lc.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED and lc.fade == OctaLOD.Fade.NONE, "dock turns the fade off")
	await _undo()
	_check(lc.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF, "undo restores the fade")
	dock._depth.button_pressed = true
	dock._apply_depth()
	_check(lc.atlas.write_depth and lc.atlas.get_material(lc.quality).shader == OctaAtlas.SHADERS[lc.quality], "dock turns depth writing back on")
	await _undo()
	_check(not lc.atlas.write_depth and lc.atlas.get_material(lc.quality).shader.code.contains("NO_DEPTH_WRITE"), "undo restores flat depth")
	var fq: Dictionary = await OctaQuality.measure(_root.get_node("Ball"), EditorInterface.get_base_control())
	_check(not fq.has("error") and fq.iou > 0.8, "quality check on a flat depth card with screen size LOD and fade gives a sane match (%.2f, wrong %.1f%%)" % [fq.get("iou", 0.0), fq.get("bad_pct", 100.0)])
	dock._debug.select(OctaDebug.Mode.VIEW_INDEX)
	dock._debug.item_selected.emit(OctaDebug.Mode.VIEW_INDEX)
	_check(OctaDebug.mode == OctaDebug.Mode.VIEW_INDEX and lc.atlas.get_material(lc.quality).shader.code.contains("DEBUG_MODE 2") and lc.atlas.get_material(lc.quality).shader.code.contains("NO_DEPTH_WRITE"), "dock debug view switches the card shaders")
	dock._debug.select(OctaDebug.Mode.OFF)
	dock._debug.item_selected.emit(OctaDebug.Mode.OFF)
	_check(OctaDebug.mode == OctaDebug.Mode.OFF and lc.atlas.get_material(lc.quality).shader.code.contains("DEBUG_MODE 0"), "debug view off restores the normal shaders")
	settings.mode = OctaLOD.Mode.REPLACE
	await _select(["Box"])
	_check(await _bake(dialog, ["Box_OctaImpostor"]), "replace mode bakes with fade enabled")
	var rc: OctaImpostor = _root.get_node("Box_OctaImpostor")
	_check(rc.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED and rc.visibility_range_begin == 0.0, "fade is ignored in replace mode (no real mesh)")
	await _select(["Box_OctaImpostor"])
	_menu.get_popup().id_pressed.emit(1)
	await get_tree().process_frame
	settings.mode = OctaLOD.Mode.DYNAMIC_LOD
	settings.lod_mode = OctaLOD.LodMode.DISTANCE
	settings.fade = OctaLOD.Fade.NONE
	settings.write_depth = true
	_check(OctaBakeSettings.new().write_depth and not _preset_flat(OctaBakeSettings.Preset.BALANCED) and _preset_flat(OctaBakeSettings.Preset.MOBILE), "presets: mobile has flat depth, others keep depth")

	var glow := MeshInstance3D.new()
	glow.mesh = BoxMesh.new()
	var gm := StandardMaterial3D.new()
	gm.roughness = 0.3
	gm.metallic = 0.8
	gm.emission_enabled = true
	gm.emission = Color(0.5, 0.0, 0.0)
	gm.emission_energy_multiplier = 2.0
	glow.mesh.material = gm
	var plain := MeshInstance3D.new()
	plain.mesh = BoxMesh.new()
	_root.add_child(glow)
	_root.add_child(plain)
	var ms := OctaBakeSettings.new()
	ms.grid_size = 3
	ms.max_atlas_size = 256
	var ga: OctaAtlas = await OctaBaker.bake([glow], _root, ms)
	var pa: OctaAtlas = await OctaBaker.bake([plain], _root, ms)
	var avg := func(tex: Texture2D) -> Color:
		var img := tex.get_image()
		var sum := Color(0, 0, 0, 0)
		var cnt := 0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.9:
					sum += c
					cnt += 1
		return sum / maxf(cnt, 1)
	var orm_avg: Color = avg.call(ga.orm)
	var em_avg: Color = avg.call(ga.emission)
	_check(ga.format_version == 3 and absf(orm_avg.g - 0.3) < 0.03 and absf(orm_avg.b - 0.8) < 0.03 and orm_avg.r > 0.95, "material map stores AO, roughness and metallic of a metallic box (%s)" % [orm_avg])
	_check(absf(em_avg.r - 0.5) < 0.03 and em_avg.g < 0.02 and ga.material_params[0].x == 2.0 and pa.orm != null and pa.emission == null, "emission map stores colour / intensity scale and is skipped when nothing glows (%s)" % [em_avg])
	glow.free()
	plain.free()

	EditorInterface.get_selection().clear()
	for i in 5:
		await get_tree().process_frame

	print("SELFTEST DONE")
	get_tree().quit()
