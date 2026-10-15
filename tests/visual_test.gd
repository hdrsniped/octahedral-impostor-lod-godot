extends SceneTree

const SIZE := 256
const VIEWS := [
	[5.0, 0.0, 3.5], [20.0, 37.0, 3.5], [35.0, 110.0, 3.5], [60.0, 200.0, 3.5],
	[85.0, 300.0, 3.5], [15.0, 70.0, 10.0], [45.0, 250.0, 10.0], [-20.0, 30.0, 4.0],
]
const QNAMES := ["low", "medium", "high", "ultra"]


func _initialize() -> void:
	_run.call_deferred()


func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.split("=", true, 1)[1]
	return def


# --- Accuracy against the real mesh ---
func _run() -> void:
	var settings := OctaBakeSettings.new()
	settings.grid_size = int(_arg("grid", "12"))
	settings.hemisphere = _arg("hemi", "1") == "1"
	settings.back_layer = _arg("back", "0") == "1"
	settings.search_steps = int(_arg("steps", "8"))
	settings.layer_tolerance = float(_arg("tol", "0.15"))
	var split := _arg("split", "0") == "1"
	settings.split_parts = split
	var only := _arg("only", "")
	var tag := _arg("tag", "default")
	var objs := DemoObjects.all().filter(func(o: Node3D) -> bool: return only.is_empty() or String(o.name).to_lower() == only)
	var groups := []
	var sources: Array[Node3D] = []
	for o: Node3D in objs:
		var parts: Array[Node3D] = [o]
		if split:
			parts = OctaLOD.split_parts([o])
		var g := []
		for p in parts:
			g.append({index = sources.size(), part = p})
			sources.append(p)
		groups.append(g)
	var t0 := Time.get_ticks_msec()
	var atlas := await OctaBaker.bake(sources, root, settings)
	var bake_ms := Time.get_ticks_msec() - t0
	print("BAKE %d sources, grid %d, atlas %dx%d, frame %dpx, back %s, %d ms" % [sources.size(), atlas.grid_size,
		atlas.albedo.get_width(), atlas.albedo.get_height(), atlas.frame_resolution, settings.back_layer, bake_ms])
	var ia := atlas.albedo.get_image()
	ia.clear_mipmaps()
	ia.save_png("res://tests/out/%s_atlas_albedo.png" % tag)
	var inn := atlas.normal_depth.get_image()
	inn.clear_mipmaps()
	inn.save_png("res://tests/out/%s_atlas_normal_depth.png" % tag)

	var nq := QNAMES.size()
	var rigs := []
	for i in nq + 1:
		rigs.append(_make_rig())
	var report := {bake_ms = bake_ms, objects = {}}
	for oi in objs.size():
		var src: Node3D = objs[oi]
		var fb: Vector4 = OctaBaker._collect(src).bounds
		for part in groups[oi]:
			part.xform = _relative(src, part.part.get_parent()) * atlas.card_transform(part.part) if split else Transform3D.IDENTITY
		rigs[0].world.add_child(src)
		for q in nq:
			for part in groups[oi]:
				var card := atlas.create_card(part.index, q)
				card.transform = part.xform
				rigs[q + 1].world.add_child(card)
		var c := Vector3(fb.x, fb.y, fb.z)
		var sheet := Image.create_empty(SIZE * (nq + 1), SIZE * VIEWS.size(), false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0.32, 0.34, 0.38))
		var stats := {}
		for qn in QNAMES:
			stats[qn] = []
		for vi in VIEWS.size():
			var v: Array = VIEWS[vi]
			var e := deg_to_rad(v[0])
			var az := deg_to_rad(v[1])
			var dir := Vector3(cos(e) * sin(az), sin(e), cos(e) * cos(az))
			var pos: Vector3 = c + dir * fb.w * float(v[2])
			for rig in rigs:
				rig.cam.look_at_from_position(pos, c, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
				rig.vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			var imgs := []
			for rig in rigs:
				var im: Image = rig.vp.get_texture().get_image()
				im.convert(Image.FORMAT_RGBA8)
				imgs.append(im)
			for col in nq + 1:
				sheet.blend_rect(imgs[col], Rect2i(0, 0, SIZE, SIZE), Vector2i(col * SIZE, vi * SIZE))
				if col > 0:
					stats[QNAMES[col - 1]].append(_compare(imgs[0], imgs[col]))
		sheet.save_png("res://tests/out/%s_sheet_%s.png" % [tag, src.name.to_lower()])
		var summary := {}
		for qn in QNAMES:
			var iou := 0.0
			var mae := 0.0
			var bad := 0.0
			var worst_iou := 1.0
			for st in stats[qn]:
				iou += st.iou
				mae += st.mae
				bad += st.bad
				worst_iou = minf(worst_iou, st.iou)
			var cnt: int = stats[qn].size()
			summary[qn] = {iou = snappedf(iou / cnt, 0.001), worst_iou = snappedf(worst_iou, 0.001), mae = snappedf(mae / cnt, 0.1),
				bad_pct = snappedf(bad / cnt * 100.0, 0.1), per_view_iou = stats[qn].map(func(x): return snappedf(x.iou, 0.01))}
			print("%-6s %-7s IoU avg %.3f worst %.3f  colour MAE %.1f/255  bad px %.1f%%  views %s" % [src.name, qn, iou / cnt, worst_iou, mae / cnt, bad / cnt * 100.0, summary[qn].per_view_iou])
		report.objects[String(src.name)] = summary
		rigs[0].world.remove_child(src)
		src.free()
		for q in nq:
			for ch in rigs[q + 1].world.get_children():
				if ch.has_meta(OctaAtlas.CARD_META):
					ch.queue_free()
		await process_frame
	var f := FileAccess.open("res://tests/out/%s_report.json" % tag, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("DONE")
	for ch in root.get_children():
		ch.queue_free()
	await process_frame
	await process_frame
	quit()


# --- Helpers ---
func _relative(top: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != top and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _compare(a: Image, b: Image) -> Dictionary:
	var inter := 0
	var uni := 0
	var err := 0.0
	var bad := 0
	for y in SIZE:
		for x in SIZE:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var ia := ca.a > 0.5
			var ib := cb.a > 0.5
			if ia or ib:
				uni += 1
			if ia and ib:
				inter += 1
				var d := (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
				err += d
				if d > 0.15:
					bad += 1
	return {iou = float(inter) / maxf(uni, 1), mae = err / maxf(inter, 1) * 255.0, bad = float(bad + uni - inter) / maxf(uni, 1)}


func _make_rig() -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = _arg("shadows", "1") == "1"
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	world.add_child(cam)
	cam.current = true
	return {vp = vp, world = world, cam = cam}
