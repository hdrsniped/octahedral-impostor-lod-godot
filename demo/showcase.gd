extends Node3D

const OctaAtlas = preload("res://addons/octahedral_impostor_lod/octa_atlas.gd")
const OctaBaker = preload("res://addons/octahedral_impostor_lod/octa_baker.gd")
const OctaBakeSettings = preload("res://addons/octahedral_impostor_lod/octa_bake_settings.gd")
const DemoObjects = preload("res://demo/demo_objects.gd")

const ASSET_NAMES: Array[String] = ["Procedural Rock", "Foliage Tree", "Gyroscope Rings"]
const ASSET_TRIS: Array[int] = [32000, 4800, 6100]
const QUALITY_NAMES: Array[String] = ["Low (1 View, Fastest)", "Medium (3-View Blend)", "High (Parallax Raymarching)"]
const METRIC_NAMES: Array[String] = ["GPU", "FPS", "VRAM", "CPU", "Draws", "Tris", "All"]
const VRAM_BUDGET_MB: float = 2048.0

var _atlas: OctaAtlas
var _cached_models: Array[Node3D] = []

var _current_level: int = 2
var _current_asset: int = 0
var _quality: int = OctaAtlas.Quality.MEDIUM
var _spawn_count: int = 1
var _is_impostor: bool = false
var _tinted: bool = false
var _auto_orbit: bool = true
var _ui_visible: bool = true
var _yaw: float = 0.0
var _pitch: float = -0.28
var _cam_dist: float = 6.0

var _simulating_benchmark: bool = false
var _target_fps_sim: float = 30.0
var _sim_timer: float = 0.0
var _stabilize_timer: float = 0.0
var _benchmark_stage: int = 0
var _benchmark_done_timer: float = 0.0
var _emergency_switch_msg: String = ""

var _smooth_gpu_ms: float = 0.0
var _smooth_cpu_ms: float = 0.0

var _current_metric: int = 0
var _wave_red: Array[float] = []
var _wave_blue: Array[float] = []
var _wave_sample_timer: float = 0.0
var _wave_canvas: Control
var _wave_title_rt: RichTextLabel
var _wave_val_label: Label
var _metric_buttons: Array[Button] = []

var _snap_real := {
	"fps": 0,
	"gpu_ms": 0.0,
	"cpu_ms": 0.0,
	"tris": 0,
	"draws": 0,
	"vram": 0.0,
	"count": 0
}

var _snap_impostor := {
	"fps": 0,
	"gpu_ms": 0.0,
	"cpu_ms": 0.0,
	"tris": 0,
	"draws": 0,
	"vram": 0.0,
	"count": 0
}

var _cam_pivot: Node3D
var _cam: Camera3D
var _stage_root: Node3D
var _level1_node: Node3D
var _level2_node: Node3D
var _left_slot: Node3D
var _right_slot: Node3D
var _left_label: Label3D
var _right_label: Label3D

var _hud: CanvasLayer
var _real_stats_rt: RichTextLabel
var _imp_stats_rt: RichTextLabel
var _diff_stats_rt: RichTextLabel
var _summary_label: Label
var _help_rt: RichTextLabel

var _analytics_panel: PanelContainer
var _analytics_visible: bool = true
var _analytics_header_rt: RichTextLabel
var _analytics_gpu_rt: RichTextLabel
var _analytics_diag_rt: RichTextLabel
var _analytics_lat_rt: RichTextLabel
var _vram_bar_canvas: Control
var _vram_info_rt: RichTextLabel
var _frame_times: Array[float] = []

var _loading_layer: CanvasLayer
var _progress_bar: ProgressBar


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var rid: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)

	_setup_loading_screen()
	_setup_environment()
	_setup_stage()
	_setup_camera()
	_setup_hud()

	_stage_root.visible = false
	_hud.visible = false

	_run_loading_and_bake()


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
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 5.0
	_progress_bar.show_percentage = false
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

	var sun := DirectionalLight3D.new()
	sun.position = Vector3(12, 18, 12)
	sun.rotation_degrees = Vector3(-45, 40, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.35
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.45
	fill.shadow_enabled = false
	add_child(fill)


func _setup_stage() -> void:
	_stage_root = Node3D.new()
	add_child(_stage_root)

	var ground := MeshInstance3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(800, 800)
	ground.mesh = plane_mesh
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.11, 0.13, 0.16)
	gmat.roughness = 0.7
	ground.material_override = gmat
	_stage_root.add_child(ground)

	var grid := MeshInstance3D.new()
	var grid_mesh := PlaneMesh.new()
	grid_mesh.size = Vector2(600, 600)
	grid.mesh = grid_mesh
	grid.position.y = 0.002
	var grid_mat := StandardMaterial3D.new()
	grid_mat.albedo_color = Color(0.15, 0.18, 0.23)
	grid_mat.roughness = 0.8
	grid.material_override = grid_mat
	_stage_root.add_child(grid)

	_level1_node = Node3D.new()
	_level1_node.visible = false
	_stage_root.add_child(_level1_node)

	_left_slot = Node3D.new()
	_left_slot.position = Vector3(-2.2, 0, 0)
	_level1_node.add_child(_left_slot)

	_right_slot = Node3D.new()
	_right_slot.position = Vector3(2.2, 0, 0)
	_level1_node.add_child(_right_slot)

	_create_pedestal(_level1_node, Vector3(-2.2, 0, 0), Color(0.2, 0.9, 0.45))
	_create_pedestal(_level1_node, Vector3(2.2, 0, 0), Color(0.2, 0.75, 1.0))

	_left_label = Label3D.new()
	_left_label.position = Vector3(-2.2, 3.2, 0)
	_left_label.font_size = 28
	_left_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_level1_node.add_child(_left_label)

	_right_label = Label3D.new()
	_right_label.position = Vector3(2.2, 3.2, 0)
	_right_label.font_size = 28
	_right_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_level1_node.add_child(_right_label)

	_level2_node = Node3D.new()
	_stage_root.add_child(_level2_node)


func _create_pedestal(parent: Node3D, pos: Vector3, accent: Color) -> void:
	var ped := Node3D.new()
	ped.position = pos

	var cyl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.7
	cm.bottom_radius = 1.75
	cm.height = 0.08
	cm.radial_segments = 64
	cyl.mesh = cm
	cyl.position.y = 0.04
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.09, 0.11, 0.14)
	pmat.roughness = 0.4
	cyl.material_override = pmat
	ped.add_child(cyl)

	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.68
	tm.outer_radius = 1.74
	tm.rings = 64
	ring.mesh = tm
	ring.position.y = 0.081
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = accent
	rmat.emission_enabled = true
	rmat.emission = accent * 0.9
	ring.material_override = rmat
	ped.add_child(ring)

	parent.add_child(ped)


func _setup_camera() -> void:
	_cam_pivot = Node3D.new()
	_cam_pivot.position = Vector3(0, 1.0, 0)
	add_child(_cam_pivot)

	_cam = Camera3D.new()
	_cam.position = Vector3(0, 0, _cam_dist)
	_cam.current = true
	_cam.far = 1200.0
	_cam_pivot.add_child(_cam)
	_update_camera()


func _setup_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 10

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0.55)
	panel_style.set_corner_radius_all(0)

	var wave_panel := PanelContainer.new()
	wave_panel.add_theme_stylebox_override("panel", panel_style)
	wave_panel.anchor_left = 0.0
	wave_panel.anchor_right = 0.0
	wave_panel.offset_left = 10
	wave_panel.offset_right = 480
	wave_panel.offset_top = 10
	wave_panel.offset_bottom = 205

	var wave_m := MarginContainer.new()
	wave_m.add_theme_constant_override("margin_left", 10)
	wave_m.add_theme_constant_override("margin_top", 8)
	wave_m.add_theme_constant_override("margin_right", 10)
	wave_m.add_theme_constant_override("margin_bottom", 8)

	var wave_vbox := VBoxContainer.new()
	wave_vbox.add_theme_constant_override("separation", 4)

	var wave_header_hbox := HBoxContainer.new()
	_wave_title_rt = RichTextLabel.new()
	_wave_title_rt.bbcode_enabled = true
	_wave_title_rt.fit_content = true
	_wave_title_rt.scroll_active = false
	_wave_title_rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	_wave_title_rt.custom_minimum_size = Vector2(280, 20)
	_wave_title_rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_title_rt.text = "[b]WAVE MONITOR[/b]  •  [color=#ff4444]■ REAL[/color]  vs  [color=#33b5ff]■ IMPOSTOR[/color]"
	wave_header_hbox.add_child(_wave_title_rt)

	_wave_val_label = Label.new()
	_wave_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wave_val_label.custom_minimum_size = Vector2(160, 20)
	wave_header_hbox.add_child(_wave_val_label)
	wave_vbox.add_child(wave_header_hbox)

	var tabs_hbox := HBoxContainer.new()
	tabs_hbox.add_theme_constant_override("separation", 3)
	_metric_buttons.clear()
	for i in METRIC_NAMES.size():
		var btn := Button.new()
		btn.text = METRIC_NAMES[i]
		_square_button(btn, Color(0, 0, 0, 0.3))
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(48, 18)
		var b_idx: int = i
		btn.pressed.connect(func(): _set_wave_metric(b_idx))
		tabs_hbox.add_child(btn)
		_metric_buttons.append(btn)
	wave_vbox.add_child(tabs_hbox)

	_wave_canvas = Control.new()
	_wave_canvas.custom_minimum_size = Vector2(450, 115)
	_wave_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wave_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_canvas.draw.connect(_draw_wave_canvas)
	wave_vbox.add_child(_wave_canvas)

	wave_m.add_child(wave_vbox)
	wave_panel.add_child(wave_m)
	_hud.add_child(wave_panel)

	_set_wave_metric(0)

	_analytics_panel = PanelContainer.new()
	var analytics_style := StyleBoxFlat.new()
	analytics_style.bg_color = Color(0, 0, 0, 0.55)
	analytics_style.set_corner_radius_all(0)
	_analytics_panel.add_theme_stylebox_override("panel", analytics_style)
	_analytics_panel.anchor_left = 0.0
	_analytics_panel.anchor_right = 0.0
	_analytics_panel.offset_left = 10
	_analytics_panel.offset_right = 480
	_analytics_panel.offset_top = 215
	_analytics_panel.offset_bottom = 215

	var a_m := MarginContainer.new()
	a_m.add_theme_constant_override("margin_left", 10)
	a_m.add_theme_constant_override("margin_top", 8)
	a_m.add_theme_constant_override("margin_right", 10)
	a_m.add_theme_constant_override("margin_bottom", 8)

	var a_vbox := VBoxContainer.new()
	a_vbox.add_theme_constant_override("separation", 4)

	_analytics_header_rt = RichTextLabel.new()
	_analytics_header_rt.bbcode_enabled = true
	_analytics_header_rt.fit_content = true
	_analytics_header_rt.scroll_active = false
	_analytics_header_rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	_analytics_header_rt.custom_minimum_size = Vector2(450, 20)
	_analytics_header_rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_analytics_header_rt.text = "[b]GRAPHIC ANALYTICS[/b]  •  VULKAN PIPELINE"
	a_vbox.add_child(_analytics_header_rt)

	_analytics_gpu_rt = RichTextLabel.new()
	_analytics_gpu_rt.bbcode_enabled = true
	_analytics_gpu_rt.fit_content = true
	_analytics_gpu_rt.scroll_active = false
	_analytics_gpu_rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	_analytics_gpu_rt.custom_minimum_size = Vector2(450, 20)
	_analytics_gpu_rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_analytics_gpu_rt.text = "GPU: Detecting GPU...  •  API: Vulkan 1.3"
	a_vbox.add_child(_analytics_gpu_rt)

	_analytics_diag_rt = RichTextLabel.new()
	_analytics_diag_rt.bbcode_enabled = true
	_analytics_diag_rt.fit_content = true
	_analytics_diag_rt.scroll_active = false
	_analytics_diag_rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	_analytics_diag_rt.custom_minimum_size = Vector2(450, 38)
	_analytics_diag_rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_analytics_diag_rt.text = "Mode: [color=#ff4444]REAL 3D MESH[/color]  •  Pipeline: INITIALIZING\nThroughput: 0.00 MTris/s  •  Draw Calls: 0"
	a_vbox.add_child(_analytics_diag_rt)

	_analytics_lat_rt = RichTextLabel.new()
	_analytics_lat_rt.bbcode_enabled = true
	_analytics_lat_rt.fit_content = true
	_analytics_lat_rt.scroll_active = false
	_analytics_lat_rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	_analytics_lat_rt.custom_minimum_size = Vector2(450, 20)
	_analytics_lat_rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_analytics_lat_rt.text = "Frame Time: 0.0 ms  •  99th% (p99): 0.0 ms  •  Jitter: 0.00 ms"
	a_vbox.add_child(_analytics_lat_rt)

	var vram_header := Label.new()
	vram_header.text = "VRAM ALLOCATION BREAKDOWN"
	vram_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vram_header.add_theme_font_size_override("font_size", 10)
	vram_header.custom_minimum_size = Vector2(450, 14)
	a_vbox.add_child(vram_header)

	_vram_bar_canvas = Control.new()
	_vram_bar_canvas.custom_minimum_size = Vector2(450, 16)
	_vram_bar_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vram_bar_canvas.draw.connect(_draw_vram_bar)
	a_vbox.add_child(_vram_bar_canvas)

	_vram_info_rt = RichTextLabel.new()
	_vram_info_rt.bbcode_enabled = true
	_vram_info_rt.fit_content = true
	_vram_info_rt.scroll_active = false
	_vram_info_rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	_vram_info_rt.custom_minimum_size = Vector2(450, 36)
	_vram_info_rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vram_info_rt.text = "■ Tex: 0.0 MB  ■ Buf: 0.0 MB  ■ Other: 0.0 MB\nTotal: 0.0 MB / 2048 MB (0.0%)"
	a_vbox.add_child(_vram_info_rt)

	a_m.add_child(a_vbox)
	_analytics_panel.add_child(a_m)
	_hud.add_child(_analytics_panel)

	var top_right_panel := PanelContainer.new()
	top_right_panel.add_theme_stylebox_override("panel", panel_style)
	top_right_panel.anchor_left = 1.0
	top_right_panel.anchor_right = 1.0
	top_right_panel.offset_left = -780
	top_right_panel.offset_right = -10
	top_right_panel.offset_top = 10
	top_right_panel.offset_bottom = 262

	var top_m := MarginContainer.new()
	top_m.add_theme_constant_override("margin_left", 10)
	top_m.add_theme_constant_override("margin_top", 8)
	top_m.add_theme_constant_override("margin_right", 10)
	top_m.add_theme_constant_override("margin_bottom", 8)

	var stats_vbox := VBoxContainer.new()

	var columns_hbox := HBoxContainer.new()
	columns_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_real_stats_rt = RichTextLabel.new()
	_real_stats_rt.bbcode_enabled = true
	_real_stats_rt.fit_content = false
	_real_stats_rt.scroll_active = false
	_real_stats_rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	_real_stats_rt.custom_minimum_size = Vector2(240, 160)
	_real_stats_rt.size_flags_horizontal = 0
	_real_stats_rt.clip_contents = true
	columns_hbox.add_child(_real_stats_rt)

	var vsep1 := VSeparator.new()
	vsep1.custom_minimum_size = Vector2(14, 0)
	columns_hbox.add_child(vsep1)

	_imp_stats_rt = RichTextLabel.new()
	_imp_stats_rt.bbcode_enabled = true
	_imp_stats_rt.fit_content = false
	_imp_stats_rt.scroll_active = false
	_imp_stats_rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	_imp_stats_rt.custom_minimum_size = Vector2(240, 160)
	_imp_stats_rt.size_flags_horizontal = 0
	_imp_stats_rt.clip_contents = true
	columns_hbox.add_child(_imp_stats_rt)

	var vsep2 := VSeparator.new()
	vsep2.custom_minimum_size = Vector2(14, 0)
	columns_hbox.add_child(vsep2)

	_diff_stats_rt = RichTextLabel.new()
	_diff_stats_rt.bbcode_enabled = true
	_diff_stats_rt.fit_content = false
	_diff_stats_rt.scroll_active = false
	_diff_stats_rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	_diff_stats_rt.custom_minimum_size = Vector2(240, 160)
	_diff_stats_rt.size_flags_horizontal = 0
	_diff_stats_rt.clip_contents = true
	columns_hbox.add_child(_diff_stats_rt)

	stats_vbox.add_child(columns_hbox)

	var hsep := HSeparator.new()
	stats_vbox.add_child(hsep)

	_summary_label = Label.new()
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_vbox.add_child(_summary_label)

	top_m.add_child(stats_vbox)
	top_right_panel.add_child(top_m)
	_hud.add_child(top_right_panel)

	var bot_panel := PanelContainer.new()
	bot_panel.add_theme_stylebox_override("panel", panel_style)
	bot_panel.anchor_left = 0.0
	bot_panel.anchor_right = 1.0
	bot_panel.anchor_top = 1.0
	bot_panel.anchor_bottom = 1.0
	bot_panel.offset_left = 10
	bot_panel.offset_right = -10
	bot_panel.offset_top = -120
	bot_panel.offset_bottom = -10

	var bm := MarginContainer.new()
	bm.add_theme_constant_override("margin_left", 12)
	bm.add_theme_constant_override("margin_top", 6)
	bm.add_theme_constant_override("margin_right", 12)
	bm.add_theme_constant_override("margin_bottom", 6)

	_help_rt = RichTextLabel.new()
	_help_rt.bbcode_enabled = true
	_help_rt.fit_content = true
	_help_rt.scroll_active = false
	_help_rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	_help_rt.custom_minimum_size = Vector2(0, 56)
	_help_rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_rt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bm.add_child(_help_rt)

	bot_panel.add_child(bm)
	_hud.add_child(bot_panel)

	add_child(_hud)


func _run_loading_and_bake() -> void:
	await get_tree().process_frame

	_progress_bar.value = 20.0
	await get_tree().process_frame

	_cached_models = [
		DemoObjects.rock(1),
		DemoObjects.tree(),
		DemoObjects.rings()
	]

	_progress_bar.value = 45.0
	await get_tree().process_frame

	var sources: Array = [
		_cached_models[0].duplicate(),
		_cached_models[1].duplicate(),
		_cached_models[2].duplicate()
	]

	var settings := OctaBakeSettings.new()
	settings.grid_size = 16
	settings.hemisphere = true
	settings.max_atlas_size = 4096
	settings.msaa = Viewport.MSAA_4X
	settings.padding_px = 2
	settings.quality = OctaAtlas.Quality.HIGH

	_atlas = await OctaBaker.bake(sources, self, settings)
	for s: Node in sources:
		s.free()

	if _atlas == null:
		push_error("OctaBaker bake failed")
		return

	_progress_bar.value = 85.0
	await get_tree().process_frame

	_switch_asset(0)

	_progress_bar.value = 100.0
	await get_tree().process_frame

	_stage_root.visible = true
	_hud.visible = true
	if _analytics_panel != null:
		_analytics_panel.visible = true
	_update_hud()
	await RenderingServer.frame_post_draw

	if _loading_layer != null:
		_loading_layer.queue_free()
		_loading_layer = null


func _reset_snapshots() -> void:
	_snap_real.fps = 0
	_snap_real.gpu_ms = 0.0
	_snap_impostor.fps = 0
	_snap_impostor.gpu_ms = 0.0


func _switch_asset(idx: int) -> void:
	_current_asset = idx
	_reset_snapshots()
	for c in _level2_node.get_children():
		c.queue_free()
	if _current_level == 1:
		_build_level_1()
	else:
		_build_level_2()


func _build_level_1() -> void:
	if _level1_node != null:
		_level1_node.visible = true
	if _level2_node != null:
		_level2_node.visible = false
	if _cam_pivot != null:
		_cam_pivot.position = Vector3(0, 1.2, 0)
	_cam_dist = 6.5
	_update_camera()

	if _left_slot != null:
		for c in _left_slot.get_children():
			c.queue_free()
	if _right_slot != null:
		for c in _right_slot.get_children():
			c.queue_free()

	if not _cached_models.is_empty() and _left_slot != null:
		var real_mesh: Node3D = _cached_models[_current_asset].duplicate()
		_left_slot.add_child(real_mesh)

	if _atlas != null and _right_slot != null:
		var card: MeshInstance3D = _atlas.create_card(_current_asset, _quality)
		_right_slot.add_child(card)

	if _left_label != null:
		_left_label.text = "REAL 3D MESH\n[ %d Tris ]" % ASSET_TRIS[_current_asset]
	if _right_label != null:
		_right_label.text = "OCTAHEDRAL IMPOSTOR\n[ 2 Tris / 1 Quad ]"

	if _tinted:
		_apply_tint()


func _build_level_2() -> void:
	if _level1_node != null:
		_level1_node.visible = false
	if _level2_node != null:
		_level2_node.visible = true
	if _cam_pivot != null:
		_cam_pivot.position = Vector3(0, 0.8, 0)
	_cam_dist = clampf(5.0 + sqrt(float(_spawn_count)) * 1.25, 5.0, 140.0)
	_update_camera()

	if _level2_node == null:
		return

	var current_slots: Array[Node] = _level2_node.get_children()
	var current_count: int = current_slots.size()

	if current_count > _spawn_count:
		for i in range(_spawn_count, current_count):
			current_slots[i].queue_free()
	elif current_count < _spawn_count:
		var rng := RandomNumberGenerator.new()
		var golden_angle: float = PI * (3.0 - sqrt(5.0))
		var spacing: float = 2.4

		for i in range(current_count, _spawn_count):
			rng.seed = 42 + i
			var pos: Vector3 = Vector3.ZERO
			if _spawn_count > 1 or i > 0:
				var r: float = spacing * sqrt(float(i + 1))
				var theta: float = float(i) * golden_angle
				pos = Vector3(cos(theta) * r, 0, sin(theta) * r)

			var slot := Node3D.new()
			slot.position = pos
			slot.rotation.y = rng.randf() * TAU
			var s: float = rng.randf_range(0.9, 1.2)
			slot.scale = Vector3.ONE * s
			_level2_node.add_child(slot)

			var real_mesh: Node3D = _cached_models[_current_asset].duplicate()
			real_mesh.name = "RealMesh"
			real_mesh.visible = not _is_impostor
			slot.add_child(real_mesh)

			var card: MeshInstance3D = _atlas.create_card(_current_asset, _quality)
			card.name = "ImpostorCard"
			card.visible = _is_impostor
			slot.add_child(card)

	if _tinted:
		_apply_tint()


func _set_impostor_mode(enabled: bool) -> void:
	_is_impostor = enabled
	for slot: Node in _level2_node.get_children():
		if slot is Node3D:
			var real_node := slot.get_node_or_null("RealMesh")
			var card_node := slot.get_node_or_null("ImpostorCard")
			if real_node is Node3D:
				real_node.visible = not _is_impostor
			if card_node is Node3D:
				card_node.visible = _is_impostor


func _toggle_impostor() -> void:
	_set_impostor_mode(not _is_impostor)


func _set_wave_metric(idx: int) -> void:
	_current_metric = idx
	for i in _metric_buttons.size():
		var btn: Button = _metric_buttons[i]
		_square_button(btn, Color(1, 1, 1, 0.16) if i == _current_metric else Color(0, 0, 0, 0.3))
	_wave_red.clear()
	_wave_blue.clear()
	if _wave_canvas != null:
		_wave_canvas.queue_redraw()


func _square_button(btn: Button, bg: Color) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(0)
		sb.set_border_width_all(0)
		btn.add_theme_stylebox_override(state, sb)


func _get_sample_value(for_impostor: bool, metric: int) -> float:
	var count_mul: int = _spawn_count if _current_level == 2 else 1
	var live_count: int = count_mul

	if for_impostor == _is_impostor:
		match metric:
			0: return _smooth_gpu_ms
			1: return float(Engine.get_frames_per_second())
			2: return Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
			3: return _smooth_cpu_ms
			4: return float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			5:
				var tris: int = (2 * live_count) if for_impostor else (ASSET_TRIS[_current_asset] * live_count)
				return float(tris) / 1000.0
			6:
				var gpu_n: float = clampf(_smooth_gpu_ms / 33.3, 0.0, 1.0)
				var cpu_n: float = clampf(_smooth_cpu_ms / 16.6, 0.0, 1.0)
				var vram_n: float = clampf((Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0) / VRAM_BUDGET_MB, 0.0, 1.0)
				var tris_n: float = clampf(float((2 * live_count) if for_impostor else (ASSET_TRIS[_current_asset] * live_count)) / 10000000.0, 0.0, 1.0)
				return ((gpu_n * 0.45) + (cpu_n * 0.2) + (vram_n * 0.15) + (tris_n * 0.2)) * 100.0
	else:
		if for_impostor:
			match metric:
				0: return _snap_impostor.gpu_ms if _snap_impostor.fps > 0 else maxf(0.8 + float(live_count) * 0.001, 1.2)
				1: return float(_snap_impostor.fps) if _snap_impostor.fps > 0 else clampf(float(Engine.get_frames_per_second()) * 3.5, 60.0, 300.0)
				2: return _snap_impostor.vram if _snap_impostor.fps > 0 else (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0) * 0.88
				3: return _snap_impostor.cpu_ms if _snap_impostor.fps > 0 else maxf(_smooth_cpu_ms * 0.55, 1.0)
				4: return float(_snap_impostor.draws) if _snap_impostor.fps > 0 else float(mini(12 + live_count / 100, 30))
				5: return float(2 * live_count) / 1000.0
				6: return 8.0 + float(live_count) * 0.002
		else:
			match metric:
				0: return _snap_real.gpu_ms if _snap_real.fps > 0 else maxf(_smooth_gpu_ms * 6.0, 16.0)
				1: return float(_snap_real.fps) if _snap_real.fps > 0 else clampf(float(Engine.get_frames_per_second()) * 0.25, 5.0, 60.0)
				2: return _snap_real.vram if _snap_real.fps > 0 else (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0) * 1.15
				3: return _snap_real.cpu_ms if _snap_real.fps > 0 else _smooth_cpu_ms * 1.8
				4: return float(_snap_real.draws) if _snap_real.fps > 0 else float(live_count + 5)
				5: return float(ASSET_TRIS[_current_asset] * live_count) / 1000.0
				6: return clampf(float(ASSET_TRIS[_current_asset] * live_count) / 80000.0 * 10.0 + 35.0, 30.0, 100.0)
	return 0.0


func _get_metric_max(metric: int) -> float:
	match metric:
		0:
			var peak_gpu: float = maxf(_snap_real.gpu_ms, _smooth_gpu_ms)
			return maxf(peak_gpu * 1.3, 33.3)
		1:
			return maxf(float(Engine.get_frames_per_second()) * 1.3, 150.0)
		2:
			return VRAM_BUDGET_MB
		3:
			var peak_cpu: float = maxf(_snap_real.cpu_ms, _smooth_cpu_ms)
			return maxf(peak_cpu * 1.3, 16.6)
		4:
			var peak_draws: float = maxf(float(_snap_real.draws), float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
			return maxf(peak_draws * 1.25, 200.0)
		5:
			var max_k: float = float(ASSET_TRIS[_current_asset] * (_spawn_count if _current_level == 2 else 1)) / 1000.0
			return maxf(max_k * 1.25, 50.0)
		6:
			return 100.0
	return 100.0


func _format_metric_val(metric: int, val: float) -> String:
	match metric:
		0, 3: return "%.0fms" % val
		1: return "%.0f" % val
		2: return "%.0fM" % val
		4: return "%.0f" % val
		5: return "%.0fK" % val
		6: return "%.0f%%" % val
	return "%.0f" % val


func _draw_wave_canvas() -> void:
	if _wave_canvas == null:
		return
	var w: float = _wave_canvas.size.x
	var h: float = _wave_canvas.size.y
	if w <= 20.0 or h <= 20.0:
		return

	_wave_canvas.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.5), true)
	_wave_canvas.draw_rect(Rect2(0, 0, w, h), Color(0.18, 0.22, 0.28), false, 1.0)

	var left_pad: float = 40.0
	var right_pad: float = 8.0
	var top_pad: float = 12.0
	var bot_pad: float = 10.0
	var plot_w: float = w - left_pad - right_pad
	var plot_h: float = h - top_pad - bot_pad

	var min_val: float = 0.0
	var max_val: float = _get_metric_max(_current_metric)

	for step in 3:
		var frac: float = float(step + 1) / 3.0
		var gy: float = top_pad + plot_h * (1.0 - frac)
		_wave_canvas.draw_line(Vector2(left_pad, gy), Vector2(w - right_pad, gy), Color(0.12, 0.15, 0.20, 0.8), 1.0)
		var val_mark: float = min_val + (max_val - min_val) * frac
		var mark_str: String = _format_metric_val(_current_metric, val_mark)
		_wave_canvas.draw_string(ThemeDB.fallback_font, Vector2(2, gy + 3), mark_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.40, 0.48, 0.58))

	_wave_canvas.draw_line(Vector2(left_pad, top_pad + plot_h), Vector2(w - right_pad, top_pad + plot_h), Color(0.18, 0.22, 0.28), 1.0)
	_wave_canvas.draw_string(ThemeDB.fallback_font, Vector2(2, top_pad + plot_h + 3), _format_metric_val(_current_metric, 0.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.40, 0.48, 0.58))

	var count: int = _wave_red.size()
	if count < 2:
		return

	var red_pts := PackedVector2Array()
	var blue_pts := PackedVector2Array()
	red_pts.resize(count)
	blue_pts.resize(count)

	var denom: float = maxf(max_val - min_val, 0.001)

	for i in count:
		var px: float = left_pad + (float(i) / float(count - 1)) * plot_w
		var r_norm: float = clampf((_wave_red[i] - min_val) / denom, 0.0, 1.0)
		var b_norm: float = clampf((_wave_blue[i] - min_val) / denom, 0.0, 1.0)
		var ry: float = top_pad + plot_h * (1.0 - r_norm)
		var by: float = top_pad + plot_h * (1.0 - b_norm)
		red_pts[i] = Vector2(px, ry)
		blue_pts[i] = Vector2(px, by)

	var red_poly := PackedVector2Array()
	red_poly.append(Vector2(left_pad, top_pad + plot_h))
	for p in red_pts:
		red_poly.append(p)
	red_poly.append(Vector2(left_pad + plot_w, top_pad + plot_h))
	_wave_canvas.draw_colored_polygon(red_poly, Color(1.0, 0.25, 0.25, 0.07))

	var blue_poly := PackedVector2Array()
	blue_poly.append(Vector2(left_pad, top_pad + plot_h))
	for p in blue_pts:
		blue_poly.append(p)
	blue_poly.append(Vector2(left_pad + plot_w, top_pad + plot_h))
	_wave_canvas.draw_colored_polygon(blue_poly, Color(0.2, 0.75, 1.0, 0.10))

	_wave_canvas.draw_polyline(red_pts, Color(1.0, 0.28, 0.28), 2.0, true)
	_wave_canvas.draw_polyline(blue_pts, Color(0.22, 0.78, 1.0), 2.0, true)


func _draw_vram_bar() -> void:
	if _vram_bar_canvas == null:
		return
	var w: float = _vram_bar_canvas.size.x
	var h: float = _vram_bar_canvas.size.y
	if w <= 10.0 or h <= 4.0:
		return

	_vram_bar_canvas.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.5), true)

	var tex_mb: float = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	var buf_mb: float = Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0
	var tot_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var oth_mb: float = maxf(tot_mb - tex_mb - buf_mb, 0.0)

	var tex_w: float = clampf((tex_mb / VRAM_BUDGET_MB) * w, 0.0, w)
	var buf_w: float = clampf((buf_mb / VRAM_BUDGET_MB) * w, 0.0, maxf(w - tex_w, 0.0))
	var oth_w: float = clampf((oth_mb / VRAM_BUDGET_MB) * w, 0.0, maxf(w - tex_w - buf_w, 0.0))

	var cur_x: float = 0.0
	if tex_w > 0.5:
		_vram_bar_canvas.draw_rect(Rect2(cur_x, 0, tex_w, h), Color(0.9, 0.9, 0.9, 0.9), true)
		cur_x += tex_w
	if buf_w > 0.5:
		_vram_bar_canvas.draw_rect(Rect2(cur_x, 0, buf_w, h), Color(0.6, 0.6, 0.6, 0.9), true)
		cur_x += buf_w
	if oth_w > 0.5:
		_vram_bar_canvas.draw_rect(Rect2(cur_x, 0, oth_w, h), Color(0.35, 0.35, 0.35, 0.9), true)
		cur_x += oth_w

	for i in range(1, 4):
		var mx: float = (float(i) * 0.25) * w
		_vram_bar_canvas.draw_line(Vector2(mx, 0), Vector2(mx, h), Color(0.3, 0.38, 0.48, 0.7), 1.0)


func _update_hud() -> void:
	var rid: RID = get_viewport().get_viewport_rid()
	var raw_gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var raw_cpu: float = RenderingServer.viewport_get_measured_render_time_cpu(rid)
	var fps: int = Engine.get_frames_per_second()
	var draws: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var vram_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0

	_smooth_gpu_ms = lerpf(_smooth_gpu_ms, raw_gpu, 0.15)
	_smooth_cpu_ms = lerpf(_smooth_cpu_ms, raw_cpu, 0.15)

	var count_mul: int = _spawn_count if _current_level == 2 else 1
	var total_real_tris: int = ASSET_TRIS[_current_asset] * count_mul
	var total_imp_tris: int = 2 * count_mul

	if not _is_impostor:
		_snap_real.fps = fps
		_snap_real.gpu_ms = _smooth_gpu_ms
		_snap_real.cpu_ms = _smooth_cpu_ms
		_snap_real.tris = total_real_tris
		_snap_real.draws = draws
		_snap_real.vram = vram_mb
		_snap_real.count = count_mul
	else:
		_snap_impostor.fps = fps
		_snap_impostor.gpu_ms = _smooth_gpu_ms
		_snap_impostor.cpu_ms = _smooth_cpu_ms
		_snap_impostor.tris = total_imp_tris
		_snap_impostor.draws = draws
		_snap_impostor.vram = vram_mb
		_snap_impostor.count = count_mul

	_real_stats_rt.text = _stats_text("ORIGINAL (REAL MESH)", _snap_real)
	_imp_stats_rt.text = _stats_text("OCTAHEDRAL IMPOSTOR", _snap_impostor)
	_diff_stats_rt.text = _diff_text()

	if _wave_title_rt != null:
		_wave_title_rt.text = "[b]WAVE MONITOR[/b] (%s Props)  •  [color=#ff4444]■ REAL[/color]  vs  [color=#33b5ff]■ IMPOSTOR[/color]" % String.num_int64(count_mul)

	if _wave_val_label != null:
		var r_curr: float = _wave_red[-1] if not _wave_red.is_empty() else 0.0
		var b_curr: float = _wave_blue[-1] if not _wave_blue.is_empty() else 0.0
		_wave_val_label.text = "[color=#ff4444]R: %s[/color] | [color=#33b5ff]B: %s[/color]" % [
			_format_metric_val(_current_metric, r_curr),
			_format_metric_val(_current_metric, b_curr)
		]

	if _analytics_panel != null:
		var adapter_name: String = RenderingServer.get_video_adapter_name()
		if adapter_name.is_empty():
			adapter_name = "Forward+ Hardware"
		var api_ver: String = RenderingServer.get_video_adapter_api_version()
		if api_ver.is_empty():
			api_ver = "Vulkan 1.3"

		_analytics_gpu_rt.text = "GPU: %s  •  API: %s" % [
			adapter_name, api_ver
		]

		var cur_mode: String = "[color=#33b5ff]OCTA IMPOSTOR[/color]" if _is_impostor else "[color=#ff4444]REAL 3D MESH[/color]"
		var diag_status: String
		if _is_impostor:
			diag_status = "OPTIMIZED (Fillrate/Geom Unconstrained)"
		elif _smooth_gpu_ms >= 20.0 or _smooth_gpu_ms > _smooth_cpu_ms * 2.0:
			diag_status = "GPU FILL / GEOMETRY BOUND"
		elif draws >= 1200 or _smooth_cpu_ms > _smooth_gpu_ms * 1.5:
			diag_status = "CPU DRAW-CALL BOUND"
		else:
			diag_status = "BALANCED PIPELINE"

		var mtris_sec: float = (float(total_imp_tris if _is_impostor else total_real_tris) * float(fps)) / 1000000.0
		_analytics_diag_rt.text = "Mode: %s  •  Pipeline: %s\nThroughput: %.2f MTris/s  •  Draws: %d" % [
			cur_mode, diag_status, mtris_sec, draws
		]

		var p99_ms: float = 0.0
		var jitter_ms: float = 0.0
		if _frame_times.size() > 5:
			var sorted_times: Array[float] = _frame_times.duplicate()
			sorted_times.sort()
			var p99_idx: int = clampi(int(float(sorted_times.size()) * 0.99), 0, sorted_times.size() - 1)
			p99_ms = sorted_times[p99_idx]

			var avg_ms: float = 0.0
			for t in _frame_times:
				avg_ms += t
			avg_ms /= float(_frame_times.size())

			var variance: float = 0.0
			for t in _frame_times:
				var d_val: float = t - avg_ms
				variance += d_val * d_val
			jitter_ms = sqrt(variance / float(_frame_times.size()))

		var frame_ms: float = 1000.0 / float(maxi(fps, 1))
		_analytics_lat_rt.text = "Frame Time: %.1f ms  •  99th%% (p99): %.1f ms  •  Jitter: %.2f ms" % [
			frame_ms, p99_ms, jitter_ms
		]

		var tex_mb: float = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
		var buf_mb: float = Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0
		var tot_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
		var oth_mb: float = maxf(tot_mb - tex_mb - buf_mb, 0.0)
		var tot_pct: float = clampf((tot_mb / VRAM_BUDGET_MB) * 100.0, 0.0, 100.0)

		_vram_info_rt.text = "■ Tex: %.1f MB  ■ Buf: %.1f MB  ■ Other: %.1f MB\nTotal: %.1f MB / %.0f MB (%.1f%%)" % [
			tex_mb, buf_mb, oth_mb, tot_mb, VRAM_BUDGET_MB, tot_pct
		]

		if _vram_bar_canvas != null and _ui_visible and _analytics_visible:
			_vram_bar_canvas.queue_redraw()

	if _is_impostor:
		_summary_label.text = "Press [F] to Hot-Swap to Real Mesh  •  [B] Auto-Benchmark  •  [G] Wave Metric"
	else:
		_summary_label.text = "Press [F] to Hot-Swap to Impostor  •  [B] Auto-Benchmark  •  [G] Wave Metric"

	_help_rt.text = """[F] HOT-SWAP  •  [B] AUTO-BENCHMARK  •  [G] WAVE  •  [A] ANALYTICS  •  [H] TOGGLE UI  •  [L] LEVEL
[b]Props (%s):[/b] [+] / [-] (one at a time)  •  [b]Asset:[/b] [1] Rock [2] Tree [3] Rings
[b]Quality:[/b] [F1] Low [F2] Med [F3] High  •  [b]Camera:[/b] [Space] Orbit | Drag | Wheel  •  [T] Tint  •  [Esc] Exit""" % String.num_int64(_spawn_count if _current_level == 2 else 1)


func _process(delta: float) -> void:
	if _auto_orbit:
		_yaw += delta * 0.28
		_update_camera()

	_frame_times.append(delta * 1000.0)
	if _frame_times.size() > 75:
		_frame_times.pop_front()

	if _benchmark_done_timer > 0.0:
		_benchmark_done_timer -= delta

	_wave_sample_timer += delta
	if _wave_sample_timer >= 0.04:
		_wave_sample_timer = 0.0
		var r_sample: float = _get_sample_value(false, _current_metric)
		var b_sample: float = _get_sample_value(true, _current_metric)
		_wave_red.append(r_sample)
		_wave_blue.append(b_sample)
		if _wave_red.size() > 75:
			_wave_red.pop_front()
		if _wave_blue.size() > 75:
			_wave_blue.pop_front()
		if _wave_canvas != null and _ui_visible:
			_wave_canvas.queue_redraw()

	if _simulating_benchmark:
		var rid: RID = get_viewport().get_viewport_rid()
		var current_fps: int = Engine.get_frames_per_second()
		var raw_gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(rid)
		var draws: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var vram_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
		var crash: String = _crash_reason(raw_gpu, delta, vram_mb, draws) if _benchmark_stage < 2 else ""

		if _benchmark_stage == 0:
			if crash != "":
				_start_impostor_stage()
			else:
				_sim_timer += delta
				if _sim_timer >= 0.12:
					_sim_timer = 0.0
					if current_fps <= int(_target_fps_sim) or _spawn_count >= 5000:
						_benchmark_stage = 1
						_stabilize_timer = 0.0
					else:
						_spawn_count = mini(_spawn_count + maxi(int(_spawn_count * 0.05), 1), 5000)
						_build_level_2()
		elif _benchmark_stage == 1:
			if crash != "":
				_start_impostor_stage()
			elif current_fps <= int(_target_fps_sim + 2.0) or _spawn_count >= 5000:
				_stabilize_timer += delta
				if _stabilize_timer >= 5.0:
					_start_impostor_stage()
			else:
				_stabilize_timer = 0.0
				_benchmark_stage = 0
		else:
			_stabilize_timer += delta
			if _stabilize_timer >= 10.0:
				_simulating_benchmark = false
				_benchmark_stage = 0
				_benchmark_done_timer = 0.0

	_update_hud()


func _start_impostor_stage() -> void:
	_benchmark_stage = 2
	_stabilize_timer = 0.0
	_set_impostor_mode(true)


func _crash_reason(raw_gpu: float, delta: float, vram_mb: float, draws: int) -> String:
	if raw_gpu >= 50.0 or _smooth_gpu_ms >= 45.0:
		return "gpu"
	if delta >= 0.14:
		return "stall"
	if vram_mb >= 1600.0:
		return "vram"
	if draws >= 4000:
		return "draws"
	if ASSET_TRIS[_current_asset] * _spawn_count >= 100000000:
		return "tris"
	return ""


func _stats_text(title: String, snap: Dictionary) -> String:
	if snap.fps <= 0:
		return "[b]%s[/b]\nSpawned Props: --\nFPS: --\nGPU Time: --\nCPU Time: --\nTriangles: --\nDraw Calls: --\nVRAM: --" % title
	return "[b]%s[/b]\nSpawned Props: %s\nFPS: %d\nGPU Time: %.2f ms\nCPU Time: %.2f ms\nTriangles: %s\nDraw Calls: %d\nVRAM: %.1f MB (%.1f%%)" % [
		title, String.num_int64(snap.count), snap.fps, snap.gpu_ms, snap.cpu_ms,
		String.num_int64(snap.tris), snap.draws, snap.vram, clampf(snap.vram / VRAM_BUDGET_MB * 100.0, 0.0, 100.0)]


func _diff_text() -> String:
	var r: Dictionary = _snap_real
	var i: Dictionary = _snap_impostor
	if r.fps <= 0 or i.fps <= 0:
		return "[b]DIFFERENCE (%)[/b]\nSpawned Props: --\nFPS: --\nGPU Time: --\nCPU Time: --\nTriangles: --\nDraw Calls: --\nVRAM: --"
	return "[b]DIFFERENCE (%%)[/b]\nSpawned Props: %s\nFPS: %s\nGPU Time: %s\nCPU Time: %s\nTriangles: %s\nDraw Calls: %s\nVRAM: %s" % [
		_pct(i.count, r.count, true), _pct(i.fps, r.fps, true), _pct(i.gpu_ms, r.gpu_ms, false), _pct(i.cpu_ms, r.cpu_ms, false),
		_pct(i.tris, r.tris, false), _pct(i.draws, r.draws, false), _pct(i.vram, r.vram, false)]


func _pct(a: float, b: float, higher_better: bool) -> String:
	var d: float = (a - b) / maxf(absf(b), 0.0001) * 100.0
	var txt: String = "%+.1f%%" % d
	if absf(d) < 0.05:
		return txt
	var good: bool = (d > 0.0) == higher_better
	return "[color=%s]%s[/color]" % ["#44ff66" if good else "#ff4444", txt]
	_update_hud()


func _update_camera() -> void:
	_cam_pivot.rotation = Vector3(_pitch, _yaw, 0)
	_cam.position = Vector3(0, 0, _cam_dist)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_yaw -= event.relative.x * 0.005
			_pitch = clampf(_pitch - event.relative.y * 0.005, -0.9, 0.8)
			_update_camera()

	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = clampf(_cam_dist - 2.0, 3.0, 180.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = clampf(_cam_dist + 2.0, 3.0, 180.0)
			_update_camera()

	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F, KEY_ENTER:
				if _current_level == 2 and not _simulating_benchmark:
					_toggle_impostor()
			KEY_B:
				if _current_level == 2 and not _simulating_benchmark:
					_simulating_benchmark = true
					_set_impostor_mode(false)
					_spawn_count = 1
					_sim_timer = 0.0
					_stabilize_timer = 0.0
					_benchmark_stage = 0
					_benchmark_done_timer = 0.0
					_emergency_switch_msg = ""
					_reset_snapshots()
					_build_level_2()

					var start_fps: int = Engine.get_frames_per_second()
					if start_fps < 30:
						_target_fps_sim = 10.0
					else:
						_target_fps_sim = 30.0
			KEY_G:
				_set_wave_metric((_current_metric + 1) % METRIC_NAMES.size())
			KEY_M, KEY_L:
				if not _simulating_benchmark:
					_current_level = 1 if _current_level == 2 else 2
					_switch_asset(_current_asset)
			KEY_1:
				if not _simulating_benchmark:
					_switch_asset(0)
			KEY_2:
				if not _simulating_benchmark:
					_switch_asset(1)
			KEY_3:
				if not _simulating_benchmark:
					_switch_asset(2)
			KEY_F1:
				if not _simulating_benchmark:
					_quality = OctaAtlas.Quality.LOW
					_apply_quality()
			KEY_F2:
				if not _simulating_benchmark:
					_quality = OctaAtlas.Quality.MEDIUM
					_apply_quality()
			KEY_F3:
				if not _simulating_benchmark:
					_quality = OctaAtlas.Quality.HIGH
					_apply_quality()
			KEY_EQUAL, KEY_KP_ADD:
				if _current_level == 2 and not _simulating_benchmark:
					var step: int = 1
					_spawn_count = mini(_spawn_count + step, 5000)
					if _is_impostor:
						_snap_real.fps = 0
					else:
						_snap_impostor.fps = 0
					_build_level_2()
			KEY_MINUS, KEY_KP_SUBTRACT:
				if _current_level == 2 and not _simulating_benchmark:
					var step: int = 1
					_spawn_count = maxi(_spawn_count - step, 1)
					if _is_impostor:
						_snap_real.fps = 0
					else:
						_snap_impostor.fps = 0
					_build_level_2()
			KEY_T:
				_tinted = not _tinted
				_apply_tint()
			KEY_SPACE:
				_auto_orbit = not _auto_orbit
			KEY_A:
				_analytics_visible = not _analytics_visible
				if _analytics_panel != null:
					_analytics_panel.visible = _analytics_visible and _ui_visible
			KEY_H, KEY_TAB:
				_ui_visible = not _ui_visible
				_hud.visible = _ui_visible
				_left_label.visible = _ui_visible and _current_level == 1
				_right_label.visible = _ui_visible and _current_level == 1
				if _analytics_panel != null:
					_analytics_panel.visible = _ui_visible and _analytics_visible
			KEY_ESCAPE:
				get_tree().quit()


func _apply_quality() -> void:
	for c in _level2_node.get_children():
		c.queue_free()
	if _current_level == 1:
		_build_level_1()
	else:
		_build_level_2()


func _apply_tint() -> void:
	var col := Color(1.0, 0.25, 0.25) if _tinted else Color.WHITE
	for q in 3:
		_atlas.get_material(q).set_shader_parameter("tint", col)
