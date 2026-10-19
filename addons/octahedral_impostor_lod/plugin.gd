@tool
extends EditorPlugin

enum { BAKE, REMOVE, CHECK, SCENE, JOIN, REBAKE, HELP, GROUP, REBAKE_ALL, SELECT_ALL, PACK }

const BAKE_VIEW := preload("res://addons/octahedral_impostor_lod/octa_bake_view.gd")
const DIALOG_WIDTH := 700.0
const DIALOG_HEIGHT_RATIO := 0.72
const DIALOG_MAX_HEIGHT := 720.0
const DIALOG_MIN_HEIGHT := 320.0

const HELP_TEXT := """[b]Menu (3D toolbar)[/b]
[b]Bake Selected...[/b]  Bake the selected objects with the dialog settings. Pick a preset, then change anything (hover an option for help). All options in the dialog header shows the full inspector; the short form keeps what a bake needs.
[b]Bake Scene...[/b]  Checklist of every object with its on-screen size; small ones are pre-ticked. A group is one item.
[b]Bake Group[/b]  Bake the selected OctaImpostorGroup with its own settings. With a Chunk LOD distance on the group, one extra card of the whole group is baked for beyond that distance and the object cards stop there.
[b]Re-bake Selected / Re-bake All Impostors in Scene[/b]  Bake again with the settings saved in each atlas (or its group). Properties you changed on a card are kept.
[b]Join Selected Impostors[/b]  Merge nearby cards of one object into MultiMeshes, one per Join Cell (one draw call each). It needs several copies of the same baked card: bake the object once and duplicate the card, because two objects baked separately are two different entries in the atlas. Adaptive Join (bake dialog, Scene and joining) also splits crowded cells into small regions in Z-order, so off-screen regions are skipped. Joined groups have no LOD distance: their real meshes are hidden and the impostors stay on at every distance (undo restores the meshes).
[b]Pack Selected Atlases...[/b]  Merge the atlases of the selected cards into shared ones without re-baking (same grid, view size, padding and options). Cards then share one material per quality and can be joined. Undoable.
[b]Remove Impostors from Selected[/b]  Delete cards and restore the real objects.
[b]Check Quality of Selected[/b]  Compare card and real mesh from 8 angles.
[b]Select Impostors in Scene[/b]  Select every card of the open scene.
All of these can be undone with Edit > Undo.

[b]Impostors dock[/b]
Batch-edit the selected cards (quality, LOD, fade). Atlas options apply to every card of the atlas: write depth, precise search, shadow views. The Group section bakes the selected OctaImpostorGroup. Debug view: Off, Tint by quality, View index, Depth, Material (ORM), Overdraw. The Atlas block shows format version, maps, half-res, write depth, shadow views, precise search and video memory.

[b]Options worth knowing[/b]
Quality Low, Medium, High, Ultra. Ultra + Complex shapes (split parts, back layer, precise search) fixes rings and see-through shapes; precise search is 2-3x slower on the GPU, use it for hero objects.
Half-res material maps store roughness, metallic, occlusion and emission at a quarter of the memory.
Shadow views 1-3: more views = smoother shadows when the light moves.
Wind (off by default): a card's wind_strength sways the top of foliage in texture space; set direction and speed with OctaWind.set_wind().
LOD by distance or by screen size (project setting octa_lod/reference_fov).

[b]Command line and runtime[/b]
godot --path <project> -s res://addons/octahedral_impostor_lod/tools/octa_bake_cli.gd -- --help
OctaBakeQueue.shared(get_tree()).enqueue(node) bakes at runtime within a frame budget."""

var _menu: MenuButton
var _dialog: ConfirmationDialog
var _info: Label
var _info_scroll: ScrollContainer
var _preset: OptionButton
var _advanced: CheckButton
var _inspector: EditorInspector
var _view: Resource
var _progress: AcceptDialog
var _progress_bar: ProgressBar
var _progress_label: Label
var _job: OctaBakeJob
var _dock: Control
var _picker: ConfirmationDialog
var _help: AcceptDialog
var _settings := OctaBakeSettings.new()
var _busy := false
var _save_queued := false
var _dock_scroll: ScrollContainer


# --- Menu and dialog ---
func _enter_tree() -> void:
	_menu = MenuButton.new()
	_menu.text = "Octahedral Impostor LOD"
	_menu.tooltip_text = "Bake the selected 3D objects into lightweight octahedral impostors"
	var pm := _menu.get_popup()
	pm.add_item("Bake Selected...", BAKE)
	pm.add_item("Bake Scene...", SCENE)
	pm.add_item("Bake Group", GROUP)
	pm.add_separator()
	pm.add_item("Re-bake Selected Impostors", REBAKE)
	pm.add_item("Re-bake All Impostors in Scene", REBAKE_ALL)
	pm.add_item("Join Selected Impostors", JOIN)
	pm.add_item("Pack Selected Atlases...", PACK)
	pm.add_item("Remove Impostors from Selected", REMOVE)
	pm.add_separator()
	pm.add_item("Check Quality of Selected", CHECK)
	pm.add_item("Select Impostors in Scene", SELECT_ALL)
	pm.add_separator()
	pm.add_item("Help...", HELP)
	pm.id_pressed.connect(_on_menu)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _menu)
	Engine.set_meta(OctaImpostorGroup.PLUGIN_META, self)
	_register_settings()

	_dialog = ConfirmationDialog.new()
	_dialog.title = "Bake Octahedral Impostors"
	_dialog.ok_button_text = "Bake"
	_dialog.min_size = Vector2i(420, 320)
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	var pl := Label.new()
	pl.text = "Preset"
	row.add_child(pl)
	_preset = OptionButton.new()
	_preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in OctaBakeSettings.PRESET_NAMES.size():
		_preset.add_item(OctaBakeSettings.PRESET_NAMES[k])
		_preset.set_item_tooltip(k, OctaBakeSettings.PRESET_TIPS[k])
	_preset.tooltip_text = "Fills in quality, atlas, depth, fade, shadow and complex-shape options for a typical use. It never changes the placement (mode, LOD distance). Change anything afterwards."
	_preset.item_selected.connect(_on_preset)
	row.add_child(_preset)
	_advanced = CheckButton.new()
	_advanced.text = "All options"
	_advanced.tooltip_text = "Show every bake option, including the rare ones. Off shows only the settings needed for a good bake."
	_advanced.toggled.connect(_on_advanced)
	row.add_child(_advanced)

	box.add_child(row)
	_info_scroll = ScrollContainer.new()
	_info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_info_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(_info_scroll)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_scroll.add_child(_info)
	_inspector = EditorInspector.new()
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_inspector.property_edited.connect(func(p: String) -> void:
		if _preset_owns(p):
			_preset.select(0)
		_queue_save()
		_update_info()
		_hints_later())
	box.add_child(_inspector)
	_dialog.add_child(box)
	_dialog.confirmed.connect(_bake)
	EditorInterface.get_base_control().add_child(_dialog)
	_load_settings()
	_preset.select(_matching_preset())
	_view = BAKE_VIEW.new()
	_view.settings = _settings
	_inspector.edit(_view)
	_hints_later()
	_build_progress()
	_build_help()
	_picker = preload("res://addons/octahedral_impostor_lod/octa_scene_picker.gd").new()
	_picker.chosen.connect(_on_picked)
	EditorInterface.get_base_control().add_child(_picker)
	_dock = preload("res://addons/octahedral_impostor_lod/octa_dock.gd").new(self)
	_dock_scroll = ScrollContainer.new()
	_dock_scroll.name = "Impostors"
	_dock_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dock_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dock_scroll.add_child(_dock)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock_scroll)


func _exit_tree() -> void:
	_busy = false
	Engine.remove_meta(OctaImpostorGroup.PLUGIN_META)
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _menu)
	_menu.queue_free()
	_dialog.queue_free()
	_progress.queue_free()
	_picker.queue_free()
	_help.queue_free()
	remove_control_from_docks(_dock_scroll)
	_dock_scroll.queue_free()
	_dock.queue_free()


func _on_menu(id: int) -> void:
	match id:
		BAKE:
			if _busy:
				_toast("A bake is already running.", EditorToaster.SEVERITY_WARNING)
			elif _selected().is_empty() and not _selected_groups().is_empty():
				bake_selected_groups(false)
			elif _selected().is_empty():
				_toast("Select one or more 3D objects with meshes first.", EditorToaster.SEVERITY_WARNING)
			else:
				var target := _dialog_target()
				_dialog.max_size = target
				_dialog.size = target
				_update_info()
				_dialog.popup_centered_clamped(target, 0.9)
		SCENE:
			open_scene_picker()
		REMOVE:
			_remove()
		JOIN:
			join_cards(selected_cards())
		PACK:
			pack_atlases(selected_cards())
		REBAKE:
			rebake(selected_cards())
		REBAKE_ALL:
			rebake_scene()
		SELECT_ALL:
			select_scene_cards()
		GROUP:
			bake_selected_groups(false)
		CHECK:
			_check()
		HELP:
			_open_help()


func _selected() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in EditorInterface.get_selection().get_top_selected_nodes():
		if n is Node3D and not n.has_meta(OctaAtlas.CARD_META) and not n is OctaImpostorGroup:
			out.append(n)
	return out


func _selected_groups() -> Array[OctaImpostorGroup]:
	var out: Array[OctaImpostorGroup] = []
	for n in EditorInterface.get_selection().get_top_selected_nodes():
		if n is OctaImpostorGroup and not out.has(n):
			out.append(n)
	return out


func _update_info() -> void:
	var nodes := _selected()
	var names := ", ".join(nodes.slice(0, 5).map(func(n: Node) -> String: return n.name))
	if nodes.size() > 5:
		names += ", ..."
	_info.text = "Selected: %s\n%s\n%s" % [names, _settings.describe(nodes.size(), nodes), _settings.cost_text(nodes)]
	if not _dialog.visible:
		_shape_info()


func _dialog_target() -> Vector2i:
	var editor := EditorInterface.get_base_control().get_viewport_rect().size
	var w := minf(clampf(editor.x * 0.66, 460.0, DIALOG_WIDTH), maxf(editor.x - 32.0, 260.0))
	var h := minf(maxf(editor.y * DIALOG_HEIGHT_RATIO, DIALOG_MIN_HEIGHT), DIALOG_MAX_HEIGHT)
	h = minf(h, maxf(editor.y - 48.0, 200.0))
	return Vector2i(int(w), int(h))


func _shape_info() -> void:
	var line := maxf(_info.get_line_height(), 1.0)
	var lines := maxi(3, int(_dialog.size.y * 0.40 / line))
	_info_scroll.custom_minimum_size = Vector2(0.0, lines * line)
	_info.size = Vector2(maxf(_dialog.size.x - 40.0, 200.0), _info.size.y)
	_info.get_minimum_size()


func _on_preset(i: int) -> void:
	_settings.apply_preset(i)
	_refresh_edit()
	_update_info()
	if i != OctaBakeSettings.Preset.CUSTOM:
		_queue_save()


func _refresh_edit() -> void:
	_inspector.edit(null)
	_inspector.edit(_settings if _advanced.button_pressed else _view)
	_hints_later()


func _hints_later() -> void:
	_apply_hints.call_deferred()
	_hints_next.call_deferred()


func _hints_next() -> void:
	await get_tree().process_frame
	_apply_hints()
	await get_tree().process_frame
	_apply_hints()


func _on_advanced(_on: bool) -> void:
	_refresh_edit()


func set_advanced(on: bool) -> void:
	_advanced.set_pressed_no_signal(on)
	_on_advanced(on)


func is_advanced() -> bool:
	return _advanced.button_pressed


func _matching_preset() -> int:
	for i in range(OctaBakeSettings.Preset.CUSTOM + 1, OctaBakeSettings.PRESET_NAMES.size()):
		var v := OctaBakeSettings.preset_values(i as OctaBakeSettings.Preset)
		var same := true
		for k: String in v:
			if _settings.get(k) != v[k]:
				same = false
				break
		if same:
			return i
	return OctaBakeSettings.Preset.CUSTOM


func _preset_owns(p: String) -> bool:
	var i := _preset.get_selected()
	if i <= OctaBakeSettings.Preset.CUSTOM:
		return false
	return OctaBakeSettings.preset_values(i as OctaBakeSettings.Preset).has(p)


func _apply_hints() -> void:
	_apply_hints_to(_inspector)


func _apply_hints_to(n: Node) -> void:
	for c in n.get_children():
		if c is EditorProperty:
			var p := String((c as EditorProperty).get_edited_property())
			var t: String = OctaBakeSettings.SHORT_HINTS.get(p, "")
			if not t.is_empty():
				_hint_control(c, t)
		_apply_hints_to(c)


func _hint_control(n: Node, t: String) -> void:
	if n is Control and (n as Control).tooltip_text.is_empty():
		(n as Control).tooltip_text = t
	for c in n.get_children():
		_hint_control(c, t)


func _queue_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	_do_save.call_deferred()


func _do_save() -> void:
	_save_queued = false
	_save_settings()



func open_bake_dialog() -> void:
	_on_menu(BAKE)


# --- Help and project setting ---
func _build_help() -> void:
	_help = AcceptDialog.new()
	_help.title = "Octahedral Impostor LOD - Help"
	_help.ok_button_text = "Close"
	_help.min_size = Vector2i(420, 320)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.text = HELP_TEXT.replace("\r", "")
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_help.add_child(text)
	_help.add_button("Open on GitHub", false, "readme")
	_help.custom_action.connect(func(_a: StringName) -> void: OS.shell_open("https://github.com/hdrsniped/octahedral-impostor-lod-godot"))
	EditorInterface.get_base_control().add_child(_help)


func _open_help() -> void:
	var target := _dialog_target()
	_help.max_size = target
	_help.size = target
	_help.popup_centered_clamped(target, 0.9)


func _register_settings() -> void:
	if not ProjectSettings.has_setting(OctaLOD.FOV_SETTING):
		ProjectSettings.set_setting(OctaLOD.FOV_SETTING, OctaLOD.DEFAULT_FOV)
	ProjectSettings.set_initial_value(OctaLOD.FOV_SETTING, OctaLOD.DEFAULT_FOV)
	ProjectSettings.add_property_info({name = OctaLOD.FOV_SETTING, type = TYPE_FLOAT, hint = PROPERTY_HINT_RANGE, hint_string = "10,120,0.5,suffix:deg"})


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
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var claimed := OctaImpostorGroup.claimed_nodes(root)
	var by_atlas := {}
	var groups: Array[OctaImpostorGroup] = []
	for c in cards:
		if not c is OctaImpostor:
			continue
		var src := _source_of(c)
		var group := OctaImpostorGroup.group_in(src, claimed) if src != null else null
		if group != null:
			if not groups.has(group):
				groups.append(group)
		elif src != null and c.atlas != null and c.atlas.bake_settings != null:
			if not by_atlas.has(c.atlas):
				var list: Array[Node3D] = []
				by_atlas[c.atlas] = list
			if not by_atlas[c.atlas].has(src):
				by_atlas[c.atlas].append(src)
	if by_atlas.is_empty() and groups.is_empty():
		_toast("Select impostor cards that still have their source object to re-bake them.", EditorToaster.SEVERITY_WARNING)
		return
	for g in groups:
		await bake_group(g, true)
	for a: OctaAtlas in by_atlas:
		await _run_bake(by_atlas[a], a.bake_settings.duplicate(), null, true)


func rebake_scene() -> void:
	await rebake(scene_cards())


func scene_cards() -> Array:
	var root := EditorInterface.get_edited_scene_root()
	return [] if root == null else root.find_children("*", "OctaImpostor", true, false)


func select_scene_cards() -> void:
	var cards := scene_cards()
	if cards.is_empty():
		_toast("This scene has no impostor cards.", EditorToaster.SEVERITY_WARNING)
		return
	var sel := EditorInterface.get_selection()
	sel.clear()
	for c in cards:
		sel.add_node(c)


func bake_selected_groups(keep_overrides: bool) -> void:
	var groups := _selected_groups()
	if groups.is_empty():
		_toast("Select an OctaImpostorGroup node first.", EditorToaster.SEVERITY_WARNING)
		return
	for g in groups:
		await bake_group(g, keep_overrides)


func bake_group(group: OctaImpostorGroup, keep_overrides := false) -> bool:
	if _busy:
		_toast("A bake is already running.", EditorToaster.SEVERITY_WARNING)
		return false
	var nodes := group.target_nodes()
	if nodes.is_empty():
		_toast("Group '%s' has no objects to bake. Add meshes as children or fill in its Targets." % group.name, EditorToaster.SEVERITY_WARNING)
		return false
	return await _run_bake(nodes, group.effective_settings().duplicate(), group, keep_overrides)


func _run_bake(nodes: Array[Node3D], s: OctaBakeSettings, group: OctaImpostorGroup = null, keep_overrides := false) -> bool:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or _busy:
		return false
	for n in nodes:
		if not OctaLOD.geometry_below(n).any(func(g: Node) -> bool: return g is MeshInstance3D and g.mesh != null and g.is_visible_in_tree()):
			_toast("'%s' has no visible mesh to bake (select the object that contains the MeshInstance3D)." % n.name, EditorToaster.SEVERITY_ERROR)
			return false
		if n == root and not OctaLOD.is_child_card(n, s.mode):
			_toast("'%s' is the scene root; this mode needs a parent. Select a child node instead." % n.name, EditorToaster.SEVERITY_ERROR)
			return false
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
		return false

	var scene_name := root.scene_file_path.get_file().get_basename()
	if scene_name.is_empty():
		scene_name = String(root.name)
	var base := s.output_dir.path_join("%s_%s" % [scene_name.to_snake_case(), String((group if group != null else nodes[0]).name).to_snake_case()])
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
		return false
	EditorInterface.get_resource_filesystem().scan()
	if root != EditorInterface.get_edited_scene_root() or not bake_list.all(func(n: Node) -> bool: return is_instance_valid(n)):
		_toast("The scene changed during the bake; the atlas was saved to %s but no cards were added." % path, EditorToaster.SEVERITY_WARNING)
		return false

	var chunk_atlas: OctaAtlas = null
	var chunk_settings: OctaBakeSettings = null
	if group != null and group.chunk_lod_distance > 0.0:
		chunk_settings = group.chunk_settings()
		var chunk_path := "%s_chunk.res" % path.get_basename()
		var cj := 2
		while ResourceLoader.exists(chunk_path):
			chunk_path = "%s_chunk_%d.res" % [path.get_basename(), cj]
			cj += 1
		_busy = true
		var cjob := OctaBakeJob.new()
		_job = cjob
		_job.progress.connect(_on_progress)
		_progress_bar.value = 0
		_progress_label.text = "Baking the chunk card..."
		_progress.popup_centered()
		chunk_atlas = await OctaBaker.bake_to_file([group], EditorInterface.get_base_control(), chunk_path, chunk_settings, cjob)
		_job = null
		_progress.hide()
		_busy = false
		EditorInterface.get_resource_filesystem().scan()
		if cjob.cancelled:
			if chunk_atlas != null:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(chunk_path))
			_toast("Bake cancelled during the chunk card. Nothing was changed.", EditorToaster.SEVERITY_WARNING)
			return false

	var ur := get_undo_redo()
	ur.create_action("Bake Octahedral Impostors")
	var replaced: Array[Node3D] = []
	var old_sources: Array[Node3D] = []
	var overrides := {}
	for o in nodes:
		for card in OctaLOD.find_cards_below(o):
			if not replaced.has(card):
				var old_src := _source_of(card)
				if keep_overrides and old_src != null:
					overrides[old_src] = OctaLOD.card_overrides(card)
				_remove_do_actions(ur, old_src, card)
				replaced.append(card)
				old_sources.append(old_src)
	for k in targets.size():
		var src := targets[k]
		var kept: Dictionary = overrides.get(src, {})
		_add_card_actions(ur, root, src, atlas.create_card(index[k], kept.get("quality", s.quality)), atlas.card_transform(src), s, replaced, kept)
	if group != null:
		ur.add_do_property(group, "atlas", atlas)
		ur.add_undo_property(group, "atlas", group.atlas)
	if group != null and chunk_atlas != null:
		ur.add_do_method(group, "attach_chunk", chunk_atlas, chunk_settings, group.chunk_lod_distance)
		ur.add_undo_method(group, "detach_chunk")
		ur.add_do_reference(chunk_atlas)
		for c in group.cards():
			ur.add_undo_property(c, "visibility_range_end", c.visibility_range_end)
	for k in replaced.size():
		_remove_undo_actions(ur, old_sources[k], replaced[k])
	ur.commit_action()
	_toast("Baked %d object(s) into %s (%s)." % [bake_list.size(), path, s.describe(bake_list.size(), [], false).get_slice(" -> ", 1)])
	if group != null and group.chunk_lod_distance > 0.0:
		if chunk_atlas == null:
			_toast("The chunk card bake failed; the object cards were baked. See the Output panel.", EditorToaster.SEVERITY_WARNING)
		else:
			_toast("Chunk card: the whole group becomes one card beyond %.0f m." % group.chunk_lod_distance)
	_dock.refresh()
	return true


func _add_card_actions(ur: EditorUndoRedoManager, root: Node, src: Node3D, card: MeshInstance3D, xform: Transform3D, s: OctaBakeSettings, replacing: Array, kept := {}) -> void:
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
	OctaLOD.apply_overrides(card, kept)
	if s.mode == OctaLOD.Mode.DYNAMIC_LOD:
		for gi in OctaLOD.geometry_below(src):
			var hops := _depth(src, gi) + (0 if as_child else 1)
			ur.add_do_property(gi, "visibility_parent", NodePath("../".repeat(hops) + String(card.name)))
			ur.add_undo_property(gi, "visibility_parent", NodePath() if gi.get_node_or_null(gi.visibility_parent) in replacing else gi.visibility_parent)
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
	_remove_undo_actions(ur, src, card)
	_remove_do_actions(ur, src, card)


func _remove_undo_actions(ur: EditorUndoRedoManager, src: Node3D, card: Node) -> void:
	var parent := card.get_parent()
	ur.add_undo_method(parent, "add_child", card)
	ur.add_undo_method(parent, "move_child", card, card.get_index())
	ur.add_undo_property(card, "owner", card.owner)
	ur.add_undo_reference(card)
	if src != null:
		for gi in OctaLOD.geometry_below(src):
			if gi.get_node_or_null(gi.visibility_parent) == card:
				ur.add_undo_property(gi, "visibility_parent", gi.visibility_parent)
		if card.get_meta(OctaLOD.MODE_META, OctaLOD.Mode.DYNAMIC_LOD) == OctaLOD.Mode.REPLACE:
			ur.add_undo_property(src, "visible", src.visible)


func _remove_do_actions(ur: EditorUndoRedoManager, src: Node3D, card: Node) -> void:
	var parent := card.get_parent()
	if src != null:
		for gi in OctaLOD.geometry_below(src):
			if gi.get_node_or_null(gi.visibility_parent) == card:
				ur.add_do_property(gi, "visibility_parent", NodePath())
		if card.get_meta(OctaLOD.MODE_META, OctaLOD.Mode.DYNAMIC_LOD) == OctaLOD.Mode.REPLACE:
			ur.add_do_property(src, "visible", true)
	ur.add_do_method(parent, "remove_child", card)


func _remove() -> void:
	var pairs := {}
	for n in EditorInterface.get_selection().get_top_selected_nodes():
		if n.has_meta(OctaAtlas.CARD_META):
			pairs[n] = _source_of(n)
		elif n is OctaImpostorGroup:
			for card in n.cards():
				pairs[card] = _source_of(card)
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
	var by_object := {}
	var atlases := {}
	for c in cards:
		if c is OctaImpostor and c.atlas != null and c.is_inside_tree():
			var cell := Vector3i((c.global_position / _settings.join_cell).floor())
			var key := "%d|%d|%d|%s|%.3f" % [c.atlas.get_instance_id(), c.object_index, c.quality, cell, c.wind_strength]
			if not groups.has(key):
				groups[key] = []
			groups[key].append(c)
			var obj_key := "%d|%d" % [c.atlas.get_instance_id(), c.object_index]
			by_object[obj_key] = int(by_object.get(obj_key, 0)) + 1
			atlases[c.atlas.get_instance_id()] = true
	var ur := get_undo_redo()
	ur.create_action("Join Impostors")
	var draw_calls := 0
	var joined := 0
	var parts: Array = []
	for key in groups:
		if _settings.join_adaptive and groups[key].size() >= 2:
			parts.append_array(_regions(groups[key]))
		else:
			parts.append(groups[key])
	for g: Array in parts:
		if g.size() < 2:
			continue
		var first: OctaImpostor = g[0]
		var xforms: Array = []
		var customs: Array = []
		for c: OctaImpostor in g:
			xforms.append(root.global_transform.affine_inverse() * c.global_transform)
			customs.append(OctaAtlas.joined_custom(c.tint, c.depth_multiplier))
		var mmi := first.atlas.create_multimesh(first.object_index, xforms, first.quality, customs, 0.0, 0.0, first.wind_strength)
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
		var near := false
		for k in by_object:
			if by_object[k] >= 2:
				near = true
		if near:
			_toast("Same-object cards must sit within %.0f m (Join Cell)." % _settings.join_cell, EditorToaster.SEVERITY_WARNING)
		elif atlases.size() > 1:
			_toast("These cards are in different atlases. Bake the objects together, then join.", EditorToaster.SEVERITY_WARNING)
		else:
			_toast("Each object is its own atlas entry. Bake them together, or duplicate one card.", EditorToaster.SEVERITY_WARNING)
		return
	ur.commit_action()
	_toast("Joined %d cards into %d draw calls. Undo restores them." % [joined, draw_calls])
	_dock.refresh()


func pack_atlases(cards: Array) -> bool:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return false
	var sources: Array = []
	for c in cards:
		if c.atlas != null and not sources.has(c.atlas):
			sources.append(c.atlas)
	if sources.size() < 2:
		_toast("Select cards from at least two different atlases.", EditorToaster.SEVERITY_WARNING)
		return false
	var limit := 4096
	for a: OctaAtlas in sources:
		limit = maxi(limit, maxi(a.albedo.get_width(), a.albedo.get_height()))
	var map := {}
	var packed := OctaPacker.pack(sources, limit, map)
	if map.is_empty():
		var why := "the layout"
		for i in range(1, sources.size()):
			var m := OctaPacker.mismatch(sources[0], sources[i])
			if not m.is_empty():
				why = m
				break
		_toast("Cannot pack: %s differs." % why, EditorToaster.SEVERITY_WARNING)
		return false
	var created: Array = []
	for s in map:
		for oi in map[s]:
			var pa: OctaAtlas = map[s][oi][0]
			if not created.has(pa):
				created.append(pa)
	var scene := root.scene_file_path
	var dir := scene.get_base_dir() if scene != "" else "res://"
	var base := scene.get_file().get_basename() if scene != "" else ""
	if base == "":
		base = "packed"
	if OctaPacker.save_packed(created, dir, base + "_packed").is_empty():
		return false
	EditorInterface.get_resource_filesystem().scan()
	var ur := get_undo_redo()
	ur.create_action("Pack Impostor Atlases")
	var moved := 0
	for c in cards:
		if c.atlas == null or not map.has(c.atlas):
			continue
		var slot: Array = map[c.atlas].get(c.object_index, [])
		if slot.is_empty() or (slot[0] == c.atlas and slot[1] == c.object_index):
			continue
		ur.add_do_property(c, "atlas", slot[0])
		ur.add_undo_property(c, "atlas", c.atlas)
		ur.add_do_property(c, "object_index", slot[1])
		ur.add_undo_property(c, "object_index", c.object_index)
		moved += 1
	for pa: OctaAtlas in created:
		ur.add_do_reference(pa)
	ur.commit_action()
	_toast("Packed %d atlases into %d; %d cards now share one material." % [sources.size(), packed.size(), moved])
	_dock.refresh()
	EditorInterface.mark_scene_as_unsaved()
	return true


func _regions(members: Array) -> Array:
	var points := PackedVector3Array()
	var all := PackedInt32Array()
	for k in members.size():
		points.append(members[k].global_position)
		all.append(k)
	var out := []
	for region: PackedInt32Array in OctaJoin.subdivide(points, all, _settings.join_region_size, _settings.join_region_count):
		var cards := []
		for k in region:
			cards.append(members[k])
		out.append(cards)
	return out


func selected_cards() -> Array:
	var out := []
	for n in EditorInterface.get_selection().get_top_selected_nodes():
		if n.has_meta(OctaAtlas.CARD_META):
			if not out.has(n):
				out.append(n)
		elif n is Node3D:
			for c in (n.cards() if n is OctaImpostorGroup else OctaLOD.find_cards_below(n)):
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
	var target: Vector2i = _picker.fit_to_editor(EditorInterface.get_base_control().get_viewport_rect().size)
	_picker.popup_centered_clamped(target, 0.9)


func _on_picked(nodes: Array) -> void:
	if nodes.is_empty():
		_toast("Nothing was ticked, so nothing was baked.", EditorToaster.SEVERITY_WARNING)
		return
	for n in nodes:
		if n is OctaImpostorGroup:
			await bake_group(n)
	var plain := nodes.filter(func(n: Node) -> bool: return not n is OctaImpostorGroup)
	if plain.is_empty():
		return
	var sel := EditorInterface.get_selection()
	sel.clear()
	for n in plain:
		sel.add_node(n)
	_on_menu(BAKE)


# --- Quality check ---
func _check() -> bool:
	if _busy:
		_toast("A bake or check is already running.", EditorToaster.SEVERITY_WARNING)
		return false
	var nodes := _selected()
	if nodes.is_empty():
		_toast("Select baked objects to check.", EditorToaster.SEVERITY_WARNING)
		return false
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
	return true


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
	if d.has("hemisphere") and not d.has("full_sphere"):
		_settings.full_sphere = not bool(d["hemisphere"])
	for p in _stored_properties():
		if d.has(p):
			_settings.set(p, d[p])
