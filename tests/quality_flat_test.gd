extends SceneTree

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


# --- Quality check with and without depth write ---
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	for v in [[true, false], [false, false], [true, true], [false, true]]:
		var depth: bool = v[0]
		var s := OctaBakeSettings.new()
		s.max_atlas_size = 1024
		s.write_depth = depth
		s.fade = OctaLOD.Fade.CROSSFADE if v[1] else OctaLOD.Fade.NONE
		s.fade_margin = 4.0
		s.lod_mode = OctaLOD.LodMode.SCREEN_SIZE
		s.lod_screen_percent = 10.0
		var ball := MeshInstance3D.new()
		ball.mesh = SphereMesh.new()
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.8, 0.3, 0.2)
		ball.mesh.material = m
		world.add_child(ball)
		var atlas := await OctaLOD.generate([ball], world, s)
		var q: Dictionary = await OctaQuality.measure(ball, root)
		_check(not q.has("error") and q.iou > 0.8, "write_depth=%s fade=%s: match %.2f, wrong %.1f%%" % [depth, v[1], q.get("iou", 0.0), q.get("bad_pct", 100.0)])
		ball.free()
		for c in world.get_children():
			c.free()
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	for c in root.get_children():
		c.queue_free()
	await process_frame
	quit(1 if _fails else 0)
