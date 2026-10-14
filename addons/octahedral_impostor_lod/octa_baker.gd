@tool
class_name OctaBaker
extends RefCounted

const CAPTURE_SHADERS := {
	false: preload("res://addons/octahedral_impostor_lod/shaders/capture_cull_back.gdshader"),
	true: preload("res://addons/octahedral_impostor_lod/shaders/capture_cull_disabled.gdshader"),
}


# --- Bake ---
static func bake(sources: Array, host: Node, settings: OctaBakeSettings = null) -> OctaAtlas:
	if settings == null:
		settings = OctaBakeSettings.new()
	if sources.is_empty() or sources.size() > OctaAtlas.MAX_OBJECTS:
		push_error("Octahedral Impostor LOD: bake 1 to %d objects at a time (got %d)." % [OctaAtlas.MAX_OBJECTS, sources.size()])
		return null
	if host == null or not host.is_inside_tree():
		push_error("Octahedral Impostor LOD: the host node must be inside the scene tree.")
		return null
	var entries: Array[Dictionary] = []
	for s: Node3D in sources:
		var e := _collect(s)
		if e.parts.is_empty():
			push_error("Octahedral Impostor LOD: '%s' has no visible MeshInstance3D to bake." % s.name)
			return null
		entries.append(e)

	var count := entries.size()
	var n := settings.grid_size
	var l := settings.layout(count)
	var fr: int = l.frame
	if l.side > 16384:
		push_error("Octahedral Impostor LOD: the atlas would be %d px wide (limit 16384). Lower frame_resolution or bake fewer objects." % l.side)
		return null
	var pad := minf(settings.padding_px, fr * 0.25)
	var frame_scale := fr / (fr - 2.0 * pad)

	var atlas := OctaAtlas.new()
	atlas.grid_size = n
	atlas.hemisphere = settings.hemisphere
	atlas.tiles = Vector2i(l.cols, l.rows)
	atlas.frame_resolution = fr
	atlas.frame_scale = frame_scale
	var img_a := Image.create_empty(l.cols * n * fr, l.rows * n * fr, false, Image.FORMAT_RGBA8)
	var img_n := Image.create_empty(l.cols * n * fr, l.rows * n * fr, false, Image.FORMAT_RGBA8)

	var rig := Node.new()
	rig.name = "_OctaBakeRig"
	host.add_child(rig)
	var world_a := _make_world()
	var world_n := _make_world()
	var holder_a := _make_holder(world_a)
	var holder_n := _make_holder(world_n)
	rig.add_child(holder_a)
	rig.add_child(holder_n)
	var k := mini(settings.batch_size, n * n)
	var vps_a: Array[SubViewport] = []
	var vps_n: Array[SubViewport] = []
	for i in k:
		vps_a.append(_make_viewport(rig, fr, world_a, false, settings.msaa))
		vps_n.append(_make_viewport(rig, fr, world_n, true, settings.msaa))
	var low_cpu := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	await RenderingServer.frame_post_draw

	for oi in count:
		var e: Dictionary = entries[oi]
		var b: Vector4 = e.bounds
		atlas.object_names.append(e.name)
		atlas.bounds.append(b)
		atlas.surface_params.append(e.surface)
		_fill_holders(e, holder_a, holder_n)
		var center := Vector3(b.x, b.y, b.z)
		var dist := b.w * 3.0
		for mat: ShaderMaterial in e.capture_mats:
			mat.set_shader_parameter("cam_dist", dist)
			mat.set_shader_parameter("radius", b.w)
		var tile := Vector2i(oi % l.cols, oi / l.cols)
		for f in range(0, n * n, k):
			var batch := mini(k, n * n - f)
			for j in batch:
				var d := OctaAtlas.frame_dir(Vector2i((f + j) % n, (f + j) / n), n, settings.hemisphere)
				for vp: SubViewport in [vps_a[j], vps_n[j]]:
					var cam: Camera3D = vp.get_child(0)
					cam.transform = Transform3D(OctaAtlas.frame_basis(d), center + d * dist)
					cam.size = 2.0 * b.w * frame_scale
					cam.near = maxf(dist - b.w * 1.1, 0.001)
					cam.far = dist + b.w * 1.1
					vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			if not is_instance_valid(rig) or not rig.is_inside_tree():
				OS.low_processor_usage_mode = low_cpu
				push_error("Octahedral Impostor LOD: bake cancelled (its host node left the scene tree).")
				return null
			for j in batch:
				var at := (tile * n + Vector2i((f + j) % n, (f + j) / n)) * fr
				_blit(vps_a[j], img_a, fr, at)
				_blit(vps_n[j], img_n, fr, at)
	rig.queue_free()
	OS.low_processor_usage_mode = low_cpu

	img_a.generate_mipmaps()
	img_n.generate_mipmaps()
	atlas.albedo = ImageTexture.create_from_image(img_a)
	atlas.normal_depth = ImageTexture.create_from_image(img_n)
	atlas.get_material(OctaAtlas.Quality.HIGH)
	return atlas


# --- Save ---
static func bake_to_file(sources: Array, host: Node, path: String, settings: OctaBakeSettings = null) -> OctaAtlas:
	if settings == null:
		settings = OctaBakeSettings.new()
	var atlas := await bake(sources, host, settings)
	if atlas == null:
		return null
	var mode := PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS
	if settings.compression == OctaBakeSettings.Compression.VRAM:
		if OS.has_feature("editor"):
			mode = PortableCompressedTexture2D.COMPRESSION_MODE_BASIS_UNIVERSAL
		else:
			push_warning("Octahedral Impostor LOD: VRAM compression needs the editor; saving lossless instead.")
	atlas.albedo = _compress(atlas.albedo, mode)
	atlas.normal_depth = _compress(atlas.normal_depth, mode)
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


static func _blit(vp: SubViewport, into: Image, size: int, at: Vector2i) -> void:
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	into.blit_rect(img, Rect2i(0, 0, size, size), at)


# --- Source collection ---
static func _collect(source: Node3D) -> Dictionary:
	var parts: Array[Dictionary] = []
	var skipped := PackedStringArray()
	_walk(source, Transform3D.IDENTITY, parts, skipped, true)
	if not skipped.is_empty():
		push_warning("Octahedral Impostor LOD: '%s': only MeshInstance3D nodes are baked; skipped %s." % [source.name, ", ".join(skipped)])
	var e := {name = String(source.name), parts = parts, bounds = Vector4(), surface = Vector4(0.9, 0.0, 0.5, 0.0), capture_mats = []}
	if parts.is_empty():
		return e
	var verts := PackedVector3Array()
	for p in parts:
		for s in p.mesh.get_surface_count():
			verts.append_array(p.xform * (p.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array))
	var aabb := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		aabb = aabb.expand(v)
	var c := aabb.get_center()
	var r2 := 0.0
	for v in verts:
		r2 = maxf(r2, c.distance_squared_to(v))
	e.bounds = Vector4(c.x, c.y, c.z, maxf(sqrt(r2), 0.001))
	var acc := Vector3.ZERO
	var nmat := 0
	for p in parts:
		for s in p.mesh.get_surface_count():
			var m: Material = p.mi.get_active_material(s)
			if m is BaseMaterial3D:
				acc += Vector3(m.roughness, m.metallic, m.metallic_specular)
				nmat += 1
	if nmat > 0:
		acc /= nmat
		e.surface = Vector4(acc.x, acc.y, acc.z, 0.0)
	return e


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
			parts.append({mesh = node.mesh, xform = xform, mi = node})
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
	vp.debug_draw = Viewport.DEBUG_DRAW_DISABLED if data_pass else Viewport.DEBUG_DRAW_UNSHADED
	vp.use_hdr_2d = data_pass
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	parent.add_child(vp)
	cam.current = true
	return vp


static func _fill_holders(e: Dictionary, holder_a: Node, holder_n: Node) -> void:
	for h in [holder_a, holder_n]:
		for c in h.get_children():
			h.remove_child(c)
			c.free()
	var albedo_mats := {}
	var data_mats := {}
	for p in e.parts:
		var a := _copy(p)
		var d := _copy(p)
		for s in p.mesh.get_surface_count():
			var m: Material = p.mi.get_active_material(s)
			if not albedo_mats.has(m):
				albedo_mats[m] = _albedo_material(m)
				data_mats[m] = _capture_material(m)
				e.capture_mats.append(data_mats[m])
			a.set_surface_override_material(s, albedo_mats[m])
			d.set_surface_override_material(s, data_mats[m])
		holder_a.add_child(a)
		holder_n.add_child(d)


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


static func _capture_material(m: Material) -> ShaderMaterial:
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
				cut = 0.5
		sm.set_shader_parameter("alpha_cut", cut)
		sm.set_shader_parameter("albedo_tex", m.albedo_texture)
		sm.set_shader_parameter("albedo_color", m.albedo_color)
		sm.set_shader_parameter("uv1_scale", m.uv1_scale)
		sm.set_shader_parameter("uv1_offset", m.uv1_offset)
	sm.shader = CAPTURE_SHADERS[cull_off]
	return sm
