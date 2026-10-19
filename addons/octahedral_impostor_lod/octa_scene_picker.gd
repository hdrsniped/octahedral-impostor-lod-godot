@tool
extends ConfirmationDialog

signal chosen(nodes: Array)

var _tree: Tree
var _percent: SpinBox
var _hint: Label
var _rows: Array[TreeItem] = []
var _settings: OctaBakeSettings


func _init() -> void:
	title = "Bake Scene"
	ok_button_text = "Bake Checked"
	min_size = Vector2i(420, 320)
	var box := VBoxContainer.new()
	var help := Label.new()
	_hint = help
	help.text = "Ticked objects are baked. By default the ones that cover less than the percentage below of the screen height at the LOD distance are ticked, so big hero objects stay as real meshes. A group appears as one item and is baked with its own settings. Objects that already have impostors are never ticked."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Tick below"
	row.add_child(label)
	_percent = SpinBox.new()
	_percent.min_value = 1.0
	_percent.max_value = 100.0
	_percent.step = 0.5
	_percent.suffix = "%"
	row.add_child(_percent)
	row.add_child(_button("Apply", _apply_threshold))
	row.add_child(_button("All", _set_all.bind(true)))
	row.add_child(_button("None", _set_all.bind(false)))
	box.add_child(row)
	_tree = Tree.new()
	_tree.columns = 4
	_tree.hide_root = true
	_tree.column_titles_visible = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var titles := ["Bake", "Object", "Screen height", "Triangles"]
	for i in 4:
		_tree.set_column_title(i, titles[i])
	box.add_child(_tree)
	add_child(box)
	confirmed.connect(_on_confirmed)


func fit_to_editor(view: Vector2) -> Vector2i:
	var w := minf(clampf(view.x * 0.66, 460.0, 760.0), maxf(view.x - 32.0, 280.0))
	var h := minf(maxf(view.y * 0.72, 320.0), 720.0)
	h = minf(h, maxf(view.y - 48.0, 220.0))
	var target := Vector2i(int(w), int(h))
	max_size = target
	size = target
	_hint.size = Vector2(maxf(w - 48.0, 240.0), _hint.size.y)
	_hint.get_minimum_size()
	return target


func populate(root: Node, s: OctaBakeSettings) -> void:
	_settings = s
	_percent.value = s.scene_pick_percent
	_tree.clear()
	_rows.clear()
	var top := _tree.create_item()
	for g in OctaImpostorGroup.find_all(root):
		var members := g.target_nodes()
		if members.is_empty():
			continue
		var row := _tree.create_item(top)
		row.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		row.set_editable(0, true)
		row.set_metadata(0, g)
		row.set_text(1, "Group %s (%d objects)" % [g.name, members.size()])
		row.set_text(2, "-")
		var tris := 0
		var cards := 0
		for m in members:
			cards += OctaLOD.find_cards_below(m).size()
			for gi in OctaLOD.geometry_below(m):
				if gi is MeshInstance3D and gi.mesh != null:
					tris += OctaLOD.triangle_count(gi.mesh)
		row.set_text(3, str(tris))
		row.set_meta("pct", 0.0)
		row.set_meta("cards", cards)
		_rows.append(row)
	for c in OctaLOD.scene_candidates(root, s.lod_distance):
		var row := _tree.create_item(top)
		row.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		row.set_editable(0, true)
		row.set_metadata(0, c.node)
		row.set_text(1, String(c.node.name) + ("  (already has impostors)" if c.cards > 0 else ""))
		row.set_text(2, "%.1f%%" % c.pct)
		row.set_text(3, str(c.tris))
		row.set_meta("pct", c.pct)
		row.set_meta("cards", c.cards)
		_rows.append(row)
	_apply_threshold()


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b


func _apply_threshold() -> void:
	_settings.scene_pick_percent = _percent.value
	for row in _rows:
		row.set_checked(0, row.get_meta("pct") <= _percent.value and row.get_meta("cards") == 0)


func _set_all(on: bool) -> void:
	for row in _rows:
		row.set_checked(0, on)


func _on_confirmed() -> void:
	var nodes := []
	for row in _rows:
		if row.is_checked(0) and is_instance_valid(row.get_metadata(0)):
			nodes.append(row.get_metadata(0))
	chosen.emit(nodes)
