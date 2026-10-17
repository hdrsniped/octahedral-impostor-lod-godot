extends SceneTree

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _wasted(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.r > 0.4 and c.b > 0.4 and c.g < 0.15:
				n += 1
	return n


func _neutral(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.r > 0.3 and absf(c.r - c.g) < 0.03 and absf(c.r - c.b) < 0.03:
				n += 1
	return n


# --- Overdraw view and card coverage ---
func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0, 5), Vector3.ZERO)
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 64
	sphere.rings = 32
	ball.mesh = sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.3, 0.2)
	ball.mesh.material = m
	vp.add_child(ball)
	var s := OctaBakeSettings.new()
	s.max_atlas_size = 1024
	var atlas := await OctaLOD.generate([ball], vp, s)
	ball.visible = false
	var card: OctaImpostor = OctaLOD.find_cards(ball)[0]
	card.visibility_range_begin = 0.0

	var counts := {}
	var covered := 0
	for mode in [OctaDebug.Mode.OFF, OctaDebug.Mode.OVERDRAW, OctaDebug.Mode.OFF]:
		OctaDebug.set_mode(mode)
		for i in 4:
			await RenderingServer.frame_post_draw
		counts[counts.size()] = _wasted(vp.get_texture().get_image())
		var center := vp.get_texture().get_image().get_pixel(128, 128)
		print("OVERDRAW mode %s: wasted-colour pixels %d, centre %s" % [OctaDebug.mode_names()[mode], counts[counts.size() - 1], center])
		if mode == OctaDebug.Mode.OVERDRAW:
			covered = _neutral(vp.get_texture().get_image())
			_check(not (center.r > 0.4 and center.b > 0.4 and center.g < 0.15), "covered pixels keep the neutral tint (centre %s)" % center)
	_check(counts[0] == 0, "mode OFF shows no wasted-colour pixels")
	_check(counts[1] > 100, "mode OVERDRAW shows wasted-colour pixels around the ball (%d)" % counts[1])
	_check(absf(float(counts[1]) / (counts[1] + covered) - (1.0 - PI / 4.0)) < 0.08, "wasted share of the card is about 1 - pi/4 (%d wasted, %d covered)" % [counts[1], covered])
	_check(counts[2] == 0, "back to OFF removes them again")

	var c := atlas.card_coverage(0)
	print("COVERAGE ball: union %.3f, mean view %.3f, rect %.3f, hull %.3f, 8-gon %.3f, 6-gon %.3f" % [c.union, c.mean_view, c.rect, c.hull, c.poly8, c.poly6])
	var disc := PI / 4.0
	_check(absf(c.mean_view - disc) < 0.06, "ball: mean covered fraction about pi/4 (%.3f)" % c.mean_view)
	_check(absf(c.union - disc) < 0.06, "ball: union about pi/4 (%.3f)" % c.union)
	_check(c.hull >= c.union - 1e-4 and c.hull <= 1.0 + 1e-4, "ball: hull holds the union and fits the quad")
	_check(c.poly8 >= c.union - 1e-4 and c.poly8 <= 1.0 + 1e-4, "ball: 8-gon holds the union and fits the quad (%.3f)" % c.poly8)
	_check(c.poly6 >= c.poly8 - 1e-4 and c.poly6 <= 1.0 + 1e-4, "ball: 6-gon is no smaller than the 8-gon (%.3f)" % c.poly6)
	_check(c.rect >= c.union and c.rect <= 1.0 + 1e-4 and c.rect > 0.9, "ball: tight rectangle is nearly the whole quad (%.3f)" % c.rect)
	_check(c.poly8 >= c.hull - 1e-4, "ball: simplified 8-gon is no smaller than the hull")

	var hud := OctaDebugHUD.new()
	vp.add_child(hud)
	cam.current = true
	var st := hud.scan()
	var fill: float = st.card_fill.values()[0] if not st.card_fill.is_empty() else -1.0
	print("HUD card fill %.1f%%" % fill)
	_check(fill > 60.0 and fill < 90.0, "HUD reports card fill near pi/4 (%.1f%%)" % fill)
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	for n in root.get_children():
		n.queue_free()
	await process_frame
	quit(1 if _fails else 0)
