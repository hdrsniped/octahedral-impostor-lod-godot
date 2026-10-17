extends SceneTree

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


# --- Joined cards with depth multiplier 0 keep their custom data ---
func _run() -> void:
	var src := DemoObjects.rock(3)
	root.add_child(src)
	var s := OctaBakeSettings.new()
	s.max_atlas_size = 1024
	var atlas := await OctaBaker.bake([src], root, s)
	var b: Vector4 = OctaBaker._collect(src).bounds
	var c := Vector3(b.x, b.y, b.z)
	src.free()

	var red := Color(1.0, 0.1, 0.1)
	var mm_flat := atlas.create_multimesh(0, [Transform3D.IDENTITY], OctaAtlas.Quality.HIGH, [Color(OctaAtlas.joined_custom(red, 1.0), 0.0)])
	var stored := mm_flat.multimesh.get_instance_custom_data(0)
	_check(stored.a > 0.0 and stored.a <= 0.01, "create_multimesh clamps depth 0 to %.3f (stored %.4f)" % [OctaAtlas.MIN_JOINED_DEPTH, stored.a])
	var mm_neg := atlas.create_multimesh(0, [Transform3D.IDENTITY], OctaAtlas.Quality.HIGH, [Color(1, 1, 1, -1.0)])
	_check(mm_neg.multimesh.get_instance_custom_data(0).a > 0.0, "negative depth is clamped too")
	_check(OctaAtlas.joined_custom(red, 0.0).a > 0.0, "joined_custom keeps depth above zero")
	var mm_full := atlas.create_multimesh(0, [Transform3D.IDENTITY], OctaAtlas.Quality.HIGH, [Color(red.r, red.g, red.b, 1.0)])
	_check(is_equal_approx(mm_full.multimesh.get_instance_custom_data(0).a, 1.0), "depth 1 is stored unchanged")
	mm_neg.free()
	mm_full.free()

	var rig_a := TestRig.make(root)
	var rig_b := TestRig.make(root)
	var rig_c := TestRig.make(root)
	rig_a.world.add_child(mm_flat)
	var card := atlas.create_card(0, OctaAtlas.Quality.HIGH)
	card.tint = red
	card.depth_multiplier = OctaAtlas.MIN_JOINED_DEPTH
	rig_b.world.add_child(card)
	var plain := atlas.create_card(0, OctaAtlas.Quality.HIGH)
	rig_c.world.add_child(plain)
	for az in [20.0, 140.0, 250.0]:
		var d := Vector3(cos(0.4) * sin(deg_to_rad(az)), sin(0.4), cos(0.4) * cos(deg_to_rad(az)))
		for rig in [rig_a, rig_b, rig_c]:
			TestRig.shoot(rig, c + d * b.w * 3.5, c)
		await RenderingServer.frame_post_draw
		var ia := TestRig.grab(rig_a)
		var ib := TestRig.grab(rig_b)
		var ic := TestRig.grab(rig_c)
		var r := TestRig.compare(ia, ib)
		var tint_diff := TestRig.compare(ia, ic)
		_check(r.iou > 0.97 and r.mae < 2.0 and tint_diff.mae > 20.0, "az %.0f: joined depth-0 instance matches a flat red card (IoU %.3f, MAE %.1f), not the untinted card (MAE %.1f)" % [az, r.iou, r.mae, tint_diff.mae])
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	for n in root.get_children():
		n.queue_free()
	await process_frame
	await process_frame
	quit(1 if _fails else 0)
