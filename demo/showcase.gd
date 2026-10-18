extends Node3D

const ASSET_NAMES: Array[String] = ["Procedural Rock", "Foliage Tree", "Gyroscope Rings", "Textured Ball"]
const QUALITY_NAMES: Array[String] = ["Low (1 View, Fastest)", "Medium (3-View Blend)", "High (Parallax Raymarching)", "Ultra (Ray Search)"]
const METRIC_NAMES: Array[String] = ["GPU", "FPS", "VRAM", "CPU", "Draws", "Tris", "All"]
const BTN_STATES: Array[String] = ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]
const SNAP := {fps = 0, gpu_ms = 0.0, cpu_ms = 0.0, tris = 0, draws = 0, vram = 0.0, count = 0}
const STATS_EMPTY := "Spawned Props: --\nFPS: --\nGPU Time: --\nCPU Time: --\nTriangles: --\nDraw Calls: --\nVRAM: --"
const SUMMARY := "Press [F] to Hot-Swap to %s  •  [B] Auto-Benchmark  •  [G] Wave Metric"
const HELP := """[F] HOT-SWAP  •  [O] AUTO LOD  •  [J] JOIN  •  [B] AUTO-BENCHMARK  •  [G] WAVE  •  [A] ANALYTICS  •  [H] TOGGLE UI  •  [L] LEVEL
[b]Props (%d):[/b] [+] / [-] (one at a time)  •  [b]Asset:[/b] [1] Rock [2] Tree [3] Rings [4] Textured  •  [b]Quality:[/b] [F1] Low [F2] Med [F3] High [F4] Ultra
[b]Plugin:[/b] [D] Debug View  •  [P] Precise Search  •  [W] Write Depth  •  [S] Shadows  •  [V] Shadow Views  •  [R] Sun Spin  •  [T] Tint  •  [K] Wind (Tree)  •  [C] Chunk LOD
[b]Camera:[/b] [Space] Orbit | Drag | Wheel | [Arrows] Move | [Q]/[E] Down/Up | [Shift] Fast  •  [Esc] Exit"""
const HEX_REAL := "#ff4444"
const HEX_IMP := "#33b5ff"
const HEX_GOOD := "#44ff66"
const PANEL_BG := Color(0, 0, 0, 0.55)
const BTN_OFF := Color(0, 0, 0, 0.3)
const BTN_ON := Color(1, 1, 1, 0.16)
const WAVE_COLORS: Array[Color] = [Color(1.0, 0.28, 0.28), Color(0.22, 0.78, 1.0)]
const WAVE_FILLS: Array[float] = [0.07, 0.10]
const GRID_TEXT := Color(0.40, 0.48, 0.58)
const VRAM_COLORS: Array[Color] = [Color(0.9, 0.9, 0.9, 0.9), Color(0.6, 0.6, 0.6, 0.9), Color(0.35, 0.35, 0.35, 0.9)]
const ACCENTS: Array[Color] = [Color(0.2, 0.9, 0.45), Color(0.2, 0.75, 1.0)]
const MB := 1048576.0
const VRAM_BUDGET_MB := 2048.0
const MAX_PROPS := 4000
const WAVE_POINTS := 75
const FLY_SPEED := 9.0
const WAVE_STEP := 0.04
const HUD_STEP := 0.125
const SCAN_STEP := 1.0
const TOAST_TIME := 2.0
const SMOOTH := 0.15
const SIDE_X := 2.2
const LOD_DISTANCE := 14.0
const LOD_FADE := 4.0
const JOIN_CELL := 50.0
const CHUNK_DISTANCE := 24.0
const CHUNK_PROPS := 3
const SUN_SPIN_DEG := 25.0
const BENCH_STEP := 0.12
const BENCH_GROW := 0.05
const BENCH_STABLE := 5.0
const BENCH_IMPOSTOR := 10.0
const JOINED := &"demo_joined"
const WIND_ASSET := 1
const WIND_STRENGTH := 0.4
const WIND_DIRECTION := Vector2(1.0, 0.4)
const WIND_SPEED := 8.0

var _atlas: OctaAtlas
var _models: Array[Node3D] = []
var _tris: Array[int] = [0, 0, 0, 0]
var _bake_ms: int = 0
var _rid: RID

var _current_level: int = 2
var _current_asset: int = 0
var _quality: int = OctaAtlas.Quality.MEDIUM
var _spawn_count: int = 1
var _is_impostor: bool = false
var _tinted: bool = false
var _auto_orbit: bool = true
var _ui_visible: bool = true
var _analytics_visible: bool = true
var _joined: bool = false
var _auto_lod: bool = false
var _sun_spin: bool = false
var _wind: bool = false
var _chunk_group: OctaImpostorGroup
var _join_stats := Vector2i.ZERO
var _join_base := Vector2(-1, -1)
var _yaw: float = 0.0
var _pitch: float = -0.28
var _cam_dist: float = 6.0

var _simulating_benchmark: bool = false
var _target_fps: int = 30
var _sim_timer: float = 0.0
var _stabilize_timer: float = 0.0
var _benchmark_stage: int = 0

var _smooth_gpu_ms: float = 0.0
var _smooth_cpu_ms: float = 0.0
var _hud_timer: float = 0.0
var _scan_timer: float = 0.0
var _toast_timer: float = 0.0
var _text_count: int = -1
var _frame_times := PackedFloat32Array()
var _frame_i: int = 0
var _mem := Vector3.ZERO
var _scan := {}

var _current_metric: int = 0
var _wave_red: Array[float] = []
var _wave_blue: Array[float] = []
var _wave_timer: float = 0.0
var _pts := PackedVector2Array()
var _poly := PackedVector2Array()
var _snap_real: Dictionary = SNAP.duplicate()
var _snap_imp: Dictionary = SNAP.duplicate()

var _cam_pivot: Node3D
var _cam: Camera3D
var _sun: DirectionalLight3D
var _level1_node: Node3D
var _level2_node: Node3D
var _field: Node3D
var _join_node: Node3D
var _sides: Array[Node] = []
var _labels: Array[Label3D] = []

var _hud: CanvasLayer
var _scan_hud: OctaDebugHUD
var _btn_off: StyleBoxFlat
var _btn_on: StyleBoxFlat
var _stat_rts: Array[RichTextLabel] = []
var _summary_label: Label
var _help_rt: RichTextLabel
var _toast_label: Label
var _wave_canvas: Control
var _wave_title_rt: RichTextLabel
var _wave_val_rt: RichTextLabel
var _metric_buttons: Array[Button] = []
var _analytics_panel: PanelContainer
var _info_rt: RichTextLabel
var _state_rt: RichTextLabel
var _vram_bar: Control
var _info_head: String = ""
var _loading_layer: CanvasLayer
var _progress_bar: ProgressBar


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_rid, true)
	_btn_off = _flat(BTN_OFF)
	_btn_on = _flat(BTN_ON)
	_frame_times.resize(WAVE_POINTS)
	_setup_loading_screen()
	_setup_environment()
	_setup_stage()
	_setup_camera()
	_setup_hud()
	_run_loading_and_bake()


func _exit_tree() -> void:
	OctaDebug.set_mode(OctaDebug.Mode.OFF)


func _flat(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	return sb


func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _setup_loading_screen() -> void:
	_loading_layer = CanvasLayer.new()
	_loading_layer.layer = 120
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.07, 0.09)
	_loading_layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_layer.add_child(center)
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(280, 4)
	_progress_bar.value = 5.0
	_progress_bar.show_percentage = false
	_progress_bar.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.12)))
	_progress_bar.add_theme_stylebox_override("fill", _flat(Color(0.8, 0.85, 0.9)))
	center.add_child(_progress_bar)
	add_child(_loading_layer)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.32, 0.40)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.position = Vector3(12, 18, 12)
	_sun.rotation_degrees = Vector3(-45, 40, 0)
	_sun.shadow_enabled = true
	_sun.light_energy = 1.35
	_sun.directional_shadow_max_distance = 80.0
	add_child(_sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.45
	add_child(fill)


func _setup_stage() -> void:
	var stage := Node3D.new()
	add_child(stage)
	for p: Array in [[800.0, 0.0, Color(0.11, 0.13, 0.16), 0.7], [600.0, 0.002, Color(0.15, 0.18, 0.23), 0.8]]:
		var pm := PlaneMesh.new()
		pm.size = Vector2(p[0], p[0])
		_add_mesh(stage, pm, Vector3(0, p[1], 0), _mat(p[2], p[3]))
	_level1_node = Node3D.new()
	_level1_node.visible = false
	stage.add_child(_level1_node)
	for i in 2:
		var pos := Vector3(SIDE_X * (2 * i - 1), 0, 0)
		var slot := Node3D.new()
		slot.position = pos
		_level1_node.add_child(slot)
		_sides.append(slot)
		_create_pedestal(pos, ACCENTS[i])
		var label := Label3D.new()
		label.position = pos + Vector3(0, 3.2, 0)
		label.font_size = 28
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_level1_node.add_child(label)
		_labels.append(label)
	_level2_node = Node3D.new()
	stage.add_child(_level2_node)
	_field = Node3D.new()
	_level2_node.add_child(_field)
	_join_node = Node3D.new()
	_level2_node.add_child(_join_node)


func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _create_pedestal(pos: Vector3, accent: Color) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 1.7
	cm.bottom_radius = 1.75
	cm.height = 0.08
	cm.radial_segments = 64
	_add_mesh(_level1_node, cm, pos + Vector3(0, 0.04, 0), _mat(Color(0.09, 0.11, 0.14), 0.4))
	var tm := TorusMesh.new()
	tm.inner_radius = 1.68
	tm.outer_radius = 1.74
	tm.rings = 64
	var rmat := _mat(accent, 0.5)
	rmat.emission_enabled = true
	rmat.emission = accent * 0.9
	_add_mesh(_level1_node, tm, pos + Vector3(0, 0.081, 0), rmat)


func _setup_camera() -> void:
	_cam_pivot = Node3D.new()
	_cam_pivot.position = Vector3(0, 1.0, 0)
	add_child(_cam_pivot)
	_cam = Camera3D.new()
	_cam.current = true
	_cam.far = 1200.0
	_cam_pivot.add_child(_cam)
	_update_camera()


func _update_camera() -> void:
	_cam_pivot.rotation = Vector3(_pitch, _yaw, 0)
	_cam.position = Vector3(0, 0, _cam_dist)


func _place_camera(pivot: Vector3, dist: float) -> void:
	_cam_pivot.position = pivot
	_cam_dist = dist
	_update_camera()


func _panel(anchor_x: Vector2, offset_x: Vector2, offset_y: Vector2, margin: Vector2i, anchor_y := 0.0) -> MarginContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat(PANEL_BG))
	panel.anchor_left = anchor_x.x
	panel.anchor_right = anchor_x.y
	panel.anchor_top = anchor_y
	panel.anchor_bottom = anchor_y
	panel.offset_left = offset_x.x
	panel.offset_right = offset_x.y
	panel.offset_top = offset_y.x
	panel.offset_bottom = offset_y.y
	var m := MarginContainer.new()
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, margin.x)
	for side in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, margin.y)
	panel.add_child(m)
	_hud.add_child(panel)
	return m


func _rich(min_size: Vector2, column := false) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	rt.custom_minimum_size = min_size
	rt.fit_content = not column
	rt.clip_contents = column
	rt.size_flags_horizontal = 0 if column else Control.SIZE_EXPAND_FILL
	return rt


func _square_button(btn: Button, on: bool) -> void:
	for state in BTN_STATES:
		btn.add_theme_stylebox_override(state, _btn_on if on else _btn_off)


func _setup_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)

	var wave := VBoxContainer.new()
	_panel(Vector2(0, 0), Vector2(10, 480), Vector2(10, 205), Vector2i(10, 8)).add_child(wave)
	var head := HBoxContainer.new()
	_wave_title_rt = _rich(Vector2(280, 20))
	_wave_val_rt = _rich(Vector2(160, 20))
	_wave_val_rt.size_flags_horizontal = 0
	head.add_child(_wave_title_rt)
	head.add_child(_wave_val_rt)
	wave.add_child(head)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	for i in METRIC_NAMES.size():
		var btn := Button.new()
		btn.text = METRIC_NAMES[i]
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(48, 18)
		btn.pressed.connect(_set_wave_metric.bind(i))
		tabs.add_child(btn)
		_metric_buttons.append(btn)
	wave.add_child(tabs)
	_wave_canvas = Control.new()
	_wave_canvas.custom_minimum_size = Vector2(450, 115)
	_wave_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wave_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_canvas.draw.connect(_draw_wave_canvas)
	wave.add_child(_wave_canvas)
	_set_wave_metric(0)

	var info := VBoxContainer.new()
	var a_margin := _panel(Vector2(0, 0), Vector2(10, 480), Vector2(215, 215), Vector2i(10, 8))
	a_margin.add_child(info)
	_analytics_panel = a_margin.get_parent()
	_info_rt = _rich(Vector2(450, 136))
	info.add_child(_info_rt)
	var vram_header := Label.new()
	vram_header.text = "VRAM ALLOCATION BREAKDOWN"
	vram_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vram_header.add_theme_font_size_override("font_size", 10)
	vram_header.custom_minimum_size = Vector2(450, 14)
	info.add_child(vram_header)
	_vram_bar = Control.new()
	_vram_bar.custom_minimum_size = Vector2(450, 16)
	_vram_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vram_bar.draw.connect(_draw_vram_bar)
	info.add_child(_vram_bar)
	_state_rt = _rich(Vector2(450, 136))
	info.add_child(_state_rt)

	var stats := VBoxContainer.new()
	_panel(Vector2(1, 1), Vector2(-780, -10), Vector2(10, 262), Vector2i(10, 8)).add_child(stats)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for i in 3:
		if i > 0:
			var sep := VSeparator.new()
			sep.custom_minimum_size = Vector2(14, 0)
			cols.add_child(sep)
		var rt := _rich(Vector2(240, 160), true)
		cols.add_child(rt)
		_stat_rts.append(rt)
	stats.add_child(cols)
	stats.add_child(HSeparator.new())
	_summary_label = Label.new()
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_child(_summary_label)

	_help_rt = _rich(Vector2(0, 56))
	_help_rt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_panel(Vector2(0, 1), Vector2(10, -10), Vector2(-120, -10), Vector2i(12, 6), 1.0).add_child(_help_rt)

	_toast_label = Label.new()
	_toast_label.add_theme_stylebox_override("normal", _flat(PANEL_BG))
	_toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_label.offset_top = -130
	_toast_label.offset_bottom = -130
	_toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast_label.visible = false
	_hud.add_child(_toast_label)

	_scan_hud = OctaDebugHUD.new()
	_scan_hud.visible = false
	_scan_hud.process_mode = Node.PROCESS_MODE_DISABLED
	_hud.add_child(_scan_hud)


func _count_tris(root: Node) -> int:
	var n := 0
	for gi in OctaLOD.geometry_below(root):
		if gi is MeshInstance3D and gi.mesh != null:
			n += gi.mesh.get_faces().size() / 3
	return n


func _run_loading_and_bake() -> void:
	await get_tree().process_frame
	_progress_bar.value = 20.0
	await get_tree().process_frame
	_models = [DemoObjects.rock(1), DemoObjects.tree(), DemoObjects.rings(), DemoObjects.textured()]
	for i in _models.size():
		_tris[i] = _count_tris(_models[i])
	_progress_bar.value = 45.0
	await get_tree().process_frame
	var sources: Array = _models.map(func(m: Node3D) -> Node3D: return m.duplicate())
	var settings := OctaBakeSettings.new()
	settings.grid_size = 16
	settings.hemisphere = true
	settings.max_atlas_size = 4096
	settings.msaa = Viewport.MSAA_4X
	settings.batch_size = 8
	settings.padding_px = 2
	settings.quality = OctaAtlas.Quality.HIGH
	var t0 := Time.get_ticks_msec()
	_atlas = await OctaBaker.bake(sources, self, settings)
	if _atlas == null:
		push_error("OctaBaker bake failed, retrying once")
		await get_tree().process_frame
		_atlas = await OctaBaker.bake(sources, self, settings)
	_bake_ms = Time.get_ticks_msec() - t0
	for s: Node in sources:
		s.free()
	if _atlas == null:
		push_error("OctaBaker bake failed")
		var failed := Label.new()
		failed.text = "The impostor atlas could not be baked."
		failed.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		_progress_bar.get_parent().add_child(failed)
		_progress_bar.hide()
		return
	_progress_bar.value = 85.0
	await get_tree().process_frame
	var adapter := RenderingServer.get_video_adapter_name()
	_info_head = "[b]GRAPHIC ANALYTICS[/b]  •  %s RENDERER
GPU: %s  •  API: %s
Atlas: %d objects  •  %d x %d views  •  %d px  •  %.0f MB  •  baked in %.1f s" % [
		RenderingServer.get_current_rendering_method().replace("_", " ").to_upper(), adapter if adapter != "" else "Hardware",
		RenderingServer.get_video_adapter_api_version(), _atlas.object_count(), _atlas.grid_size, _atlas.grid_size,
		_atlas.albedo.get_width(), _atlas.vram_bytes() / MB, _bake_ms / 1000.0]
	_progress_bar.value = 100.0
	_rebuild()
	await RenderingServer.frame_post_draw
	_loading_layer.queue_free()
	_loading_layer = null


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _slots() -> Array[Node]:
	return _sides if _current_level == 1 else _field.get_children()


func _count() -> int:
	return _spawn_count if _current_level == 2 else 1


func _live_imp() -> bool:
	return _is_impostor and _current_level == 2


func _rebuild() -> void:
	if is_instance_valid(_chunk_group):
		_chunk_group.queue_free()
	_chunk_group = null
	_clear(_field)
	_clear(_join_node)
	for s in _sides:
		_clear(s)
	_snap_real.fps = 0
	_snap_imp.fps = 0
	if _current_level == 1:
		_build_level_1()
	else:
		_build_level_2()
	_apply_ui()


func _fill_slot(slot: Node3D) -> void:
	var real: Node3D = _models[_current_asset].duplicate()
	real.name = "RealMesh"
	slot.add_child(real)
	var card := _atlas.create_card(_current_asset, _quality)
	card.name = "ImpostorCard"
	card.wind_strength = _wind_strength()
	slot.add_child(card)
	if _auto_lod:
		_set_slot_lod(slot, true)


func _build_level_1() -> void:
	_level1_node.visible = true
	_level2_node.visible = false
	_place_camera(Vector3(0, 1.2, 0), 6.5)
	for s in _sides:
		_fill_slot(s)
	_apply_view()


func _build_level_2() -> void:
	_level1_node.visible = false
	_level2_node.visible = true
	_place_camera(Vector3(0, 0.8, 0), clampf(5.0 + sqrt(float(_spawn_count)) * 1.25, 5.0, 140.0))
	var have: int = _field.get_child_count()
	while have > _spawn_count:
		have -= 1
		var extra := _field.get_child(have)
		_field.remove_child(extra)
		extra.queue_free()
	var rng := RandomNumberGenerator.new()
	var golden_angle: float = PI * (3.0 - sqrt(5.0))
	for i in range(have, _spawn_count):
		rng.seed = 42 + i
		var slot := Node3D.new()
		if _spawn_count > 1 or i > 0:
			var r: float = 2.4 * sqrt(float(i + 1))
			slot.position = Vector3(cos(i * golden_angle) * r, 0, sin(i * golden_angle) * r)
		slot.rotation.y = rng.randf() * TAU
		slot.scale = Vector3.ONE * rng.randf_range(0.9, 1.2)
		_field.add_child(slot)
		_fill_slot(slot)
		_style_slot(slot, not _is_impostor)
	if _joined:
		_rebuild_join()


func _style_slot(slot: Node, real_on: bool) -> void:
	var real: Node3D = slot.get_child(0)
	var card: Node3D = slot.get_child(1)
	real.visible = _auto_lod or real_on
	card.visible = _auto_lod or not (real_on or card.get_meta(JOINED, false))


func _apply_view() -> void:
	_scan_timer = INF
	if _current_level == 1:
		for i in 2:
			_style_slot(_sides[i], (i == 0) != _is_impostor)
			_labels[i].text = _side_text(i)
	else:
		for s in _field.get_children():
			_style_slot(s, not _is_impostor)
		_join_node.visible = _is_impostor
	_summary_label.text = SUMMARY % ("Real Mesh" if _is_impostor else "Impostor")


func _side_text(i: int) -> String:
	if _auto_lod:
		return "AUTO LOD\nswaps at %d m" % LOD_DISTANCE
	if (i == 0) != _is_impostor:
		return "REAL 3D MESH\n[ %d Tris ]" % _tris[_current_asset]
	return "OCTAHEDRAL IMPOSTOR\n[ 2 Tris / 1 Quad ]"


func _apply_ui() -> void:
	_hud.visible = _ui_visible
	_analytics_panel.visible = _analytics_visible
	for label in _labels:
		label.visible = _ui_visible and _current_level == 1
	_apply_view()


func _set_slot_lod(slot: Node, on: bool) -> void:
	var card: OctaImpostor = slot.get_child(1)
	card.lod_distance = LOD_DISTANCE if on else 0.0
	card.fade_margin = LOD_FADE
	card.fade = OctaLOD.Fade.CROSSFADE if on else OctaLOD.Fade.NONE
	for gi in OctaLOD.geometry_below(slot.get_child(0)):
		gi.visibility_parent = gi.get_path_to(card) if on else NodePath()


func _set_auto_lod(on: bool) -> void:
	if on == _auto_lod:
		return
	if on:
		_set_joined(false)
	_auto_lod = on
	for s in _slots():
		_set_slot_lod(s, on)
	_apply_view()


func _set_impostor_mode(on: bool) -> void:
	_set_auto_lod(false)
	_is_impostor = on
	_apply_view()


func _set_joined(on: bool) -> void:
	if on == _joined:
		return
	if on:
		_set_auto_lod(false)
		_join_base = Vector2(_snap_imp.draws, _snap_imp.cpu_ms) if _snap_imp.fps > 0 else Vector2(-1, -1)
		_is_impostor = true
	_joined = on
	_rebuild_join()


func _rebuild_join() -> void:
	_clear(_join_node)
	var slots: Array = []
	var points := PackedVector3Array()
	for s in _field.get_children():
		s.get_child(1).set_meta(JOINED, false)
		slots.append(s)
		points.append(s.position)
	_join_stats = Vector2i.ZERO
	if _joined:
		var custom := OctaAtlas.joined_custom(Color.WHITE, 1.0)
		var rules := OctaBakeSettings.new()
		for region: PackedInt32Array in OctaJoin.partition(points, JOIN_CELL, rules.join_adaptive, rules.join_region_size, rules.join_region_count):
			if region.size() < 2:
				continue
			var xforms: Array = []
			var customs: Array = []
			for i in region:
				xforms.append(slots[i].transform)
				slots[i].get_child(1).set_meta(JOINED, true)
				customs.append(custom)
			_join_node.add_child(_atlas.create_multimesh(_current_asset, xforms, _quality, customs, 0.0, 0.0, _wind_strength()))
			_join_stats += Vector2i(1, region.size())
	_apply_view()


func _wind_strength() -> float:
	return WIND_STRENGTH if _wind and _current_asset == WIND_ASSET else 0.0


func _set_wind(on: bool) -> void:
	_wind = on
	OctaWind.set_wind(WIND_DIRECTION, WIND_SPEED)
	for s in _slots():
		s.get_child(1).wind_strength = _wind_strength()
	_rebuild_join()


func _set_chunk(on: bool) -> void:
	if not on:
		if is_instance_valid(_chunk_group):
			_chunk_group.queue_free()
			_chunk_group = null
			_toast("Chunk LOD: removed")
		return
	if is_instance_valid(_chunk_group):
		return
	_toast("Chunk LOD: baking %d props..." % CHUNK_PROPS)
	var g := OctaImpostorGroup.new()
	g.name = "ChunkDemo"
	g.position = Vector3(0, 0, -8)
	add_child(g)
	var s := OctaBakeSettings.new()
	s.grid_size = 8
	s.max_atlas_size = 512
	s.material_maps = false
	s.emission = false
	s.half_res_material_maps = true
	g.settings = s
	g.chunk_lod_distance = CHUNK_DISTANCE
	g.chunk_quality = OctaAtlas.Quality.HIGH
	var props: Array[Node3D] = []
	for i in CHUNK_PROPS:
		var prop: Node3D = _models[_current_asset].duplicate()
		prop.name = "ChunkProp%d" % (i + 1)
		prop.position = Vector3((i - 1) * 2.6, 0, 0)
		g.add_child(prop)
		props.append(prop)
	_chunk_group = g
	var cs := g.chunk_settings()
	var chunk_atlas := await OctaBaker.bake([g], self, cs)
	if not is_instance_valid(g) or _chunk_group != g:
		if is_instance_valid(g):
			g.queue_free()
		return
	if chunk_atlas == null:
		g.queue_free()
		_chunk_group = null
		_toast("Chunk LOD: bake failed")
		return
	for prop in props:
		OctaLOD.attach_card(prop, _atlas, _current_asset, OctaLOD.Mode.DYNAMIC_LOD, CHUNK_DISTANCE, _quality)
	g.attach_chunk(chunk_atlas, cs, CHUNK_DISTANCE)
	_toast("Chunk LOD: %d props, one chunk card beyond %d m (press [C] to remove)" % [CHUNK_PROPS, int(CHUNK_DISTANCE)])


func _set_quality(q: int) -> void:
	_quality = q
	_snap_imp.fps = 0
	for s in _slots():
		s.get_child(1).quality = q
	for mmi: GeometryInstance3D in _join_node.get_children():
		mmi.material_override = _atlas.get_material(q)
	_apply_tint()


func _apply_tint() -> void:
	var col := Color(1.0, 0.25, 0.25) if _tinted else Color.WHITE
	for m in _atlas.materials:
		if m != null:
			m.set_shader_parameter("tint", col)


func _change_props(step: int) -> void:
	_spawn_count = clampi(_spawn_count + step, 1, MAX_PROPS)
	_join_base = Vector2(-1, -1)
	var other: Dictionary = _snap_real if _is_impostor else _snap_imp
	other.fps = 0
	_build_level_2()


func _start_benchmark() -> void:
	_simulating_benchmark = true
	_set_joined(false)
	_set_impostor_mode(false)
	_spawn_count = 1
	_sim_timer = 0.0
	_stabilize_timer = 0.0
	_benchmark_stage = 0
	_snap_real.fps = 0
	_snap_imp.fps = 0
	_build_level_2()
	_target_fps = 10 if Engine.get_frames_per_second() < 30 else 30


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_yaw -= event.relative.x * 0.005
			_pitch = clampf(_pitch - event.relative.y * 0.005, -0.9, 0.8)
			_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = clampf(_cam_dist - 2.0, 3.0, 180.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = clampf(_cam_dist + 2.0, 3.0, 180.0)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		_on_key(event.keycode)


func _fly(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_UP):
		dir -= _cam_pivot.basis.z
	if Input.is_physical_key_pressed(KEY_DOWN):
		dir += _cam_pivot.basis.z
	if Input.is_physical_key_pressed(KEY_LEFT):
		dir -= _cam_pivot.basis.x
	if Input.is_physical_key_pressed(KEY_RIGHT):
		dir += _cam_pivot.basis.x
	if Input.is_physical_key_pressed(KEY_Q):
		dir -= Vector3.UP
	if Input.is_physical_key_pressed(KEY_E):
		dir += Vector3.UP
	if dir == Vector3.ZERO:
		return
	var speed := FLY_SPEED * (4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	_cam_pivot.position += dir.normalized() * speed * delta
	_cam_pivot.position.y = maxf(_cam_pivot.position.y, 0.4)


func _toast(text: String) -> void:
	_toast_label.text = text
	_toast_label.visible = true
	_toast_timer = TOAST_TIME


func _flag(title: String, on: bool, note := "") -> void:
	_toast("%s: %s%s" % [title, "ON" if on else "OFF", note])


func _on_key(k: Key) -> void:
	if _atlas == null:
		if k == KEY_ESCAPE:
			get_tree().quit()
		return
	match k:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_G:
			_set_wave_metric((_current_metric + 1) % METRIC_NAMES.size())
		KEY_T:
			_tinted = not _tinted
			_apply_tint()
			_flag("Tint", _tinted)
		KEY_SPACE:
			_auto_orbit = not _auto_orbit
		KEY_A:
			_analytics_visible = not _analytics_visible
			_apply_ui()
		KEY_H, KEY_TAB:
			_ui_visible = not _ui_visible
			_apply_ui()
		_:
			if not _simulating_benchmark:
				_on_plugin_key(k)


func _on_plugin_key(k: Key) -> void:
	var field: bool = _current_level == 2
	match k:
		KEY_B:
			if field:
				_start_benchmark()
		KEY_F, KEY_ENTER:
			_set_impostor_mode(not _is_impostor)
		KEY_L, KEY_M:
			_current_level = 3 - _current_level
			_rebuild()
		KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT:
			if field:
				_change_props(1 if k in [KEY_EQUAL, KEY_KP_ADD] else -1)
		KEY_1, KEY_2, KEY_3, KEY_4:
			_current_asset = k - KEY_1
			_rebuild()
			_toast("Asset: " + ASSET_NAMES[_current_asset])
		KEY_F1, KEY_F2, KEY_F3, KEY_F4:
			_set_quality(k - KEY_F1)
			_toast("Quality: " + QUALITY_NAMES[_quality])
		KEY_D:
			OctaDebug.set_mode(((OctaDebug.mode + 1) % OctaDebug.Mode.size()) as OctaDebug.Mode)
			if OctaDebug.mode != OctaDebug.Mode.OFF and field and not _is_impostor and not _auto_lod:
				_set_impostor_mode(true)
			_toast("Debug view: " + OctaDebug.mode_names()[OctaDebug.mode])
		KEY_P:
			_atlas.precise_search = not _atlas.precise_search
			_flag("Precise search", _atlas.precise_search, " (Ultra only, about 2-3x GPU cost)")
		KEY_W:
			_atlas.write_depth = not _atlas.write_depth
			_flag("Write depth", _atlas.write_depth)
		KEY_S:
			_sun.shadow_enabled = not _sun.shadow_enabled
			_flag("Sun shadows", _sun.shadow_enabled)
		KEY_V:
			_atlas.shadow_views = _atlas.shadow_views % 3 + 1
			_toast("Shadow views: %d" % _atlas.shadow_views)
		KEY_R:
			_sun_spin = not _sun_spin
			_flag("Sun spin", _sun_spin)
		KEY_O:
			_set_auto_lod(not _auto_lod)
			_flag("Auto LOD", _auto_lod, " (cards beyond %d m)" % LOD_DISTANCE)
		KEY_K:
			_set_wind(not _wind)
			_flag("Wind", _wind, " (Foliage Tree impostors only%s)" % ("" if _current_asset == WIND_ASSET else ", press [2]"))
		KEY_C:
			if field:
				_set_chunk(not is_instance_valid(_chunk_group))
			else:
				_toast("Chunk LOD needs Level 2")
		KEY_J:
			if field:
				_set_joined(not _joined)
				_flag("Join", _joined, " (%d groups, %d cards)" % [_join_stats.x, _join_stats.y])
			else:
				_toast("Join needs Level 2")


func _set_wave_metric(idx: int) -> void:
	_current_metric = idx
	for i in _metric_buttons.size():
		_square_button(_metric_buttons[i], i == idx)
	_wave_red.clear()
	_wave_blue.clear()
	_wave_canvas.queue_redraw()


func _draws() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)


func _vram_mb() -> float:
	return Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / MB


func _sample(imp: bool, metric: int) -> float:
	var n: int = _count()
	var tris: float = float((2 if imp else _tris[_current_asset]) * n)
	var fps: float = float(Engine.get_frames_per_second())
	if imp == _live_imp():
		match metric:
			0: return _smooth_gpu_ms
			1: return fps
			2: return _vram_mb()
			3: return _smooth_cpu_ms
			4: return float(_draws())
			5: return tris / 1000.0
		var cost := clampf(_smooth_gpu_ms / 33.3, 0.0, 1.0) * 0.45 + clampf(_smooth_cpu_ms / 16.6, 0.0, 1.0) * 0.2
		return (cost + clampf(_vram_mb() / VRAM_BUDGET_MB, 0.0, 1.0) * 0.15 + clampf(tris / 10000000.0, 0.0, 1.0) * 0.2) * 100.0
	var s: Dictionary = _snap_imp if imp else _snap_real
	var ok: bool = s.fps > 0
	match metric:
		0: return s.gpu_ms if ok else (maxf(0.8 + n * 0.001, 1.2) if imp else maxf(_smooth_gpu_ms * 6.0, 16.0))
		1: return float(s.fps) if ok else (clampf(fps * 3.5, 60.0, 300.0) if imp else clampf(fps * 0.25, 5.0, 60.0))
		2: return s.vram if ok else _vram_mb() * (0.88 if imp else 1.15)
		3: return s.cpu_ms if ok else (maxf(_smooth_cpu_ms * 0.55, 1.0) if imp else _smooth_cpu_ms * 1.8)
		4: return float(s.draws) if ok else (float(mini(12 + n / 100, 30)) if imp else float(n + 5))
		5: return tris / 1000.0
	return 8.0 + n * 0.002 if imp else clampf(tris / 8000.0 + 35.0, 30.0, 100.0)


func _metric_max(metric: int) -> float:
	match metric:
		0: return maxf(maxf(_snap_real.gpu_ms, _smooth_gpu_ms) * 1.3, 33.3)
		1: return maxf(float(Engine.get_frames_per_second()) * 1.3, 150.0)
		2: return VRAM_BUDGET_MB
		3: return maxf(maxf(_snap_real.cpu_ms, _smooth_cpu_ms) * 1.3, 16.6)
		4: return maxf(maxf(float(_snap_real.draws), float(_draws())) * 1.25, 200.0)
		5: return maxf(float(_tris[_current_asset] * _count()) / 1000.0 * 1.25, 50.0)
	return 100.0


func _fmt(metric: int, v: float) -> String:
	match metric:
		0, 3: return "%.0fms" % v
		2: return "%.0fM" % v
		5: return "%.0fK" % v
		6: return "%.0f%%" % v
	return "%.0f" % v


func _draw_wave_canvas() -> void:
	var c := _wave_canvas
	var w: float = c.size.x
	var h: float = c.size.y
	if w <= 20.0 or h <= 20.0:
		return
	c.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.5), true)
	c.draw_rect(Rect2(0, 0, w, h), Color(0.18, 0.22, 0.28), false, 1.0)
	var left := 40.0
	var top := 12.0
	var plot_w: float = w - left - 8.0
	var plot_h: float = h - top - 10.0
	var base: float = top + plot_h
	var max_val: float = _metric_max(_current_metric)
	var font := ThemeDB.fallback_font
	for step in 3:
		var frac: float = float(step + 1) / 3.0
		var gy: float = top + plot_h * (1.0 - frac)
		c.draw_line(Vector2(left, gy), Vector2(w - 8.0, gy), Color(0.12, 0.15, 0.20, 0.8), 1.0)
		c.draw_string(font, Vector2(2, gy + 3), _fmt(_current_metric, max_val * frac), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, GRID_TEXT)
	c.draw_line(Vector2(left, base), Vector2(w - 8.0, base), Color(0.18, 0.22, 0.28), 1.0)
	c.draw_string(font, Vector2(2, base + 3), _fmt(_current_metric, 0.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, GRID_TEXT)
	var n: int = _wave_red.size()
	if n < 2:
		return
	_pts.resize(n)
	_poly.resize(n + 2)
	_poly[0] = Vector2(left, base)
	_poly[n + 1] = Vector2(left + plot_w, base)
	var denom: float = maxf(max_val, 0.001)
	for s in 2:
		var data: Array[float] = _wave_blue if s == 1 else _wave_red
		for i in n:
			var p := Vector2(left + float(i) / float(n - 1) * plot_w, top + plot_h * (1.0 - clampf(data[i] / denom, 0.0, 1.0)))
			_pts[i] = p
			_poly[i + 1] = p
		c.draw_colored_polygon(_poly, Color(WAVE_COLORS[s], WAVE_FILLS[s]))
		c.draw_polyline(_pts, WAVE_COLORS[s], 2.0, true)


func _draw_vram_bar() -> void:
	var w: float = _vram_bar.size.x
	var h: float = _vram_bar.size.y
	if w <= 10.0 or h <= 4.0:
		return
	_vram_bar.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.5), true)
	var x := 0.0
	for i in 3:
		var pw: float = clampf(_mem[i] / VRAM_BUDGET_MB * w, 0.0, maxf(w - x, 0.0))
		if pw > 0.5:
			_vram_bar.draw_rect(Rect2(x, 0, pw, h), VRAM_COLORS[i], true)
			x += pw
	for i in range(1, 4):
		_vram_bar.draw_line(Vector2(i * 0.25 * w, 0), Vector2(i * 0.25 * w, h), Color(0.3, 0.38, 0.48, 0.7), 1.0)


func _process(delta: float) -> void:
	if _auto_orbit:
		_yaw += delta * 0.28
		_update_camera()
	if _atlas == null:
		return
	if not _simulating_benchmark:
		_fly(delta)
	if _sun_spin:
		_sun.rotation.y += deg_to_rad(SUN_SPIN_DEG) * delta
	_frame_times[_frame_i % WAVE_POINTS] = delta * 1000.0
	_frame_i += 1
	_smooth_gpu_ms = lerpf(_smooth_gpu_ms, RenderingServer.viewport_get_measured_render_time_gpu(_rid), SMOOTH)
	_smooth_cpu_ms = lerpf(_smooth_cpu_ms, RenderingServer.viewport_get_measured_render_time_cpu(_rid), SMOOTH)
	_wave_timer += delta
	if _wave_timer >= WAVE_STEP:
		_wave_timer = 0.0
		_wave_red.append(_sample(false, _current_metric))
		_wave_blue.append(_sample(true, _current_metric))
		if _wave_red.size() > WAVE_POINTS:
			_wave_red.pop_front()
			_wave_blue.pop_front()
		if _ui_visible:
			_wave_canvas.queue_redraw()
	if _simulating_benchmark:
		_step_benchmark(delta)
	if _toast_timer > 0.0:
		_toast_timer -= delta
		_toast_label.visible = _toast_timer > 0.0
	_hud_timer += delta
	_scan_timer += delta
	if _hud_timer >= HUD_STEP:
		_hud_timer = 0.0
		_update_hud()


func _crashed(raw_gpu: float, delta: float) -> bool:
	return raw_gpu >= 50.0 or _smooth_gpu_ms >= 45.0 or delta >= 0.14 or _vram_mb() >= 1600.0 or _draws() >= 4000 or _tris[_current_asset] * _spawn_count >= 100000000


func _start_impostor_stage() -> void:
	_benchmark_stage = 2
	_stabilize_timer = 0.0
	_set_impostor_mode(true)


func _step_benchmark(delta: float) -> void:
	var fps: int = Engine.get_frames_per_second()
	var crashed: bool = _benchmark_stage < 2 and _crashed(RenderingServer.viewport_get_measured_render_time_gpu(_rid), delta)
	if _benchmark_stage == 0:
		if crashed:
			_start_impostor_stage()
			return
		_sim_timer += delta
		if _sim_timer >= BENCH_STEP:
			_sim_timer = 0.0
			if fps <= _target_fps or _spawn_count >= MAX_PROPS:
				_benchmark_stage = 1
				_stabilize_timer = 0.0
			else:
				_spawn_count = mini(_spawn_count + maxi(int(_spawn_count * BENCH_GROW), 1), MAX_PROPS)
				_build_level_2()
	elif _benchmark_stage == 1:
		if crashed:
			_start_impostor_stage()
		elif fps <= _target_fps + 2 or _spawn_count >= MAX_PROPS:
			_stabilize_timer += delta
			if _stabilize_timer >= BENCH_STABLE:
				_start_impostor_stage()
		else:
			_stabilize_timer = 0.0
			_benchmark_stage = 0
	else:
		_stabilize_timer += delta
		if _stabilize_timer >= BENCH_IMPOSTOR:
			_simulating_benchmark = false
			_benchmark_stage = 0


func _live_tris() -> int:
	if _auto_lod:
		return _scan.get("real_visible", 0) * _tris[_current_asset] + _scan.get("impostor_visible", 0) * 2
	return (2 if _live_imp() else _tris[_current_asset]) * _count()


func _update_hud() -> void:
	var fps: int = Engine.get_frames_per_second()
	var count: int = _count()
	var draws: int = _draws()
	var imp: bool = _live_imp()
	_mem = Vector3(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED), Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED), 0.0) / MB
	var total: float = _vram_mb()
	_mem.z = maxf(total - _mem.x - _mem.y, 0.0)
	if not _auto_lod:
		var snap: Dictionary = _snap_imp if imp else _snap_real
		snap.merge({fps = fps, gpu_ms = _smooth_gpu_ms, cpu_ms = _smooth_cpu_ms, tris = (2 if imp else _tris[_current_asset]) * count,
				draws = draws, vram = total, count = count}, true)
	if not _hud.visible:
		return
	_stat_rts[0].text = _stats_text("ORIGINAL (REAL MESH)", _snap_real)
	_stat_rts[1].text = _stats_text("OCTAHEDRAL IMPOSTOR", _snap_imp)
	_stat_rts[2].text = _diff_text()
	if count != _text_count:
		_text_count = count
		_wave_title_rt.text = "[b]WAVE MONITOR[/b] (%d Props)  •  [color=%s]■ REAL[/color]  vs  [color=%s]■ IMPOSTOR[/color]" % [count, HEX_REAL, HEX_IMP]
		_help_rt.text = HELP % count
	_wave_val_rt.text = "[right][color=%s]R: %s[/color] | [color=%s]B: %s[/color][/right]" % [
		HEX_REAL, _fmt(_current_metric, _wave_red.back() if not _wave_red.is_empty() else 0.0),
		HEX_IMP, _fmt(_current_metric, _wave_blue.back() if not _wave_blue.is_empty() else 0.0)]
	if not _analytics_visible:
		return
	if _scan_timer >= SCAN_STEP * maxf(1.0, count / 400.0) and not _simulating_benchmark:
		_scan_timer = 0.0
		_scan = _scan_hud.scan()
	_update_analytics(fps, draws, imp)


func _update_analytics(fps: int, draws: int, imp: bool) -> void:
	var mode := "SIDE-BY-SIDE"
	if _auto_lod:
		mode = "[color=#ffd24a]AUTO LOD[/color]"
	elif _current_level == 2:
		mode = "[color=%s]%s[/color]" % [HEX_IMP, "OCTA IMPOSTOR"] if imp else "[color=%s]REAL 3D MESH[/color]" % HEX_REAL
	var status := "BALANCED PIPELINE"
	if imp:
		status = "OPTIMIZED (Fillrate/Geom Unconstrained)"
	elif _smooth_gpu_ms >= 20.0 or _smooth_gpu_ms > _smooth_cpu_ms * 2.0:
		status = "GPU FILL / GEOMETRY BOUND"
	elif draws >= 1200 or _smooth_cpu_ms > _smooth_gpu_ms * 1.5:
		status = "CPU DRAW-CALL BOUND"
	var n: int = mini(_frame_i, WAVE_POINTS)
	var p99 := 0.0
	var jitter := 0.0
	if n > 5:
		var ft := _frame_times.slice(0, n)
		ft.sort()
		p99 = ft[clampi(int(n * 0.99), 0, n - 1)]
		var sum := 0.0
		var squares := 0.0
		for t in ft:
			sum += t
			squares += t * t
		jitter = sqrt(maxf(squares / n - pow(sum / n, 2.0), 0.0))
	_info_rt.text = "%s
Mode: %s  •  Pipeline: %s
Throughput: %.2f MTris/s  •  Draws: %d
Frame Time: %.1f ms  •  99th%% (p99): %.1f ms  •  Jitter: %.2f ms" % [
		_info_head, mode, status, float(_live_tris()) * fps / 1000000.0, draws, 1000.0 / maxi(fps, 1), p99, jitter]
	_vram_bar.queue_redraw()
	_state_rt.text = _state_text(draws)


func _state_text(draws: int) -> String:
	var precise := "OFF"
	if _atlas.precise_search:
		precise = "ON (Ultra, 2-3x)" if _quality == OctaAtlas.Quality.ULTRA else "ON (needs Ultra)"
	var lod := "HOT-SWAP"
	if _auto_lod:
		lod = "AUTO %d m (%s crossfade %d m)" % [LOD_DISTANCE, OctaLOD.fade_kind(), LOD_FADE]
	var join := "n/a (Level 2)"
	if _current_level == 2:
		join = "OFF"
	if _joined and _current_level == 2:
		join = "%d groups / %d cards" % [_join_stats.x, _join_stats.y]
		if _join_base.x >= 0.0:
			join += ", draws %d (was %d), CPU %.1f (was %.1f) ms" % [draws, _join_base.x, _smooth_cpu_ms, _join_base.y]
	var fill: float = _scan.get("card_fill", {}).get(_atlas, -1.0)
	var real: int = _scan.get("real_visible", 0) - (_join_stats.y if _joined and _is_impostor else 0)
	var chunk := "OFF" if not is_instance_valid(_chunk_group) else "%d props at %d m" % [CHUNK_PROPS, int(CHUNK_DISTANCE)]
	var total := _vram_mb()
	return "■ Tex: %.1f MB  ■ Buf: %.1f MB  ■ Other: %.1f MB
Total: %.1f MB / %.0f MB (%.1f%%)
Quality: %s  •  Debug: %s  •  Write depth: %s
Precise: %s  •  Shadows: %s (%d view)  •  Sun spin: %s  •  Wind: %s
LOD: %s  •  Join: %s  •  Chunk: %s
Cards: %d drawn / %d real  •  Card fill: %s" % [
		_mem.x, _mem.y, _mem.z, total, VRAM_BUDGET_MB, clampf(total / VRAM_BUDGET_MB * 100.0, 0.0, 100.0),
		OctaAtlas.Quality.keys()[_quality], OctaDebug.mode_names()[OctaDebug.mode], _onoff(_atlas.write_depth),
		precise, _onoff(_sun.shadow_enabled), _atlas.shadow_views, _onoff(_sun_spin), _onoff(_wind), lod, join, chunk,
		_scan.get("impostor_visible", 0), real, "%.0f%%" % fill if fill >= 0.0 else "--"]


func _onoff(on: bool) -> String:
	return "ON" if on else "OFF"


func _stats_text(title: String, s: Dictionary) -> String:
	if s.fps <= 0:
		return "[b]%s[/b]\n%s" % [title, STATS_EMPTY]
	return "[b]%s[/b]\nSpawned Props: %d\nFPS: %d\nGPU Time: %.2f ms\nCPU Time: %.2f ms\nTriangles: %d\nDraw Calls: %d\nVRAM: %.1f MB (%.1f%%)" % [
		title, s.count, s.fps, s.gpu_ms, s.cpu_ms, s.tris, s.draws, s.vram, clampf(s.vram / VRAM_BUDGET_MB * 100.0, 0.0, 100.0)]


func _diff_text() -> String:
	var r: Dictionary = _snap_real
	var i: Dictionary = _snap_imp
	if r.fps <= 0 or i.fps <= 0:
		return "[b]DIFFERENCE (%)[/b]\n" + STATS_EMPTY
	return "[b]DIFFERENCE (%%)[/b]\nSpawned Props: %s\nFPS: %s\nGPU Time: %s\nCPU Time: %s\nTriangles: %s\nDraw Calls: %s\nVRAM: %s" % [
		_pct(i.count, r.count, true), _pct(i.fps, r.fps, true), _pct(i.gpu_ms, r.gpu_ms, false), _pct(i.cpu_ms, r.cpu_ms, false),
		_pct(i.tris, r.tris, false), _pct(i.draws, r.draws, false), _pct(i.vram, r.vram, false)]


func _pct(a: float, b: float, higher_better: bool) -> String:
	var d: float = (a - b) / maxf(absf(b), 0.0001) * 100.0
	var txt: String = "%+.1f%%" % d
	if absf(d) < 0.05:
		return txt
	return "[color=%s]%s[/color]" % [HEX_GOOD if (d > 0.0) == higher_better else HEX_REAL, txt]
