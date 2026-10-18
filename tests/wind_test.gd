extends SceneTree

class ErrorCatcher extends Logger:
	var errors: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != Logger.ERROR_TYPE_WARNING and not file.contains("wasapi"):
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])


const TREE := 0
const RED_A := 1
const GREEN := 2
const RED_B := 3
const CALM := 0.001
const MIN_TOP_SHIFT := 4.0
const MAX_BASE_SHIFT := 1.0
const MIN_RATIO := 4.0
const CAM_DISTANCE := 25.0

var _fails := 0
var _renderer := ""
var _catcher := ErrorCatcher.new()
var _atlas: OctaAtlas
var _centre := Vector3.ZERO
var _full := true


func _initialize() -> void:
	OS.add_logger(_catcher)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


# --- Far-field wind ---
func _run() -> void:
	_renderer = RenderingServer.get_current_rendering_method()
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--combos=0":
			_full = false
	print("RENDERER ", _renderer)
	await _bake()
	_shader_keys()
	await _atlas_variant()
	await _identical_when_off()
	await _sway()
	await _direction()
	await _animation()
	await _no_bleed()
	await _shadow()
	await _cards_and_groups()
	await _reload()
	await _combinations()
	_api()
	_check(_catcher.errors.is_empty(), "no engine or script errors (%d)" % _catcher.errors.size())
	for e in _catcher.errors.slice(0, 8):
		print("ERROR ", e)
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	OctaWind.reset()
	for c in root.get_children():
		c.queue_free()
	await process_frame
	await process_frame
	_atlas = null
	OctaAtlas._variants.clear()
	quit(1 if _fails else 0)


func _bake() -> void:
	var sources: Array = [DemoObjects.tree(), _ball(Color(0.9, 0.05, 0.05)), _ball(Color(0.1, 0.75, 0.15)), _ball(Color(0.9, 0.05, 0.05))]
	for s: Node3D in sources:
		root.add_child(s)
	var s := OctaBakeSettings.new()
	s.max_atlas_size = 1024
	s.grid_size = 8
	_atlas = await OctaBaker.bake(sources, root, s)
	for n: Node in sources:
		n.free()
	var b := _atlas.bounds[TREE]
	_centre = Vector3(b.x, b.y, b.z)
	_check(_atlas != null and _atlas.object_count() == 4, "test atlas baked (tree, red ball, green ball, red ball)")


func _ball(color: Color) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	mi.material_override = m
	n.add_child(mi)
	return n


func _rig(fov := 15.0) -> Dictionary:
	var rig := TestRig.make(root)
	rig.cam.fov = fov
	return rig


func _shot(rig: Dictionary, from: Vector3, at: Vector3) -> Image:
	TestRig.shoot(rig, from, at)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return TestRig.grab(rig)


func _card(rig: Dictionary, index := TREE, quality := OctaAtlas.Quality.HIGH, pos := Vector3.ZERO, strength := 0.0) -> OctaImpostor:
	var card := _atlas.create_card(index, quality)
	card.position = pos
	card.wind_strength = strength
	rig.world.add_child(card)
	return card


func _side(rig: Dictionary, x_offset := 0.0) -> Image:
	return await _shot(rig, _centre + Vector3(x_offset, 0.0, CAM_DISTANCE), _centre + Vector3(x_offset, 0.0, 0.0))


func _differing(a: Image, b: Image) -> int:
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if ca.r8 != cb.r8 or ca.g8 != cb.g8 or ca.b8 != cb.b8 or ca.a8 != cb.a8:
				n += 1
	return n


func _extent(im: Image, x0: int, x1: int) -> Vector2i:
	var top := -1
	var bottom := -1
	for y in im.get_height():
		for x in range(x0, x1):
			if im.get_pixel(x, y).a > 0.5:
				if top < 0:
					top = y
				bottom = y
				break
	return Vector2i(top, bottom)


func _centroid(im: Image, y: int, x0: int, x1: int) -> float:
	var sum := 0.0
	var n := 0
	for x in range(x0, x1):
		if im.get_pixel(x, y).a > 0.5:
			sum += x
			n += 1
	return sum / n if n > 0 else NAN


func _band_shift(a: Image, b: Image, x0: int, x1: int, y0: int, y1: int) -> float:
	var total := 0.0
	var rows := 0
	for y in range(y0, y1 + 1):
		var ca := _centroid(a, y, x0, x1)
		var cb := _centroid(b, y, x0, x1)
		if not is_nan(ca) and not is_nan(cb):
			total += cb - ca
			rows += 1
	return total / rows if rows > 0 else 0.0


func _profile(still: Image, swayed: Image, x0 := 0, x1 := TestRig.SIZE) -> Dictionary:
	var e := _extent(still, x0, x1)
	var h := e.y - e.x
	return {
		top = _band_shift(still, swayed, x0, x1, e.x + int(h * 0.1), e.x + int(h * 0.25)),
		mid = _band_shift(still, swayed, x0, x1, e.x + int(h * 0.45), e.x + int(h * 0.6)),
		base = _band_shift(still, swayed, x0, x1, e.y - int(h * 0.1), e.y),
	}


# --- Compile-time variants ---
func _shader_keys() -> void:
	var seen := {}
	var combos := 0
	var plain := 0
	for q in 4:
		for depth in [true, false]:
			for debug in 6:
				for precise in [false, true]:
					for fade in [false, true]:
						for wind in [false, true]:
							var sh := OctaAtlas.shader_for(q, depth, debug, precise, fade, wind)
							var eff_precise: bool = precise and q == 3
							var ok: bool = sh.code.contains("#define CARD_WIND") == wind and sh.code.contains("#define CARD_FADE") == fade and sh.code.contains("#define PRECISE_SEARCH") == eff_precise and sh.code.contains("#define NO_DEPTH_WRITE") != depth
							if sh == OctaAtlas.SHADERS[q]:
								plain += 1
								ok = ok or (depth and debug == 0 and not eff_precise and not fade and not wind)
							if not ok or sh != OctaAtlas.shader_for(q, depth, debug, precise, fade, wind):
								_check(false, "variant q%d depth %s debug %d precise %s fade %s wind %s has the right defines and is cached" % [q, depth, debug, precise, fade, wind])
								return
							seen[sh] = true
							combos += 1
	var wind_shaders := 0
	for sh: Shader in seen:
		if sh.code.contains("#define CARD_WIND"):
			wind_shaders += 1
	_check(plain == 7 and OctaAtlas.shader_for(2, true, 0, false, false, false) == OctaAtlas.SHADERS[2], "only the plain combinations return the shipped shaders (%d of %d, fade/precise/wind off)" % [plain, combos])
	_check(wind_shaders == 120 and seen.size() == 240, "wind adds 120 cached variants, none shares a key with the %d others (%d distinct shaders)" % [seen.size() - 120, seen.size()])
	_check(OctaAtlas.shader_for(3, true, 0, true, true, true).code.contains("PRECISE_SEARCH") and OctaAtlas.shader_for(0, false, 5, false, true, true).code.contains("CARD_FADE"), "wind combines with precise search, fade, flat depth and debug views")


# --- The shared material only changes when something asks for wind ---
func _atlas_variant() -> void:
	var plain := OctaAtlas.SHADERS[OctaAtlas.Quality.HIGH]
	var rig := _rig()
	_check(_atlas.get_material(OctaAtlas.Quality.HIGH).shader == plain and not _atlas.wind_active(), "a fresh atlas uses the shipped shader")
	var still := _card(rig)
	_check(_atlas.get_material(OctaAtlas.Quality.HIGH).shader == plain and not _atlas.wind_active() and still.get_instance_shader_parameter("card_wind") == null, "a card at strength 0 leaves the shader and the instance uniform alone")
	var card := _card(rig, TREE, OctaAtlas.Quality.HIGH, Vector3(5, 0, 0), 0.5)
	var variant := _atlas.get_material(OctaAtlas.Quality.HIGH).shader
	_check(variant != plain and variant.code.contains("#define CARD_WIND") and _atlas.wind_active(), "the first card with strength > 0 switches the atlas to the wind variant")
	_check(is_equal_approx(card.get_instance_shader_parameter("card_wind"), 0.5) and card.wind_strength == 0.5, "wind_strength reaches the instance uniform of that card")
	_check(_atlas.get_material(OctaAtlas.Quality.ULTRA).shader.code.contains("#define CARD_WIND") and _atlas.get_material(OctaAtlas.Quality.LOW).shader.code.contains("#define CARD_WIND"), "materials of the other qualities follow")
	_check(_atlas.get_material(OctaAtlas.Quality.HIGH).get_shader_parameter("wind_dir") == OctaWind.direction, "the global wind reaches the material")
	card.wind_strength = 0.0
	_check(_atlas.get_material(OctaAtlas.Quality.HIGH).shader == plain and not _atlas.wind_active() and _atlas.get_material(OctaAtlas.Quality.ULTRA).shader == OctaAtlas.SHADERS[OctaAtlas.Quality.ULTRA], "strength back to 0 returns the shipped shaders")
	card.wind_strength = 0.5
	rig.world.remove_child(card)
	_check(_atlas.get_material(OctaAtlas.Quality.HIGH).shader == plain, "a card leaving the tree stops asking for wind")
	rig.world.add_child(card)
	_check(_atlas.get_material(OctaAtlas.Quality.HIGH).shader != plain, "and asks again when it returns")
	_atlas.write_depth = false
	_check(_atlas.get_material(OctaAtlas.Quality.HIGH).shader.code.contains("NO_DEPTH_WRITE") and _atlas.get_material(OctaAtlas.Quality.HIGH).shader.code.contains("CARD_WIND"), "flat depth keeps the wind variant")
	_atlas.write_depth = true
	card.free()
	_check(_atlas.get_material(OctaAtlas.Quality.HIGH).shader == plain or not _atlas.wind_active(), "a freed card is dropped from the users")
	var group := _atlas.create_multimesh(TREE, [Transform3D.IDENTITY], OctaAtlas.Quality.HIGH, [], 0.0, 0.0, 0.5)
	_check(group is OctaJoinedGroup and group.atlas == _atlas and is_equal_approx(group.wind_strength, 0.5) and not _atlas.wind_active(), "a joined group outside the tree does not ask for wind")
	rig.world.add_child(group)
	_check(_atlas.get_material(OctaAtlas.Quality.HIGH).shader.code.contains("CARD_WIND") and _atlas.wind_counts() == Vector2i(0, 1), "a joined group in the tree selects the variant without any card (counts %s)" % _atlas.wind_counts())
	var second := _card(rig, TREE, OctaAtlas.Quality.HIGH, Vector3(5, 0, 0), 0.5)
	_check(_atlas.wind_counts() == Vector2i(1, 1), "cards and groups are counted apart (%s)" % _atlas.wind_counts())
	second.free()
	group.wind_strength = 0.0
	_check(_atlas.get_material(OctaAtlas.Quality.HIGH).shader == plain and not _atlas.wind_active(), "a group at strength 0 releases the variant")
	group.wind_strength = 0.5
	_check(_atlas.get_material(OctaAtlas.Quality.HIGH).shader != plain, "and asks again when raised")
	rig.world.remove_child(group)
	_check(_atlas.get_material(OctaAtlas.Quality.HIGH).shader == plain and _atlas.get_material(OctaAtlas.Quality.ULTRA).shader == OctaAtlas.SHADERS[OctaAtlas.Quality.ULTRA], "a group leaving the tree returns the atlas to the shipped shaders")
	rig.world.add_child(group)
	group.free()
	_check(_atlas.get_material(OctaAtlas.Quality.HIGH).shader == plain and not _atlas.wind_active(), "a freed group is dropped from the users")
	rig.vp.queue_free()
	await process_frame


# --- Wind off renders exactly like the shipped shader ---
func _identical_when_off() -> void:
	for q in [OctaAtlas.Quality.LOW, OctaAtlas.Quality.MEDIUM, OctaAtlas.Quality.HIGH, OctaAtlas.Quality.ULTRA]:
		var rig := _rig()
		var card := _card(rig, TREE, q)
		var plain_shader := _atlas.get_material(q).shader
		var a := await _side(rig)
		var user := RefCounted.new()
		_atlas.set_wind_user(user, true)
		var b := await _side(rig)
		var variant := _atlas.get_material(q).shader
		var diff := _differing(a, b)
		_check(plain_shader == OctaAtlas.SHADERS[q] and variant != plain_shader and diff == 0, "quality %d: strength 0 in the wind variant renders identically to the shipped shader (%d differing pixels)" % [q, diff])
		_atlas.set_wind_user(user, false)
		_check(_atlas.get_material(q).shader == OctaAtlas.SHADERS[q], "quality %d: the shipped shader is back" % q)
		card.free()
		rig.vp.queue_free()
		await process_frame


# --- The top moves, the base stays ---
func _sway() -> void:
	OctaWind.set_wind(Vector2.RIGHT, 0.0, 0.0, CALM)
	for q in [OctaAtlas.Quality.LOW, OctaAtlas.Quality.MEDIUM, OctaAtlas.Quality.HIGH, OctaAtlas.Quality.ULTRA]:
		var rig := _rig()
		var card := _card(rig, TREE, q)
		var still := await _side(rig)
		card.wind_strength = 1.0
		var swayed := await _side(rig)
		var p := _profile(still, swayed)
		print("SWAY %s quality %d: top %.2f px, middle %.2f px, base %.2f px" % [_renderer, q, p.top, p.mid, p.base])
		_check(p.top > MIN_TOP_SHIFT and absf(p.base) < MAX_BASE_SHIFT and p.top > MIN_RATIO * absf(p.base) and p.top > p.mid and p.mid > p.base - 0.1, "quality %d: the top leans downwind (%.1f px), the middle less (%.1f), the base row stays (%.2f)" % [q, p.top, p.mid, p.base])
		card.wind_strength = 0.5
		var half := await _side(rig)
		var ph := _profile(still, half)
		_check(ph.top > 0.3 * p.top and ph.top < 0.7 * p.top, "quality %d: half the strength gives about half the sway (%.1f px vs %.1f px)" % [q, ph.top, p.top])
		card.free()
		rig.vp.queue_free()
		await process_frame


# --- The global direction decides the motion ---
func _direction() -> void:
	var rig := _rig()
	var card := _card(rig)
	var still := await _side(rig)
	card.wind_strength = 1.0
	var tops := {}
	for entry: Array in [["+x", Vector2(1, 0)], ["-x", Vector2(-1, 0)], ["+z", Vector2(0, 1)], ["-z", Vector2(0, -1)], ["diagonal", Vector2(1, 1)]]:
		OctaWind.set_wind(entry[1], 0.0, 0.0, CALM)
		var im := await _side(rig)
		tops[entry[0]] = _profile(still, im).top
	print("DIRECTION %s: +x %.2f, -x %.2f, +z %.2f, -z %.2f, diagonal %.2f px" % [_renderer, tops["+x"], tops["-x"], tops["+z"], tops["-z"], tops["diagonal"]])
	_check(tops["+x"] > MIN_TOP_SHIFT and tops["-x"] < -MIN_TOP_SHIFT and absf(tops["+x"] + tops["-x"]) < 1.5, "direction +x moves the top right and -x moves it left by the same amount")
	_check(absf(tops["+z"]) < 0.25 * tops["+x"] and absf(tops["-z"]) < 0.25 * tops["+x"], "wind along the view axis does not move the picture sideways")
	_check(tops["diagonal"] > 0.5 * tops["+x"] and tops["diagonal"] < 0.9 * tops["+x"], "a diagonal wind gives its x share (%.2f of %.2f)" % [tops["diagonal"], tops["+x"]])
	var cam_top := _centre + Vector3(0.0, CAM_DISTANCE, 0.01)
	OctaWind.set_wind(Vector2(0, 1), 0.0, 0.0, CALM)
	card.wind_strength = 0.0
	var below_still := await _shot(rig, cam_top, _centre)
	card.wind_strength = 1.0
	var below := await _shot(rig, cam_top, _centre)
	OctaWind.set_wind(Vector2(1, 0), 0.0, 0.0, CALM)
	var other := await _shot(rig, cam_top, _centre)
	_check(_differing(below_still, below) > 20 and _differing(below, other) > 20, "seen from above the picture still changes with the strength and with the direction")
	card.free()
	rig.vp.queue_free()
	await process_frame


# --- Time moves it ---
func _animation() -> void:
	OctaWind.set_wind(Vector2.RIGHT, 12.0, 0.5, 0.05)
	var rig := _rig()
	var card := _card(rig, TREE, OctaAtlas.Quality.HIGH, Vector3.ZERO, 1.0)
	var a := await _side(rig)
	await create_timer(0.7).timeout
	var b := await _side(rig)
	await create_timer(0.7).timeout
	var c := await _side(rig)
	var d1 := _differing(a, b)
	var d2 := _differing(b, c)
	_check(d1 > 50 and d2 > 50, "with speed above 0 the sway changes over time (%d and %d pixels differ between frames 0.7 s apart)" % [d1, d2])
	OctaWind.set_wind(Vector2.RIGHT, 0.0, 0.0, CALM)
	var e := await _side(rig)
	await create_timer(0.3).timeout
	var f := await _side(rig)
	_check(_differing(e, f) == 0, "speed 0 freezes it (%d differing pixels)" % _differing(e, f))
	card.free()
	rig.vp.queue_free()
	await process_frame


# --- Nothing is read from the neighbouring tiles ---
func _no_bleed() -> void:
	var views := [[0.0, 0.0], [35.0, 20.0], [90.0, -30.0], [180.0, 55.0], [270.0, 10.0], [315.0, 80.0]]
	for q in [OctaAtlas.Quality.LOW, OctaAtlas.Quality.MEDIUM, OctaAtlas.Quality.HIGH, OctaAtlas.Quality.ULTRA]:
		var rig := _rig(15.0)
		var green := _card(rig, GREEN, q)
		var control := _card(rig, RED_A, q, Vector3(0, -80, 0))
		var worst := 0
		var base_worst := 0
		var covered := 0
		var red_seen := 0
		for dir_x in [2.0, 1.0, -1.0, 0.0]:
			OctaWind.set_wind(Vector2(dir_x, 1.0 - absf(dir_x)), 3.0, 1.0, 0.2)
			green.wind_strength = 0.0 if dir_x > 1.5 else 1.0
			for v in views:
				var yaw := deg_to_rad(v[0])
				var pitch := deg_to_rad(v[1])
				var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
				var im := await _shot(rig, _centre + dir * 14.0, _centre)
				var reds := 0
				for y in im.get_height():
					for x in im.get_width():
						var p := im.get_pixel(x, y)
						if p.a > 0.1 and p.r > 0.5 and p.g < 0.3 and p.b < 0.3:
							reds += 1
				if dir_x > 1.5:
					base_worst = maxi(base_worst, reds)
				else:
					worst = maxi(worst, reds)
					covered += 1
		var rc := await _shot(rig, _centre + Vector3(0, -80, 14), _centre + Vector3(0, -80, 0))
		for y in rc.get_height():
			for x in rc.get_width():
				var p := rc.get_pixel(x, y)
				if p.a > 0.1 and p.r > 0.5 and p.g < 0.3 and p.b < 0.3:
					red_seen += 1
		_check(red_seen > 200 and worst == 0 and base_worst == 0, "quality %d: full wind adds no red pixel of the neighbouring tiles over %d views (worst %d with wind, %d without; the red control card shows %d red pixels)" % [q, covered, worst, base_worst, red_seen])
		green.free()
		control.free()
		rig.vp.queue_free()
		await process_frame


# --- Shadows sway with the card ---
func _shadow() -> void:
	OctaWind.set_wind(Vector2.RIGHT, 0.0, 0.0, CALM)
	var cells := {}
	for strength in [0.0, 1.0, 0.0]:
		var rig := TestRig.make(root, true)
		rig.sun.rotation_degrees = Vector3(-90, 0, 0)
		rig.sun.light_energy = 2.0
		rig.cam.fov = 30.0
		var ground := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(60, 60)
		ground.mesh = pm
		rig.world.add_child(ground)
		var card := _card(rig, TREE, OctaAtlas.Quality.HIGH, Vector3.ZERO, strength)
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		rig.cam.look_at_from_position(Vector3(0, 12.0, 0.001), Vector3.ZERO)
		rig.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		for i in 4:
			await RenderingServer.frame_post_draw
		var im := TestRig.grab(rig)
		var lit := 0.0
		for y in im.get_height():
			for x in im.get_width():
				lit = maxf(lit, im.get_pixel(x, y).get_luminance())
		var sx := 0.0
		var n := 0
		for y in im.get_height():
			for x in im.get_width():
				if im.get_pixel(x, y).get_luminance() < lit * 0.5:
					sx += x
					n += 1
		cells[cells.size()] = {x = sx / maxf(n, 1.0), n = n}
		rig.vp.queue_free()
		await process_frame
	var shift: float = cells[1].x - cells[0].x
	print("SHADOW %s: still %d px at x %.2f, swayed %d px at x %.2f (shift %.2f px)" % [_renderer, cells[0].n, cells[0].x, cells[1].n, cells[1].x, shift])
	_check(cells[0].n > 400 and shift > 1.5 and absf(cells[2].x - cells[0].x) < 0.3, "the shadow moves downwind with the card (%.1f px) and comes back at strength 0" % shift)


# --- Per-card strength and joined groups ---
func _cards_and_groups() -> void:
	OctaWind.set_wind(Vector2.RIGHT, 0.0, 0.0, CALM)
	var rig := _rig(40.0)
	var left := _card(rig, TREE, OctaAtlas.Quality.HIGH, Vector3(-5, 0, 0))
	var right := _card(rig, TREE, OctaAtlas.Quality.HIGH, Vector3(5, 0, 0))
	var at := _centre
	var still := await _shot(rig, at + Vector3(0, 0, 30), at)
	right.wind_strength = 0.6
	var one := await _shot(rig, at + Vector3(0, 0, 30), at)
	var half := TestRig.SIZE / 2
	var lp := _profile(still, one, 0, half)
	var rp := _profile(still, one, half, TestRig.SIZE)
	print("CARDS %s: left top %.2f base %.2f, right top %.2f base %.2f" % [_renderer, lp.top, lp.base, rp.top, rp.base])
	_check(_differing(_crop(still, 0, half), _crop(one, 0, half)) == 0 and rp.top > 1.0, "wind_strength is per card: only the card with strength sways (right top %.1f px)" % rp.top)
	left.free()
	right.free()
	rig.vp.queue_free()
	await process_frame

	rig = _rig(40.0)
	var xs := [Transform3D(Basis.IDENTITY, Vector3(-5, 0, 0)), Transform3D(Basis.IDENTITY, Vector3(-4.5, 0, -8))]
	var windy := _atlas.create_multimesh(TREE, xs, OctaAtlas.Quality.HIGH, [], 0.0, 0.0, 1.0)
	var calm := _atlas.create_multimesh(TREE, [Transform3D(Basis.IDENTITY, Vector3(5, 0, 0))])
	rig.world.add_child(windy)
	rig.world.add_child(calm)
	_check(_atlas.wind_active() and is_equal_approx(windy.get_instance_shader_parameter("card_wind"), 1.0) and windy.material_override.shader.code.contains("CARD_WIND"), "a group with a wind strength selects the variant and sets its instance uniform once in the tree")
	windy.wind_strength = 0.0
	var g0 := await _shot(rig, at + Vector3(0, 0, 30), at)
	windy.wind_strength = 1.0
	var g1 := await _shot(rig, at + Vector3(0, 0, 30), at)
	var wp := _profile(g0, g1, 0, half)
	var cp := _profile(g0, g1, half, TestRig.SIZE)
	print("GROUP %s: windy group top %.2f base %.2f, plain group of the same atlas top %.2f" % [_renderer, wp.top, wp.base, cp.top])
	_check(wp.top > 2.0 and absf(wp.base) < MAX_BASE_SHIFT and _differing(_crop(g0, half, TestRig.SIZE), _crop(g1, half, TestRig.SIZE)) == 0, "a joined group sways (top %.1f px, base %.2f px) while a group with strength 0 of the same atlas stays identical" % [wp.top, wp.base])
	OctaWind.set_wind(Vector2.LEFT, 0.0, 0.0, CALM)
	var g2 := await _shot(rig, at + Vector3(0, 0, 30), at)
	var lp2 := _profile(g0, g2, 0, half)
	_check(lp2.top < -2.0, "changing the global direction turns the joined group around (%.1f px)" % lp2.top)
	windy.free()
	calm.free()
	rig.vp.queue_free()
	await process_frame
	_check(not _atlas.wind_active() and _atlas.get_material(OctaAtlas.Quality.HIGH).shader == OctaAtlas.SHADERS[OctaAtlas.Quality.HIGH], "after the last group is freed the atlas is back on the shipped shader")


func _crop(im: Image, x0: int, x1: int) -> Image:
	return im.get_region(Rect2i(x0, 0, x1 - x0, im.get_height()))


# --- A saved scene with a wind group still sways after a reload ---
func _reload() -> void:
	OctaWind.set_wind(Vector2.RIGHT, 0.0, 0.0, CALM)
	var atlas_path := "user://octa_wind_reload_atlas.res"
	var scene_path := "user://octa_wind_reload_scene.tscn"
	var plain := OctaAtlas.SHADERS[OctaAtlas.Quality.HIGH]
	var rig := _rig(40.0)
	var holder := Node3D.new()
	holder.name = "SavedScene"
	rig.world.add_child(holder)
	var group := _atlas.create_multimesh(TREE, [Transform3D(Basis.IDENTITY, Vector3(-5, 0, 0)), Transform3D(Basis.IDENTITY, Vector3(-4.5, 0, -8))], OctaAtlas.Quality.HIGH, [], 0.0, 0.0, 1.0)
	holder.add_child(group)
	group.owner = holder
	var saved_atlas_err := ResourceSaver.save(_atlas, atlas_path, ResourceSaver.FLAG_CHANGE_PATH)
	var pack := PackedScene.new()
	var pack_err := pack.pack(holder)
	var scene_err := ResourceSaver.save(pack, scene_path)
	_check(saved_atlas_err == OK and pack_err == OK and scene_err == OK, "an atlas and a scene holding a wind group save (%d, %d, %d)" % [saved_atlas_err, pack_err, scene_err])
	holder.free()
	rig.vp.queue_free()
	await process_frame
	_check(not _atlas.wind_active() and _atlas.get_material(OctaAtlas.Quality.HIGH).shader == plain, "freeing the saved scene returns the source atlas to the shipped shader")

	var loaded_pack: PackedScene = ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var loaded: Node3D = loaded_pack.instantiate()
	var lg: OctaJoinedGroup = loaded.get_child(0)
	var fresh := lg.atlas
	_check(fresh != null and fresh != _atlas and is_equal_approx(lg.wind_strength, 1.0), "the reloaded group keeps its atlas and strength (own atlas copy: %s)" % [fresh != _atlas])
	_check(not fresh.wind_active(), "a loaded atlas does not claim wind before its group is in the tree")
	rig = _rig(40.0)
	rig.world.add_child(loaded)
	_check(fresh.wind_active() and fresh.wind_counts() == Vector2i(0, 1) and fresh.get_material(OctaAtlas.Quality.HIGH).shader.code.contains("CARD_WIND"), "the reloaded group registers its wind when it enters the tree")
	var at := _centre
	lg.wind_strength = 0.0
	var s0 := await _shot(rig, at + Vector3(0, 0, 30), at)
	lg.wind_strength = 1.0
	var s1 := await _shot(rig, at + Vector3(0, 0, 30), at)
	var prof := _profile(s0, s1, 0, TestRig.SIZE / 2)
	print("RELOAD %s: reloaded group top %.2f base %.2f" % [_renderer, prof.top, prof.base])
	_check(prof.top > 2.0 and absf(prof.base) < MAX_BASE_SHIFT, "the reloaded wind group sways (top %.1f px, base %.2f px)" % [prof.top, prof.base])
	loaded.free()
	rig.vp.queue_free()
	await process_frame
	_check(not fresh.wind_active() and fresh.get_material(OctaAtlas.Quality.HIGH).shader == plain, "the loaded atlas returns to the shipped shader when its group leaves")
	DirAccess.remove_absolute(atlas_path)
	DirAccess.remove_absolute(scene_path)
	_atlas.resource_path = ""


# --- Every shader combination compiles ---
func _combinations() -> void:
	OctaWind.set_wind(Vector2.RIGHT, 2.0, 0.3, 0.05)
	var rig := _rig(30.0)
	var errors_before := _catcher.errors.size()
	var count := 0
	var holder := Node3D.new()
	rig.world.add_child(holder)
	for q in 4:
		for depth in [true, false]:
			for debug in 6:
				for precise in [false, true]:
					if precise and q != 3:
						continue
					for fade in [false, true]:
						if not _full and (debug > 0 and (precise or fade or not depth)):
							continue
						var m := ShaderMaterial.new()
						m.shader = OctaAtlas.shader_for(q, depth, debug, precise, fade, true)
						_atlas._apply_params(m)
						OctaWind.apply_to(m)
						var mi := MeshInstance3D.new()
						mi.mesh = _atlas.get_mesh(TREE)
						mi.material_override = m
						mi.position = Vector3((count % 12) * 0.1, 0, 0)
						holder.add_child(mi)
						mi.set_instance_shader_parameter("octa_index", TREE)
						mi.set_instance_shader_parameter("card_wind", 0.7)
						count += 1
	await _shot(rig, _centre + Vector3(0, 0, CAM_DISTANCE), _centre)
	var frames := 3
	for i in frames:
		await RenderingServer.frame_post_draw
	var im := TestRig.grab(rig)
	var painted := 0
	for y in im.get_height():
		for x in im.get_width():
			if im.get_pixel(x, y).a > 0.5:
				painted += 1
	_check(_catcher.errors.size() == errors_before and painted > 500, "%d wind variants (quality x depth x debug x precise x fade) compile and draw without errors (%d painted pixels)" % [count, painted])
	rig.vp.queue_free()
	await process_frame


# --- API ---
func _api() -> void:
	OctaWind.set_wind(Vector2(3, 4), 5.0, 2.0, 5.0)
	_check(OctaWind.direction.is_equal_approx(Vector2(0.6, 0.8)) and OctaWind.speed == 5.0 and OctaWind.gust == 1.0 and OctaWind.frequency == 1.0, "set_wind normalises the direction and clamps gust and frequency")
	OctaWind.set_wind(Vector2.ZERO, 1.0)
	_check(OctaWind.direction.is_equal_approx(Vector2(0.6, 0.8)) and OctaWind.speed == 1.0, "a zero direction keeps the last one")
	OctaWind.reset()
	_check(OctaWind.direction == Vector2.RIGHT and OctaWind.speed == OctaWind.DEFAULT_SPEED, "reset restores the defaults")
	var settings := OctaBakeSettings.new()
	_check(settings.wind_strength == 0.0, "the bake setting defaults to 0 (wind off)")
	settings.wind_strength = 0.3
	var rig := _rig()
	var card := _atlas.create_card(TREE)
	rig.world.add_child(card)
	card.configure(settings, 1.0)
	_check(is_equal_approx(card.wind_strength, 0.3) and is_equal_approx(card.get_instance_shader_parameter("card_wind"), 0.3) and _atlas.wind_active(), "new cards take the bake setting as their wind strength")
	_atlas.bake_settings = OctaBakeSettings.new()
	_check(OctaLOD.card_overrides(card).get("wind_strength", -1.0) == card.wind_strength, "a changed strength is kept as a card override on re-bake")
	var fresh := _atlas.create_card(TREE)
	OctaLOD.apply_overrides(fresh, {wind_strength = 0.8})
	_check(is_equal_approx(fresh.wind_strength, 0.8), "overrides restore the strength")
	fresh.free()
	card.free()
	rig.vp.queue_free()
