extends SceneTree

const SIZE := 256
const VIEWS := [
	[5.0, 0.0, 3.5], [20.0, 37.0, 3.5], [35.0, 110.0, 3.5], [60.0, 200.0, 3.5],
	[85.0, 300.0, 3.5], [15.0, 70.0, 10.0], [45.0, 250.0, 10.0], [-20.0, 30.0, 4.0],
]
const FAR_VIEWS := [
	[12.0, 17.0, 9.0], [28.0, 83.0, 11.0], [45.0, 151.0, 13.0], [62.0, 222.0, 16.0],
	[20.0, 291.0, 9.0], [38.0, 340.0, 11.0], [55.0, 41.0, 13.0], [8.0, 120.0, 16.0],
	[33.0, 195.0, 10.0], [70.0, 260.0, 12.0], [-15.0, 330.0, 11.0], [18.0, 60.0, 14.0],
]
const QNAMES := ["low", "medium", "high", "ultra"]
const EDGE_BAND := 2


var _views: Array = VIEWS
var _peak_video := 0.0


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
	settings.precise_search = _arg("precise", "0") == "1"
	settings.layer_tolerance = float(_arg("tol", "0.15"))
	settings.padding_px = int(_arg("pad", "2"))
	settings.half_res_material_maps = _arg("half", "1") == "1"
	settings.material_maps = _arg("maps", "1") == "1"
	settings.max_atlas_size = int(_arg("atlas", "2048"))
	var split := _arg("split", "0") == "1"
	settings.split_parts = split
	if _arg("far", "0") == "1":
		_views = FAR_VIEWS.map(func(v: Array) -> Array: return [v[0], v[1], v[2] * float(_arg("kscale", "1"))])
	var only := _arg("only", "")
	var tag := _arg("tag", "default")
	var pool := DemoObjects.all()
	if only == "textured" or _arg("textured", "0") == "1":
		pool.append(DemoObjects.textured())
	var objs := pool.filter(func(o: Node3D) -> bool: return only.is_empty() or String(o.name).to_lower() == only)
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
	print("SHADOWS %s (%s)" % ["on" if _shadows() else "off", RenderingServer.get_current_rendering_method()])
	var t0 := Time.get_ticks_msec()
	process_frame.connect(_sample_memory)
	var atlas := await OctaBaker.bake(sources, root, settings)
	process_frame.disconnect(_sample_memory)
	var bake_ms := Time.get_ticks_msec() - t0
	print("BAKE %d sources, grid %d, atlas %dx%d, frame %dpx, back %s, %d ms, peak video memory %.0f MB, peak RAM %.0f MB" % [sources.size(), atlas.grid_size,
		atlas.albedo.get_width(), atlas.albedo.get_height(), atlas.frame_resolution, settings.back_layer, bake_ms, _peak_video / 1048576.0, OS.get_static_memory_peak_usage() / 1048576.0])
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
		var sheet := Image.create_empty(SIZE * (nq + 1), SIZE * _views.size(), false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0.32, 0.34, 0.38))
		var stats := {}
		for qn in QNAMES:
			stats[qn] = []
		for vi in _views.size():
			var v: Array = _views[vi]
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
			var sums := {iou = 0.0, mae = 0.0, bad = 0.0, edge = 0.0, edge_comp = 0.0, fringe = 0.0}
			var worst_iou := 1.0
			for st in stats[qn]:
				for k in sums:
					sums[k] += st[k]
				worst_iou = minf(worst_iou, st.iou)
			var cnt: int = stats[qn].size()
			summary[qn] = {iou = snappedf(sums.iou / cnt, 0.001), worst_iou = snappedf(worst_iou, 0.001), mae = snappedf(sums.mae / cnt, 0.1),
				bad_pct = snappedf(sums.bad / cnt * 100.0, 0.1), edge_mae = snappedf(sums.edge / cnt, 0.01), edge_comp = snappedf(sums.edge_comp / cnt, 0.01), fringe = snappedf(sums.fringe / cnt, 0.01),
				per_view_iou = stats[qn].map(func(x): return snappedf(x.iou, 0.01))}
			print("%-6s %-7s IoU avg %.4f worst %.3f  colour MAE %.2f/255  bad px %.2f%%  edge MAE %.2f  edge composite %.2f  fringe %+.2f  views %s" % [src.name, qn, sums.iou / cnt, worst_iou, sums.mae / cnt, sums.bad / cnt * 100.0, sums.edge / cnt, sums.edge_comp / cnt, sums.fringe / cnt, summary[qn].per_view_iou])
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
func _sample_memory() -> void:
	_peak_video = maxf(_peak_video, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))


func _shadows() -> bool:
	var mode := _arg("shadows", "auto")
	if mode == "auto":
		return RenderingServer.get_current_rendering_method() != "gl_compatibility"
	return mode == "1"


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
	var inside := {}
	for y in SIZE:
		for x in SIZE:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var ia := ca.a > 0.5
			var ib := cb.a > 0.5
			if ia or ib:
				uni += 1
				inside[y * SIZE + x] = true
			if ia and ib:
				inter += 1
				var d := (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
				err += d
				if d > 0.15:
					bad += 1
	var edge_err := 0.0
	var edge_n := 0
	var comp_err := 0.0
	var comp_n := 0
	var edge_bias := 0.0
	var inner_bias := 0.0
	var inner_n := 0
	for key: int in inside:
		var x := key % SIZE
		var y := key / SIZE
		var ca := a.get_pixel(x, y)
		var cb := b.get_pixel(x, y)
		if not _on_rim(inside, x, y):
			if ca.a > 0.5 and cb.a > 0.5:
				inner_bias += cb.get_luminance() - ca.get_luminance()
				inner_n += 1
			continue
		comp_err += (absf(_over(ca).r - _over(cb).r) + absf(_over(ca).g - _over(cb).g) + absf(_over(ca).b - _over(cb).b)) / 3.0
		comp_n += 1
		if ca.a > 0.5 and cb.a > 0.5:
			edge_err += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			edge_bias += cb.get_luminance() - ca.get_luminance()
			edge_n += 1
	return {iou = float(inter) / maxf(uni, 1), mae = err / maxf(inter, 1) * 255.0, bad = float(bad + uni - inter) / maxf(uni, 1),
		edge = edge_err / maxf(edge_n, 1) * 255.0, edge_comp = comp_err / maxf(comp_n, 1) * 255.0,
		fringe = (edge_bias / maxf(edge_n, 1) - inner_bias / maxf(inner_n, 1)) * 255.0}


func _on_rim(inside: Dictionary, x: int, y: int) -> bool:
	for dy in range(-EDGE_BAND, EDGE_BAND + 1):
		for dx in range(-EDGE_BAND, EDGE_BAND + 1):
			var nx := x + dx
			var ny := y + dy
			if nx < 0 or ny < 0 or nx >= SIZE or ny >= SIZE or not inside.has(ny * SIZE + nx):
				return true
	return false


func _over(c: Color) -> Color:
	return Color(c.r * c.a + 0.5 * (1.0 - c.a), c.g * c.a + 0.5 * (1.0 - c.a), c.b * c.a + 0.5 * (1.0 - c.a))


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
	sun.shadow_enabled = _shadows()
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	world.add_child(cam)
	cam.current = true
	return {vp = vp, world = world, cam = cam}
