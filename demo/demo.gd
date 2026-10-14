extends Node3D

const COUNT := 400
const FIELD := 260.0
const LOD_DISTANCE := 40.0

var _atlas: OctaAtlas
var _cards: Array[MeshInstance3D] = []
var _quality := 2
var _tinted := false
var _impostors_on := true
var _cam: Camera3D
var _label: Label
var _look := Vector2(-0.15, 0.0)


# --- Bake and spawn ---
func _ready() -> void:
	_build_world()
	_label.text = "Baking impostors... (a few seconds)"
	var sources := DemoObjects.all()
	_atlas = await OctaBaker.bake(sources, self)
	for s: Node in sources:
		s.free()
	if _atlas == null:
		_label.text = "Bake failed - see the Output panel."
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in COUNT:
		var kind := rng.randi_range(0, 2)
		var obj: Node3D = [DemoObjects.rock(rng.randi_range(1, 3)), DemoObjects.tree(), DemoObjects.rings()][kind]
		obj.position = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * FIELD * 0.5
		obj.rotation.y = rng.randf() * TAU
		obj.scale = Vector3.ONE * rng.randf_range(0.8, 1.6)
		add_child(obj)
		_cards.append(OctaLOD.attach_card(obj, _atlas, kind, OctaLOD.Mode.DYNAMIC_LOD, LOD_DISTANCE, _quality))


# --- Scene ---
func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * FIELD * 1.4
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.42, 0.30)
	ground.material_override = gm
	add_child(ground)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 3, 30)
	_cam.far = 1000.0
	add_child(_cam)
	var ui := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(12, 10)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	ui.add_child(_label)
	add_child(ui)


# --- Controls ---
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_look += Vector2(-event.relative.y, -event.relative.x) * 0.004
		_look.x = clampf(_look.x, -1.4, 1.4)
	if not (event is InputEventKey and event.pressed and not event.echo) or _atlas == null:
		return
	match event.keycode:
		KEY_T:
			_tinted = not _tinted
			for q in 3:
				_atlas.get_material(q).set_shader_parameter("tint", Color(1, 0.2, 0.2) if _tinted else Color.WHITE)
		KEY_F:
			_impostors_on = not _impostors_on
			for c in _cards:
				c.visibility_range_begin = LOD_DISTANCE if _impostors_on else 100000.0
		KEY_1, KEY_2, KEY_3:
			_quality = event.keycode - KEY_1
			for c in _cards:
				c.material_override = _atlas.get_material(_quality)
		KEY_ESCAPE:
			get_tree().quit()


# --- Camera and HUD ---
func _process(delta: float) -> void:
	_cam.rotation = Vector3(_look.x, _look.y, 0)
	var dir := Vector3.ZERO
	dir.x = float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	dir.z = float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	dir.y = float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q))
	var speed := 30.0 if Input.is_key_pressed(KEY_SHIFT) else 8.0
	_cam.position += _cam.basis * dir * speed * delta
	_cam.position.y = maxf(_cam.position.y, 0.5)
	if _atlas == null:
		return
	_label.text = "\n".join([
		"FPS %d   |   triangles drawn: %s   |   draw calls: %d" % [Engine.get_frames_per_second(),
			_millions(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)],
		"%d objects, real mesh closer than %d m, impostor beyond" % [COUNT, LOD_DISTANCE],
		"",
		"Hold right mouse + move: look    W A S D: move    Q / E: down / up    Shift: fast",
		"T: paint impostors red (%s)    F: impostors %s    1 / 2 / 3: quality Low / Medium / High (now %s)" % [
			"on" if _tinted else "off", "ON" if _impostors_on else "OFF - all real meshes, heavy", ["Low", "Medium", "High"][_quality]],
		"Esc: quit",
	])


func _millions(n: float) -> String:
	return "%.1f million" % (n / 1e6) if n >= 1e6 else "%d thousand" % (n / 1e3)
