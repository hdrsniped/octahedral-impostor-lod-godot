extends SceneTree

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


# --- Debug views and HUD ---
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
	ball.mesh = SphereMesh.new()
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
	var off_shader: Shader = card.material_override.shader
	_check(off_shader == OctaAtlas.SHADERS[card.quality], "debug off keeps the plain shader (no extra variant)")

	var shots := {}
	for mode in OctaDebug.Mode.values():
		OctaDebug.set_mode(mode)
		for i in 4:
			await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		shots[mode] = img.get_pixel(128, 128)
		var want: Shader = OctaAtlas.SHADERS[card.quality] if mode == OctaDebug.Mode.OFF else OctaAtlas.shader_for(card.quality, true, mode)
		_check(card.material_override.shader == want and shots[mode].a > 0.99 and shots[mode] != Color.BLACK, "mode %s renders (%s)" % [OctaDebug.mode_names()[mode], shots[mode]])
	_check(shots[OctaDebug.Mode.TINT_BY_LOD] != shots[OctaDebug.Mode.OFF] and shots[OctaDebug.Mode.VIEW_INDEX] != shots[OctaDebug.Mode.DEPTH] and shots[OctaDebug.Mode.DEPTH].r == shots[OctaDebug.Mode.DEPTH].g, "debug views differ from the normal render")

	card.atlas.write_depth = false
	OctaDebug.set_mode(OctaDebug.Mode.DEPTH)
	_check(card.material_override.shader.code.contains("NO_DEPTH_WRITE") and card.material_override.shader.code.contains("DEBUG_MODE 3"), "debug and flat depth combine")
	card.atlas.write_depth = true
	OctaDebug.set_mode(OctaDebug.Mode.OFF)

	var hud := OctaDebugHUD.new()
	vp.add_child(hud)
	var st := hud.scan()
	_check(st.cards == 1 and st.atlases >= 1 and st.vram_mb > 0.0 and st.impostor_visible == 1, "HUD counts cards, atlases and VRAM (%s)" % [st])

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ok_churn := true
	for round in 6:
		var groups: Array[MultiMeshInstance3D] = []
		for g in 3:
			var xf: Array = []
			for i in 5:
				xf.append(Transform3D(Basis(), Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2))))
			var grp := atlas.create_multimesh(0, xf, OctaAtlas.Quality.HIGH, [], 0.0, 0.0, 0.5 if g < 2 else 0.0)
			vp.add_child(grp)
			groups.append(grp)
		var pending := groups.duplicate()
		pending.shuffle()
		for grp in pending:
			var seen := hud.scan()
			ok_churn = ok_churn and seen.cards >= 1
			if rng.randf() < 0.5:
				grp.queue_free()
				await process_frame
			else:
				grp.get_parent().remove_child(grp)
				var after := hud.scan()
				ok_churn = ok_churn and after.cards >= 1
				grp.free()
		hud.scan()
		await process_frame
		ok_churn = ok_churn and atlas.wind_counts() == Vector2i(0, 0) and not atlas.wind_active()
	_check(ok_churn, "HUD scans while joined wind groups are freed in random order (6 rounds), wind registry ends empty and the plain shader returns")
	ball.visible = true
	var temp_atlas: OctaAtlas = await OctaLOD.generate([ball], vp, s)
	ball.visible = false
	var temp_grp := temp_atlas.create_multimesh(0, [Transform3D()], OctaAtlas.Quality.HIGH, [], 0.0, 0.0, 0.5)
	vp.add_child(temp_grp)
	hud.scan()
	temp_atlas = null
	temp_grp.free()
	var live := OctaAtlas.live_atlases()
	var st2 := hud.scan()
	_check(live.size() == st2.atlases and st2.cards >= 1, "HUD survives an atlas whose last joined group was freed (%d live)" % live.size())
	var first := OctaCoverage.mean_covered(atlas, 0)
	var t0 := Time.get_ticks_usec()
	for i in 200:
		OctaCoverage.mean_covered(atlas, 0)
	_check(first > 0.0 and first <= 1.0 and Time.get_ticks_usec() - t0 < 50000, "coverage mean is cached after the first read (%.3f)" % first)
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	for c in root.get_children():
		c.queue_free()
	await process_frame
	quit(1 if _fails else 0)
