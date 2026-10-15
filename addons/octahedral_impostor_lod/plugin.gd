@tool
extends EditorPlugin

enum { BAKE, REMOVE, CHECK, SCENE, JOIN, REBAKE, HELP }

var _menu: MenuButton
var _dialog: ConfirmationDialog
var _info: Label
var _preset: OptionButton
var _inspector: EditorInspector
var _progress: AcceptDialog
var _progress_bar: ProgressBar
var _progress_label: Label
var _job: OctaBakeJob
var _dock: Control
var _picker: ConfirmationDialog
var _settings := OctaBakeSettings.new()
var _busy := false


# --- Menu and dialog ---
func _enter_tree() -> void:
	_menu = MenuButton.new()
	_menu.text = "Octahedral Impostor LOD"
	_menu.tooltip_text = "Bake the selected 3D objects into lightweight octahedral impostors"
	var pm := _menu.get_popup()
	pm.add_item("Bake Selected...", BAKE)
	pm.add_item("Bake Scene...", SCENE)
	pm.add_item("Remove Impostors from Selected", REMOVE)
	pm.add_item("Join Selected Impostors", JOIN)
	pm.add_item("Re-bake Selected Impostors", REBAKE)
	pm.add_item("Check Quality of Selected", CHECK)
	pm.add_separator()
	pm.add_item("Help (README)", HELP)
	pm.id_pressed.connect(_on_menu)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _menu)

	_dialog = ConfirmationDialog.new()
	_dialog.title = "Bake Octahedral Impostors"
	_dialog.ok_button_text = "Bake"
	_dialog.min_size = Vector2i(Vector2(460, 560) * EditorInterface.get_editor_scale())
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	var pl := Label.new()
	pl.text = "Preset"
	row.add_child(pl)
	_preset = OptionButton.new()
	_preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for preset_name in OctaBakeSettings.PRESET_NAMES:
		_preset.add_item(preset_name)
	_preset.tooltip_text = "Fills in the settings below for a typical use. Change anything afterwards."
	_preset.item_selected.connect(_on_preset)
	row.add_child(_preset)
	box.add_child(row)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	_inspector = EditorInspector.new()
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector.property_edited.connect(func(_p: String) -> void:
		_preset.select(0)
		_update_info())
	box.add_child(_inspector)
	_dialog.add_child(box)
	_dialog.confirmed.connect(_bake)
	EditorInterface.get_base_control().add_child(_dialog)
	_load_settings()
	_inspector.edit(_settings)
	_build_progress()
	_picker = preload("res://addons/octahedral_impostor_lod/octa_scene_picker.gd").new()
	_picker.chosen.connect(_on_picked)
	EditorInterface.get_base_control().add_child(_picker)
	_dock = preload("res://addons/octahedral_impostor_lod/octa_dock.gd").new(self)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _menu)
	_menu.queue_free()
	_dialog.queue_free()
	_progress.queue_free()
	_picker.queue_free()
	remove_control_from_docks(_dock)
	_dock.queue_free()


func _on_menu(id: int) -> void:
	match id:
		BAKE:
			if _busy:
				_toast("A bake is already running.", EditorToaster.SEVERITY_WARNING)
			elif _selected().is_empty():
				_toast("Select one or more 3D objects with meshes first.", EditorToaster.SEVERITY_WARNING)
			else:
				_update_info()
				_dialog.popup_centered()
		SCENE:
			open_scene_picker()
		REMOVE:
			_remove()
		JOIN:
			join_cards(selected_cards())
		REBAKE:
			rebake(selected_cards())
		CHECK:
			_check()
		HELP:
			OS.shell_open(ProjectSettings.globalize_path("res://addons/octahedral_impostor_lod/README.md"))


func _selected() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in EditorInterface.get_selection().get_top_selected_nodes():
		if n is Node3D and not n.has_meta(OctaAtlas.CARD_META):
			out.append(n)
	return out


func _update_info() -> void:
	var nodes := _selected()
	var names := ", ".join(nodes.slice(0, 5).map(func(n: Node) -> String: return n.name))
	if nodes.size() > 5:
		names += ", ..."
	_info.text = "Selected: %s\n%s\n%s" % [names, _settings.describe(nodes.size()), _settings.cost_text()]


func _on_preset(i: int) -> void:
	_settings.apply_preset(i)
	_inspector.edit(null)
	_inspector.edit(_settings)
	_update_info()


func open_bake_dialog() -> void:
	_on_menu(BAKE)


# --- Progress ---
func _build_progress() -> void:
	_progress = AcceptDialog.new()
	_progress.title = "Baking Octahedral Impostors"
	_progress.ok_button_text = "Cancel"
	_progress.exclusive = false
	_progress.min_size = Vector2i(Vector2(380, 0) * EditorInterface.get_editor_scale())
	var box := VBoxContainer.new()
	_progress_label = Label.new()
	box.add_child(_progress_label)
	_progress_bar = ProgressBar.new()
	box.add_child(_progress_bar)
	_progress.add_child(box)
	_progress.confirmed.connect(_cancel_bake)
	_progress.canceled.connect(_cancel_bake)
	EditorInterface.get_base_control().add_child(_progress)


func _cancel_bake() -> void:
	if _job != null:
		_job.cancel()
		_progress_label.text = "Cancelling..."


func _on_progress(done: int, total: int, text: String) -> void:
	_progress_bar.max_value = total
	_progress_bar.value = done
	var left := _job.seconds_left(done, total)
	_progress_label.text = "%s - view %d of %d%s" % [text, done, total, "" if left < 0.0 else ", about %ds left" % ceili(left)]


# --- Bake ---
func _bake() -> void:
	var nodes := _selected()
	if nodes.is_empty():
		return
	_save_settings()
	_run_bake(nodes, _settings.duplicate())


func rebake(cards: Array) -> void:
	var nodes: Array[Node3D] = []
	var settings: OctaBakeSettings = null
	for c in cards:
		if c is OctaImpostor and c.atlas != null and c.atlas.bake_settings != null:
			settings = c.atlas.bake_settings
			var src := _source_of(c)
			if src != null and not nodes.has(src):
				nodes.append(src)
	if nodes.is_empty() or settings == null:
		_toast("Select impostor cards that still have their source object to re-bake them.", EditorToaster.SEVERITY_WARNING)
		return
	_run_bake(nodes, settings.duplicate())


func _run_bake(nodes: Array[Node3D], s: OctaBakeSettings) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or _busy:
		return
	for n in nodes:
		if not OctaLOD.geometry_below(n).any(func(g: Node) -> bool: return g is MeshInstance3D and g.mesh != null and g.is_visible_in_tree()):
			_toast("'%s' has no visible mesh to bake (select the object that contains the MeshInstance3D)." % n.name, EditorToaster.SEVERITY_ERROR)
			return
		if n == root and not OctaLOD.is_child_card(n, s.mode):
			_toast("'%s' is the scene root; this mode needs a parent. Select a child node instead." % n.name, EditorToaster.SEVERITY_ERROR)
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
	if bake_list.size() > OctaAtlas.MAX_OBJECTS:
		_toast("Bake at most %d different objects at a time." % OctaAtlas.MAX_OBJECTS, EditorToaster.SEVERITY_ERROR)
		return

	var scene_name := root.scene_file_path.get_file().get_basename()
	if scene_name.is_empty():
		scene_name = String(root.name)
	var base := s.output_dir.path_join("%s_%s" % [scene_name.to_snake_case(), String(nodes[0].name).to_snake_case()])
	var path := base + ".res"
	var i := 2
	while ResourceLoader.exists(path):
		path = "%s_%d.res" % [base, i]
		i += 1

	_busy = true
	_job = OctaBakeJob.new()
	_job.progress.connect(_on_progress)
	_progress_bar.value = 0
	_progress_label.text = "Starting..."
	_progress.popup_centered()
	var atlas := await OctaBaker.bake_to_file(bake_list, EditorInterface.get_base_control(), path, s, _job)
	var cancelled := _job.cancelled
	_job = null
	_progress.hide()
	_busy = false
	if atlas == null:
		if cancelled:
			_toast("Bake cancelled. Nothing was changed.", EditorToaster.SEVERITY_WARNING)
		else:
			_toast("Bake failed. See the Output panel for the reason.", EditorToaster.SEVERITY_ERROR)
		return
	EditorInterface.get_resource_filesystem().scan()
	if root != EditorInterface.get_edited_scene_root() or not bake_list.all(func(n: Node) -> bool: return is_instance_valid(n)):
		_toast("The scene changed during the bake; the atlas was saved to %s but no cards were added." % path, EditorToaster.SEVERITY_WARNING)
		return

	var ur := get_undo_redo()
	ur.create_action("Bake Octahedral Impostors")
	var replaced: Array[Node3D] = []
	for o in nodes:
		for card in OctaLOD.find_cards_below(o):
			if not replaced.has(card):
				_remove_card_actions(ur, _source_of(card), card)
				replaced.append(card)
	for k in targets.size():
		var src := targets[k]
		_add_card_actions(ur, root, src, atlas.create_card(index[k], s.quality), atlas.card_transform(src), s, replaced)
	ur.commit_action()
	_toast("Baked %d object(s) into %s (%s)." % [bake_list.size(), path, s.describe(bake_list.size()).get_slice(" -> ", 1)])
	_dock.refresh()


func _add_card_actions(ur: EditorUndoRedoManager, root: Node, src: Node3D, card: MeshInstance3D, xform: Transform3D, s: OctaBakeSettings, replacing: Array) -> void:
	var as_child := OctaLOD.is_child_card(src, s.mode)
	var parent := src if as_child else src.get_parent()
	if as_child:
		card.name = _unique_name(parent, "OctaImpostor", replacing)
		card.set_meta(OctaLOD.SOURCE_META, NodePath(".."))
	else:
		card.name = _unique_name(parent, String(src.name) + "_OctaImpostor", replacing)
		card.transform = xform
		card.set_meta(OctaLOD.SOURCE_META, NodePath("../" + String(src.name)))
	card.set_meta(OctaLOD.MODE_META, s.mode)
	ur.add_do_method(parent, "add_child", card)
	ur.add_do_property(card, "owner", root)
	ur.add_do_reference(card)
	ur.add_undo_method(parent, "remove_child", card)
	var cs := card.transform.basis.get_scale().abs()
	card.configure(s, OctaLOD.world_scale(parent) * maxf(cs.x, maxf(cs.y, cs.z)))
	if s.mode == OctaLOD.Mode.DYNAMIC_LOD:
		for gi in OctaLOD.geometry_below(src):
			var hops := _depth(src, gi) + (0 if as_child else 1)
			ur.add_do_property(gi, "visibility_parent", NodePath("../".repeat(hops) + String(card.name)))
			ur.add_undo_property(gi, "visibility_parent", gi.visibility_parent)
	elif s.mode == OctaLOD.Mode.REPLACE:
		ur.add_do_property(src, "visible", false)
		ur.add_undo_property(src, "visible", src.visible)
		if s.strip_source and not s.split_parts:
			var sp := src.get_parent()
			ur.add_do_method(sp, "remove_child", src)
			ur.add_undo_method(sp, "add_child", src)
			ur.add_undo_method(sp, "move_child", src, src.get_index())
			ur.add_undo_property(src, "owner", src.owner)
			ur.add_undo_reference(src)


# --- Remove ---
func _remove_card_actions(ur: EditorUndoRedoManager, src: Node3D, card: Node) -> void:
	var parent := card.get_parent()
	ur.add_undo_method(parent, "add_child", card)
	ur.add_undo_method(parent, "move_child", card, card.get_index())
	ur.add_undo_property(card, "owner", card.owner)
	ur.add_undo_reference(card)
	if src != null:
		for gi in OctaLOD.geometry_below(src):
			if gi.get_node_or_null(gi.visibility_parent) == card:
				ur.add_do_property(gi, "visibility_parent", NodePath())
				ur.add_undo_property(gi, "visibility_parent", gi.visibility_parent)
		if card.get_meta(OctaLOD.MODE_META, OctaLOD.Mode.DYNAMIC_LOD) == OctaLOD.Mode.REPLACE:
			ur.add_do_property(src, "visible", true)
			ur.add_undo_property(src, "visible", src.visible)
	ur.add_do_method(parent, "remove_child", card)


func _remove() -> void:
	var pairs := {}
	for n in EditorInterface.get_selection().get_top_selected_nodes():
		if n.has_meta(OctaAtlas.CARD_META):
			pairs[n] = _source_of(n)
		elif n is Node3D:
			for card in OctaLOD.find_cards_below(n):
				pairs[card] = _source_of(card)
	if pairs.is_empty():
		_toast("No octahedral impostors found. Select a baked object or its card.", EditorToaster.SEVERITY_WARNING)
		return
	var ur := get_undo_redo()
	ur.create_action("Remove Impostors")
	for card: Node in pairs:
		_remove_card_actions(ur, pairs[card], card)
	ur.commit_action()
	_toast("Removed %d impostor(s)." % pairs.size())
	_dock.refresh()


# --- Join and selection ---
func join_cards(cards: Array) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var groups := {}
	for c in cards:
		if c is OctaImpostor and c.atlas != null and c.is_inside_tree():
			var cell := Vector3i((c.global_position / _settings.join_cell).floor())
			var key := "%d|%d|%d|%s" % [c.atlas.get_instance_id(), c.object_index, c.quality, cell]
			if not groups.has(key):
				groups[key] = []
			groups[key].append(c)
	var ur := get_undo_redo()
	ur.create_action("Join Impostors")
	var draw_calls := 0
	var joined := 0
	for key in groups:
		var g: Array = groups[key]
		if g.size() < 2:
			continue
		var first: OctaImpostor = g[0]
		var xforms: Array = []
		var customs: Array = []
		for c: OctaImpostor in g:
			xforms.append(root.global_transform.affine_inverse() * c.global_transform)
			customs.append(Color(c.tint.r, c.tint.g, c.tint.b, maxf(c.depth_multiplier, 0.001)))
		var mmi := first.atlas.create_multimesh(first.object_index, xforms, first.quality, customs)
		var nm := "OctaJoined_%d" % (draw_calls + 1)
		var i := 2
		while root.has_node(NodePath(nm)):
			nm = "OctaJoined_%d_%d" % [draw_calls + 1, i]
			i += 1
		mmi.name = nm
		ur.add_do_method(root, "add_child", mmi)
		ur.add_do_property(mmi, "owner", root)
		ur.add_do_reference(mmi)
		ur.add_undo_method(root, "remove_child", mmi)
		for c: OctaImpostor in g:
			var src := _source_of(c)
			var was_visible := src.visible if src != null else true
			_remove_card_actions(ur, src, c)
			if src != null:
				ur.add_do_property(src, "visible", false)
				ur.add_undo_property(src, "visible", was_visible)
		draw_calls += 1
		joined += g.size()
	if draw_calls == 0:
		_toast("Select at least two impostors of the same object that are close together to join them.", EditorToaster.SEVERITY_WARNING)
		return
	ur.commit_action()
	_toast("Joined %d impostor(s) into %d draw call(s). Their real meshes are hidden; undo restores them." % [joined, draw_calls])
	_dock.refresh()


func selected_cards() -> Array:
	var out := []
	for n in EditorInterface.get_selection().get_top_selected_nodes():
		if n.has_meta(OctaAtlas.CARD_META):
			if not out.has(n):
				out.append(n)
		elif n is Node3D:
			for c in OctaLOD.find_cards_below(n):
				if not out.has(c):
					out.append(c)
	return out


func _source_of(card: Node) -> Node3D:
	if not card.is_inside_tree():
		return null
	return card.get_node_or_null(card.get_meta(OctaLOD.SOURCE_META, NodePath(".."))) as Node3D


# --- Bake Scene ---
func open_scene_picker() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_toast("Open a scene first.", EditorToaster.SEVERITY_WARNING)
		return
	_picker.populate(root, _settings)
	_picker.popup_centered()


func _on_picked(nodes: Array) -> void:
	if nodes.is_empty():
		_toast("Nothing was ticked, so nothing was baked.", EditorToaster.SEVERITY_WARNING)
		return
	var sel := EditorInterface.get_selection()
	sel.clear()
	for n in nodes:
		sel.add_node(n)
	_on_menu(BAKE)


# --- Quality check ---
func _check() -> void:
	if _busy:
		_toast("A bake or check is already running.", EditorToaster.SEVERITY_WARNING)
		return
	var nodes := _selected()
	if nodes.is_empty():
		_toast("Select baked objects to check.", EditorToaster.SEVERITY_WARNING)
		return
	_busy = true
	for n in nodes:
		var r: Dictionary = await OctaQuality.measure(n, EditorInterface.get_base_control())
		if r.has("error"):
			_toast(r.error, EditorToaster.SEVERITY_WARNING)
			continue
		var msg := "%s: shape match %.0f%% (worst view %.0f%%), wrong pixels %.1f%%. %s" % [r.name, r.iou * 100.0, r.worst_iou * 100.0, r.bad_pct, r.suggestion]
		print("Octahedral Impostor LOD quality check - ", msg)
		_toast(msg, EditorToaster.SEVERITY_INFO if r.good else EditorToaster.SEVERITY_WARNING)
	_busy = false


# --- Helpers ---
func _unique_name(parent: Node, base: String, ignore: Array) -> String:
	var n := base
	var i := 2
	while parent.has_node(NodePath(n)) and not parent.get_node(NodePath(n)) in ignore:
		n = "%s%d" % [base, i]
		i += 1
	return n


func _depth(src: Node, gi: Node) -> int:
	var d := 0
	while gi != src:
		gi = gi.get_parent()
		d += 1
	return d


func _toast(msg: String, severity := EditorToaster.SEVERITY_INFO) -> void:
	EditorInterface.get_editor_toaster().push_toast("Octahedral Impostor LOD: " + msg, severity)
	if severity != EditorToaster.SEVERITY_INFO:
		print_rich("[color=yellow]Octahedral Impostor LOD:[/color] ", msg)


# --- Remembered settings ---
func _stored_properties() -> Array[String]:
	var out: Array[String] = []
	for p in _settings.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(p.name)
	return out


func _save_settings() -> void:
	var d := {}
	for p in _stored_properties():
		d[p] = _settings.get(p)
	EditorInterface.get_editor_settings().set_project_metadata("octa_lod", "bake_settings", d)


func _load_settings() -> void:
	var d: Dictionary = EditorInterface.get_editor_settings().get_project_metadata("octa_lod", "bake_settings", {})
	for p in _stored_properties():
		if d.has(p):
			_settings.set(p, d[p])
