extends SceneTree

class ErrorCatcher extends Logger:
	var errors: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != Logger.ERROR_TYPE_WARNING and not file.contains("wasapi"):
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])


const LOAD_TIMEOUT_MS := 90000
const DRAW_TIMEOUT_MS := 30000

var _fails := 0
var _catcher := ErrorCatcher.new()
var _scene: Node
var _shots := ""


func _initialize() -> void:
	OS.add_logger(_catcher)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wake() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		print("NOTE window was minimized, restoring it")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _drawn() -> void:
	var done := [false]
	var mark := func() -> void: done[0] = true
	RenderingServer.frame_post_draw.connect(mark, CONNECT_ONE_SHOT)
	var t0 := Time.get_ticks_msec()
	while not done[0] and Time.get_ticks_msec() - t0 < DRAW_TIMEOUT_MS:
		await process_frame
		_wake()
	if not done[0]:
		RenderingServer.frame_post_draw.disconnect(mark)
		_check(false, "the window rendered a frame within %d s (it stopped drawing)" % [DRAW_TIMEOUT_MS / 1000])


func _key(k: Key, wait := 4) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(wait)


func _cards() -> Array:
	return _scene._slots().map(func(s: Node) -> Node: return s.get_child(1))


func _reals() -> Array:
	return _scene._slots().map(func(s: Node) -> Node: return s.get_child(0))


func _shot(name: String) -> void:
	await _frames(20)
	await _drawn()
	var img := root.get_viewport().get_texture().get_image()
	var path := _shots.path_join(name + ".png")
	_check(img.save_png(path) == OK and img.get_width() >= 1280, "screenshot %s (%dx%d)" % [path, img.get_width(), img.get_height()])


func _red_pixels() -> int:
	await _frames(20)
	await _drawn()
	var img := root.get_viewport().get_texture().get_image()
	var n := 0
	for y in range(380, 800, 3):
		for x in range(560, 1360, 3):
			var c := img.get_pixel(x, y)
			if c.r > 0.55 and c.g < 0.35 and c.b < 0.35:
				n += 1
	return n


func _layout() -> Array:
	return [_scene._help_rt.get_parent().get_parent().size, _scene._summary_label.get_parent().get_parent().get_parent().size, _scene._stat_rts[0].size]


func _shader_ok(card: Node) -> bool:
	var a: OctaAtlas = _scene._atlas
	return card.material_override.shader == OctaAtlas.shader_for(card.quality, a.write_depth, -1, a.precise_search, a.card_fade and not OctaLOD.fade_supported())


# --- Keys that exist on both levels ---
func _common(level: int) -> void:
	var tag := "L%d " % level
	var s := _scene
	var a: OctaAtlas = s._atlas
	var layout0 := _layout()
	for i in 4:
		await _key((KEY_1 + i) as Key)
		var slots: Array = s._slots()
		var want: int = 2 if level == 1 else s._spawn_count
		var idx_ok := _cards().all(func(c: Node) -> bool: return c.object_index == i)
		_check(s._current_asset == i and slots.size() == want and idx_ok and slots.all(func(n: Node) -> bool: return n.get_child_count() == 2), tag + "asset key %d builds %d slots" % [i + 1, want])
	for q in 4:
		await _key((KEY_F1 + q) as Key)
		_check(s._quality == q and _cards().all(func(c: Node) -> bool: return c.quality == q and _shader_ok(c)), tag + "quality F%d" % (q + 1))
	await _key(KEY_F3)

	var was: bool = s._is_impostor
	await _key(KEY_F)
	var left_card: bool = (_cards()[0] as Node3D).visible if level == 1 else true
	_check(s._is_impostor != was, tag + "hot-swap toggles the mode")
	if level == 2:
		_check(_reals().all(func(r: Node3D) -> bool: return r.visible != s._is_impostor) and _cards().all(func(c: Node3D) -> bool: return c.visible == s._is_impostor), tag + "hot-swap shows real or cards")
	else:
		_check(left_card == s._is_impostor and (_reals()[1] as Node3D).visible == s._is_impostor, tag + "hot-swap swaps the two sides")
	await _key(KEY_F)

	await _key(KEY_T)
	_check(s._tinted and a.get_material(s._quality).get_shader_parameter("tint") == Color(1.0, 0.25, 0.25), tag + "tint on")
	await _key(KEY_T)
	_check(not s._tinted and a.get_material(s._quality).get_shader_parameter("tint") == Color.WHITE, tag + "tint off")

	for i in 6:
		await _key(KEY_D)
		var m: int = (i + 1) % OctaDebug.Mode.size()
		var code: String = _cards()[0].material_override.shader.code
		_check(OctaDebug.mode == m and (m == 0 or code.contains("DEBUG_MODE %d" % m)) and _cards().all(func(c: Node) -> bool: return _shader_ok(c)), tag + "debug view %s" % OctaDebug.mode_names()[m])
		_check(level == 1 or _cards().all(func(c: Node3D) -> bool: return c.visible == s._is_impostor), tag + "debug view keeps cards drawn")
	await _key(KEY_F)
	await _key(KEY_F)

	await _key(KEY_F4)
	await _key(KEY_P)
	_check(a.precise_search and _cards()[0].material_override.shader.code.contains("PRECISE_SEARCH"), tag + "precise search on (Ultra)")
	await _key(KEY_F3)
	_check(a.precise_search and not _cards()[0].material_override.shader.code.contains("PRECISE_SEARCH") and _cards().all(func(c: Node) -> bool: return _shader_ok(c)), tag + "precise search ignored below Ultra")
	await _key(KEY_P)
	_check(not a.precise_search, tag + "precise search off")

	await _key(KEY_W)
	_check(not a.write_depth and _cards()[0].material_override.shader.code.contains("NO_DEPTH_WRITE"), tag + "write depth off")
	await _key(KEY_W)
	_check(a.write_depth and _cards().all(func(c: Node) -> bool: return _shader_ok(c)), tag + "write depth on")

	var sun: DirectionalLight3D = s._sun
	var shadows: bool = sun.shadow_enabled
	await _key(KEY_S)
	_check(sun.shadow_enabled != shadows, tag + "sun shadows toggle")
	await _key(KEY_S)
	var views: int = a.shadow_views
	for i in 3:
		await _key(KEY_V)
		views = views % 3 + 1
		_check(a.shadow_views == views and a.get_material(s._quality).get_shader_parameter("shadow_views") == views, tag + "shadow views %d" % views)
	var yaw: float = sun.rotation.y
	await _key(KEY_R, 20)
	_check(s._sun_spin and not is_equal_approx(sun.rotation.y, yaw), tag + "sun spin rotates the light")
	await _key(KEY_R)
	var asset_before: int = s._current_asset
	await _key(KEY_2)
	await _key(KEY_K)
	_check(s._wind and _cards().all(func(c: OctaImpostor) -> bool: return is_equal_approx(c.wind_strength, s.WIND_STRENGTH)) and a.get_material(s._quality).shader.code.contains("CARD_WIND") and s._state_text(s._draws()).contains("Wind: ON"), tag + "wind key sways the tree cards (wind variant, HUD line)")
	await _key(KEY_K)
	_check(not s._wind and _cards().all(func(c: OctaImpostor) -> bool: return c.wind_strength == 0.0) and not a.wind_active() and not a.get_material(s._quality).shader.code.contains("CARD_WIND") and s._state_text(s._draws()).contains("Wind: OFF"), tag + "wind key off returns the normal shader")
	await _key(KEY_1 + asset_before)

	await _key(KEY_O, 8)
	var fade_ok: bool = _cards().all(func(c: OctaImpostor) -> bool: return c.fade == OctaLOD.Fade.CROSSFADE)
	_check(s._auto_lod and _cards().all(func(c: OctaImpostor) -> bool: return is_equal_approx(c.visibility_range_begin, s.LOD_DISTANCE) and c.visible) and fade_ok, tag + "auto LOD sets the visibility range on every card")
	_check(_reals().all(func(r: Node3D) -> bool: return r.visible and OctaLOD.geometry_below(r).all(func(g: GeometryInstance3D) -> bool: return not g.visibility_parent.is_empty())), tag + "auto LOD links the real meshes to their cards")
	var seen: Dictionary = s._scan_hud.scan()
	_check(seen.impostor_visible + seen.real_visible == s._slots().size(), tag + "HUD scan counts every card (%s)" % [seen])
	await _key(KEY_O, 8)
	_check(not s._auto_lod and _cards().all(func(c: OctaImpostor) -> bool: return c.visibility_range_begin == 0.0 and c.fade == OctaLOD.Fade.NONE), tag + "auto LOD off resets the cards")

	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	var dist: float = s._cam_dist
	Input.parse_input_event(wheel)
	await _frames(2)
	_check(s._cam_dist > dist, tag + "mouse wheel zooms")
	var metric: int = s._current_metric
	await _key(KEY_G)
	_check(s._current_metric == (metric + 1) % s.METRIC_NAMES.size(), tag + "wave metric G")
	await _key(KEY_A)
	_check(not s._analytics_panel.visible, tag + "analytics hidden")
	await _key(KEY_A)
	_check(s._analytics_panel.visible, tag + "analytics shown")
	await _key(KEY_H)
	_check(not s._hud.visible and not s._labels[0].visible, tag + "UI hidden")
	await _key(KEY_H)
	_check(s._hud.visible and s._labels[0].visible == (level == 1), tag + "UI shown")
	var orbit: bool = s._auto_orbit
	await _key(KEY_SPACE)
	_check(s._auto_orbit != orbit, tag + "orbit toggle")
	await _key(KEY_SPACE)
	var l: Array = _layout()
	_check(l == layout0, tag + "bottom bar and stats panel keep their size %s" % [l])
	if s._is_impostor:
		await _key(KEY_F)


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
	if _shots.is_empty():
		_shots = ProjectSettings.globalize_path("user://")
	DirAccess.make_dir_recursive_absolute(_shots)
	_scene = load("res://demo/showcase.tscn").instantiate()
	root.add_child(_scene)
	var s := _scene
	for k in [KEY_D, KEY_EQUAL, KEY_F4, KEY_B, KEY_J, KEY_O, KEY_T, KEY_A, KEY_H, KEY_G, KEY_P, KEY_S, KEY_L, KEY_C]:
		await _key(k, 1)
	_check(s._atlas == null and OctaDebug.mode == OctaDebug.Mode.OFF and s._spawn_count == 1 and not s._simulating_benchmark and not s._tinted and s._analytics_visible and s._ui_visible and s._current_level == 2, "keys pressed while loading are ignored")
	var n := 0
	var t_wait := Time.get_ticks_msec()
	while (s._loading_layer != null or s._atlas == null) and Time.get_ticks_msec() - t_wait < LOAD_TIMEOUT_MS:
		await process_frame
		n += 1
		_wake()
	var a: OctaAtlas = s._atlas
	if a == null or s._loading_layer != null:
		_check(false, "startup bake finished within %d s (atlas %s, loading screen %s, %d frames)" % [LOAD_TIMEOUT_MS / 1000, "missing" if a == null else "ready", "still shown" if s._loading_layer != null else "gone", n])
		print("RESULT FAIL (%d failures)" % _fails)
		quit(1)
		return
	_check(a.object_count() == 4 and a.orm != null and s._tris.all(func(t: int) -> bool: return t > 0), "startup bake: 4 objects incl. the textured ball (orm map %s, %d ms, %d frames)" % [a.orm != null, s._bake_ms, n])
	await _frames(20)
	_check(s._current_level == 2 and s._field.get_child_count() == 1 and s._level2_node.visible, "starts on Level 2")
	await _key(KEY_SPACE)

	await _common(2)

	await _key(KEY_EQUAL)
	await _key(KEY_EQUAL)
	await _key(KEY_KP_ADD)
	_check(s._spawn_count == 4 and s._field.get_child_count() == 4, "+ adds one prop per press")
	await _key(KEY_MINUS)
	_check(s._spawn_count == 3 and s._field.get_child_count() == 3, "- removes one prop per press")
	s._change_props(57)
	await _frames(5)
	_check(s._spawn_count == 60 and s._field.get_child_count() == 60, "60 props")

	await _key(KEY_F)
	s._hud.visible = false
	await _frames(40)
	var draws_cards: int = s._draws()
	var objects_cards: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	_check(s._is_impostor and s._join_node.get_child_count() == 0, "60 impostor cards, not joined (%d draw calls, %d objects)" % [draws_cards, objects_cards])
	var cpu_cards: float = s._smooth_cpu_ms
	await _key(KEY_J, 40)
	var joined_cards := 0
	var instances := 0
	for m: MultiMeshInstance3D in s._join_node.get_children():
		instances += m.multimesh.instance_count
	for c: Node3D in _cards():
		joined_cards += 0 if c.visible else 1
	_check(s._joined and s._join_node.get_child_count() >= 1 and instances == joined_cards and instances + _cards().filter(func(c: Node3D) -> bool: return c.visible).size() == 60, "join merges %d cards into %d MultiMesh groups" % [instances, s._join_node.get_child_count()])
	var objects_joined: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	_check(objects_joined < objects_cards, "join lowers the objects drawn (%d -> %d; draw calls %d -> %d, CPU %.2f -> %.2f ms)" % [objects_cards, objects_joined, draws_cards, s._draws(), cpu_cards, s._smooth_cpu_ms])
	s._hud.visible = true
	_check(s._join_base.x >= 0.0 and s._state_text(s._draws()).contains("was"), "join line shows the draw calls before")
	await _key(KEY_EQUAL)
	_check(s._joined and s._spawn_count == 61 and s._join_node.get_child_count() >= 1, "adding a prop keeps the join")
	await _key(KEY_O)
	_check(s._auto_lod and not s._joined and s._join_node.get_child_count() == 0, "auto LOD and join exclude each other")
	await _key(KEY_O)
	await _key(KEY_J)
	_check(s._joined and not s._auto_lod, "join back on")
	await _key(KEY_F)
	_check(not s._join_node.visible and _reals().all(func(r: Node3D) -> bool: return r.visible), "hot-swap to real hides the joined groups")
	await _key(KEY_F)
	await _key(KEY_J)
	_check(not s._joined and s._join_node.get_child_count() == 0 and _cards().all(func(c: Node3D) -> bool: return c.visible), "join off restores the cards")
	await _key(KEY_F)
	s._spawn_count = 1
	s._build_level_2()
	await _frames(5)

	await _key(KEY_F4)
	await _key(KEY_B, 1)
	_check(s._simulating_benchmark and s._spawn_count <= 3 and s._benchmark_stage == 0 and not s._is_impostor, "benchmark starts on real meshes %s" % [[s._simulating_benchmark, s._spawn_count, s._benchmark_stage, s._is_impostor]])
	var state := [s._quality, OctaDebug.mode, s._atlas.precise_search, s._atlas.write_depth, s._sun.shadow_enabled, s._atlas.shadow_views, s._current_asset]
	for k in [KEY_F1, KEY_D, KEY_P, KEY_W, KEY_S, KEY_V, KEY_2, KEY_O, KEY_J, KEY_L, KEY_EQUAL, KEY_F]:
		await _key(k, 1)
	_check(state == [s._quality, OctaDebug.mode, s._atlas.precise_search, s._atlas.write_depth, s._sun.shadow_enabled, s._atlas.shadow_views, s._current_asset] and not s._auto_lod and not s._joined and s._current_level == 2 and not s._is_impostor, "quality, debug, plugin toggles, asset, level and props are ignored during the benchmark")
	s._target_fps = 0
	var seen := {}
	for i in 90:
		await process_frame
		seen[s._benchmark_stage] = true
		if s._spawn_count > 2 or s._benchmark_stage != 0:
			break
	_check(s._spawn_count > 1 and s._benchmark_stage == 0, "stage 0 ramps real meshes (%d props)" % s._spawn_count)
	s._target_fps = 100000
	n = 0
	while s._benchmark_stage == 0 and n < 120:
		await process_frame
		n += 1
	_check(s._benchmark_stage == 1 and not s._is_impostor, "stage 1 stabilises the real meshes")
	var count: int = s._spawn_count
	s._stabilize_timer = 4.95
	n = 0
	while s._benchmark_stage == 1 and n < 120:
		await process_frame
		n += 1
	_check(s._benchmark_stage == 2 and s._is_impostor and s._spawn_count == count, "stage 2 switches to impostors at the same count (%d)" % count)
	s._stabilize_timer = 9.95
	n = 0
	while s._simulating_benchmark and n < 120:
		await process_frame
		n += 1
	_check(not s._simulating_benchmark and s._is_impostor, "benchmark finishes and keys work again")
	await _key(KEY_F)
	await _key(KEY_F)

	await _key(KEY_C, 30)
	var t_chunk := Time.get_ticks_msec()
	while (s._chunk_group == null or s._chunk_group.chunk_card() == null) and Time.get_ticks_msec() - t_chunk < 60000:
		await process_frame
	var cg: OctaImpostorGroup = s._chunk_group
	_check(cg != null and cg.chunk_card() != null and cg.chunk_atlas != null and is_equal_approx(cg.chunk_card().visibility_range_begin, s.CHUNK_DISTANCE), "C builds a chunk LOD group with a chunk card beyond %d m" % s.CHUNK_DISTANCE)
	_check(cg != null and cg.target_nodes().size() == s.CHUNK_PROPS and cg.cards().size() == s.CHUNK_PROPS + 1 and s._toast_label.text.contains("Chunk LOD") and s._state_text(s._draws()).contains("Chunk: %d props" % s.CHUNK_PROPS), "chunk group has %d object cards, one chunk card, a toast and a HUD row" % s.CHUNK_PROPS)
	await _key(KEY_C, 20)
	_check(s._chunk_group == null and not is_instance_valid(cg), "C again removes the chunk demo")

	await _key(KEY_L)
	_check(s._current_level == 1 and s._level1_node.visible and not s._level2_node.visible and s._field.get_child_count() == 0 and s._sides[0].get_child_count() == 2, "L switches to Level 1")
	var props: int = s._spawn_count
	for k in [KEY_EQUAL, KEY_MINUS, KEY_B, KEY_J]:
		await _key(k, 2)
	_check(s._spawn_count == props and not s._simulating_benchmark and not s._joined, "+, -, B and J are Level 2 only")
	await _common(1)
	await _key(KEY_L)
	_check(s._current_level == 2 and s._field.get_child_count() == s._spawn_count, "L returns to Level 2")
	await _key(KEY_L)

	await _key(KEY_F3)
	await _key(KEY_1)
	s._auto_orbit = false
	await _key(KEY_T)
	await _key(KEY_O, 30)
	var near := await _red_pixels()
	s._cam_dist = 25.0
	s._update_camera()
	var far := await _red_pixels()
	_check(far > 100 and near * 5 < far, "auto LOD swaps the real meshes for the (tinted) cards when the camera moves back (%d red pixels at 6.5 m, %d at 25 m)" % [near, far])
	await _shot("level1_auto_lod")
	await _key(KEY_T)
	await _key(KEY_O)
	s._cam_dist = 6.5
	s._update_camera()
	await _key(KEY_F, 40)
	await _key(KEY_F, 40)
	_check(s._snap_real.fps > 0, "the stats panel is measured on Level 1")
	await _shot("level1")
	await _key(KEY_L)
	s._spawn_count = 1
	s._change_props(23)
	await _frames(40)
	await _key(KEY_F, 50)
	await _shot("level2_stats")
	var diff: String = s._stat_rts[2].text
	_check(diff.contains("[color=#44ff66]") or diff.contains("[color=#ff4444]"), "difference column is coloured")
	await _key(KEY_J, 40)
	await _key(KEY_F4)
	await _key(KEY_P)
	await _key(KEY_D)
	await _key(KEY_D)
	await _key(KEY_D)
	await _shot("level2_join_ultra_debug")

	OctaDebug.set_mode(OctaDebug.Mode.OFF)
	s.queue_free()
	await _frames(3)
	_check(_catcher.errors.is_empty(), "no engine or script errors (%d)" % _catcher.errors.size())
	for e in _catcher.errors.slice(0, 8):
		print("ERROR ", e)
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails else 0)
