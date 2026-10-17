extends SceneTree

const SIZE := 320
const GROUND_LIGHTS := [Vector2(25, 20), Vector2(50, 140), Vector2(75, 250), Vector2(38, 320)]
const SELF_LIGHTS := [Vector2(50, 30), Vector2(25, 200), Vector2(70, 120)]
const SELF_VIEWS := [Vector3(20, 37, 3.5), Vector3(60, 200, 3.5), Vector3(35, 110, 3.5)]
const FLICKER_LIGHT := Vector2(45, 140)
const HEIGHTS := [8.0, 20.0, 50.0, 100.0]
const YAWS := [0.0, 20.0, 45.0, 70.0, 90.0, 130.0, 200.0, 300.0]
const SPIN_START := 0.0
const SPIN_STEP := 3.0
const SPIN_STEPS := 21
const SHADOW_DISTANCE := 150.0
const MIN_CONTRAST := 12
const SELF_DELTA := 0.08
const QUALITIES := {"high": OctaAtlas.Quality.HIGH, "ultra": OctaAtlas.Quality.ULTRA, "blend": OctaAtlas.Quality.MEDIUM}
const SELF_QUALITIES := ["high", "ultra"]
const BLEND_VIEWS := 3
const MIN_GROUND_IOU := 0.85
const MAX_FLICKER_EXTRA := 1.5
const MAX_SPIN_DEFICIT := 0.4
const MAX_BLEND_SPIN_DEFICIT := 0.1
const MAX_SELF_MAE_RISE := 2.5

var _fails := 0
var _sign := 1.0
var _atlas: OctaAtlas
var _objects: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.split("=", true, 1)[1]
	return def


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


# --- Shadow accuracy, self-shadowing and flicker ---
func _run() -> void:
	var method := RenderingServer.get_current_rendering_method()
	var compat := method == "gl_compatibility"
	print("SHADOW renderer %s" % method)
	var only := _arg("only", "")
	var s := OctaBakeSettings.new()
	s.max_atlas_size = int(_arg("atlas", "2048"))
	var sources: Array[Node3D] = []
	for o: Node3D in DemoObjects.all():
		if only.is_empty() or String(o.name).to_lower() == only:
			sources.append(o)
	_atlas = await OctaBaker.bake(sources, root, s)
	var ground := _make_ground_rig()
	var spot := _make_self_rig()
	for i in sources.size():
		var src := sources[i]
		var fb: Vector4 = OctaBaker._collect(src).bounds
		var obj := {name = String(src.name), src = src, bounds = fb, bottom = _bottom(src)}
		for qn in QUALITIES:
			obj[qn] = _atlas.create_card(i, QUALITIES[qn])
		_atlas.get_material(OctaAtlas.Quality.MEDIUM).set_shader_parameter("shadow_views", BLEND_VIEWS)
		_enter(ground, obj)
		await _ground_accuracy(ground, obj)
		await _flicker(ground, obj)
		_leave(ground, obj)
		_enter(spot, obj)
		await _self_shadow(spot, obj, compat)
		_leave(spot, obj, true)
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	for c in root.get_children():
		c.queue_free()
	await process_frame
	await process_frame
	quit(1 if _fails else 0)


# --- Rigs ---
func _make_ground_rig() -> Dictionary:
	var rig := TestRig.make(root, true)
	rig.vp.size = Vector2i(SIZE, SIZE)
	rig.vp.msaa_3d = Viewport.MSAA_DISABLED
	rig.world.get_child(0).environment.ambient_light_energy = 0.15
	rig.sun.light_energy = 1.5
	rig.sun.directional_shadow_max_distance = SHADOW_DISTANCE
	var plane := PlaneMesh.new()
	plane.size = Vector2(1000.0, 1000.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.9, 0.9)
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	plane.material = mat
	var g := MeshInstance3D.new()
	g.mesh = plane
	rig.world.add_child(g)
	rig.ground = g
	rig.cam.far = 400.0
	return rig


func _make_self_rig() -> Dictionary:
	var rig := TestRig.make(root, true)
	rig.vp.size = Vector2i(TestRig.SIZE, TestRig.SIZE)
	return rig


func _enter(rig: Dictionary, obj: Dictionary) -> void:
	rig.world.add_child(obj.src)
	for qn in QUALITIES:
		rig.world.add_child(obj[qn])
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if rig.has("ground") else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for n: Node in [obj.src, obj.high, obj.ultra, obj.blend]:
		_set_casting(n, mode)
	if rig.has("ground"):
		rig.ground.position.y = obj.bottom


func _leave(rig: Dictionary, obj: Dictionary, release := false) -> void:
	rig.world.remove_child(obj.src)
	for qn in QUALITIES:
		rig.world.remove_child(obj[qn])
	if release:
		obj.src.free()
		for qn in QUALITIES:
			obj[qn].free()


func _set_casting(n: Node, mode: int) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = mode
	for c in n.get_children():
		_set_casting(c, mode)


func _show(obj: Dictionary, key: String) -> void:
	obj.src.visible = key == "real"
	for qn in QUALITIES:
		obj[qn].visible = key == qn


func _shot(rig: Dictionary) -> Image:
	rig.vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var im: Image = rig.vp.get_texture().get_image()
	im.convert(Image.FORMAT_RGBA8)
	return im


func _bottom(src: Node3D) -> float:
	var low := INF
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var t := Transform3D.IDENTITY
		var n: Node = m
		while n != src.get_parent() and n is Node3D:
			t = (n as Node3D).transform * t
			n = n.get_parent()
		for k in 8:
			low = minf(low, (t * m.get_aabb().get_endpoint(k)).y)
	return low


func _luma(im: Image) -> PackedByteArray:
	var l := im.duplicate() as Image
	l.convert(Image.FORMAT_L8)
	return l.get_data()


func _mask(luma: PackedByteArray, mid: int) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(luma.size())
	for i in luma.size():
		m[i] = 1 if luma[i] < mid else 0
	return m


func _iou(a: PackedByteArray, b: PackedByteArray) -> float:
	var inter := 0
	var uni := 0
	for i in a.size():
		if a[i] == 1 or b[i] == 1:
			uni += 1
			if a[i] == 1 and b[i] == 1:
				inter += 1
	return float(inter) / maxf(uni, 1)


func _area(m: PackedByteArray) -> int:
	var n := 0
	for v in m:
		n += v
	return n


func _levels(luma: PackedByteArray) -> Vector2i:
	var lo := 255
	var hi := 0
	for v in luma:
		lo = mini(lo, v)
		hi = maxi(hi, v)
	return Vector2i(lo, hi)


func _mean_diff(a: PackedByteArray, b: PackedByteArray, lit: int) -> float:
	var sum := 0
	var n := 0
	for i in a.size():
		if a[i] < lit - 2 or b[i] < lit - 2:
			sum += absi(a[i] - b[i])
			n += 1
	return float(sum) / maxf(n, 1)


func _aim_ground(rig: Dictionary, obj: Dictionary, light: Vector2, height: float, ortho: bool) -> void:
	var b: Vector4 = obj.bounds
	var elev := deg_to_rad(light.x)
	rig.sun.rotation_degrees = Vector3(-light.x, light.y, 0)
	var travel: Vector3 = -(rig.sun.global_transform.basis.z)
	var dh := Vector3(travel.x, 0.0, travel.z).normalized()
	var reach: float = b.w / tan(elev)
	var centre := Vector3(b.x, obj.bottom, b.z) + dh * reach
	rig.cam.projection = Camera3D.PROJECTION_ORTHOGONAL if ortho else Camera3D.PROJECTION_PERSPECTIVE
	rig.cam.size = 2.4 * (b.w + reach) + 0.5 * b.w
	rig.cam.look_at_from_position(centre + Vector3(0.0, height, 0.0), centre, Vector3(0, 0, -1))


# --- Shadow on the ground, card vs real mesh ---
func _ground_accuracy(rig: Dictionary, obj: Dictionary) -> void:
	var sums := {}
	for qn in QUALITIES:
		sums[qn] = {iou = 0.0, area = 0.0, worst = 1.0}
	_aim_ground(rig, obj, GROUND_LIGHTS[0], 3.0 * obj.bounds.w + 5.0, true)
	_show(obj, "real")
	await _shot(rig)
	for light: Vector2 in GROUND_LIGHTS:
		_aim_ground(rig, obj, light, 3.0 * obj.bounds.w + 5.0, true)
		_show(obj, "real")
		var real := _luma(await _shot(rig))
		var lv := _levels(real)
		if lv.y - lv.x < MIN_CONTRAST:
			_check(false, "%s light %s: ground contrast %d..%d too low to measure" % [obj.name, light, lv.x, lv.y])
			continue
		var mid := (lv.x + lv.y) / 2
		var real_mask := _mask(real, mid)
		var line := "SHADOW ground %-6s elev %2d az %3d  real area %5d px" % [obj.name, light.x, light.y, _area(real_mask)]
		for qn in QUALITIES:
			_show(obj, qn)
			var m := _mask(_luma(await _shot(rig)), mid)
			var iou := _iou(real_mask, m)
			var ratio := float(_area(m)) / maxf(_area(real_mask), 1)
			sums[qn].iou += iou
			sums[qn].area += ratio
			sums[qn].worst = minf(sums[qn].worst, iou)
			line += "  %s IoU %.3f area x%.3f" % [qn, iou, ratio]
		print(line)
	var n := GROUND_LIGHTS.size()
	for qn in QUALITIES:
		var avg: float = sums[qn].iou / n
		print("SHADOW ground %-6s %-6s avg IoU %.4f worst %.3f avg area ratio %.3f" % [obj.name, qn, avg, sums[qn].worst, sums[qn].area / n])
		_check(avg > MIN_GROUND_IOU, "%s %s ground shadow IoU %.3f > %.2f" % [obj.name, qn, avg, MIN_GROUND_IOU])


# --- Shadow stability while the camera and the light move ---
func _flicker(rig: Dictionary, obj: Dictionary) -> void:
	var keys := ["real", "high", "ultra", "blend"]
	var ref := {}
	var diffs := {}
	for key in keys:
		diffs[key] = 0.0
	var lit := 255
	for hi in HEIGHTS.size():
		_aim_ground(rig, obj, FLICKER_LIGHT, HEIGHTS[hi], true)
		var line := "SHADOW cascade %-6s camera height %5.0f" % [obj.name, HEIGHTS[hi]]
		for key in keys:
			_show(obj, key)
			var l := _luma(await _shot(rig))
			if hi == 0:
				ref[key] = l
				if key == "real":
					lit = _levels(l).y
			diffs[key] = maxf(diffs[key], _mean_diff(ref[key], l, lit))
			line += "  %s diff vs lowest %.2f" % [key, _mean_diff(ref[key], l, lit)]
		print(line)
	_report_flicker(obj, "camera height across the cascade splits", diffs)

	_aim_ground(rig, obj, FLICKER_LIGHT, 3.0 * obj.bounds.w + 5.0, false)
	var centre: Vector3 = rig.cam.global_transform.origin
	var target := centre - Vector3(0.0, rig.cam.global_transform.origin.y - obj.bottom, 0.0)
	var yaw_ref := {}
	diffs = {}
	for key in keys:
		diffs[key] = 0.0
	for yi in YAWS.size():
		var up := Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(YAWS[yi]))
		rig.cam.look_at_from_position(centre, target, up)
		for key in keys:
			_show(obj, key)
			var l := _luma(await _shot(rig))
			if yi == 0:
				yaw_ref[key] = l
				continue
			if yi == 4 and key == "real":
				_pick_sign(yaw_ref.real, l, YAWS[yi])
			diffs[key] = maxf(diffs[key], _mean_diff(yaw_ref[key], _unrotate(l, YAWS[yi], lit), lit))
	_report_flicker(obj, "camera yaw", diffs)

	_aim_ground(rig, obj, FLICKER_LIGHT, 3.0 * obj.bounds.w + 5.0, true)
	var prev := {}
	var worst := {high = 1.0, ultra = 1.0, blend = 1.0}
	var deficit := {high = 0.0, ultra = 0.0, blend = 0.0}
	var real_worst := 1.0
	for si in SPIN_STEPS:
		var light := Vector2(FLICKER_LIGHT.x, SPIN_START + SPIN_STEP * si)
		_aim_ground(rig, obj, light, 3.0 * obj.bounds.w + 5.0, true)
		_show(obj, "real")
		var real := _luma(await _shot(rig))
		if si == 0:
			lit = _levels(real).y
		var mid := (_levels(real).x + lit) / 2
		var masks := {real = _mask(real, mid)}
		for qn in QUALITIES:
			_show(obj, qn)
			masks[qn] = _mask(_luma(await _shot(rig)), mid)
		if si > 0:
			var r_iou := _iou(prev.real, masks.real)
			real_worst = minf(real_worst, r_iou)
			for qn in QUALITIES:
				var c_iou := _iou(prev[qn], masks[qn])
				worst[qn] = minf(worst[qn], c_iou)
				deficit[qn] = maxf(deficit[qn], r_iou - c_iou)
		prev = masks
	for qn in QUALITIES:
		print("SHADOW light spin %-6s %-6s worst consecutive IoU %.3f (real %.3f), max deficit vs real %.3f" % [obj.name, qn, worst[qn], real_worst, deficit[qn]])
		var limit := MAX_BLEND_SPIN_DEFICIT if qn == "blend" else MAX_SPIN_DEFICIT
		_check(deficit[qn] < limit, "%s %s light rotation: no jump beyond the real mesh (deficit %.3f < %.2f)" % [obj.name, qn, deficit[qn], limit])


func _report_flicker(obj: Dictionary, what: String, diffs: Dictionary) -> void:
	for qn in QUALITIES:
		var limit: float = maxf(diffs.real * MAX_FLICKER_EXTRA, 0.5)
		print("SHADOW flicker %-6s %-6s %s: mean pixel diff %.3f/255 (real %.3f)" % [obj.name, qn, what, diffs[qn], diffs.real])
		_check(diffs[qn] <= limit, "%s %s shadow stable under %s (%.3f <= %.3f)" % [obj.name, qn, what, diffs[qn], limit])


func _pick_sign(ref: PackedByteArray, l: PackedByteArray, deg: float) -> void:
	var lit := _levels(ref).y
	_sign = 1.0
	var a := _mean_diff(ref, _unrotate(l, deg, lit), lit)
	_sign = -1.0
	var b := _mean_diff(ref, _unrotate(l, deg, lit), lit)
	_sign = 1.0 if a <= b else -1.0


func _unrotate(l: PackedByteArray, deg: float, fill: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(l.size())
	var c := (SIZE - 1) * 0.5
	var ca := cos(deg_to_rad(deg) * _sign)
	var sa := sin(deg_to_rad(deg) * _sign)
	for y in SIZE:
		for x in SIZE:
			var dx := x - c
			var dy := y - c
			var sx := c + dx * ca - dy * sa
			var sy := c + dx * sa + dy * ca
			var x0 := floori(sx)
			var y0 := floori(sy)
			if x0 < 0 or y0 < 0 or x0 >= SIZE - 1 or y0 >= SIZE - 1:
				out[y * SIZE + x] = fill
				continue
			var fx := sx - x0
			var fy := sy - y0
			var i := y0 * SIZE + x0
			var v := (l[i] * (1.0 - fx) + l[i + 1] * fx) * (1.0 - fy) + (l[i + SIZE] * (1.0 - fx) + l[i + SIZE + 1] * fx) * fy
			out[y * SIZE + x] = int(round(v))
	return out


# --- Self-shadowing on the surface, card vs real mesh ---
func _self_shadow(rig: Dictionary, obj: Dictionary, compat: bool) -> void:
	var b: Vector4 = obj.bounds
	var c := Vector3(b.x, b.y, b.z)
	var acc := {}
	for qn in SELF_QUALITIES:
		acc[qn] = {acne = 0.0, leak = 0.0, mae_on = 0.0, mae_off = 0.0, n = 0}
	for light: Vector2 in SELF_LIGHTS:
		rig.sun.rotation_degrees = Vector3(-light.x, light.y, 0)
		for v: Vector3 in SELF_VIEWS:
			var e := deg_to_rad(v.x)
			var az := deg_to_rad(v.y)
			var dir := Vector3(cos(e) * sin(az), sin(e), cos(e) * cos(az))
			rig.cam.look_at_from_position(c + dir * b.w * v.z, c, Vector3.UP)
			var imgs := {}
			var pics := {}
			for key in ["real", "high", "ultra"]:
				_show(obj, key)
				for sh in [true, false]:
					rig.sun.shadow_enabled = sh
					var im := await _shot(rig)
					pics["%s%s" % [key, sh]] = im
					imgs["%s%s" % [key, sh]] = im.get_data()
			if _arg("dump", "0") == "1":
				var sheet := Image.create_empty(TestRig.SIZE * 4, TestRig.SIZE, false, Image.FORMAT_RGBA8)
				sheet.fill(Color(0.3, 0.3, 0.34))
				for k in 4:
					sheet.blend_rect(pics[["realtrue", "hightrue", "ultratrue", "realfalse"][k]], Rect2i(0, 0, TestRig.SIZE, TestRig.SIZE), Vector2i(k * TestRig.SIZE, 0))
				sheet.save_png("res://tests/out/shadow_self_%s_%d_%d.png" % [obj.name.to_lower(), int(light.y), int(v.y)])
			rig.sun.shadow_enabled = true
			for qn in SELF_QUALITIES:
				var r := _self_metrics(imgs["real" + str(true)], imgs["real" + str(false)], imgs[qn + str(true)], imgs[qn + str(false)])
				for k in r:
					acc[qn][k] += r[k]
				acc[qn].n += 1
	for qn in SELF_QUALITIES:
		var a: Dictionary = acc[qn]
		var n: int = a.n
		print("SHADOW self %-6s %-6s acne %.2f%% leak %.2f%% colour MAE shadows on %.2f off %.2f" % [obj.name, qn, a.acne / n * 100.0, a.leak / n * 100.0, a.mae_on / n, a.mae_off / n])
		if compat:
			continue
		_check(a.mae_on / n < a.mae_off / n + MAX_SELF_MAE_RISE, "%s %s self-shadowing keeps the colour match (on %.2f, off %.2f)" % [obj.name, qn, a.mae_on / n, a.mae_off / n])


func _self_metrics(real_on: PackedByteArray, real_off: PackedByteArray, card_on: PackedByteArray, card_off: PackedByteArray) -> Dictionary:
	var n := 0
	var acne := 0
	var leak := 0
	var err_on := 0.0
	var err_off := 0.0
	for i in range(0, real_on.size(), 4):
		if real_on[i + 3] < 128 or card_on[i + 3] < 128:
			continue
		var lr_on := _lum4(real_on, i)
		var lr_off := _lum4(real_off, i)
		var lc_on := _lum4(card_on, i)
		var lc_off := _lum4(card_off, i)
		n += 1
		var dr := lr_off - lr_on
		var dc := lc_off - lc_on
		if dc - dr > SELF_DELTA:
			acne += 1
		elif dr - dc > SELF_DELTA:
			leak += 1
		err_on += absf(lc_on - lr_on)
		err_off += absf(lc_off - lr_off)
	return {acne = float(acne) / maxf(n, 1), leak = float(leak) / maxf(n, 1), mae_on = err_on / maxf(n, 1) * 255.0, mae_off = err_off / maxf(n, 1) * 255.0}


func _lum4(d: PackedByteArray, i: int) -> float:
	return (d[i] + d[i + 1] + d[i + 2]) / 765.0
