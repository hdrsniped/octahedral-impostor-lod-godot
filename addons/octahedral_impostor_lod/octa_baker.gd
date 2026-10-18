@tool
class_name OctaBaker
extends RefCounted

const CAPTURE_SHADERS := {
	false: preload("res://addons/octahedral_impostor_lod/shaders/capture_cull_back.gdshader"),
	true: preload("res://addons/octahedral_impostor_lod/shaders/capture_cull_disabled.gdshader"),
}
const MAP_SHADERS := {
	false: preload("res://addons/octahedral_impostor_lod/shaders/capture_material_back.gdshader"),
	true: preload("res://addons/octahedral_impostor_lod/shaders/capture_material_disabled.gdshader"),
}
const BACK_SHADER := preload("res://addons/octahedral_impostor_lod/shaders/capture_cull_front.gdshader")
const CONSTANT_TOLERANCE := 0.15
const CONSTANT_AO := 1.0
const CAMERA_DISTANCE := 3.0
const CLIP_MARGIN := 1.1
const MIN_RADIUS := 0.001
const MIN_NEAR := 0.001
const MAX_ATLAS_SIDE := 16384
const MAX_PAD_FRACTION := 0.25
const MIN_MAP_FRAME := 4
const TRANSPARENT_CUT := 0.5
const LUMA := Vector4(0.2126, 0.7152, 0.0722, 0)


# --- Bake ---
static func bake(sources: Array, host: Node, settings: OctaBakeSettings = null, job: OctaBakeJob = null) -> OctaAtlas:
	if settings == null:
		settings = OctaBakeSettings.new()
	if sources.is_empty() or sources.size() > OctaAtlas.MAX_OBJECTS:
		push_error("Octahedral Impostor LOD: bake 1 to %d objects at a time (got %d)." % [OctaAtlas.MAX_OBJECTS, sources.size()])
		return null
	if host == null or not host.is_inside_tree():
		push_error("Octahedral Impostor LOD: the host node must be inside the scene tree.")
		return null
	var entries: Array[Dictionary] = []
	var mesh_cache := {}
	for s: Node3D in sources:
		var e := _collect(s, settings.split_parts, mesh_cache)
		if e.parts.is_empty():
			push_error("Octahedral Impostor LOD: '%s' has no visible MeshInstance3D to bake." % s.name)
			return null
		entries.append(e)

	var hooks := _any_hook(entries)
	var want_orm := settings.material_maps and (_needs_material_map(entries) or hooks)
	var want_em := false
	if settings.emission:
		want_em = hooks
		for e in entries:
			want_em = want_em or e.emit_scale > 0.0
	var count := entries.size()
	var n := settings.grid_size
	var l := settings.layout(count)
	var fr: int = l.frame
	if l.side > MAX_ATLAS_SIDE:
		push_error("Octahedral Impostor LOD: the atlas would be %d px wide (limit 16384). Lower frame_resolution or bake fewer objects." % l.side)
		return null
	var pad := minf(settings.padding_px, fr * MAX_PAD_FRACTION)
	var frame_scale := fr / (fr - 2.0 * pad)
	var fm := map_frame_resolution(fr, settings.half_res_material_maps)

	var atlas := OctaAtlas.new()
	atlas.format_version = OctaAtlas.FORMAT_VERSION
	atlas.bake_settings = settings.duplicate()
	atlas.write_depth = settings.write_depth
	atlas.precise_search = settings.precise_search
	atlas.view_visibility = settings.view_visibility
	atlas.pyramid_search = settings.coverage_pyramid
	atlas.parallax_refine = settings.parallax_refine
	atlas.shadow_views = settings.shadow_views
	atlas.grid_size = n
	atlas.hemisphere = settings.hemisphere
	atlas.parent_space = settings.split_parts
	atlas.tiles = Vector2i(l.cols, l.rows)
	atlas.frame_resolution = fr
	atlas.frame_scale = frame_scale
	var img_a := Image.create_empty(l.cols * n * fr, l.rows * n * fr, false, Image.FORMAT_RGBA8)
	var img_n := Image.create_empty(l.cols * n * fr, l.rows * n * fr, false, Image.FORMAT_RGBA8)
	var img_b: Image = Image.create_empty(l.cols * n * fr, l.rows * n * fr, false, Image.FORMAT_R8) if settings.back_layer else null
	var img_o: Image = Image.create_empty(l.cols * n * fm, l.rows * n * fm, false, Image.FORMAT_RGBA8) if want_orm else null
	var img_e: Image = Image.create_empty(l.cols * n * fm, l.rows * n * fm, false, Image.FORMAT_RGBA8) if want_em else null

	var rig := Node.new()
	rig.name = "_OctaBakeRig"
	host.add_child(rig)
	var world_a := _make_world()
	var world_n := _make_world()
	var holder_a := _make_holder(world_a)
	var holder_n := _make_holder(world_n)
	rig.add_child(holder_a)
	rig.add_child(holder_n)
	var world_b: World3D = _make_world() if settings.back_layer else null
	var holder_b: SubViewport = _make_holder(world_b) if settings.back_layer else null
	if holder_b != null:
		rig.add_child(holder_b)
	var world_o: World3D = _make_world() if want_orm else null
	var holder_o: SubViewport = _make_holder(world_o) if want_orm else null
	if holder_o != null:
		rig.add_child(holder_o)
	var world_e: World3D = _make_world() if want_em else null
	var holder_e: SubViewport = _make_holder(world_e) if want_em else null
	if holder_e != null:
		rig.add_child(holder_e)
	var k := mini(settings.batch_size, n * n)
	if job != null and job.paced and job.max_views > 0:
		k = mini(k, job.max_views)
	var vps_a: Array[SubViewport] = []
	var vps_n: Array[SubViewport] = []
	var vps_b: Array[SubViewport] = []
	var vps_o: Array[SubViewport] = []
	var vps_e: Array[SubViewport] = []
	for i in k:
		vps_a.append(_make_viewport(rig, fr, world_a, false, settings.msaa))
		vps_n.append(_make_viewport(rig, fr, world_n, true, settings.msaa))
		if world_b != null:
			vps_b.append(_make_viewport(rig, fr, world_b, true, settings.msaa))
		if world_o != null:
			vps_o.append(_make_viewport(rig, fm, world_o, true, settings.msaa))
		if world_e != null:
			vps_e.append(_make_viewport(rig, fm, world_e, true, settings.msaa))
	var low_cpu := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	await _tick(job, true)
	if job != null and job.cancelled:
		return _abort(rig, low_cpu)

	for oi in count:
		var e: Dictionary = entries[oi]
		var b: Vector4 = e.bounds
		atlas.object_names.append(e.name)
		atlas.bounds.append(b)
		atlas.surface_params.append(e.surface)
		atlas.material_params.append(Vector4(maxf(e.emit_scale, 1.0), e.ao_affect, e.ao_const, 0.0))
		_fill_holders(e, holder_a, holder_n, holder_b, holder_o, holder_e)
		await _tick(job, false)
		if job != null and job.cancelled:
			return _abort(rig, low_cpu)
		var center := Vector3(b.x, b.y, b.z)
		var dist := b.w * CAMERA_DISTANCE
		for mat: ShaderMaterial in e.capture_mats:
			mat.set_shader_parameter("cam_dist", dist)
			mat.set_shader_parameter("radius", b.w)
		var tile := Vector2i(oi % l.cols, oi / l.cols)
		var f := 0
		while f < n * n:
			var batch := mini(k, n * n - f)
			if job != null and job.paced:
				batch = mini(batch, maxi(job.max_views, 1))
				job.last_batch = batch
			for j in batch:
				var d := OctaAtlas.frame_dir(Vector2i((f + j) % n, (f + j) / n), n, settings.hemisphere)
				var set_vps: Array[SubViewport] = [vps_a[j], vps_n[j]]
				if not vps_b.is_empty():
					set_vps.append(vps_b[j])
				if not vps_o.is_empty():
					set_vps.append(vps_o[j])
				if not vps_e.is_empty():
					set_vps.append(vps_e[j])
				for vp: SubViewport in set_vps:
					var cam: Camera3D = vp.get_child(0)
					cam.transform = Transform3D(OctaAtlas.frame_basis(d), center + d * dist)
					cam.size = 2.0 * b.w * frame_scale
					cam.near = maxf(dist - b.w * CLIP_MARGIN, MIN_NEAR)
					cam.far = dist + b.w * CLIP_MARGIN
					vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await _tick(job, true)
			if not is_instance_valid(rig) or not rig.is_inside_tree():
				OS.low_processor_usage_mode = low_cpu
				push_error("Octahedral Impostor LOD: bake cancelled (its host node left the scene tree).")
				return null
			if job != null and job.cancelled:
				return _abort(rig, low_cpu)
			for j in batch:
				var at := (tile * n + Vector2i((f + j) % n, (f + j) / n)) * fr
				_blit(vps_a[j], img_a, fr, at)
				_blit(vps_n[j], img_n, fr, at)
				if img_b != null:
					_blit(vps_b[j], img_b, fr, at, Image.FORMAT_R8)
				var at_m := (tile * n + Vector2i((f + j) % n, (f + j) / n)) * fm
				if img_o != null:
					_blit(vps_o[j], img_o, fm, at_m)
				if img_e != null:
					_blit(vps_e[j], img_e, fm, at_m)
			if job != null:
				job.progress.emit(oi * n * n + f + batch, count * n * n, "%s (%d of %d)" % [e.name, oi + 1, count])
			f += batch
	rig.queue_free()
	OS.low_processor_usage_mode = low_cpu

	await _mips(img_a, job)
	if settings.coverage_pyramid:
		atlas.max_coverage = _max_coverage_texture(img_n)
	await _mips(img_n, job)
	atlas.albedo = ImageTexture.create_from_image(img_a)
	await _tick(job, false)
	atlas.normal_depth = ImageTexture.create_from_image(img_n)
	await _tick(job, false)
	if img_o != null:
		await _mips(img_o, job)
		atlas.orm = ImageTexture.create_from_image(img_o)
		await _tick(job, false)
	if img_e != null:
		await _mips(img_e, job)
		atlas.emission = ImageTexture.create_from_image(img_e)
		await _tick(job, false)
	if img_b != null:
		await _mips(img_b, job)
		atlas.back_depth = ImageTexture.create_from_image(img_b)
		await _tick(job, false)
	var paced := job != null and job.paced
	if not paced or settings.quality == OctaAtlas.Quality.ULTRA:
		var ultra := atlas.get_material(OctaAtlas.Quality.ULTRA)
		ultra.set_shader_parameter("search_steps", settings.search_steps)
		ultra.set_shader_parameter("layer_tolerance", settings.layer_tolerance)
		await _tick(job, false)
	atlas.get_material(settings.quality if paced else OctaAtlas.Quality.HIGH)
	await _tick(job, false)
	if job != null and job.cancelled:
		return null
	return atlas


# --- Time slicing ---
static func _tick(job: OctaBakeJob, render: bool) -> void:
	if job != null and job.paced:
		job.wait_render = render
		job.wait_frame = Engine.get_process_frames()
		await job.resume
	elif render:
		await RenderingServer.frame_post_draw


static func _abort(rig: Node, low_cpu: bool) -> OctaAtlas:
	if is_instance_valid(rig):
		rig.queue_free()
	OS.low_processor_usage_mode = low_cpu
	return null


static func _mips(img: Image, job: OctaBakeJob) -> void:
	if job != null and job.paced:
		var id := WorkerThreadPool.add_task(img.generate_mipmaps)
		while not WorkerThreadPool.is_task_completed(id):
			await _tick(job, true)
		WorkerThreadPool.wait_for_task_completion(id)
	else:
		img.generate_mipmaps()


static func _max_coverage_texture(src: Image) -> ImageTexture:
	var w := src.get_width()
	var h := src.get_height()
	var cw := maxi(w / OctaAtlas.COVERAGE_BLOCK, 1)
	var ch := maxi(h / OctaAtlas.COVERAGE_BLOCK, 1)
	var s := src.get_data()
	var d := PackedByteArray()
	d.resize(cw * ch)
	var stride := w * 4
	for by in ch:
		var top := by * OctaAtlas.COVERAGE_BLOCK * stride
		for bx in cw:
			var col := bx * OctaAtlas.COVERAGE_BLOCK * 4 + 3
			var m := 0
			for y in OctaAtlas.COVERAGE_BLOCK:
				var i := top + y * stride + col
				for x in OctaAtlas.COVERAGE_BLOCK:
					var a: int = s[i]
					if a > m:
						m = a
					i += 4
			d[by * cw + bx] = m
	var img := Image.create_from_data(cw, ch, false, Image.FORMAT_R8, d)
	return ImageTexture.create_from_image(img)


# --- Save ---
static func bake_to_file(sources: Array, host: Node, path: String, settings: OctaBakeSettings = null, job: OctaBakeJob = null) -> OctaAtlas:
	if settings == null:
		settings = OctaBakeSettings.new()
	var atlas := await bake(sources, host, settings, job)
	if atlas == null:
		return null
	return save_atlas(atlas, path, settings)


static func save_atlas(atlas: OctaAtlas, path: String, settings: OctaBakeSettings) -> OctaAtlas:
	var mode := PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS
	if settings.compression == OctaBakeSettings.Compression.VRAM:
		if OS.has_feature("editor"):
			mode = PortableCompressedTexture2D.COMPRESSION_MODE_BASIS_UNIVERSAL
		else:
			push_warning("Octahedral Impostor LOD: VRAM compression needs the editor; saving lossless instead.")
	atlas.albedo = _compress(atlas.albedo, mode)
	atlas.normal_depth = _compress(atlas.normal_depth, mode)
	if atlas.back_depth != null:
		atlas.back_depth = _compress(atlas.back_depth, mode)
	if atlas.orm != null:
		atlas.orm = _compress(atlas.orm, mode)
	if atlas.emission != null:
		atlas.emission = _compress(atlas.emission, mode)
	atlas.refresh_materials()
	for q in OctaAtlas.Quality.size():
		atlas.get_material(q)
	atlas.get_material(OctaAtlas.Quality.HIGH)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := ResourceSaver.save(atlas, path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("Octahedral Impostor LOD: could not save %s (%s)." % [path, error_string(err)])
		return null
	atlas.take_over_path(path)
	return atlas


static func _compress(tex: Texture2D, mode: PortableCompressedTexture2D.CompressionMode) -> Texture2D:
	var t := PortableCompressedTexture2D.new()
	t.keep_compressed_buffer = true
	t.create_from_image(tex.get_image(), mode)
	return t


static func _blit(vp: SubViewport, into: Image, size: int, at: Vector2i, fmt := Image.FORMAT_RGBA8) -> void:
	var img := vp.get_texture().get_image()
	img.convert(fmt)
	into.blit_rect(img, Rect2i(0, 0, size, size), at)


# --- Source collection ---
static func _collect(source: Node3D, parent_space := false, cache := {}) -> Dictionary:
	var parts: Array[Dictionary] = []
	var skipped := PackedStringArray()
	_walk(source, Transform3D(source.basis, Vector3.ZERO) if parent_space else Transform3D.IDENTITY, parts, skipped, true)
	if not skipped.is_empty():
		push_warning("Octahedral Impostor LOD: '%s': only MeshInstance3D nodes are baked; skipped %s." % [source.name, ", ".join(skipped)])
	var e := {name = String(source.name), parts = parts, bounds = Vector4(), surface = OctaAtlas.DEFAULT_SURFACE, capture_mats = [], emit_scale = 0.0, ao_affect = 0.0, ao_const = CONSTANT_AO, textured = false, spread = 0.0}
	if parts.is_empty():
		return e
	var verts := PackedVector3Array()
	for p in parts:
		var key := [p.mesh, p.xform]
		if not cache.has(key):
			var placed := PackedVector3Array()
			for s in p.mesh.get_surface_count():
				placed.append_array(p.xform * (p.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array))
			cache[key] = placed
		verts.append_array(cache[key])
	var aabb := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		aabb = aabb.expand(v)
	var c := aabb.get_center()
	var r2 := 0.0
	for v in verts:
		r2 = maxf(r2, c.distance_squared_to(v))
	e.bounds = Vector4(c.x, c.y, c.z, maxf(sqrt(r2), MIN_RADIUS))
	_scan_materials(parts, e)
	return e


# --- Material constants ---
static func _scan_materials(parts: Array[Dictionary], e: Dictionary) -> void:
	var acc := Vector3.ZERO
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var nmat := 0
	var ao_sum := 0.0
	var ao_n := 0
	for p in parts:
		for s in p.mesh.get_surface_count():
			var m: Material = p.mats[s]
			if m is BaseMaterial3D:
				acc += Vector3(m.roughness, m.metallic, m.metallic_specular)
				lo = lo.min(Vector2(m.roughness, m.metallic))
				hi = hi.max(Vector2(m.roughness, m.metallic))
				nmat += 1
				if _has_map_texture(m):
					e.textured = true
				if _emits(m):
					e.emit_scale = maxf(e.emit_scale, m.emission_energy_multiplier)
				if m.ao_enabled:
					ao_sum += m.ao_light_affect
					ao_n += 1
	if ao_n > 0:
		e.ao_affect = ao_sum / ao_n
	if nmat > 0:
		acc /= nmat
		e.surface = Vector4(acc.x, acc.y, acc.z, 0.0)
		e.spread = maxf(hi.x - lo.x, hi.y - lo.y)


static func _has_map_texture(m: BaseMaterial3D) -> bool:
	if m is ORMMaterial3D and m.get("orm_texture") != null:
		return true
	return m.roughness_texture != null or m.metallic_texture != null or (m.ao_enabled and m.ao_texture != null)


static func _needs_material_map(entries: Array[Dictionary]) -> bool:
	for e in entries:
		if e.textured or e.spread > CONSTANT_TOLERANCE:
			return true
	return false


static func _scan_sources(sources: Array, split_parts: bool) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for s: Node3D in sources:
		var parts: Array[Dictionary] = []
		_walk(s, Transform3D(s.basis, Vector3.ZERO) if split_parts else Transform3D.IDENTITY, parts, PackedStringArray(), true)
		var e := {textured = false, spread = 0.0, surface = OctaAtlas.DEFAULT_SURFACE, emit_scale = 0.0, ao_affect = 0.0}
		_scan_materials(parts, e)
		entries.append(e)
	return entries


static func needs_material_map(sources: Array, split_parts := false) -> bool:
	return _needs_material_map(_scan_sources(sources, split_parts))


static func has_mixed_constants(sources: Array, split_parts := false) -> bool:
	for e in _scan_sources(sources, split_parts):
		if e.spread > CONSTANT_TOLERANCE:
			return true
	return false


static func map_frame_resolution(frame: int, half: bool) -> int:
	return maxi((frame + 1) / 2, MIN_MAP_FRAME) if half else frame


static func _walk(node: Node, xform: Transform3D, parts: Array[Dictionary], skipped: PackedStringArray, is_root: bool) -> void:
	if node.has_meta(OctaAtlas.CARD_META):
		return
	if node is Node3D:
		if not node.visible:
			return
		if not is_root:
			xform = xform * node.transform
	if node is MeshInstance3D:
		if node.mesh != null:
			var mats := []
			for s in node.mesh.get_surface_count():
				mats.append(node.get_active_material(s))
			parts.append({mesh = node.mesh, xform = xform, mats = mats})
	elif node is GeometryInstance3D:
		skipped.append("%s (%s)" % [node.name, node.get_class()])
	for child in node.get_children():
		_walk(child, xform, parts, skipped, false)


# --- Capture rig ---
static func _make_world() -> World3D:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	var w := World3D.new()
	w.environment = env
	return w


static func _make_holder(world: World3D) -> SubViewport:
	var h := SubViewport.new()
	h.size = Vector2i(2, 2)
	h.world_3d = world
	h.render_target_update_mode = SubViewport.UPDATE_DISABLED
	return h


static func _make_viewport(parent: Node, size: int, world: World3D, data_pass: bool, msaa: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.world_3d = world
	vp.transparent_bg = true
	vp.msaa_3d = msaa
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	vp.use_debanding = false
	vp.use_occlusion_culling = false
	vp.mesh_lod_threshold = 0.0
	vp.positional_shadow_atlas_size = 0
	vp.scaling_3d_scale = 1.0
	vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	vp.use_hdr_2d = data_pass
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	parent.add_child(vp)
	cam.current = true
	return vp


static func _fill_holders(e: Dictionary, holder_a: Node, holder_n: Node, holder_b: Node, holder_o: Node, holder_e: Node) -> void:
	for h in [holder_a, holder_n, holder_b, holder_o, holder_e]:
		if h == null:
			continue
		for c in h.get_children():
			h.remove_child(c)
			c.free()
	var albedo_mats := {}
	var data_mats := {}
	var back_mats := {}
	var orm_mats := {}
	var em_mats := {}
	for p in e.parts:
		var a := _copy(p)
		var d := _copy(p)
		for s in p.mesh.get_surface_count():
			var m: Material = p.mats[s]
			if not albedo_mats.has(m):
				albedo_mats[m] = _albedo_material(m)
				data_mats[m] = _capture_material(m)
				e.capture_mats.append(data_mats[m])
				if holder_b != null:
					back_mats[m] = _capture_material(m, true)
					e.capture_mats.append(back_mats[m])
				if holder_o != null:
					orm_mats[m] = _orm_material_for(m)
				if holder_e != null:
					em_mats[m] = _emission_material_for(m, e.emit_scale)
			a.set_surface_override_material(s, albedo_mats[m])
			d.set_surface_override_material(s, data_mats[m])
		holder_a.add_child(a)
		holder_n.add_child(d)
		if holder_o != null:
			var om := _copy(p)
			for s in p.mesh.get_surface_count():
				om.set_surface_override_material(s, orm_mats[p.mats[s]])
			holder_o.add_child(om)
		if holder_e != null:
			var em := _copy(p)
			for s in p.mesh.get_surface_count():
				em.set_surface_override_material(s, em_mats[p.mats[s]])
			holder_e.add_child(em)
		if holder_b != null:
			var bk := _copy(p)
			for s in p.mesh.get_surface_count():
				bk.set_surface_override_material(s, back_mats[p.mats[s]])
			holder_b.add_child(bk)


static func _copy(part: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = part.mesh
	mi.transform = part.xform
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- Capture materials ---
static func _albedo_material(m: Material) -> Material:
	if m is BaseMaterial3D and (m.metallic > 0.0 or m.metallic_texture != null):
		var d: BaseMaterial3D = m.duplicate()
		d.metallic = 0.0
		d.metallic_texture = null
		return d
	return m


static func _capture_material(m: Material, back := false) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	var cull_off := false
	if m is BaseMaterial3D:
		cull_off = m.cull_mode == BaseMaterial3D.CULL_DISABLED
		var cut := -1.0
		match m.transparency:
			BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				cut = m.alpha_scissor_threshold
			BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_HASH, \
			BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
				cut = TRANSPARENT_CUT
		sm.set_shader_parameter("alpha_cut", cut)
		sm.set_shader_parameter("albedo_tex", m.albedo_texture)
		sm.set_shader_parameter("albedo_color", m.albedo_color)
		sm.set_shader_parameter("uv1_scale", m.uv1_scale)
		sm.set_shader_parameter("uv1_offset", m.uv1_offset)
	sm.shader = CAPTURE_SHADERS[cull_off] if not back or cull_off else BACK_SHADER
	return sm


static func _emits(m: BaseMaterial3D) -> bool:
	return m.emission_enabled and (m.emission_texture != null or m.emission.r + m.emission.g + m.emission.b > 0.0)


static func _channel(c: int) -> Vector4:
	match c:
		BaseMaterial3D.TEXTURE_CHANNEL_RED:
			return Vector4(1, 0, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Vector4(0, 1, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Vector4(0, 0, 1, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Vector4(0, 0, 0, 1)
	return LUMA


static func _map_material(m: Material, mode: int) -> ShaderMaterial:
	var sm := _capture_material(m)
	sm.shader = MAP_SHADERS[m is BaseMaterial3D and m.cull_mode == BaseMaterial3D.CULL_DISABLED]
	sm.set_shader_parameter("map_mode", mode)
	return sm


static func _orm_material(m: Material) -> ShaderMaterial:
	var sm := _map_material(m, 0)
	if not m is BaseMaterial3D:
		return sm
	sm.set_shader_parameter("roughness", m.roughness)
	sm.set_shader_parameter("metallic", m.metallic)
	var packed: Texture2D = m.get("orm_texture") if m is ORMMaterial3D else null
	if packed != null:
		sm.set_shader_parameter("rough_tex", packed)
		sm.set_shader_parameter("rough_ch", Vector4(0, 1, 0, 0))
		sm.set_shader_parameter("metal_tex", packed)
		sm.set_shader_parameter("metal_ch", Vector4(0, 0, 1, 0))
		sm.set_shader_parameter("ao_tex", packed)
		sm.set_shader_parameter("ao_ch", Vector4(1, 0, 0, 0))
		return sm
	sm.set_shader_parameter("rough_tex", m.roughness_texture)
	sm.set_shader_parameter("rough_ch", _channel(m.roughness_texture_channel))
	sm.set_shader_parameter("metal_tex", m.metallic_texture)
	sm.set_shader_parameter("metal_ch", _channel(m.metallic_texture_channel))
	if m.ao_enabled:
		sm.set_shader_parameter("ao_tex", m.ao_texture)
		sm.set_shader_parameter("ao_ch", _channel(m.ao_texture_channel))
	return sm


static func _emission_material(m: Material, scale: float) -> ShaderMaterial:
	var sm := _map_material(m, 1)
	if m is BaseMaterial3D and _emits(m):
		sm.set_shader_parameter("emission_color", Vector3(m.emission.r, m.emission.g, m.emission.b))
		sm.set_shader_parameter("emission_tex", m.emission_texture)
		sm.set_shader_parameter("emission_mul", m.emission_energy_multiplier / maxf(scale, 1.0))
		sm.set_shader_parameter("emission_add", m.emission_operator == BaseMaterial3D.EMISSION_OP_ADD)
	else:
		sm.set_shader_parameter("emission_mul", 0.0)
	return sm


# --- Bake hook ---
static func _any_hook(entries: Array[Dictionary]) -> bool:
	for e in entries:
		for p in e.parts:
			for m in p.mats:
				if _has_bake_hook(m):
					return true
	return false


static func _has_bake_hook(m: Material) -> bool:
	if not m is ShaderMaterial:
		return false
	var sh: Shader = (m as ShaderMaterial).shader
	if sh == null:
		return false
	return sh.code.contains("octa_bake_mode") or sh.code.contains("octa_bake_hook")


static func _orm_material_for(m: Material) -> Material:
	if _has_bake_hook(m):
		var d: ShaderMaterial = m.duplicate()
		d.set_shader_parameter("octa_bake_mode", 1)
		return d
	return _orm_material(m)


static func _emission_material_for(m: Material, scale: float) -> Material:
	if _has_bake_hook(m):
		var d: ShaderMaterial = m.duplicate()
		d.set_shader_parameter("octa_bake_mode", 2)
		d.set_shader_parameter("octa_bake_scale", scale)
		return d
	return _emission_material(m, scale)
