class_name OctaPacker
extends RefCounted

const MAX_SIDE := 16384


# --- Compatibility ---
static func compatible(a: OctaAtlas, b: OctaAtlas) -> bool:
	return mismatch(a, b).is_empty()


static func mismatch(a: OctaAtlas, b: OctaAtlas) -> String:
	if a == null or b == null:
		return "a missing atlas"
	if a.format_version != b.format_version:
		return "the atlas format"
	if a.grid_size != b.grid_size:
		return "the grid size"
	if a.frame_resolution != b.frame_resolution:
		return "the view size"
	if not is_equal_approx(a.frame_scale, b.frame_scale):
		return "the padding"
	if a.hemisphere != b.hemisphere:
		return "the full sphere mode"
	if a.write_depth != b.write_depth or a.precise_search != b.precise_search:
		return "the depth or search option"
	if a.view_visibility != b.view_visibility or a.pyramid_search != b.pyramid_search or a.parallax_refine != b.parallax_refine:
		return "a shading option"
	if a.shadow_views != b.shadow_views:
		return "the shadow views"
	if tile_shape(a.albedo, a) != tile_shape(b.albedo, b) \
			or tile_shape(a.normal_depth, a) != tile_shape(b.normal_depth, b) \
			or tile_shape(a.orm, a) != tile_shape(b.orm, b) \
			or tile_shape(a.emission, a) != tile_shape(b.emission, b) \
			or tile_shape(a.back_depth, a) != tile_shape(b.back_depth, b) \
			or tile_shape(a.max_coverage, a) != tile_shape(b.max_coverage, b):
		return "the maps"
	return ""


static func tile_shape(tex: Texture2D, atlas: OctaAtlas) -> Vector2i:
	if tex == null:
		return Vector2i.ZERO
	return Vector2i(maxi(tex.get_width() / maxi(atlas.tiles.x, 1), 1), maxi(tex.get_height() / maxi(atlas.tiles.y, 1), 1))


# --- Packing ---
static func pack(atlases: Array, max_side: int = 4096, out: Dictionary = {}) -> Array[OctaAtlas]:
	var result: Array[OctaAtlas] = []
	var groups: Array = []
	for a: OctaAtlas in atlases:
		if a == null or a.object_count() == 0:
			continue
		var placed := false
		for g: Array in groups:
			if compatible(g[0], a):
				g.append(a)
				placed = true
				break
		if not placed:
			groups.append([a])
	for g: Array in groups:
		if g.size() < 2:
			result.append(g[0])
			continue
		result.append_array(_pack_run(g, max_side, out))
	return result


static func _pack_run(run: Array, max_side: int, out: Dictionary) -> Array[OctaAtlas]:
	var first: OctaAtlas = run[0]
	var block := first.grid_size * first.frame_resolution
	var per_side := maxi(mini(max_side, MAX_SIDE) / maxi(block, 1), 1)
	var cap := mini(per_side * per_side, OctaAtlas.MAX_OBJECTS)
	var entries: Array = []
	for a: OctaAtlas in run:
		for oi in a.object_count():
			entries.append([a, oi])
	var result: Array[OctaAtlas] = []
	var start := 0
	while start < entries.size():
		var slice := entries.slice(start, start + cap)
		start += cap
		var cols := mini(int(ceil(sqrt(float(slice.size())))), per_side)
		var rows := int(ceil(float(slice.size()) / float(cols)))
		result.append(_build(slice, cols, rows, first, out))
	return result


static func _build(slice: Array, cols: int, rows: int, first: OctaAtlas, out: Dictionary) -> OctaAtlas:
	var atlas := OctaAtlas.new()
	atlas.format_version = first.format_version
	atlas.bake_settings = first.bake_settings.duplicate() if first.bake_settings != null else null
	atlas.write_depth = first.write_depth
	atlas.precise_search = first.precise_search
	atlas.view_visibility = first.view_visibility
	atlas.pyramid_search = first.pyramid_search
	atlas.parallax_refine = first.parallax_refine
	atlas.shadow_views = first.shadow_views
	atlas.grid_size = first.grid_size
	atlas.hemisphere = first.hemisphere
	atlas.parent_space = first.parent_space
	atlas.tiles = Vector2i(cols, rows)
	atlas.frame_resolution = first.frame_resolution
	atlas.frame_scale = first.frame_scale
	var ta := tile_shape(first.albedo, first)
	var tn := tile_shape(first.normal_depth, first)
	var tb := tile_shape(first.back_depth, first)
	var to := tile_shape(first.orm, first)
	var te := tile_shape(first.emission, first)
	var tc := tile_shape(first.max_coverage, first)
	var img_a := Image.create_empty(cols * ta.x, rows * ta.y, false, Image.FORMAT_RGBA8)
	var img_n := Image.create_empty(cols * tn.x, rows * tn.y, false, Image.FORMAT_RGBA8)
	var img_b: Image = Image.create_empty(cols * tb.x, rows * tb.y, false, Image.FORMAT_R8) if first.back_depth != null else null
	var img_o: Image = Image.create_empty(cols * to.x, rows * to.y, false, Image.FORMAT_RGBA8) if first.orm != null else null
	var img_e: Image = Image.create_empty(cols * te.x, rows * te.y, false, Image.FORMAT_RGBA8) if first.emission != null else null
	var img_c: Image = Image.create_empty(cols * tc.x, rows * tc.y, false, Image.FORMAT_R8) if first.max_coverage != null else null
	var cache := {}
	for i in slice.size():
		var src: OctaAtlas = slice[i][0]
		var oi: int = slice[i][1]
		var sx := oi % src.tiles.x
		var sy := oi / src.tiles.x
		var dx := i % cols
		var dy := i / cols
		_blit(img_a, _image_for(cache, src.albedo, Image.FORMAT_RGBA8), sx, sy, dx, dy, ta)
		_blit(img_n, _image_for(cache, src.normal_depth, Image.FORMAT_RGBA8), sx, sy, dx, dy, tn)
		if img_b != null:
			_blit(img_b, _image_for(cache, src.back_depth, Image.FORMAT_R8), sx, sy, dx, dy, tb)
		if img_o != null:
			_blit(img_o, _image_for(cache, src.orm, Image.FORMAT_RGBA8), sx, sy, dx, dy, to)
		if img_e != null:
			_blit(img_e, _image_for(cache, src.emission, Image.FORMAT_RGBA8), sx, sy, dx, dy, te)
		if img_c != null:
			_blit(img_c, _image_for(cache, src.max_coverage, Image.FORMAT_R8), sx, sy, dx, dy, tc)
		atlas.object_names.append(src.object_names[oi] if oi < src.object_names.size() else "")
		atlas.bounds.append(src.bounds[oi] if oi < src.bounds.size() else Vector4(0.0, 0.0, 0.0, 1.0))
		atlas.surface_params.append(src.surface_params[oi] if oi < src.surface_params.size() else OctaAtlas.DEFAULT_SURFACE)
		var mp: Vector4 = src.material_params[oi] if oi < src.material_params.size() else OctaAtlas.DEFAULT_MATERIAL
		if src.format_version < 4:
			mp = Vector4(mp.x, mp.y, 1.0, 0.0)
		atlas.material_params.append(mp)
		if not out.has(src):
			out[src] = {}
		out[src][oi] = [atlas, i]
	img_a.generate_mipmaps()
	img_n.generate_mipmaps()
	atlas.albedo = ImageTexture.create_from_image(img_a)
	atlas.normal_depth = ImageTexture.create_from_image(img_n)
	atlas.max_coverage = ImageTexture.create_from_image(img_c) if img_c != null else null
	if img_o != null:
		img_o.generate_mipmaps()
		atlas.orm = ImageTexture.create_from_image(img_o)
	if img_e != null:
		img_e.generate_mipmaps()
		atlas.emission = ImageTexture.create_from_image(img_e)
	if img_b != null:
		img_b.generate_mipmaps()
		atlas.back_depth = ImageTexture.create_from_image(img_b)
	return atlas


static func _blit(dst: Image, src: Image, sx: int, sy: int, dx: int, dy: int, block: Vector2i) -> void:
	if src == null:
		return
	dst.blit_rect(src, Rect2i(sx * block.x, sy * block.y, block.x, block.y), Vector2i(dx * block.x, dy * block.y))


static func _image_for(cache: Dictionary, tex: Texture2D, fmt: int) -> Image:
	if tex == null:
		return null
	var key := tex.get_instance_id()
	if cache.has(key):
		return cache[key]
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	if img.has_mipmaps():
		img.clear_mipmaps()
	if img.get_format() != fmt:
		img.convert(fmt)
	cache[key] = img
	return img


# --- Saving ---
static func save_packed(atlases: Array, dir: String, base_name: String) -> Array[String]:
	var paths: Array[String] = []
	var folder := dir if dir != "" else "res://"
	if not folder.ends_with("/"):
		folder += "/"
	for i in atlases.size():
		var base := "%s%s%s" % [folder, base_name, "" if i == 0 else "_%d" % (i + 1)]
		var path := base + ".res"
		var n := 2
		while ResourceLoader.exists(path):
			path = "%s_%d.res" % [base, n]
			n += 1
		var err := ResourceSaver.save(atlases[i], path, ResourceSaver.FLAG_COMPRESS)
		if err != OK:
			push_error("Octahedral Impostor LOD: could not save %s (%d)" % [path, err])
			continue
		atlases[i].take_over_path(path)
		paths.append(path)
	return paths
