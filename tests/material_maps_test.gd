extends SceneTree

const VIEWS := [Vector3(5, 0, 3.5), Vector3(20, 37, 3.5), Vector3(35, 110, 3.5), Vector3(60, 200, 3.5), Vector3(85, 300, 3.5), Vector3(15, 70, 10), Vector3(45, 250, 10), Vector3(-20, 30, 4)]
const MAX_RELATIVE_MAE := 0.05
const MAX_CONSTANT_DIFF := 1.0
const MAX_BORDER_ALPHA := 0.1
const MAX_ALIGN_ERROR := 0.03

var _fails := 0
var _world: Node3D
var _shadows := true


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


# --- Constant skip, half-res maps ---
func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_shadows = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	print("RENDERER %s, shadows %s" % [RenderingServer.get_current_rendering_method(), _shadows])
	await _constants()
	await _mixed()
	await _textured()
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	for c in root.get_children():
		c.queue_free()
	await process_frame
	await process_frame
	quit(1 if _fails else 0)


func _bake(src: Node3D, half: bool, size := 1024, maps := true) -> OctaAtlas:
	var s := OctaBakeSettings.new()
	s.max_atlas_size = size
	s.half_res_material_maps = half
	s.material_maps = maps
	return await OctaBaker.bake([src], root, s)


func _mb(bytes: int) -> String:
	return "%.2f MB" % (bytes / 1048576.0)


func _constants() -> void:
	for src: Node3D in DemoObjects.all():
		var oname := String(src.name)
		_world.add_child(src)
		var plain := await _bake(src, true)
		var d := plain.object_data().get_image()
		_check(plain.format_version == OctaAtlas.FORMAT_VERSION and plain.orm == null and is_equal_approx(d.get_pixel(3, 0).b, 1.0) and plain.emission == null,
				"%s: constant materials skip the ORM atlas and store AO 1 in obj_data (format %d)" % [oname, plain.format_version])
		var surf := d.get_pixel(1, 0)
		var forced_src := _forced_orm(src)
		_world.add_child(forced_src)
		_world.remove_child(src)
		var full := await _bake(forced_src, false)
		var half := await _bake(forced_src, true)
		_check(full.orm != null and half.orm != null and half.orm.get_width() < full.orm.get_width(), "%s: a roughness texture forces the ORM atlas (full %dx%d, half %dx%d)" % [oname, full.orm.get_width(), full.orm.get_height(), half.orm.get_width(), half.orm.get_height()])
		print("VRAM %s (1024 atlas): constants %s, ORM full-res %s, ORM half-res %s: skipping saves %.1f%% of the full-res total and %.1f%% of the half-res total" % [
				oname, _mb(plain.vram_bytes()), _mb(full.vram_bytes()), _mb(half.vram_bytes()),
				100.0 * (1.0 - float(plain.vram_bytes()) / full.vram_bytes()), 100.0 * (1.0 - float(plain.vram_bytes()) / half.vram_bytes())])
		var diff := 0.0
		var rig_a := TestRig.make(root, _shadows)
		var rig_b := TestRig.make(root, _shadows)
		var card_a := plain.create_card(0, OctaAtlas.Quality.HIGH)
		var card_b := full.create_card(0, OctaAtlas.Quality.HIGH)
		rig_a.world.add_child(card_a)
		rig_b.world.add_child(card_b)
		var b := plain.bounds[0]
		for v: Vector3 in VIEWS:
			var dir := _dir(v)
			TestRig.shoot(rig_a, Vector3(b.x, b.y, b.z) + dir * b.w * v.z, Vector3(b.x, b.y, b.z))
			TestRig.shoot(rig_b, Vector3(b.x, b.y, b.z) + dir * b.w * v.z, Vector3(b.x, b.y, b.z))
			await RenderingServer.frame_post_draw
			diff += TestRig.difference(TestRig.grab(rig_a), TestRig.grab(rig_b)) / VIEWS.size()
		print("ACCURACY %s: constants card vs ORM card (same values, per pixel map): mean colour difference %.3f/255, surface constants %s" % [oname, diff, surf])
		_check(diff < MAX_CONSTANT_DIFF, "%s: card with per-object constants matches the card with a baked ORM map (%.3f/255 < %.1f)" % [oname, diff, MAX_CONSTANT_DIFF])
		rig_a.vp.queue_free()
		rig_b.vp.queue_free()
		forced_src.free()
		src.free()


func _mixed() -> void:
	var holder := Node3D.new()
	_world.add_child(holder)
	var matte := StandardMaterial3D.new()
	matte.roughness = 1.0
	var chrome := StandardMaterial3D.new()
	chrome.roughness = 0.1
	chrome.metallic = 1.0
	var close := StandardMaterial3D.new()
	close.roughness = 1.0 - OctaBaker.CONSTANT_TOLERANCE * 0.5
	for pair in [[matte, chrome, true], [matte, close, false]]:
		var node := Node3D.new()
		for i in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = BoxMesh.new()
			mi.position.x = i * 1.5
			mi.material_override = pair[i]
			node.add_child(mi)
		node.name = "Mixed"
		holder.add_child(node)
		var atlas := await _bake(node, true, 256)
		_check((atlas.orm != null) == pair[2], "objects whose materials disagree keep the ORM map, agreeing ones do not (needs map %s, got %s)" % [pair[2], atlas.orm != null])
		holder.remove_child(node)
		node.free()
	holder.free()


func _textured() -> void:
	var src := DemoObjects.textured()
	_world.add_child(src)
	var full := await _bake(src, false, 2048)
	var half := await _bake(src, true, 2048)
	_check(full.orm != null and full.emission != null and half.orm != null and half.emission != null, "textured object bakes an ORM and an emission map")
	_check(half.has_half_res_maps() and not full.has_half_res_maps(), "half-res detection from the texture sizes")
	var maps_full := _bytes(full.orm) + _bytes(full.emission)
	var maps_half := _bytes(half.orm) + _bytes(half.emission)
	print("VRAM Textured (2048 atlas): maps full %s -> half %s (saved %.1f%%), whole atlas %s -> %s (saved %.1f%%)" % [
			_mb(maps_full), _mb(maps_half), 100.0 * (1.0 - float(maps_half) / maps_full), _mb(full.vram_bytes()), _mb(half.vram_bytes()), 100.0 * (1.0 - float(half.vram_bytes()) / full.vram_bytes())])
	_check(float(maps_half) / maps_full < 0.27, "half-res maps use about a quarter of the memory")
	for t: Texture2D in [half.orm, half.emission]:
		var img := t.get_image()
		img.clear_mipmaps()
		var frame := OctaBaker.map_frame_resolution(half.frame_resolution, true)
		var ref := full.albedo.get_image()
		ref.clear_mipmaps()
		ref.resize(img.get_width(), img.get_height(), Image.INTERPOLATE_BILINEAR)
		var err := 0.0
		for y in img.get_height():
			for x in img.get_width():
				err += absf(img.get_pixel(x, y).a - ref.get_pixel(x, y).a)
		err /= img.get_width() * img.get_height()
		var border := 0.0
		var n := half.grid_size
		for fy in n:
			for fx in n:
				for k in frame:
					for p: Vector2i in [Vector2i(k, 0), Vector2i(k, frame - 1), Vector2i(0, k), Vector2i(frame - 1, k)]:
						border = maxf(border, img.get_pixel(fx * frame + p.x, fy * frame + p.y).a)
		var label := "ORM" if t == half.orm else "emission"
		print("LAYOUT half-res %s: %dx%d vs albedo %dx%d, coverage alignment error %.4f, max alpha on frame borders %.3f" % [label, img.get_width(), img.get_height(), full.albedo.get_width(), full.albedo.get_height(), err, border])
		_check(err < MAX_ALIGN_ERROR and border < MAX_BORDER_ALPHA, "half-res %s lines up with the full-res tile layout and nothing bleeds across frames" % label)
	var c := Vector3(full.bounds[0].x, full.bounds[0].y, full.bounds[0].z)
	var radius := full.bounds[0].w
	var real := TestRig.make(root, _shadows)
	var rigs := {}
	for key in ["full", "half"]:
		rigs[key] = TestRig.make(root, _shadows)
	var qualities := [OctaAtlas.Quality.HIGH, OctaAtlas.Quality.ULTRA]
	var res := {}
	var between := {}
	_world.remove_child(src)
	real.world.add_child(src)
	for q in qualities:
		var cards := {}
		for key in rigs:
			for ch in rigs[key].world.get_children():
				if ch.has_meta(OctaAtlas.CARD_META):
					ch.free()
			cards[key] = (full if key == "full" else half).create_card(0, q)
			rigs[key].world.add_child(cards[key])
		var stats := {full = {mae = 0.0, bad = 0.0, iou = 0.0}, half = {mae = 0.0, bad = 0.0, iou = 0.0}}
		var gap := 0.0
		for v: Vector3 in VIEWS:
			var pos := c + _dir(v) * radius * v.z
			TestRig.shoot(real, pos, c)
			for key in rigs:
				TestRig.shoot(rigs[key], pos, c)
			await RenderingServer.frame_post_draw
			var ri := TestRig.grab(real)
			var imgs := {}
			for key in rigs:
				imgs[key] = TestRig.grab(rigs[key])
				var r := TestRig.compare(ri, imgs[key])
				for k in stats[key]:
					stats[key][k] += r[k] / VIEWS.size()
			gap += TestRig.difference(imgs.full, imgs.half) / VIEWS.size()
		res[q] = stats
		between[q] = gap
		var rel_mae: float = stats.half.mae / stats.full.mae - 1.0
		var rel_bad: float = stats.half.bad / stats.full.bad - 1.0
		var qname: String = OctaAtlas.Quality.keys()[q]
		print("ACCURACY Textured %s: full-res maps MAE %.2f bad %.2f%% IoU %.4f | half-res MAE %.2f bad %.2f%% IoU %.4f | MAE change %+.1f%%, bad px change %+.1f%%, card-to-card difference %.2f/255" % [
				qname, stats.full.mae, stats.full.bad, stats.full.iou, stats.half.mae, stats.half.bad, stats.half.iou, rel_mae * 100.0, rel_bad * 100.0, gap])
		_check(rel_mae < MAX_RELATIVE_MAE, "half-res maps change the colour error by less than %.0f%% at %s (%+.1f%%)" % [MAX_RELATIVE_MAE * 100.0, qname, rel_mae * 100.0])
	real.world.remove_child(src)
	src.free()


func _bytes(t: Texture2D) -> int:
	return 0 if t == null else int(t.get_width() * t.get_height() * 4.0 * 4.0 / 3.0)


func _dir(v: Vector3) -> Vector3:
	var e := deg_to_rad(v.x)
	var az := deg_to_rad(v.y)
	return Vector3(cos(e) * sin(az), sin(e), cos(e) * cos(az))


func _forced_orm(src: Node3D) -> Node3D:
	var copy: Node3D = src.duplicate()
	var white := Image.create_empty(2, 2, false, Image.FORMAT_L8)
	white.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(white)
	var nodes := [copy]
	while not nodes.is_empty():
		var n: Node = nodes.pop_back()
		nodes.append_array(n.get_children())
		if n is MeshInstance3D:
			var m: BaseMaterial3D = n.get_active_material(0).duplicate()
			m.roughness_texture = tex
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			n.material_override = m
	return copy
