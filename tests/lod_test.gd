extends SceneTree

const LOD_DIST := 40.0
const DISTANCES := [8.0, 18.0, 30.0, 36.0, 46.0, 60.0, 85.0, 120.0]

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


# --- Save, LOD switching, MultiMesh, modes, compression ---
func _run() -> void:
	var path := "res://tests/out/lod_atlas.res"
	var bake_sources := [DemoObjects.rock(3), DemoObjects.tree()]
	var baked := await OctaBaker.bake_to_file(bake_sources, root, path)
	for n: Node in bake_sources:
		n.free()
	_check(baked != null and FileAccess.file_exists(path), "atlas saved to %s (%d KB)" % [path, FileAccess.get_file_as_bytes(path).size() / 1024])
	var atlas: OctaAtlas = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(atlas != null and atlas.object_count() == 2 and atlas.object_names == PackedStringArray(["Rock", "Tree"]), "atlas reloads with 2 objects")
	_check(atlas.albedo.get_image().has_mipmaps() and atlas.normal_depth.get_image().has_mipmaps(), "reloaded textures keep mipmaps")
	_check(atlas.get_material(OctaAtlas.Quality.HIGH) == atlas.get_material(OctaAtlas.Quality.HIGH), "one shared material per quality")

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 360)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.1, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40
	cam.far = 500
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.0, 0), Vector3(0, 1.0, 10))

	atlas.get_material(OctaAtlas.Quality.HIGH).set_shader_parameter("tint", Color(1.0, 0.1, 0.1))
	var rocks: Array[Node3D] = []
	for i in DISTANCES.size():
		var rock := DemoObjects.rock(3)
		var d: float = DISTANCES[i]
		var x := (i - 3.5) * d * 0.09
		rock.position = Vector3(x, 0, d)
		var s := d / 12.0
		rock.scale = Vector3.ONE * s
		vp.add_child(rock)
		OctaLOD.attach_card(rock, atlas, 0, OctaLOD.Mode.DYNAMIC_LOD, LOD_DIST)
		rocks.append(rock)
	for i in 10:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png("res://tests/out/lod_row.png")
	for i in rocks.size():
		var rock := rocks[i]
		var card: MeshInstance3D = rock.get_node("OctaImpostor")
		var b := atlas.bounds[0]
		var center := rock.global_transform * Vector3(b.x, b.y, b.z)
		var px := Vector2i(cam.unproject_position(center))
		var red := _red_fraction(img, px, 6)
		var dist := cam.global_position.distance_to(card.global_transform * Vector3(b.x, b.y, b.z))
		var want_card := dist > LOD_DIST
		_check((red > 0.5) == want_card, "rock at %.0f m shows %s (red %.2f)" % [dist, "card" if red > 0.5 else "mesh", red])

	for r in rocks:
		r.queue_free()
	var xfs := []
	for i in 500:
		xfs.append(Transform3D(Basis(), Vector3((i % 25 - 12) * 3.0, 0, 20 + (i / 25) * 3.0)))
	var mmi := atlas.create_multimesh(1, xfs)
	vp.add_child(mmi)
	for i in 4:
		await RenderingServer.frame_post_draw
	var mm_img := vp.get_texture().get_image()
	mm_img.save_png("res://tests/out/lod_multimesh.png")
	_check(_red_fraction(mm_img, Vector2i(640, 180), 600) > 0.05, "MultiMesh of 500 tree cards renders")

	var holder := Node3D.new()
	vp.add_child(holder)
	var src := DemoObjects.tree()
	src.position = Vector3(3, 0, 7)
	src.rotation.y = 0.7
	holder.add_child(src)
	var dup := OctaLOD.attach_card(src, atlas, 1, OctaLOD.Mode.DUPLICATE)
	_check(dup.get_parent() == holder and dup.transform.is_equal_approx(src.transform) and src.visible, "DUPLICATE card is a sibling with the same transform")

	var rock_root := DemoObjects.rock(3)
	var mesh_src: MeshInstance3D = rock_root.get_child(0)
	rock_root.remove_child(mesh_src)
	rock_root.free()
	mesh_src.position = Vector3(0, 0, 70)
	mesh_src.scale = Vector3.ONE * 5.0
	holder.add_child(mesh_src)
	var sib := OctaLOD.attach_card(mesh_src, atlas, 0, OctaLOD.Mode.DYNAMIC_LOD, LOD_DIST)
	_check(sib.get_parent() == holder and mesh_src.get_node_or_null(mesh_src.visibility_parent) == sib, "mesh source links to a sibling card")
	mmi.queue_free()
	for c in holder.get_children():
		if c != mesh_src and c != sib:
			c.queue_free()
	for i in 4:
		await RenderingServer.frame_post_draw
	var far_img := vp.get_texture().get_image()
	var b0 := atlas.bounds[0]
	var px := Vector2i(cam.unproject_position(mesh_src.global_transform * Vector3(b0.x, b0.y, b0.z)))
	_check(_red_fraction(far_img, px, 6) > 0.5, "mesh source beyond LOD distance shows its card")

	var rep := DemoObjects.tree()
	holder.add_child(rep)
	OctaLOD.attach_card(rep, atlas, 1, OctaLOD.Mode.REPLACE)
	_check(not rep.visible and OctaLOD.find_cards(rep).size() == 1, "REPLACE hides the source and the card is found")
	OctaLOD.remove_cards(rep)
	_check(rep.visible and OctaLOD.find_cards(rep).is_empty(), "remove_cards() shows a replaced source again")
	var lod_src := DemoObjects.rock(2)
	holder.add_child(lod_src)
	OctaLOD.attach_card(lod_src, atlas, 0)
	OctaLOD.remove_cards(lod_src)
	var linked := OctaLOD.geometry_below(lod_src).filter(func(g: GeometryInstance3D) -> bool: return not g.visibility_parent.is_empty())
	_check(linked.is_empty() and OctaLOD.find_cards(lod_src).is_empty(), "remove_cards() clears LOD links")

	var vram := OctaBakeSettings.new()
	vram.compression = OctaBakeSettings.Compression.VRAM
	vram.max_atlas_size = 1024
	var vsrc := [DemoObjects.rock(4)]
	var vpath := "res://tests/out/lod_atlas_vram.res"
	var vbaked := await OctaBaker.bake_to_file(vsrc, root, vpath, vram)
	vsrc[0].free()
	var vatlas: OctaAtlas = ResourceLoader.load(vpath, "", ResourceLoader.CACHE_MODE_IGNORE) if vbaked else null
	_check(vatlas != null and (vatlas.albedo as PortableCompressedTexture2D).get_compression_mode() == PortableCompressedTexture2D.COMPRESSION_MODE_BASIS_UNIVERSAL,
			"VRAM-compressed atlas saved (%d KB) and reloaded" % (FileAccess.get_file_as_bytes(vpath).size() / 1024))

	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	await _clean_quit(1 if _fails else 0)


# --- Helpers ---
func _red_fraction(img: Image, c: Vector2i, half: int) -> float:
	var red := 0
	var lit := 0
	for y in range(c.y - half, c.y + half + 1):
		for x in range(c.x - half, c.x + half + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var p := img.get_pixel(x, y)
			if p.r + p.g + p.b < 0.45:
				continue
			lit += 1
			if p.r > p.g * 2.0 and p.r > p.b * 2.0:
				red += 1
	return float(red) / maxf(lit, 1)


func _clean_quit(code: int) -> void:
	for c in root.get_children():
		c.queue_free()
	await process_frame
	await process_frame
	quit(code)
