extends SceneTree

const LOD := 40.0
const MARGIN := 10.0
const DISTANCES := [22.0, 34.0, 40.0, 46.0, 58.0]
const BAND_TOLERANCE := 0.1
const MAX_MEAN_DIFF := 0.05
const MAX_DIFF_PIXELS := 0.0005
const FIXTURE_ATLAS := "res://tests/fixtures/v2_plain.res"
const REFS := "res://tests/fixtures/fade_refs"

var _fails := 0
var _native := false
var _renderer := ""


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


# --- Smooth LOD fade on every renderer ---
func _run() -> void:
	_renderer = RenderingServer.get_current_rendering_method()
	_native = OctaLOD.fade_supported()
	print("RENDERER %s, native fade %s, kind %s" % [_renderer, _native, OctaLOD.fade_kind()])
	_check(OctaLOD.fade_available() and _native == (_renderer == "forward_plus"), "fade is available everywhere, native only on Forward+")
	_shader_keys()
	await _references()
	var src := DemoObjects.rock(3)
	root.add_child(src)
	var s := OctaBakeSettings.new()
	s.max_atlas_size = 1024
	var atlas := await OctaBaker.bake([src], root, s)
	src.free()
	await _atlas_variant(atlas)
	await _curves(atlas)
	await _shadows(atlas)
	await _joined(atlas)
	_materials()
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	for c in root.get_children():
		c.queue_free()
	await process_frame
	await process_frame
	quit(1 if _fails else 0)


func _shader_keys() -> void:
	var codes := {}
	var plain := 0
	var expected := 0
	for q in 4:
		for depth in [true, false]:
			for debug in 6:
				for precise in [false, true]:
					for fade in [false, true]:
						var sh := OctaAtlas.shader_for(q, depth, debug, precise, fade)
						var ultra: bool = precise and q == 3
						var has_fade: bool = sh.code.contains("#define CARD_FADE")
						var has_precise: bool = sh.code.contains("#define PRECISE_SEARCH")
						var has_depth: bool = not sh.code.contains("#define NO_DEPTH_WRITE")
						var ok: bool = has_fade == fade and has_precise == ultra and has_depth == depth and (sh == OctaAtlas.SHADERS[q] or sh.code.contains("#define DEBUG_MODE %d" % debug))
						if not ok:
							_check(false, "shader variant q%d depth %s debug %d precise %s fade %s has the right defines" % [q, depth, debug, precise, fade])
							return
						codes[sh.code if sh != OctaAtlas.SHADERS[q] else "plain%d" % q] = sh
						expected += 1
						plain += 1 if sh == OctaAtlas.SHADERS[q] else 0
	_check(plain == 7 and OctaAtlas.shader_for(2, true, 0, false, false) == OctaAtlas.SHADERS[2], "only the plain combinations (Precise is ignored below Ultra) return the shipped shaders (%d of %d)" % [plain, expected])
	_check(OctaAtlas.shader_for(2, true, 0, false, true) != OctaAtlas.shader_for(2, true, 0, true, false) and OctaAtlas.shader_for(3, true, 0, true, true) != OctaAtlas.shader_for(3, true, 0, true, false), "fade, precise, depth and debug variants never share a cache key (%d distinct shaders)" % codes.size())
	_check(OctaAtlas.shader_for(3, true, 0, true, true).code.contains("PRECISE_SEARCH") and OctaAtlas.shader_for(3, false, 5, true, true).code.contains("CARD_FADE"), "fade combines with precise search, flat depth and debug views")


func _make_rig() -> Dictionary:
	var rig := TestRig.make(root)
	rig.cam.fov = 15.0
	return rig


func _alpha_sum(rig: Dictionary, from: Vector3, at: Vector3, mask: int, region := Rect2i(0, 0, TestRig.SIZE, TestRig.SIZE)) -> float:
	rig.cam.cull_mask = mask
	rig.cam.look_at_from_position(from, at)
	rig.vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var im := TestRig.grab(rig)
	var sum := 0.0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			sum += im.get_pixel(x, y).a
	return sum


func _a(d: float) -> float:
	return smoothstep(LOD - MARGIN, LOD + MARGIN, d)


# --- Forward+ and Fade None render like the previous version ---
func _references() -> void:
	var atlas := ResourceLoader.load(FIXTURE_ATLAS, "", ResourceLoader.CACHE_MODE_IGNORE) as OctaAtlas
	for case_name: String in FadeRender.CASES:
		if case_name == "native" and not _native:
			continue
		var ref := Image.load_from_file("%s/%s/%s.png" % [REFS, _renderer, case_name])
		if ref == null:
			_check(false, "%s: reference for %s exists" % [case_name, _renderer])
			continue
		ref.convert(Image.FORMAT_RGBA8)
		var now: Image = await FadeRender.sheet(atlas, root, case_name)
		var r := _compare(ref, now)
		print("REFERENCE %s (%s): mean difference %.4f/255, differing pixels %.4f%%, max channel difference %d" % [case_name, _renderer, r.mean, r.fraction * 100.0, r.max])
		_check(now.get_size() == ref.get_size() and r.mean < MAX_MEAN_DIFF and r.fraction < MAX_DIFF_PIXELS,
				"%s renders like the version before the fade work (%s)" % ["Fade None" if case_name == "none" else "Forward+ native crossfade", _renderer])


func _compare(a: Image, b: Image) -> Dictionary:
	var sum := 0.0
	var diff := 0
	var worst := 0
	var total := a.get_width() * a.get_height()
	if a.get_size() != b.get_size():
		return {mean = 255.0, fraction = 1.0, max = 255}
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := maxi(maxi(absi(ca.r8 - cb.r8), absi(ca.g8 - cb.g8)), maxi(absi(ca.b8 - cb.b8), absi(ca.a8 - cb.a8)))
			sum += d
			worst = maxi(worst, d)
			if d > 0:
				diff += 1
	return {mean = sum / total, fraction = float(diff) / total, max = worst}


# --- The shared material only changes when something asks for the fade ---
func _atlas_variant(atlas: OctaAtlas) -> void:
	var plain := OctaAtlas.SHADERS[OctaAtlas.Quality.HIGH]
	_check(atlas.get_material(OctaAtlas.Quality.HIGH).shader == plain and not atlas.card_fade, "a fresh atlas uses the shipped shader")
	var holder := Node3D.new()
	root.add_child(holder)
	var none := atlas.create_card(0)
	holder.add_child(none)
	none.lod_distance = LOD
	_check(atlas.get_material(OctaAtlas.Quality.HIGH).shader == plain and not atlas.card_fade, "Fade None and a LOD distance leave the shader alone")
	var card := atlas.create_card(0)
	holder.add_child(card)
	card.lod_distance = LOD
	card.fade = OctaLOD.Fade.CROSSFADE
	card.fade_margin = MARGIN
	var shader := atlas.get_material(OctaAtlas.Quality.HIGH).shader
	if _native:
		_check(shader == plain and not atlas.card_fade and card.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF and is_equal_approx(card.visibility_range_begin_margin, MARGIN), "Forward+ keeps the native fade (card fade mode SELF, margin %.0f) and the shipped shader" % MARGIN)
	else:
		_check(shader != plain and shader.code.contains("#define CARD_FADE") and atlas.card_fade, "%s switches the atlas to the dither shader variant" % _renderer)
		_check(card.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF and is_equal_approx(card.visibility_range_begin_margin, MARGIN) and is_equal_approx(card.visibility_range_begin, LOD), "the card still uses the visibility range fade mode for its culling band")
		_check(card.get_instance_shader_parameter("card_fade") == Vector2(LOD - MARGIN, LOD + MARGIN) and none.get_instance_shader_parameter("card_fade") != Vector2(LOD - MARGIN, LOD + MARGIN), "the band is an instance parameter of this card only")
	atlas.card_fade = false
	_check(atlas.get_material(OctaAtlas.Quality.HIGH).shader == plain, "card_fade off returns the shipped shader")
	card.fade = OctaLOD.Fade.NONE
	_check(atlas.get_material(OctaAtlas.Quality.HIGH).shader == plain and card.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED, "turning the fade off restores the card")
	holder.free()


# --- Coverage across the fade band ---
func _curves(atlas: OctaAtlas) -> void:
	for setup: String in ["crossfade", "card only", "shader material", "none"]:
		var rig := _make_rig()
		var base := _make_rig()
		var rock := DemoObjects.rock(3)
		rock.scale = Vector3.ONE * 3.0
		rig.world.add_child(rock)
		var mesh: MeshInstance3D = rock.get_child(0)
		var settings := OctaBakeSettings.new()
		settings.lod_distance = LOD
		settings.fade = OctaLOD.Fade.NONE if setup == "none" else OctaLOD.Fade.CROSSFADE
		settings.fade_margin = MARGIN
		settings.fade_real_mesh = setup != "card only"
		if setup == "shader material":
			var sm := ShaderMaterial.new()
			sm.shader = Shader.new()
			sm.shader.code = "shader_type spatial;\nvoid fragment() { ALBEDO = vec3(0.6, 0.5, 0.4); }\n"
			mesh.material_override = sm
		var card := OctaLOD.attach_card(rock, atlas, 0, OctaLOD.Mode.DYNAMIC_LOD, LOD, OctaAtlas.Quality.HIGH, null, settings)
		card.layers = 2
		var rock_b := DemoObjects.rock(3)
		rock_b.scale = Vector3.ONE * 3.0
		base.world.add_child(rock_b)
		var card_b := atlas.create_card(0)
		rock_b.add_child(card_b)
		card_b.layers = 2
		var b := atlas.bounds[0]
		var c := rock.global_transform * Vector3(b.x, b.y, b.z)
		var dithered_mesh := not _native and setup == "crossfade"
		var line := "COVERAGE %s %s:" % [_renderer, setup]
		var good := true
		var mesh_faded_seen := false
		for d: float in DISTANCES:
			var from := c + Vector3(0, 0, d)
			var card_now := await _alpha_sum(rig, from, c, 2)
			var card_ref := await _alpha_sum(base, from, c, 2)
			var mesh_now := await _alpha_sum(rig, from, c, 1)
			var mesh_ref := await _alpha_sum(base, from, c, 1)
			var both := await _alpha_sum(rig, from, c, 3)
			var cc := card_now / maxf(card_ref, 1.0)
			var mc := mesh_now / maxf(mesh_ref, 1.0)
			var ac := both / maxf(mesh_ref, 1.0)
			line += " d%.0f card %.2f mesh %.2f all %.2f;" % [d, cc, mc, ac]
			var want_card := _a(d) if setup != "none" else (1.0 if d > LOD else 0.0)
			var want_mesh := 1.0 - want_card if dithered_mesh else (1.0 if (d < LOD + MARGIN if setup != "none" else d <= LOD) else 0.0)
			good = good and absf(cc - want_card) < BAND_TOLERANCE and absf(mc - want_mesh) < BAND_TOLERANCE + (0.05 if dithered_mesh else 0.0)
			if dithered_mesh and d > 30.0 and d < 50.0:
				mesh_faded_seen = mesh_faded_seen or (mc > 0.05 and mc < 0.95)
				good = good and ac > 0.93 and ac < 1.08
		print(line)
		var label: String = {"crossfade": "crossfade with real mesh fade", "card only": "crossfade without real mesh fade", "shader material": "crossfade, real mesh has a ShaderMaterial", "none": "Fade None"}[setup]
		_check(good, "%s (%s): card %s, mesh %s" % [label, _renderer, "follows smoothstep(%.0f, %.0f) with partial coverage in the band" % [LOD - MARGIN, LOD + MARGIN] if setup != "none" else "pops at %.0f m" % LOD, "dithers out, card + mesh fill the silhouette without holes" if dithered_mesh else "stays whole until %.0f m" % (LOD + MARGIN if setup != "none" else LOD)])
		if dithered_mesh:
			_check(mesh_faded_seen, "the real mesh shows partial coverage inside the band")
		if setup == "crossfade":
			await _restore_checks(atlas, rock, mesh, card, rig)
		if setup == "shader material":
			_check(not OctaMeshFade.is_faded(mesh) and mesh.material_override is ShaderMaterial, "ShaderMaterial sources are skipped (overlap fallback: the mesh stays until the card is complete)")
		rig.vp.queue_free()
		base.vp.queue_free()
		await process_frame


func _restore_checks(atlas: OctaAtlas, rock: Node3D, mesh: MeshInstance3D, card: OctaImpostor, rig: Dictionary) -> void:
	var original: Material = mesh.mesh.surface_get_material(0)
	if _native:
		_check(not OctaMeshFade.is_faded(mesh) and mesh.get_surface_override_material(0) == null, "Forward+: the real mesh materials are never touched")
		return
	var faded := mesh.get_surface_override_material(0)
	_check(OctaMeshFade.is_faded(mesh) and faded != null and faded != original and faded is BaseMaterial3D and faded.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_OBJECT_DITHER, "the real mesh gets a distance fade dither material copy")
	_check(is_equal_approx(faded.distance_fade_min_distance, LOD + MARGIN) and is_equal_approx(faded.distance_fade_max_distance, LOD - MARGIN), "the copy fades out across the same band as the card fades in (reversed distances %.0f > %.0f)" % [faded.distance_fade_min_distance, faded.distance_fade_max_distance])
	_check(original.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED and mesh.mesh.surface_get_material(0) == original, "the original material is not changed")
	card.fade_margin = 4.0
	var narrower := mesh.get_surface_override_material(0)
	_check(narrower != faded and is_equal_approx(narrower.distance_fade_max_distance, LOD - 4.0) and card.get_instance_shader_parameter("card_fade") == Vector2(LOD - 4.0, LOD + 4.0), "changing the margin rebuilds the copy and the card band")
	card.fade_margin = MARGIN
	card.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	_check(not OctaMeshFade.is_faded(mesh) and mesh.get_surface_override_material(0) == null and not mesh.has_meta(OctaMeshFade.RECORD_META), "before a scene save the real mesh is back to its own materials (nothing leaks into the file)")
	card.notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
	_check(OctaMeshFade.is_faded(mesh), "after the save the fade is applied again")
	card.fade_real_mesh = false
	_check(not OctaMeshFade.is_faded(mesh) and mesh.get_surface_override_material(0) == null, "fade_real_mesh off restores the original materials")
	card.fade_real_mesh = true
	card.fade = OctaLOD.Fade.NONE
	_check(not OctaMeshFade.is_faded(mesh) and mesh.get_surface_override_material(0) == null, "Fade None restores the original materials")
	card.fade = OctaLOD.Fade.CROSSFADE
	_check(OctaMeshFade.is_faded(mesh), "Crossfade applies them again")
	var custom := StandardMaterial3D.new()
	custom.albedo_color = Color.RED
	card.fade_real_mesh = false
	mesh.set_surface_override_material(0, custom)
	card.fade_real_mesh = true
	var custom_copy := mesh.get_surface_override_material(0)
	_check(custom_copy != custom and custom_copy.albedo_color == Color.RED and custom.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED, "an own surface override is copied, not changed")
	OctaLOD.remove_cards(rock)
	_check(mesh.get_surface_override_material(0) == custom and not mesh.has_meta(OctaMeshFade.RECORD_META) and mesh.visibility_parent.is_empty(), "Remove Impostors puts the user's own override back and clears the link")
	mesh.set_surface_override_material(0, null)
	var again := OctaLOD.attach_card(rock, atlas, 0, OctaLOD.Mode.DYNAMIC_LOD, LOD, OctaAtlas.Quality.HIGH, null, _fade_settings())
	again.layers = 2
	_check(OctaMeshFade.is_faded(mesh), "re-baking (a new card) fades the real mesh again")
	again.get_parent().remove_child(again)
	_check(not OctaMeshFade.is_faded(mesh) and mesh.get_surface_override_material(0) == null, "taking the card out of the tree restores the real mesh (undo of a bake)")
	rock.add_child(again)
	_check(OctaMeshFade.is_faded(mesh), "putting it back (redo) fades again")


func _fade_settings() -> OctaBakeSettings:
	var s := OctaBakeSettings.new()
	s.lod_distance = LOD
	s.fade = OctaLOD.Fade.CROSSFADE
	s.fade_margin = MARGIN
	return s


# --- The shadow pass is not dithered ---
func _shadows(atlas: OctaAtlas) -> void:
	if _native:
		print("SHADOWS skipped on Forward+ (native fade, the card shader has no dither)")
		return
	var means := {}
	for mode: String in ["fade", "plain", "none"]:
		var rig := TestRig.make(root, true)
		rig.sun.rotation_degrees = Vector3(-90, 0, 0)
		rig.sun.light_energy = 2.0
		rig.cam.fov = 30.0
		var ground := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(60, 60)
		ground.mesh = pm
		rig.world.add_child(ground)
		var holder := Node3D.new()
		holder.scale = Vector3.ONE * 3.0
		holder.position = Vector3(0, 3, 0)
		rig.world.add_child(holder)
		if mode != "none":
			var card := atlas.create_card(0)
			holder.add_child(card)
			card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			if mode == "fade":
				card.configure(_fade_settings(), 3.0)
		var b := atlas.bounds[0]
		var c := holder.global_transform * Vector3(b.x, b.y, b.z)
		var sum := 0.0
		var region := Rect2i(90, 90, 76, 76)
		rig.cam.look_at_from_position(c + Vector3(0, 40.0, 0.001), c)
		rig.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		for i in 4:
			await RenderingServer.frame_post_draw
		var im := TestRig.grab(rig)
		for y in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				var p := im.get_pixel(x, y)
				sum += (p.r + p.g + p.b) / 3.0
		means[mode] = sum / (region.size.x * region.size.y)
		rig.vp.queue_free()
		await process_frame
	var dark_ref: float = means["none"] - means["plain"]
	var dark_fade: float = means["none"] - means["fade"]
	print("SHADOWS %s: ground without card %.3f, with a plain card %.3f, with a card at half fade %.3f" % [_renderer, means["none"], means["plain"], means["fade"]])
	_check(dark_ref > 0.05 and absf(dark_fade - dark_ref) < 0.03 * dark_ref + 0.002, "%s: the card casts its full shadow at half fade (shadow %.3f vs %.3f without fade): the shadow pass is not dithered" % [_renderer, dark_fade, dark_ref])


# --- Joined MultiMesh groups ---
func _joined(atlas: OctaAtlas) -> void:
	var b := atlas.bounds[0]
	var bearings := [-16.0, -8.0, 0.0, 8.0, 16.0]
	var results := {}
	for fade in [true, false]:
		var rig := TestRig.make(root)
		rig.cam.fov = 50.0
		var xforms: Array = []
		var centers: Array = []
		for i in DISTANCES.size():
			var d: float = DISTANCES[i]
			var dir := Vector3(sin(deg_to_rad(bearings[i])), 0.0, -cos(deg_to_rad(bearings[i])))
			var p: Vector3 = dir * d
			var s := d / 30.0
			xforms.append(Transform3D(Basis.from_scale(Vector3.ONE * s), p - Vector3(b.x, b.y, b.z) * s))
			centers.append(p)
		var mmi := atlas.create_multimesh(0, xforms, OctaAtlas.Quality.HIGH, [], LOD if fade else 0.0, MARGIN if fade else 0.0)
		rig.world.add_child(mmi)
		rig.cam.look_at_from_position(Vector3.ZERO, Vector3(0, 0, -1))
		rig.vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var im := TestRig.grab(rig)
		var per := []
		for i in DISTANCES.size():
			var px := Vector2i(rig.cam.unproject_position(centers[i]))
			var sum := 0.0
			for y in range(px.y - 22, px.y + 22):
				for x in range(px.x - 22, px.x + 22):
					sum += im.get_pixel(clampi(x, 0, TestRig.SIZE - 1), clampi(y, 0, TestRig.SIZE - 1)).a
			per.append(sum)
		results[fade] = per
		if fade:
			var shader := atlas.get_material(OctaAtlas.Quality.HIGH).shader
			_check(_native or (shader.code.contains("CARD_FADE") and mmi.get_instance_shader_parameter("card_fade") == Vector2(LOD - MARGIN, LOD + MARGIN)), "%s: a joined group carries the band as one instance parameter of its MultiMeshInstance3D" % _renderer)
		rig.vp.queue_free()
		await process_frame
	var line := "JOINED %s:" % _renderer
	var good := true
	for i in DISTANCES.size():
		var ratio: float = results[true][i] / maxf(results[false][i], 1.0)
		line += " d%.0f %.2f;" % [DISTANCES[i], ratio]
		var want := 1.0 if _native else _a(DISTANCES[i])
		good = good and absf(ratio - want) < BAND_TOLERANCE + 0.04
	print(line)
	_check(good, "%s: joined instances %s" % [_renderer, "ignore the band (Forward+ has no per-instance native fade, they stay whole)" if _native else "fade per instance: 0 before the band, partial inside, whole after it"])
	atlas.card_fade = false


# --- Material copies ---
func _materials() -> void:
	var band := Vector2(30, 50)
	var std := StandardMaterial3D.new()
	std.albedo_color = Color.GREEN
	var a := MeshInstance3D.new()
	a.mesh = BoxMesh.new()
	a.material_override = std
	var b := MeshInstance3D.new()
	b.mesh = SphereMesh.new()
	b.material_override = std
	var multi := MeshInstance3D.new()
	var arr_mesh := ArrayMesh.new()
	var box := BoxMesh.new().get_mesh_arrays()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box)
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box)
	arr_mesh.surface_set_material(0, std)
	arr_mesh.surface_set_material(1, std)
	multi.mesh = arr_mesh
	var before := OctaMeshFade.copy_count()
	OctaMeshFade.apply(a, band)
	OctaMeshFade.apply(b, band)
	OctaMeshFade.apply(multi, band)
	_check(a.material_override == b.material_override and a.material_override != std and multi.get_surface_override_material(0) == multi.get_surface_override_material(1) and multi.get_surface_override_material(0) == a.material_override, "one copy is shared by every user of a material and band (%d new copy)" % (OctaMeshFade.copy_count() - before))
	OctaMeshFade.apply(b, Vector2(20, 40))
	_check(b.material_override != a.material_override, "another band gets its own copy")
	_check(std.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED and std.albedo_color == Color.GREEN, "the original material stays untouched")
	OctaMeshFade.restore(a)
	OctaMeshFade.restore(b)
	OctaMeshFade.restore(multi)
	_check(a.material_override == std and b.material_override == std and multi.get_surface_override_material(0) == null and not a.has_meta(OctaMeshFade.RECORD_META), "restore puts the originals back and leaves no record behind")
	var own := StandardMaterial3D.new()
	own.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	var shader := ShaderMaterial.new()
	var chained := StandardMaterial3D.new()
	chained.next_pass = StandardMaterial3D.new()
	for m: Material in [own, shader, chained]:
		var n := MeshInstance3D.new()
		n.mesh = BoxMesh.new()
		n.material_override = m
		_check(OctaMeshFade.apply(n, band) == 0 and n.material_override == m and not OctaMeshFade.is_faded(n), "%s is skipped (the real mesh keeps its own material and falls back to the overlap)" % ["a material with its own distance fade" if m == own else ("a ShaderMaterial" if m == shader else "a material with a next pass")])
		n.free()
	a.free()
	b.free()
	multi.free()
	var mixed := MeshInstance3D.new()
	var mixed_mesh := ArrayMesh.new()
	mixed_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box)
	mixed_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box)
	mixed_mesh.surface_set_material(0, std)
	mixed_mesh.surface_set_material(1, shader)
	mixed.mesh = mixed_mesh
	_check(OctaMeshFade.apply(mixed, band) == 1 and mixed.get_surface_override_material(0) != null and mixed.get_surface_override_material(1) == null, "a mesh with one fadeable surface fades that surface and leaves the other one")
	OctaMeshFade.restore(mixed)
	mixed.free()
