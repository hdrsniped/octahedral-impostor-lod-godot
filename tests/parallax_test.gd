extends SceneTree

const VIEWS := [
	[5.0, 0.0, 3.5], [20.0, 37.0, 3.5], [35.0, 110.0, 3.5], [60.0, 200.0, 3.5],
	[85.0, 300.0, 3.5], [15.0, 70.0, 10.0], [45.0, 250.0, 10.0], [-20.0, 30.0, 4.0],
]

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


# --- Parallax refine: variant plumbing and Low/Medium accuracy ---
func _run() -> void:
	var medium := OctaAtlas.Quality.MEDIUM
	var low := OctaAtlas.Quality.LOW
	var plain := OctaAtlas.shader_variant(medium, true, 0)
	var refine := OctaAtlas.shader_variant(medium, true, 0, OctaAtlas.V_PARALLAX)
	_check(plain == OctaAtlas.SHADERS[medium], "parallax off keeps the shipped Medium shader resource")
	_check(refine != plain and refine.code.contains("#define PARALLAX_REFINE"), "parallax on is its own compile-time variant")
	_check(refine == OctaAtlas.shader_variant(medium, true, 0, OctaAtlas.V_PARALLAX), "the refine variant is cached")
	_check(OctaAtlas.shader_variant(low, false, 0, OctaAtlas.V_PARALLAX).code.contains("NO_DEPTH_WRITE") and OctaAtlas.shader_variant(low, false, 0, OctaAtlas.V_PARALLAX).code.contains("PARALLAX_REFINE"), "parallax combines with flat depth")
	_check(OctaAtlas.shader_variant(OctaAtlas.Quality.ULTRA, true, 0, OctaAtlas.V_PARALLAX) == OctaAtlas.SHADERS[OctaAtlas.Quality.ULTRA], "parallax is ignored by Ultra")
	_check(OctaAtlas.shader_variant(OctaAtlas.Quality.HIGH, true, 0, OctaAtlas.V_PARALLAX) == OctaAtlas.SHADERS[OctaAtlas.Quality.HIGH], "parallax is ignored at High (already 3 samples)")
	_check(OctaAtlas.shader_for(medium, true, 0, false, false, false, false, false, true) == refine and OctaAtlas.shader_for(OctaAtlas.Quality.HIGH, true, 0, false, false, false, false, false, true) == OctaAtlas.SHADERS[OctaAtlas.Quality.HIGH], "shader_for delegates its positional flags to shader_variant")

	var world := Node3D.new()
	root.add_child(world)
	var src := DemoObjects.rock(1)
	world.add_child(src)
	var results := {}
	var atlases := {}
	for on in [false, true]:
		var s := OctaBakeSettings.new()
		s.quality = medium
		s.parallax_refine = on
		var atlas := await OctaBaker.bake([src], root, s)
		atlases[on] = atlas
		_check(atlas.parallax_refine == on, "baker copies parallax_refine=%s to the atlas" % on)
		results[on] = await _measure(src, atlas, medium)
		print("ACCURACY rock medium parallax=%s: IoU %.4f, MAE %.2f, bad px %.2f%%" % [on, results[on].iou, results[on].mae, results[on].bad])
	var off_shader: Shader = atlases[false].get_material(medium).shader
	var on_shader: Shader = atlases[true].get_material(medium).shader
	_check(off_shader == plain and on_shader == refine and on_shader != off_shader, "materials use the plain / refine shader")
	_check(results[true].bad < results[false].bad, "parallax refine lowers bad pixels (%.2f%% vs %.2f%%)" % [results[true].bad, results[false].bad])
	var a: OctaAtlas = atlases[false]
	a.parallax_refine = true
	_check(a.get_material(medium).shader == refine and a.materials[medium].shader == refine, "setting parallax_refine swaps the shader on existing materials")
	a.parallax_refine = false
	_check(a.materials[medium].shader == plain, "and swaps it back")
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	for c in root.get_children():
		c.queue_free()
	await process_frame
	await process_frame
	quit(1 if _fails else 0)


func _measure(src: Node3D, atlas: OctaAtlas, quality: int) -> Dictionary:
	var b: Vector4 = OctaBaker._collect(src).bounds
	var c := Vector3(b.x, b.y, b.z)
	var real := TestRig.make(root)
	var fake := TestRig.make(root)
	var parent := src.get_parent()
	parent.remove_child(src)
	real.world.add_child(src)
	fake.world.add_child(atlas.create_card(0, quality))
	var iou := 0.0
	var mae := 0.0
	var bad := 0.0
	for v in VIEWS:
		var pitch := deg_to_rad(v[0])
		var yaw := deg_to_rad(v[1])
		var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
		for rig in [real, fake]:
			TestRig.shoot(rig, c + dir * b.w * v[2], c)
		await RenderingServer.frame_post_draw
		var r := TestRig.compare(TestRig.grab(real), TestRig.grab(fake))
		iou += r.iou
		mae += r.mae
		bad += r.bad
	real.world.remove_child(src)
	parent.add_child(src)
	real.vp.queue_free()
	fake.vp.queue_free()
	var n := float(VIEWS.size())
	return {iou = iou / n, mae = mae / n, bad = bad / n}
