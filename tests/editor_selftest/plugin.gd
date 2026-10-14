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
	settings.max_atlas_size = 1024

	await _select(["Ball", "Ring"])
	_check(await _bake(dialog, ["Ball/OctaImpostor", "Ring_OctaImpostor"]), "bake dialog opens and cards are added")
	var mesh: GeometryInstance3D = _root.get_node("Ball/Mesh")
	var ring: GeometryInstance3D = _root.get_node("Ring")
	var card := _root.get_node("Ball/OctaImpostor")
	var ring_card: Node3D = _root.get_node("Ring_OctaImpostor")
	_check(mesh.get_node_or_null(mesh.visibility_parent) == card and card.owner == _root, "Ball mesh linked to its child card, owner set")
	_check(ring.get_node_or_null(ring.visibility_parent) == ring_card and ring_card.transform.is_equal_approx(ring.transform), "Ring linked to a sibling card with the same transform")
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

	print("SELFTEST DONE")
	get_tree().quit()
