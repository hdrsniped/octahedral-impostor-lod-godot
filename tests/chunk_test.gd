extends SceneTree

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


# --- Chunk LOD: one card for the whole group beyond a distance ---
func _run() -> void:
	var group := OctaImpostorGroup.new()
	group.name = "Chunk"
	root.add_child(group)
	var targets: Array[Node3D] = []
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.name = "Prop%d" % i
		mi.mesh = BoxMesh.new()
		mi.position = Vector3(i * 3.0, 0.0, 0.0)
		group.add_child(mi)
		targets.append(mi)
	group.chunk_lod_distance = 50.0
	group.settings.grid_size = 8
	group.settings.max_atlas_size = 1024
	_check(group.target_nodes().size() == 3, "group holds three props")

	var chunk_atlas := await OctaBaker.bake([group], root, group.settings)
	_check(chunk_atlas != null and chunk_atlas.object_count() == 1, "the whole group bakes as one object")
	var whole: Vector4 = chunk_atlas.bounds[0]
	_check(whole.w > 3.4, "the chunk card covers the group (radius %.2f)" % whole.w)
	var obj_atlas := await OctaBaker.bake(targets, root, group.settings)
	_check(not OctaPacker.compatible(chunk_atlas, obj_atlas), "the group atlas and the object atlas have different view sizes (%d vs %d)" % [chunk_atlas.frame_resolution, obj_atlas.frame_resolution])
	var cards: Array[Node3D] = []
	for i in targets.size():
		var c := obj_atlas.create_card(i, OctaAtlas.Quality.HIGH)
		c.set_meta(OctaLOD.SOURCE_META, NodePath(".."))
		c.set_meta(OctaLOD.MODE_META, OctaLOD.Mode.DYNAMIC_LOD)
		targets[i].add_child(c)
		cards.append(c)
	_check(group.cards().size() == 3, "group finds its three object cards")

	var cc := group.attach_chunk(chunk_atlas, group.chunk_settings(), 50.0)
	_check(cc != null and group.chunk_card() == cc, "attach_chunk adds the chunk card as a child of the group")
	_check(group.cards().size() == 4 and group.chunk_atlas == chunk_atlas, "the group knows its chunk atlas and card")
	_check(is_equal_approx(cc.visibility_range_begin, 50.0), "chunk card starts at the chunk distance (%.2f)" % cc.visibility_range_begin)
	_check(cards.all(func(c: Node3D) -> bool: return is_equal_approx(c.visibility_range_end, 50.0)), "object cards stop at the chunk distance")
	_check(cc.quality == group.chunk_quality and cc.atlas == chunk_atlas, "chunk card uses the chunk quality and atlas")

	var iou := await _measure(group, chunk_atlas, 50.0 * 1.1)
	print("ACCURACY chunk card vs real group at 55 m: IoU %.4f, MAE %.2f, bad px %.2f%%" % [iou.iou, iou.mae, iou.bad])
	_check(iou.iou > 0.85, "the chunk card matches the real group at the switch distance")

	var settings := group.chunk_settings()
	_check(settings.lod_mode == OctaLOD.LodMode.DISTANCE and is_equal_approx(settings.lod_distance, 50.0) and settings.fade == OctaLOD.Fade.NONE and settings.mode == OctaLOD.Mode.DYNAMIC_LOD, "chunk settings come from the group")

	group.detach_chunk()
	_check(group.chunk_card() == null and group.cards().size() == 3, "detach_chunk removes the card")
	_check(cards.all(func(c: Node3D) -> bool: return is_equal_approx(c.visibility_range_end, 0.0)), "detach_chunk restores the object cards")

	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	for c in root.get_children():
		c.queue_free()
	await process_frame
	await process_frame
	quit(1 if _fails else 0)


func _measure(group: OctaImpostorGroup, chunk_atlas: OctaAtlas, distance: float) -> Dictionary:
	var b: Vector4 = OctaBaker._collect(group).bounds
	var c := Vector3(b.x, b.y, b.z)
	var real := TestRig.make(root)
	var fake := TestRig.make(root)
	var parent := group.get_parent()
	parent.remove_child(group)
	real.world.add_child(group)
	fake.world.add_child(chunk_atlas.create_card(0, group.chunk_quality))
	var dir := Vector3(0.35, 0.45, 1.0).normalized()
	for rig in [real, fake]:
		TestRig.shoot(rig, c + dir * distance, c)
	await RenderingServer.frame_post_draw
	var r := TestRig.compare(TestRig.grab(real), TestRig.grab(fake))
	real.world.remove_child(group)
	parent.add_child(group)
	real.vp.queue_free()
	fake.vp.queue_free()
	return r
