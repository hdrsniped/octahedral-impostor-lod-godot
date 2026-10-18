extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


var _fails := 0


# --- Packing separately baked atlases ---
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var rock := DemoObjects.rock(1)
	var tree := DemoObjects.tree()
	world.add_child(rock)
	world.add_child(tree)
	var s := OctaBakeSettings.new()
	s.grid_size = 8
	s.max_atlas_size = 1024
	var a1 := await OctaBaker.bake([rock], root, s)
	var a2 := await OctaBaker.bake([tree], root, s)
	_check(a1 != null and a2 != null and a1.object_count() == 1 and a2.object_count() == 1, "two single-object atlases baked")
	_check(OctaPacker.compatible(a1, a2), "same settings are compatible")
	var map := {}
	var packed := OctaPacker.pack([a1, a2], 4096, map)
	_check(packed.size() == 1, "two atlases pack into one (%d)" % packed.size())
	if packed.size() != 1:
		_finish()
		return
	var p: OctaAtlas = packed[0]
	_check(p.object_count() == 2, "packed atlas holds both objects")
	_check(p.tiles == Vector2i(2, 1), "packed tiles are 2x1 (%s)" % p.tiles)
	_check(p.grid_size == 8 and p.frame_resolution == a1.frame_resolution, "grid and view size kept")
	_check(p.object_names == PackedStringArray([a1.object_names[0], a2.object_names[0]]), "object names kept in order")
	_check(p.bounds[0] == a1.bounds[0] and p.bounds[1] == a2.bounds[0], "bounds kept")
	_check(p.material_params[0] == a1.material_params[0] and p.material_params[1] == a2.material_params[0], "material params kept")
	_check(map.has(a1) and map[a1][0][0] == p and map[a1][0][1] == 0 and map[a2][0][0] == p and map[a2][0][1] == 1, "pack map points every source object at its new slot")

	var block := 8 * a1.frame_resolution
	var src_a := a1.albedo.get_image()
	var src_n := a1.normal_depth.get_image()
	var dst_a := p.albedo.get_image()
	var dst_n := p.normal_depth.get_image()
	_check(_same_rect(src_a, Rect2i(0, 0, block, block), dst_a, Vector2i(0, 0)), "first object's albedo tile copied exactly")
	var src2 := a2.albedo.get_image()
	_check(_same_rect(src2, Rect2i(0, 0, block, block), dst_a, Vector2i(block, 0)), "second object's albedo tile copied exactly")
	_check(_same_rect(src_n, Rect2i(0, 0, block, block), dst_n, Vector2i(0, 0)), "normal/depth tile copied exactly")
	_check(p.albedo.get_image().has_mipmaps(), "packed albedo has mipmaps")
	_check(p.get_material(OctaAtlas.Quality.HIGH) != null, "packed atlas builds its material")

	var d0 := await _grab(a1, 0, rock)
	var d1 := await _grab(p, 0, rock)
	var cmp := TestRig.compare(d0, d1)
	_check(cmp.iou == 1.0 and cmp.mae < 0.01, "card from the packed atlas renders identically (IoU %.4f, MAE %.3f)" % [cmp.iou, cmp.mae])

	var other := OctaBakeSettings.new()
	other.grid_size = 12
	var a3 := await OctaBaker.bake([DemoObjects.rings()], root, other)
	_check(not OctaPacker.compatible(a1, a3), "different grid sizes are incompatible")
	var kept := OctaPacker.pack([a1, a3], 4096)
	_check(kept.size() == 2 and kept[0].object_count() == 1 and kept[1].object_count() == 1, "incompatible atlases stay separate")

	var big := OctaPacker.pack([a1, a2], a1.tiles.x * 8 * a1.frame_resolution + 8)
	_check(big.size() == 2, "one atlas per slice when the maximum side is too small (%d)" % big.size())

	var three := await OctaBaker.bake([DemoObjects.rock(1), DemoObjects.rock(2), DemoObjects.rock(3)], root, s)
	_check(three.object_count() == 3 and three.tiles.x * three.tiles.y > 3, "three objects bake into a grid with an empty slot (%s)" % three.tiles)
	var two := await OctaBaker.bake([DemoObjects.tree(), DemoObjects.rings()], root, s)
	var many := OctaPacker.pack([three, two], 4096)
	_check(many.size() == 1 and many[0].object_count() == 5, "an atlas with an empty grid slot packs into 5 objects (%d)" % (many[0].object_count() if not many.is_empty() else -1))
	if not many.is_empty():
		var names := many[0].object_names
		_check(names.size() == 5 and names[0] == three.object_names[0] and names[4] == two.object_names[1], "packed names follow the object order")

	var old_a := load("res://tests/fixtures/v2_all.res") as OctaAtlas
	_check(old_a != null and old_a.format_version < OctaAtlas.FORMAT_VERSION, "loaded an old-format atlas (format %d)" % (old_a.format_version if old_a != null else -1))
	var old_pack := OctaPacker.pack([old_a, old_a], 4096)
	_check(old_pack.size() == 1 and old_pack[0].object_count() == old_a.object_count() * 2, "old-format atlases pack into one shared atlas")
	_check(not old_pack.is_empty() and old_pack[0].format_version == old_a.format_version, "the packed atlas keeps the old format version")
	_check(not old_pack.is_empty() and old_pack[0].material_params[0].z > 0.5, "old-format objects get the AO default instead of 0")
	_check(not OctaPacker.compatible(old_a, a1), "old and new atlases are not mixed")
	_finish()


func _same_rect(a: Image, r: Rect2i, b: Image, at: Vector2i) -> bool:
	for y in r.size.y:
		for x in r.size.x:
			if a.get_pixel(r.position.x + x, r.position.y + y) != b.get_pixel(at.x + x, at.y + y):
				return false
	return true


func _grab(atlas: OctaAtlas, index: int, src: Node3D) -> Image:
	var b: Vector4 = OctaBaker._collect(src).bounds
	var c := Vector3(b.x, b.y, b.z)
	var dir := Vector3(0.4, 0.5, 1.0).normalized()
	var rig := TestRig.make(root)
	rig.world.add_child(atlas.create_card(index))
	TestRig.shoot(rig, c + dir * b.w * 3.5, c)
	await RenderingServer.frame_post_draw
	var img := TestRig.grab(rig)
	rig.vp.queue_free()
	return img


func _finish() -> void:
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	for c in root.get_children():
		c.queue_free()
	await process_frame
	await process_frame
	quit(1 if _fails else 0)
