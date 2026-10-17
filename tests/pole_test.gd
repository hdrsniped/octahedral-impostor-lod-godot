extends SceneTree

const TILTS := [-6.0, -4.0, -3.0, -2.6, -2.5, -2.0, -1.0, -0.5, -0.2, 0.0, 0.2, 0.5, 1.0, 2.0, 2.5, 2.6, 3.0, 4.0, 6.0]
const RING_TILT := 1.5
const RING_STEPS := 12
const QUALITIES := {"medium": OctaAtlas.Quality.MEDIUM, "high": OctaAtlas.Quality.HIGH, "ultra": OctaAtlas.Quality.ULTRA}
const MAX_STEP_WOBBLE := 0.4
const MAX_MAE_SPREAD := 3.0

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


# --- No wobble looking straight down and straight up at a card ---
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var objects := {"Rock": DemoObjects.rock(3), "Tree": DemoObjects.tree()}
	for oname in objects:
		var src: Node3D = objects[oname]
		world.add_child(src)
		for hemi in [true, false]:
			var s := OctaBakeSettings.new()
			s.max_atlas_size = 1024
			s.hemisphere = hemi
			var atlas := await OctaBaker.bake([src], root, s)
			for from_below in ([false] if hemi else [false, true]):
				for qname in QUALITIES:
					await _sweep(src, atlas, QUALITIES[qname], from_below, "%s %s %s" % [oname, "below (full sphere)" if from_below else ("above (hemisphere)" if hemi else "above (full sphere)"), qname])
		src.free()
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	for c in root.get_children():
		c.queue_free()
	await process_frame
	await process_frame
	quit(1 if _fails else 0)


func _sweep(src: Node3D, atlas: OctaAtlas, quality: int, from_below: bool, label: String) -> void:
	var b: Vector4 = OctaBaker._collect(src).bounds
	var c := Vector3(b.x, b.y, b.z)
	var real := TestRig.make(root)
	var fake := TestRig.make(root)
	for rig in [real, fake]:
		rig.sun.rotation_degrees = Vector3(50 if from_below else -50, 30, 0)
	var parent := src.get_parent()
	parent.remove_child(src)
	real.world.add_child(src)
	var card := atlas.create_card(0, quality)
	fake.world.add_child(card)
	var sign_y := -1.0 if from_below else 1.0
	var spots: Array[Vector2] = []
	for t: float in TILTS:
		spots.append(Vector2(t, 0.0))
	for i in RING_STEPS:
		spots.append(Vector2(RING_TILT, 360.0 / RING_STEPS * i))
	var reals: Array[Image] = []
	var fakes: Array[Image] = []
	var maes: Array[float] = []
	var worst_iou := 1.0
	for spot in spots:
		var dir: Vector3
		if spot.y == 0.0 and spots.find(spot) < TILTS.size():
			var th := deg_to_rad(spot.x)
			dir = Vector3(sin(th), sign_y * cos(th), 0.0)
		else:
			var th := deg_to_rad(spot.x)
			var ph := deg_to_rad(spot.y)
			dir = Vector3(sin(th) * sin(ph), sign_y * cos(th), sin(th) * cos(ph))
		for rig in [real, fake]:
			TestRig.shoot(rig, c + dir * b.w * 3.5, c, Vector3.FORWARD)
		await RenderingServer.frame_post_draw
		var ra := TestRig.grab(real)
		var rb := TestRig.grab(fake)
		reals.append(ra)
		fakes.append(rb)
		var r := TestRig.compare(ra, rb)
		maes.append(r.mae)
		worst_iou = minf(worst_iou, r.iou)
	var step_wobble := 0.0
	var edge_flip := 0.0
	for i in TILTS.size() - 1:
		step_wobble = maxf(step_wobble, TestRig.interior_difference(fakes[i], fakes[i + 1]) - TestRig.interior_difference(reals[i], reals[i + 1]))
		edge_flip = maxf(edge_flip, (1.0 - TestRig.compare(fakes[i], fakes[i + 1]).iou) - (1.0 - TestRig.compare(reals[i], reals[i + 1]).iou))
	var lo := INF
	var hi := -INF
	for m in maes:
		lo = minf(lo, m)
		hi = maxf(hi, m)
	_check(step_wobble < MAX_STEP_WOBBLE and hi - lo < MAX_MAE_SPREAD and worst_iou > 0.85,
			"%s: interior step wobble %.2f, colour MAE %.1f..%.1f, worst IoU %.3f (silhouette flip %.1f%%)" % [label, step_wobble, lo, hi, worst_iou, edge_flip * 100.0])
	real.world.remove_child(src)
	parent.add_child(src)
	real.vp.queue_free()
	fake.vp.queue_free()
