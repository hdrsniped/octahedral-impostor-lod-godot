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

	var qcard: OctaImpostor = _root.get_node("Ball/OctaImpostor")
	qcard.call("_check_quality")
	var q2: Variant = qcard.call("_check_quality")
	_check(q2 == false and qcard._checking, "a second Check Quality on the same card is ignored while one runs")
	for i in 600:
		if not qcard._checking:
			break
		await get_tree().process_frame
	_check(not qcard._checking, "the card's check releases its busy flag when done")
	await _select(["Ball"])
	var chk: Object = dock._plugin
	chk._check()
	var p2: Variant = chk._check()
	_check(p2 == false and chk._busy, "a second Check Quality from the menu or dock is ignored while one runs")
	for i in 600:
		if not chk._busy:
			break
		await get_tree().process_frame
	_check(not chk._busy, "the menu check releases its busy flag when done")

	var dc: OctaImpostor = qcard.atlas.create_card(0, OctaAtlas.Quality.HIGH)
	dc.lod_distance = 55.0
	_check(is_equal_approx(dc.lod_distance, 55.0), "lod_distance reads back before the card is in the tree")
	_root.add_child(dc)
	_check(is_equal_approx(dc.lod_distance, 55.0) and is_equal_approx(dc.visibility_range_begin, 55.0), "lod_distance stays 55 after entering the tree")
	_root.remove_child(dc)
	_check(is_equal_approx(dc.lod_distance, 55.0), "lod_distance stays 55 after leaving the tree")
	_root.add_child(dc)
	dc.set_lod(OctaLOD.LodMode.SCREEN_SIZE, 0.0, 10.0)
	var derived := OctaLOD.distance_for_screen_size(dc.card_radius(), 10.0)
	_check(absf(dc.lod_distance - derived) < 0.01 and absf(dc.lod_distance - 55.0) > 0.5, "screen size mode still derives its own lod_distance (%.2f m)" % dc.lod_distance)
	_root.remove_child(dc)
	dc.free()

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
	dock._shadow_views.value = 3
	dock._apply_shadow_views()
	_check(lc.atlas.shadow_views == 3 and lc.atlas.get_material(lc.quality).get_shader_parameter("shadow_views") == 3, "dock sets shadow views on the atlas and material")
	await _undo()
	_check(lc.atlas.shadow_views == 1 and lc.atlas.get_material(lc.quality).get_shader_parameter("shadow_views") == 1, "undo restores shadow views")
	settings.shadow_views = 3
	await _select(["Ball"])
	_check(await _bake(dialog, ["Ball/OctaImpostor"]) and _root.get_node("Ball/OctaImpostor").atlas.get_material(OctaAtlas.Quality.HIGH).get_shader_parameter("shadow_views") == 3, "baking with shadow_views=3 sets the material parameter")
	await _undo()
	settings.shadow_views = 1
	var ultra := OctaAtlas.Quality.ULTRA
	_check(not lc.atlas.precise_search and not lc.atlas.get_material(ultra).shader.code.contains("PRECISE_SEARCH") and not dock._precise.button_pressed, "precise search is off by default")
	dock._precise.button_pressed = true
	dock._apply_precise()
	_check(lc.atlas.precise_search and lc.atlas.get_material(ultra).shader.code.contains("PRECISE_SEARCH") and lc.atlas.get_material(lc.quality).shader.code.contains("NO_DEPTH_WRITE"), "dock turns precise search on for the atlas")
	await _undo()
	_check(not lc.atlas.precise_search and not lc.atlas.get_material(ultra).shader.code.contains("PRECISE_SEARCH"), "undo restores the normal Ultra shader")
	settings.quality = ultra
	settings.precise_search = true
	await _select(["Ball"])
	_check(await _bake(dialog, ["Ball/OctaImpostor"]), "bake with precise search")
	var pc: OctaImpostor = _root.get_node("Ball/OctaImpostor")
	_check(pc.atlas.precise_search and pc.atlas.bake_settings.precise_search and pc.material_override.shader.code.contains("PRECISE_SEARCH"), "precise_search reaches the atlas and the card material")
	_check(settings.cost_text().contains("Precise") and settings.describe(1).contains("precise"), "cost text and description mention precise search")
	await _undo()
	settings.precise_search = false
	settings.quality = OctaAtlas.Quality.HIGH
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

	var ro: OctaImpostor = _root.get_node("Ring_OctaImpostor")
	ro.tint = Color(1.0, 0.2, 0.2)
	ro.lod_distance = 63.0
	ro.depth_multiplier = 0.4
	var ro_id := ro.get_instance_id()
	await plug.rebake([ro])
	var ro2: OctaImpostor = _root.get_node("Ring_OctaImpostor")
	_check(ro2.get_instance_id() != ro_id and ro2.tint.is_equal_approx(Color(1.0, 0.2, 0.2)) and absf(ro2.lod_distance - 63.0) < 0.01 and absf(ro2.depth_multiplier - 0.4) < 0.001 and ro2.quality == OctaAtlas.Quality.HIGH, "re-bake keeps the properties changed on the card (tint, lod distance, depth)")

	settings.grid_size = 12
	settings.quality = OctaAtlas.Quality.HIGH
	settings.lod_distance = 40.0
	var grp := OctaImpostorGroup.new()
	grp.name = "Props"
	_root.add_child(grp)
	grp.owner = _root
	for spec in [["PropA", BoxMesh.new(), Vector3(0, 0, 4)], ["PropB", SphereMesh.new(), Vector3(2, 0, 4)]]:
		var pm := MeshInstance3D.new()
		pm.name = spec[0]
		pm.mesh = spec[1]
		pm.position = spec[2]
		grp.add_child(pm)
		pm.owner = _root
	grp.settings.grid_size = 8
	grp.settings.max_atlas_size = 512
	grp.settings.lod_distance = 25.0
	grp.settings.quality = OctaAtlas.Quality.MEDIUM
	_check(grp.target_nodes().size() == 2 and grp.cards().is_empty(), "group with no targets uses its direct children")
	grp.targets = [NodePath("PropB")]
	_check(grp.target_nodes().size() == 1 and grp.target_nodes()[0].name == "PropB", "group targets override the children")
	grp.targets = []
	_check(OctaLOD.scene_candidates(_root, 40.0).all(func(c: Dictionary) -> bool: return c.node != grp and c.node.get_parent() != grp) and OctaLOD.scene_candidates(_root, 40.0, false).any(func(c: Dictionary) -> bool: return c.node == grp), "plain scene candidates skip group targets; ignoring groups restores the old list")

	var picker = plug._picker
	plug.open_scene_picker()
	await get_tree().process_frame
	var picker_rows: Array = picker._rows
	var group_rows := picker_rows.filter(func(r: TreeItem) -> bool: return r.get_text(1).begins_with("Group "))
	_check(group_rows.size() == 1 and group_rows[0].get_text(1) == "Group Props (2 objects)" and group_rows[0].is_checked(0) and picker_rows.all(func(r: TreeItem) -> bool: return not r.get_text(1).begins_with("Prop")), "Bake Scene lists a group as one ticked item")
	picker.hide()
	var atlas_files := DirAccess.get_files_at("res://octa_impostors").size()
	picker.chosen.emit([grp])
	for i in 900:
		await get_tree().process_frame
		if grp.atlas != null and not plug._busy:
			break
	var pa_card: OctaImpostor = _root.get_node_or_null("Props/PropA_OctaImpostor")
	var pb_card: OctaImpostor = _root.get_node_or_null("Props/PropB_OctaImpostor")
	_check(grp.atlas != null and grp.atlas.grid_size == 8 and grp.atlas.object_count() == 2 and pa_card != null and pb_card != null and pa_card.atlas == grp.atlas and pb_card.atlas == grp.atlas, "group bake uses the group settings (grid 8, not the dialog's 12) and one atlas for all targets")
	_check(pa_card.quality == OctaAtlas.Quality.MEDIUM and absf(pa_card.lod_distance - 25.0) < 0.01 and DirAccess.get_files_at("res://octa_impostors").size() == atlas_files + 1 and grp.atlas.resource_path.contains("scene_props"), "group cards take quality and LOD from the group settings, atlas saved as scene_props")
	_check(_root.get_node("Props/PropA").visibility_parent == NodePath("../PropA_OctaImpostor") and grp.target_nodes().size() == 2, "group children stay in place and are linked to their sibling cards")
	await _undo()
	_check(_root.get_node_or_null("Props/PropA_OctaImpostor") == null and _root.get_node_or_null("Props/PropB_OctaImpostor") == null and grp.atlas == null and _root.get_node("Props/PropA").visibility_parent.is_empty(), "undo of a group bake removes the cards and clears the group atlas")

	_check(await plug.bake_group(grp) and grp.atlas != null, "Bake Group works again after undo")
	var group_atlas_1 := grp.atlas
	pa_card = _root.get_node("Props/PropA_OctaImpostor")
	pb_card = _root.get_node("Props/PropB_OctaImpostor")
	pa_card.lod_distance = 77.0
	pa_card.tint = Color(0.2, 0.8, 0.2)
	pa_card.quality = OctaAtlas.Quality.ULTRA
	pa_card.depth_multiplier = 1.5
	grp.settings.grid_size = 6
	grp.settings.lod_distance = 55.0
	await plug.rebake([pb_card])
	var pa2: OctaImpostor = _root.get_node("Props/PropA_OctaImpostor")
	var pb2: OctaImpostor = _root.get_node("Props/PropB_OctaImpostor")
	_check(grp.atlas != group_atlas_1 and grp.atlas.grid_size == 6 and pa2 != pa_card and pa2.atlas == grp.atlas, "re-bake of a grouped card re-bakes the group with the changed group settings (grid 8 to 6)")
	_check(absf(pa2.lod_distance - 77.0) < 0.01 and pa2.tint.is_equal_approx(Color(0.2, 0.8, 0.2)) and pa2.quality == OctaAtlas.Quality.ULTRA and absf(pa2.depth_multiplier - 1.5) < 0.001, "card overrides survive a group re-bake")
	_check(absf(pb2.lod_distance - 55.0) < 0.01 and pb2.quality == OctaAtlas.Quality.MEDIUM and pb2.tint == Color.WHITE, "untouched cards follow the new group settings")
	await _undo()
	_check(grp.atlas == group_atlas_1 and _root.get_node("Props/PropA_OctaImpostor") == pa_card, "undo of a group re-bake restores the old atlas and cards")
	_check(await plug.bake_group(grp, false), "Bake Group without keeping overrides")
	pa2 = _root.get_node("Props/PropA_OctaImpostor")
	_check(absf(pa2.lod_distance - 55.0) < 0.01 and pa2.quality == OctaAtlas.Quality.MEDIUM and pa2.tint == Color.WHITE and grp.atlas.grid_size == 6, "a fresh group bake uses the group settings for every card")

	await _select(["Props"])
	dock.refresh()
	_check(dock._group_info.text.contains("Props") and dock._group_info.text.contains("2 object") and dock._cards().size() == 2 and not dock._group_buttons[0].disabled, "dock shows the selected group and its cards")
	var gi: String = dock._info.text
	_check(gi.contains("Format version 4") and gi.contains("Maps: albedo, normal+depth") and gi.contains("Half-res material maps: ") and gi.contains("Write depth: on") and gi.contains("shadow views: 1") and gi.contains("precise search: off") and gi.contains("MB of video memory"), "dock atlas info lists format, maps, half-res, depth, shadow views, precise search and VRAM")
	await _select(["Ball"])
	dock.refresh()
	_check(dock._group_buttons[0].disabled, "dock group buttons are disabled when no group is selected")
	EditorInterface.save_scene()
	var gtxt := FileAccess.get_file_as_string("res://tests/editor_tmp/scene.tscn")
	_check(gtxt.contains("octa_impostor_group.gd") and gtxt.contains("octa_bake_settings.gd") and gtxt.contains("grid_size = 6"), "group and its settings are saved in the scene")
	var reloaded: PackedScene = ResourceLoader.load("res://tests/editor_tmp/scene.tscn", "", ResourceLoader.CACHE_MODE_IGNORE)
	var inst := reloaded.instantiate()
	var g2 := inst.get_node_or_null("Props") as OctaImpostorGroup
	_check(g2 != null and g2.settings != null and g2.settings.grid_size == 6 and g2.atlas != null and g2.atlas.resource_path == grp.atlas.resource_path, "reloaded group keeps its settings and atlas")
	inst.free()
	await _select(["Props"])
	_menu.get_popup().id_pressed.emit(1)
	await get_tree().process_frame
	_check(_cards("Props/PropA") == 0 and _cards("Props/PropB") == 0 and _root.get_node_or_null("Props/PropA_OctaImpostor") == null, "Remove with a group selected removes its cards")
	await _undo()
	grp.free()

	var glow := MeshInstance3D.new()
	glow.mesh = BoxMesh.new()
	var gm := StandardMaterial3D.new()
	gm.roughness = 0.3
	gm.metallic = 0.8
	gm.emission_enabled = true
	gm.emission = Color(0.5, 0.0, 0.0)
	gm.emission_energy_multiplier = 2.0
	var white := Image.create_empty(2, 2, false, Image.FORMAT_L8)
	white.fill(Color.WHITE)
	gm.roughness_texture = ImageTexture.create_from_image(white)
	gm.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
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
	_check(ga.format_version == 4 and ga.orm != null and absf(orm_avg.g - 0.3) < 0.03 and absf(orm_avg.b - 0.8) < 0.03 and orm_avg.r > 0.95, "material map stores AO, roughness and metallic of a metallic box (%s)" % [orm_avg])
	_check(absf(em_avg.r - 0.5) < 0.03 and em_avg.g < 0.02 and ga.material_params[0].x == 2.0 and pa.orm == null and pa.emission == null and is_equal_approx(pa.material_params[0].z, 1.0) and pa.surface_params[0].x > 0.0, "emission map stores colour / intensity scale; ORM and emission are skipped for a constant plain box (%s)" % [em_avg])
	var half_s := ms.duplicate()
	half_s.half_res_material_maps = false
	var gf: OctaAtlas = await OctaBaker.bake([glow], _root, half_s)
	_check(ga.has_half_res_maps() and not gf.has_half_res_maps() and ga.orm.get_width() < gf.orm.get_width() and ga.vram_bytes() < gf.vram_bytes(), "half-res material maps are smaller than full-res ones (%d vs %d bytes)" % [ga.vram_bytes(), gf.vram_bytes()])
	var ti: String = dock._atlas_text(ga)
	var tp: String = dock._atlas_text(pa)
	_check(ti.contains("Maps: albedo, normal+depth, ORM, emission") and ti.contains("Half-res material maps: yes") and tp.contains("ORM skipped (constant materials)") and not tp.contains("emission") and tp.contains("Half-res material maps: no") and dock._atlas_text(gf).contains("Half-res material maps: no"), "dock atlas info shows which maps exist and whether they are half-res")
	_check(ms.describe(1, [plain]).contains("constant materials") and not ms.describe(1, [glow]).contains("constant materials"), "dialog estimate knows when the material map is skipped")
	var mixed := Node3D.new()
	for r in [0.1, 0.9]:
		var part := MeshInstance3D.new()
		part.mesh = BoxMesh.new()
		var pm := StandardMaterial3D.new()
		pm.roughness = r
		part.mesh.material = pm
		mixed.add_child(part)
	_root.add_child(mixed)
	var ns := ms.duplicate()
	ns.material_maps = false
	_check(ns.describe(1, [mixed]).contains("averaged") and ns.cost_text([mixed]).contains("averaged"), "estimate and cost text say roughness is averaged when material maps are off and the materials differ")
	_check(not ns.describe(1, [plain]).contains("averaged") and not ns.cost_text([plain]).contains("averaged") and not ns.describe(1).contains("averaged"), "no averaging note for constant materials or without sources")
	ns.material_maps = true
	_check(not ns.describe(1, [mixed]).contains("averaged") and not ns.cost_text([mixed]).contains("averaged"), "no averaging note while material maps are on")
	mixed.free()
	glow.free()
	plain.free()

	await _options_checks(dock, plug, dialog, settings)

	EditorInterface.get_selection().clear()
	for i in 5:
		await get_tree().process_frame

	print("SELFTEST DONE")
	get_tree().quit()


# --- Options and re-bake all ---
func _options_checks(dock: Object, plug: Object, dialog: ConfirmationDialog, settings: OctaBakeSettings) -> void:
	var fov := {}
	for pi in ProjectSettings.get_property_list():
		if pi.name == OctaLOD.FOV_SETTING:
			fov = pi
	_check(ProjectSettings.has_setting(OctaLOD.FOV_SETTING) and fov.get("type") == TYPE_FLOAT and fov.get("hint") == PROPERTY_HINT_RANGE and String(fov.get("hint_string", "")).begins_with("10,120") and is_equal_approx(ProjectSettings.property_get_revert(OctaLOD.FOV_SETTING), 75.0), "octa_lod/reference_fov is registered as a 10-120 float with default 75")

	var pm := _menu.get_popup()
	var items := []
	for i in pm.item_count:
		items.append(pm.get_item_text(i))
	_check(["Bake Selected...", "Bake Scene...", "Bake Group", "Re-bake Selected Impostors", "Re-bake All Impostors in Scene", "Join Selected Impostors", "Remove Impostors from Selected", "Check Quality of Selected", "Select Impostors in Scene", "Help..."].all(func(t: String) -> bool: return items.has(t)), "menu lists every action including re-bake all and select all")
	pm.id_pressed.emit(plug.HELP)
	await get_tree().process_frame
	var help: AcceptDialog = _find(EditorInterface.get_base_control(), func(n: Node) -> bool: return n is AcceptDialog and n.title == "Octahedral Impostor LOD - Help")
	var help_text: String = _find(help, func(n: Node) -> bool: return n is RichTextLabel).get_parsed_text() if help != null else ""
	_check(help != null and help.visible and ["Bake Scene", "Re-bake All", "Select Impostors in Scene", "Overdraw", "precise search", "half-res", "Shadow views", "--help", "OctaBakeQueue.shared", "OctaImpostorGroup"].all(func(t: String) -> bool: return help_text.contains(t)), "help dialog describes the menu, groups, options, debug views, CLI and queue")
	if help != null:
		help.hide()

	var presets := {}
	for p in [OctaBakeSettings.Preset.MOBILE, OctaBakeSettings.Preset.BALANCED, OctaBakeSettings.Preset.HIGH_QUALITY, OctaBakeSettings.Preset.COMPLEX_SHAPES]:
		var s := OctaBakeSettings.new()
		s.precise_search = true
		s.shadow_views = 3
		s.half_res_material_maps = not s.half_res_material_maps
		s.write_depth = not p == OctaBakeSettings.Preset.MOBILE
		s.fade = OctaLOD.Fade.CROSSFADE if p != OctaBakeSettings.Preset.HIGH_QUALITY else OctaLOD.Fade.NONE
		s.apply_preset(p)
		presets[p] = s
	var mo: OctaBakeSettings = presets[OctaBakeSettings.Preset.MOBILE]
	var ba: OctaBakeSettings = presets[OctaBakeSettings.Preset.BALANCED]
	var hq: OctaBakeSettings = presets[OctaBakeSettings.Preset.HIGH_QUALITY]
	var cs: OctaBakeSettings = presets[OctaBakeSettings.Preset.COMPLEX_SHAPES]
	_check(not mo.write_depth and mo.half_res_material_maps and mo.shadow_views == 1 and not mo.precise_search and mo.fade == OctaLOD.Fade.NONE, "Mobile preset: flat depth, half-res maps, 1 shadow view, no precise search, no fade")
	_check(ba.write_depth and ba.half_res_material_maps and ba.shadow_views == 1 and not ba.precise_search and ba.fade == OctaLOD.Fade.NONE, "Balanced preset: depth, half-res maps, 1 shadow view, no precise search, no fade")
	_check(hq.write_depth and not hq.half_res_material_maps and hq.shadow_views == 2 and not hq.precise_search and hq.fade == OctaLOD.Fade.CROSSFADE, "High quality preset: depth, full-res maps, 2 shadow views, crossfade")
	_check(cs.write_depth and cs.half_res_material_maps and cs.shadow_views == 1 and not cs.precise_search and cs.fade == OctaLOD.Fade.NONE and cs.quality == OctaAtlas.Quality.ULTRA and cs.split_parts and cs.back_layer and cs.search_steps == 12, "Complex shapes preset: Ultra, split parts, back layer, 12 steps, precise search left off")
	var preset_ui: OptionButton = _find(dialog, func(n: Node) -> bool: return n is OptionButton)
	_check(OctaBakeSettings.PRESET_TIPS.size() == OctaBakeSettings.PRESET_NAMES.size() and preset_ui.item_count == OctaBakeSettings.PRESET_NAMES.size() and range(preset_ui.item_count).all(func(i: int) -> bool: return not preset_ui.get_item_tooltip(i).is_empty()), "every preset has a tooltip in the dialog")

	_check(dock._debug.item_count == OctaDebug.Mode.size() and dock._debug.get_item_text(OctaDebug.Mode.OVERDRAW) == "Overdraw" and OctaDebug.mode_names().size() == OctaDebug.Mode.size(), "debug dropdown has an entry for every OctaDebug mode")
	_check(_find(dock, func(n: Node) -> bool: return n is Button and n.text == "Re-bake All") != null and _find(dock, func(n: Node) -> bool: return n is Button and n.text == "Select All") != null, "dock has Re-bake All and Select All buttons")

	plug.select_scene_cards()
	for i in 5:
		await get_tree().process_frame
	var all_cards: Array = plug.scene_cards()
	_check(not all_cards.is_empty() and EditorInterface.get_selection().get_selected_nodes().size() == all_cards.size(), "Select Impostors in Scene selects every card (%d)" % all_cards.size())
	pm.id_pressed.emit(plug.REMOVE)
	await get_tree().process_frame
	_check(plug.scene_cards().is_empty(), "scene is clean before the re-bake all test")

	var spec := {RebakeA = [BoxMesh.new(), Vector3(6, 0, 6), 4], RebakeB = [SphereMesh.new(), Vector3(8, 0, 6), 6]}
	for nm: String in spec:
		var mi := MeshInstance3D.new()
		mi.name = nm
		mi.mesh = spec[nm][0]
		mi.position = spec[nm][1]
		_root.add_child(mi)
		mi.owner = _root
	settings.mode = OctaLOD.Mode.DYNAMIC_LOD
	settings.max_atlas_size = 256
	settings.dedupe = true
	for nm: String in spec:
		settings.grid_size = spec[nm][2]
		await _select([nm])
		_check(await _bake(dialog, [nm + "_OctaImpostor"]), "bake %s with grid %d" % [nm, spec[nm][2]])
	var ca: OctaImpostor = _root.get_node("RebakeA_OctaImpostor")
	var cb: OctaImpostor = _root.get_node("RebakeB_OctaImpostor")
	ca.tint = Color(0.3, 0.9, 0.3)
	settings.grid_size = 12
	await plug.rebake_scene()
	var na: OctaImpostor = _root.get_node("RebakeA_OctaImpostor")
	var nb: OctaImpostor = _root.get_node("RebakeB_OctaImpostor")
	_check(na != ca and nb != cb and plug.scene_cards().size() == 2, "Re-bake All replaces every card in the scene")
	_check(na.atlas.grid_size == 4 and nb.atlas.grid_size == 6 and na.atlas != nb.atlas, "Re-bake All uses each card's own atlas settings, not the dialog's")
	_check(na.tint.is_equal_approx(Color(0.3, 0.9, 0.3)) and nb.tint == Color.WHITE, "Re-bake All keeps the properties changed on a card")
	await _undo()
	await _undo()
	_check(_root.get_node("RebakeA_OctaImpostor") == ca and _root.get_node("RebakeB_OctaImpostor") == cb, "undo of Re-bake All restores the old cards")
