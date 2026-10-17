@tool
extends VBoxContainer

var _plugin
var _selection: Label
var _info: Label
var _quality: OptionButton
var _lod: SpinBox
var _lod_mode: OptionButton
var _fade: OptionButton
var _fade_margin: SpinBox
var _depth: CheckBox
var _precise: CheckBox
var _shadow_views: SpinBox
var _debug: OptionButton
var _group_info: Label
var _group_buttons: Array[Button] = []
var _batch: Array[Control] = []
var _joins: Array[Button] = []


# --- Layout ---
func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin
	name = "Impostors"
	add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "Octahedral Impostor LOD"
	title.add_theme_font_override("font", EditorInterface.get_editor_theme().get_font("bold", "EditorFonts"))
	add_child(title)
	_selection = _label()
	add_child(_selection)

	var actions := HFlowContainer.new()
	actions.add_child(_button("Bake Selected...", "Bake the selected objects into impostors.", _plugin.open_bake_dialog))
	actions.add_child(_button("Check Quality", "Compare the impostors with the real meshes from 8 angles.", _plugin._check))
	actions.add_child(_button("Bake Scene...", "Pick objects from the whole scene to bake with a checklist.", _plugin.open_scene_picker))
	actions.add_child(_button("Remove", "Remove the impostors of the selected objects (undoable).", _plugin._remove))
	var join := _button("Join", "Merge the selected impostors that are close together into one draw call (undoable). Their real meshes are hidden.", _join)
	actions.add_child(join)
	var rebake := _button("Re-bake", "Bake the selected impostors again with their saved settings.", _rebake)
	actions.add_child(rebake)
	_joins = [join, rebake]
	actions.add_child(_button("Select Impostors", "Select the impostor cards of the selected objects.", _select_cards))
	actions.add_child(_button("Select Sources", "Select the real objects of the selected cards.", _select_sources))
	actions.add_child(_button("Re-bake All", "Bake every impostor of the open scene again with the settings saved in its atlas or group (undoable). Properties you changed on a card are kept.", _plugin.rebake_scene))
	actions.add_child(_button("Select All", "Select every impostor card of the open scene.", _plugin.select_scene_cards))
	add_child(actions)

	add_child(HSeparator.new())
	add_child(_heading("Group"))
	_group_info = _label()
	add_child(_group_info)
	var group_row := HFlowContainer.new()
	group_row.add_child(_button("Bake Group", "Bake the objects of the selected group with the group's own settings (undoable).", _plugin.bake_selected_groups.bind(false)))
	group_row.add_child(_button("Re-bake Group", "Bake the selected group again with its settings; properties you changed on its cards are kept (undoable).", _plugin.bake_selected_groups.bind(true)))
	_group_buttons.assign(group_row.get_children())
	add_child(group_row)

	add_child(HSeparator.new())
	add_child(_heading("Selected impostors"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_child(_label("Quality"))
	_quality = OptionButton.new()
	for q in OctaAtlas.Quality.keys():
		_quality.add_item(q.capitalize())
	_quality.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_quality)
	grid.add_child(_button("Apply", "Set this quality on every selected card (undoable).", _apply_quality))
	grid.add_child(_label("LOD"))
	var lod_row := HBoxContainer.new()
	_lod_mode = OptionButton.new()
	_lod_mode.add_item("Distance")
	_lod_mode.add_item("Screen size")
	_lod_mode.tooltip_text = "Distance: fixed meters. Screen size: the card takes over below this share of the screen height (converted with the reference field of view)."
	_lod_mode.item_selected.connect(_on_lod_mode)
	lod_row.add_child(_lod_mode)
	_lod = SpinBox.new()
	_lod.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lod_row.add_child(_lod)
	grid.add_child(lod_row)
	_setup_lod_spin(OctaLOD.LodMode.DISTANCE)
	grid.add_child(_button("Apply", "Set where the selected cards replace the real mesh (undoable).", _apply_lod))
	grid.add_child(_label("Fade"))
	var fade_row := HBoxContainer.new()
	_fade = OptionButton.new()
	_fade.add_item("None")
	_fade.add_item("Crossfade")
	_fade.tooltip_text = "Crossfade dithers the real mesh into the card. Forward+ only; not used by Replace mode."
	fade_row.add_child(_fade)
	_fade_margin = SpinBox.new()
	_fade_margin.max_value = 100.0
	_fade_margin.step = 0.5
	_fade_margin.suffix = "m"
	_fade_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fade_row.add_child(_fade_margin)
	grid.add_child(fade_row)
	grid.add_child(_button("Apply", "Set the fade of the selected cards (undoable).", _apply_fade))
	grid.add_child(_label("Write depth"))
	_depth = CheckBox.new()
	_depth.text = "On"
	_depth.tooltip_text = "Off = flat card depth, cheaper on mobile. Applies to every card that shares the atlas."
	grid.add_child(_depth)
	grid.add_child(_button("Apply", "Set depth writing for the atlases of the selected cards (undoable).", _apply_depth))
	grid.add_child(_label("Precise search"))
	_precise = CheckBox.new()
	_precise.text = "On"
	_precise.tooltip_text = "Ultra only. Finds thin features (rings, wire, branches) much more reliably at the same step count. About 2-3x slower on the GPU, so use it for hero objects. Applies to every card that shares the atlas."
	grid.add_child(_precise)
	grid.add_child(_button("Apply", "Set the precise ray search for the atlases of the selected cards (undoable).", _apply_precise))
	grid.add_child(_label("Shadow views"))
	_shadow_views = SpinBox.new()
	_shadow_views.min_value = 1
	_shadow_views.max_value = 3
	_shadow_views.tooltip_text = "Views blended in the shadow pass. 1 is fastest; 3 avoids shadow popping when the light moves. Applies to every card that shares the atlas."
	_shadow_views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_shadow_views)
	grid.add_child(_button("Apply", "Set the shadow views for the atlases of the selected cards (undoable).", _apply_shadow_views))
	add_child(grid)
	var shared := _button("Edit Shared Look", "Open the material shared by every card of this atlas and quality.", _edit_shared)
	add_child(shared)
	_batch.append_array([_quality, _lod, _lod_mode, _fade, _fade_margin, _depth, _precise, _shadow_views, shared])
	_batch.append_array(grid.get_children().filter(func(c: Node) -> bool: return c is Button))

	add_child(HSeparator.new())
	add_child(_heading("Debug view"))
	_debug = OptionButton.new()
	for n in OctaDebug.mode_names():
		_debug.add_item(n)
	_debug.tooltip_text = "Show how impostors are drawn, in the editor and in running scenes. Off costs nothing. Reset to Off when the plugin unloads."
	_debug.item_selected.connect(func(i: int) -> void: OctaDebug.set_mode(i as OctaDebug.Mode))
	add_child(_debug)

	add_child(HSeparator.new())
	add_child(_heading("Atlas"))
	_info = _label()
	add_child(_info)
	EditorInterface.get_selection().selection_changed.connect(refresh)
	refresh.call_deferred()


func _label(text := "") -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	return l


func _heading(text: String) -> Label:
	var l := _label(text)
	l.add_theme_color_override("font_color", EditorInterface.get_editor_theme().get_color("accent_color", "Editor"))
	return l


func _button(text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(action)
	return b


func _exit_tree() -> void:
	OctaDebug.set_mode(OctaDebug.Mode.OFF)


# --- State ---
func _cards() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in EditorInterface.get_selection().get_top_selected_nodes():
		if not n.is_inside_tree():
			continue
		var found: Array[Node3D] = []
		if n.has_meta(OctaAtlas.CARD_META):
			found.append(n)
		elif n is OctaImpostorGroup:
			found = n.cards()
		elif n is Node3D:
			found = OctaLOD.find_cards_below(n)
		for c in found:
			if not out.has(c):
				out.append(c)
	return out


func refresh() -> void:
	if not is_inside_tree():
		return
	var cards := _cards()
	var sel := EditorInterface.get_selection().get_top_selected_nodes().size()
	_selection.text = "Nothing selected." if sel == 0 else "%d node(s) selected, %d impostor card(s) found." % [sel, cards.size()]
	var groups: Array[OctaImpostorGroup] = _plugin._selected_groups()
	for b in _group_buttons:
		b.disabled = groups.is_empty()
	_group_info.text = "No group selected. Add an OctaImpostorGroup node to bake objects with shared settings, then select it here." if groups.is_empty() else "
".join(groups.map(func(g: OctaImpostorGroup) -> String: return g.info()))
	for c in _batch:
		c.set("disabled", cards.is_empty())
	for b in _joins:
		b.disabled = cards.is_empty()
	_lod.editable = not cards.is_empty()
	_fade_margin.editable = not cards.is_empty()
	var card: OctaImpostor = null
	for c in cards:
		if c is OctaImpostor and c.atlas != null:
			card = c
			break
	if card == null:
		_info.text = "Select a baked object or a card to see its atlas." if cards.is_empty() else "These cards were made with v1.0. Re-bake them to edit them here."
		return
	_quality.select(card.quality)
	_lod_mode.select(card.lod_mode)
	_setup_lod_spin(card.lod_mode)
	_lod.value = card.lod_distance if card.lod_mode == OctaLOD.LodMode.DISTANCE else card.screen_percent
	_fade.select(card.fade)
	_fade_margin.value = card.fade_margin
	_depth.button_pressed = card.atlas.write_depth
	_precise.button_pressed = card.atlas.precise_search
	_shadow_views.value = card.atlas.shadow_views
	_info.text = _atlas_text(card.atlas)


func _atlas_text(a: OctaAtlas) -> String:
	var maps := PackedStringArray(["albedo", "normal+depth"])
	if a.orm:
		maps.append("ORM")
	elif a.format_version >= 4:
		maps.append("ORM skipped (constant materials)")
	if a.emission:
		maps.append("emission")
	if a.back_depth:
		maps.append("back layer")
	var w := a.albedo.get_width() if a.albedo else 0
	var h := a.albedo.get_height() if a.albedo else 0
	return "%s\nFormat version %d, %d object(s), %dx%d atlas, %d px per view, %d views each\nMaps: %s\nHalf-res material maps: %s\nWrite depth: %s, shadow views: %d, precise search: %s\nAbout %.0f MB of video memory before compression" % [
		a.resource_path.get_file() if not a.resource_path.is_empty() else "(not saved)", a.format_version, a.object_count(), w, h, a.frame_resolution, a.grid_size * a.grid_size,
		", ".join(maps), "yes" if a.has_half_res_maps() else "no", "on" if a.write_depth else "off", a.shadow_views, "on" if a.precise_search else "off", a.vram_bytes() / 1048576.0]


# --- Batch edits ---
func _apply_quality() -> void:
	_set_all({quality = _quality.selected}, "Set Impostor Quality")


func _on_lod_mode(i: int) -> void:
	_setup_lod_spin(i)
	for c in _cards():
		if c is OctaImpostor:
			_lod.value = c.lod_distance if i == OctaLOD.LodMode.DISTANCE else c.screen_percent
			break


func _setup_lod_spin(mode: int) -> void:
	if mode == OctaLOD.LodMode.DISTANCE:
		_lod.min_value = 0.0
		_lod.max_value = 100000.0
		_lod.step = 0.5
		_lod.suffix = "m"
	else:
		_lod.min_value = 0.1
		_lod.max_value = 100.0
		_lod.step = 0.1
		_lod.suffix = "%"


func _apply_lod() -> void:
	var cards := _cards().filter(func(c: Node) -> bool: return c is OctaImpostor)
	if cards.is_empty():
		return
	var mode := _lod_mode.selected
	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	ur.create_action("Set Impostor LOD")
	for c: OctaImpostor in cards:
		var dist: float = _lod.value if mode == OctaLOD.LodMode.DISTANCE else c.lod_distance
		var pct: float = _lod.value if mode == OctaLOD.LodMode.SCREEN_SIZE else c.screen_percent
		ur.add_do_method(c, "set_lod", mode, dist, pct)
		ur.add_undo_method(c, "set_lod", c.lod_mode, c.lod_distance, c.screen_percent)
	ur.commit_action()
	refresh()


func _apply_fade() -> void:
	_set_all({fade = _fade.selected, fade_margin = _fade_margin.value}, "Set Impostor Fade")


func _apply_depth() -> void:
	_set_atlases("write_depth", _depth.button_pressed, "Set Impostor Depth Writing")


func _apply_precise() -> void:
	_set_atlases("precise_search", _precise.button_pressed, "Set Impostor Precise Search")


func _apply_shadow_views() -> void:
	_set_atlases("shadow_views", int(_shadow_views.value), "Set Impostor Shadow Views")


func _set_atlases(prop: String, value: Variant, action: String) -> void:
	var atlases: Array[OctaAtlas] = []
	for c in _cards():
		if c is OctaImpostor and c.atlas != null and not atlases.has(c.atlas):
			atlases.append(c.atlas)
	if atlases.is_empty():
		return
	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	ur.create_action(action, UndoRedo.MERGE_DISABLE, _cards()[0])
	for a in atlases:
		ur.add_do_property(a, prop, value)
		ur.add_do_method(self, "_save_atlas", a)
		ur.add_undo_property(a, prop, a.get(prop))
		ur.add_undo_method(self, "_save_atlas", a)
	ur.commit_action()
	refresh()


func _save_atlas(a: OctaAtlas) -> void:
	if a.resource_path.begins_with("res://") and not a.resource_path.contains("::"):
		ResourceSaver.save(a)


func _set_all(props: Dictionary, action: String) -> void:
	var cards := _cards().filter(func(c: Node) -> bool: return c is OctaImpostor)
	if cards.is_empty():
		return
	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	ur.create_action(action)
	for c: OctaImpostor in cards:
		for prop: String in props:
			ur.add_do_property(c, prop, props[prop])
			ur.add_undo_property(c, prop, c.get(prop))
	ur.commit_action()
	refresh()


func _edit_shared() -> void:
	for c in _cards():
		if c is GeometryInstance3D and c.material_override != null:
			EditorInterface.edit_resource(c.material_override)
			return


func _join() -> void:
	_plugin.join_cards(_cards())


func _rebake() -> void:
	_plugin.rebake(_cards())


func _select_cards() -> void:
	_select(_cards())


func _select_sources() -> void:
	var out: Array[Node3D] = []
	for c in _cards():
		var src := c.get_node_or_null(c.get_meta(OctaLOD.SOURCE_META, NodePath(".."))) as Node3D
		if src != null and not out.has(src):
			out.append(src)
	_select(out)


func _select(nodes: Array[Node3D]) -> void:
	if nodes.is_empty():
		return
	var s := EditorInterface.get_selection()
	s.clear()
	for n in nodes:
		s.add_node(n)
