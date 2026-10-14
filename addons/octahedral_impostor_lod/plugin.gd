@tool
extends EditorPlugin

enum { BAKE, REMOVE, HELP }

var _menu: MenuButton
var _dialog: ConfirmationDialog
var _info: Label
var _settings := OctaBakeSettings.new()
var _busy := false


# --- Menu and dialog ---
func _enter_tree() -> void:
	_menu = MenuButton.new()
	_menu.text = "Octahedral Impostor LOD"
	_menu.tooltip_text = "Bake the selected 3D objects into lightweight octahedral impostors"
	var pm := _menu.get_popup()
	pm.add_item("Bake Selected...", BAKE)
	pm.add_item("Remove Impostors from Selected", REMOVE)
	pm.add_separator()
	pm.add_item("Help (README)", HELP)
	pm.id_pressed.connect(_on_menu)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _menu)

	_dialog = ConfirmationDialog.new()
	_dialog.title = "Bake Octahedral Impostors"
	_dialog.ok_button_text = "Bake"
	_dialog.min_size = Vector2i(Vector2(460, 560) * EditorInterface.get_editor_scale())
	var box := VBoxContainer.new()
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	var inspector := EditorInspector.new()
	inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector.property_edited.connect(func(_p: String) -> void: _update_info())
	box.add_child(inspector)
	_dialog.add_child(box)
	_dialog.confirmed.connect(_bake)
	EditorInterface.get_base_control().add_child(_dialog)
	_load_settings()
	inspector.edit(_settings)


func _exit_tree() -> void:
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _menu)
	_menu.queue_free()
	_dialog.queue_free()


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
		REMOVE:
			_remove()
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
	_info.text = "Selected: %s\n%s" % [names, _settings.describe(nodes.size())]


# --- Bake ---
func _bake() -> void:
	var nodes := _selected()
	var root := EditorInterface.get_edited_scene_root()
	if nodes.is_empty() or root == null:
		return
	_save_settings()
	var s: OctaBakeSettings = _settings.duplicate()
	for n in nodes:
		if not OctaLOD.geometry_below(n).any(func(g: Node) -> bool: return g is MeshInstance3D and g.mesh != null and g.is_visible_in_tree()):
			_toast("'%s' has no visible mesh to bake (select the object that contains the MeshInstance3D)." % n.name, EditorToaster.SEVERITY_ERROR)
			return
		if n == root and not OctaLOD.is_child_card(n, s.mode):
			_toast("'%s' is the scene root; this mode needs a parent. Select a child node instead." % n.name, EditorToaster.SEVERITY_ERROR)
			return
	if nodes.size() > OctaAtlas.MAX_OBJECTS:
		_toast("Bake at most %d objects at a time." % OctaAtlas.MAX_OBJECTS, EditorToaster.SEVERITY_ERROR)
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
	_toast("Baking %d object(s)..." % nodes.size())
	var atlas := await OctaBaker.bake_to_file(nodes, EditorInterface.get_base_control(), path, s)
	_busy = false
	if atlas == null:
		_toast("Bake failed. See the Output panel for the reason.", EditorToaster.SEVERITY_ERROR)
		return
	EditorInterface.get_resource_filesystem().scan()
	if root != EditorInterface.get_edited_scene_root() or not nodes.all(func(n) -> bool: return is_instance_valid(n)):
		_toast("The scene changed during the bake; the atlas was saved to %s but no cards were added." % path, EditorToaster.SEVERITY_WARNING)
		return

	var ur := get_undo_redo()
	ur.create_action("Bake Octahedral Impostors")
	for k in nodes.size():
		var src := nodes[k]
		var old := OctaLOD.find_cards(src)
		for card in old:
			_remove_card_actions(ur, src, card)
		_add_card_actions(ur, root, src, atlas.create_card(k, s.quality), s, old)
	ur.commit_action()
	_toast("Baked %d object(s) into %s (%s)." % [nodes.size(), path, s.describe(nodes.size()).get_slice(" -> ", 1)])


func _add_card_actions(ur: EditorUndoRedoManager, root: Node, src: Node3D, card: MeshInstance3D, s: OctaBakeSettings, replacing: Array) -> void:
	var as_child := OctaLOD.is_child_card(src, s.mode)
	var parent := src if as_child else src.get_parent()
	if as_child:
		card.name = _unique_name(parent, "OctaImpostor", replacing)
		card.set_meta(OctaLOD.SOURCE_META, NodePath(".."))
	else:
		card.name = _unique_name(parent, String(src.name) + "_OctaImpostor", replacing)
		card.transform = src.transform
		card.set_meta(OctaLOD.SOURCE_META, NodePath("../" + String(src.name)))
	card.set_meta(OctaLOD.MODE_META, s.mode)
	ur.add_do_method(parent, "add_child", card)
	ur.add_do_property(card, "owner", root)
	ur.add_do_reference(card)
	ur.add_undo_method(parent, "remove_child", card)
	if s.mode == OctaLOD.Mode.DYNAMIC_LOD:
		card.visibility_range_begin = s.lod_distance
		card.visibility_range_begin_margin = 1.0
		for gi in OctaLOD.geometry_below(src):
			var hops := _depth(src, gi) + (0 if as_child else 1)
			ur.add_do_property(gi, "visibility_parent", NodePath("../".repeat(hops) + String(card.name)))
			ur.add_undo_property(gi, "visibility_parent", gi.visibility_parent)
	elif s.mode == OctaLOD.Mode.REPLACE:
		ur.add_do_property(src, "visible", false)
		ur.add_undo_property(src, "visible", src.visible)


# --- Remove ---
func _remove_card_actions(ur: EditorUndoRedoManager, src: Node3D, card: Node) -> void:
	var parent := card.get_parent()
	ur.add_undo_method(parent, "add_child", card)
	ur.add_undo_method(parent, "move_child", card, card.get_index())
	ur.add_undo_property(card, "owner", card.owner)
	ur.add_undo_reference(card)
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
			var src := n.get_node_or_null(n.get_meta(OctaLOD.SOURCE_META, NodePath("..")))
			if src is Node3D:
				pairs[n] = src
		elif n is Node3D:
			for card in OctaLOD.find_cards(n):
				pairs[card] = n
	if pairs.is_empty():
		_toast("No octahedral impostors found. Select a baked object or its card.", EditorToaster.SEVERITY_WARNING)
		return
	var ur := get_undo_redo()
	ur.create_action("Remove Impostors")
	for card: Node in pairs:
		_remove_card_actions(ur, pairs[card], card)
	ur.commit_action()
	_toast("Removed %d impostor(s)." % pairs.size())


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
