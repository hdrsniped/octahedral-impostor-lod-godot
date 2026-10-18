@tool
class_name OctaLOD
extends RefCounted

enum Mode {
	DYNAMIC_LOD,
	DUPLICATE,
	REPLACE,
}

enum LodMode {
	DISTANCE,
	SCREEN_SIZE,
}

enum Fade {
	NONE,
	CROSSFADE,
}

const DEFAULT_FOV := 75.0
const FOV_SETTING := "octa_lod/reference_fov"

static var _fade_cache := -1
const SOURCE_META := &"octa_source"
const MODE_META := &"octa_mode"


# --- Generate and attach ---
static func generate(sources: Array, host: Node, settings: OctaBakeSettings = null, save_path := "", job: OctaBakeJob = null) -> OctaAtlas:
	if settings == null:
		settings = OctaBakeSettings.new()
	if settings.split_parts:
		sources = split_parts(sources)
	var atlas: OctaAtlas
	if save_path.is_empty():
		atlas = await OctaBaker.bake(sources, host, settings, job)
	else:
		atlas = await OctaBaker.bake_to_file(sources, host, save_path, settings, job)
	if atlas != null:
		for i in sources.size():
			attach_card(sources[i], atlas, i, settings.mode, settings.lod_distance, settings.quality, null, settings)
	return atlas


static func attach_card(source: Node3D, atlas: OctaAtlas, index: int, mode := Mode.DYNAMIC_LOD,
		lod_distance := 40.0, quality := OctaAtlas.Quality.HIGH, owner: Node = null, settings: OctaBakeSettings = null) -> MeshInstance3D:
	var card := atlas.create_card(index, quality)
	if is_child_card(source, mode):
		source.add_child(card, true)
	else:
		card.name = String(source.name) + "_OctaImpostor"
		card.transform = atlas.card_transform(source)
		source.get_parent().add_child(card, true)
	card.set_meta(SOURCE_META, card.get_path_to(source))
	card.set_meta(MODE_META, mode)
	if settings != null:
		card.configure(settings, world_scale(card))
	if mode == Mode.DYNAMIC_LOD:
		if settings == null:
			card.visibility_range_begin = lod_distance
			card.visibility_range_begin_margin = 1.0
		for gi in geometry_below(source):
			gi.visibility_parent = gi.get_path_to(card)
		card.refresh_fade()
	elif mode == Mode.REPLACE:
		source.visible = false
	if owner != null:
		card.owner = owner
	return card


static func signature(node: Node3D) -> String:
	var parts := PackedStringArray()
	for gi in geometry_below(node):
		if gi is MeshInstance3D and gi.mesh != null:
			var mats := PackedStringArray()
			for s in gi.mesh.get_surface_count():
				var m: Material = gi.get_active_material(s)
				mats.append(str(m.get_instance_id() if m != null else 0))
			var rel := node.global_transform.affine_inverse() * gi.global_transform
			parts.append("%d|%s|%s" % [gi.mesh.get_instance_id(), rel, ",".join(mats)])
	return ";".join(parts)


static func scene_candidates(root: Node, lod_distance: float, use_groups := true) -> Array:
	var out := []
	_gather_candidates(root, lod_distance, out, OctaImpostorGroup.claimed_nodes(root) if use_groups else {}, use_groups)
	return out


static func _gather_candidates(node: Node, lod: float, out: Array, claimed: Dictionary, use_groups: bool) -> void:
	for c: Node in node.get_children():
		if c.has_meta(OctaAtlas.CARD_META) or (c is Node3D and not c.visible) or claimed.has(c):
			continue
		if not c is Node3D or (use_groups and c is OctaImpostorGroup):
			_gather_candidates(c, lod, out, claimed, use_groups)
			continue
		var geo := geometry_below(c).filter(func(g: Node) -> bool: return g is MeshInstance3D and g.mesh != null)
		if geo.is_empty():
			_gather_candidates(c, lod, out, claimed, use_groups)
			continue
		var radius := candidate_radius(c)
		var tris := 0
		for g: MeshInstance3D in geo:
			tris += triangle_count(g.mesh)
		var pct := screen_size_for_distance(radius, lod)
		out.append({node = c, pct = pct, tris = tris, cards = find_cards(c).size()})


static func candidate_radius(node: Node3D) -> float:
	var corners: Array[Vector3] = []
	_candidate_corners(node, Transform3D.IDENTITY, true, corners)
	if corners.is_empty():
		return OctaBaker.MIN_RADIUS
	var lo := corners[0]
	var hi := corners[0]
	for p in corners:
		lo = lo.min(p)
		hi = hi.max(p)
	var c := (lo + hi) * 0.5
	var r2 := 0.0
	for p in corners:
		r2 = maxf(r2, c.distance_squared_to(p))
	return maxf(sqrt(r2), OctaBaker.MIN_RADIUS)


static func _candidate_corners(node: Node, xform: Transform3D, is_root: bool, out: Array[Vector3]) -> void:
	if node.has_meta(OctaAtlas.CARD_META):
		return
	if node is Node3D:
		if not node.visible:
			return
		if not is_root:
			xform = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var box: AABB = (node as MeshInstance3D).mesh.get_aabb()
		for i in 8:
			out.append(xform * (box.position + box.size * Vector3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1))))
	for child in node.get_children():
		_candidate_corners(child, xform, false, out)


static func triangle_count(mesh: Mesh) -> int:
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		var n := 0
		for s in am.get_surface_count():
			var indices := am.surface_get_array_index_len(s)
			n += (indices if indices > 0 else am.surface_get_array_len(s)) / 3
		return n
	return mesh.get_faces().size() / 3


static func split_parts(sources: Array) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for s: Node3D in sources:
		for gi in geometry_below(s):
			if gi is MeshInstance3D and gi.mesh != null and gi.visible and not out.has(gi):
				out.append(gi)
	return out


# --- Remove ---
static func remove_cards(source: Node3D) -> void:
	for card in find_cards(source):
		_restore(source, card)
		card.get_parent().remove_child(card)
		card.queue_free()


static func find_cards_below(source: Node) -> Array[Node3D]:
	var found := {}
	for c in find_cards(source):
		found[c] = true
	var stack: Array[Node] = [source]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n != source and n.has_meta(OctaAtlas.CARD_META):
			if n.get_node_or_null(n.get_meta(SOURCE_META, NodePath(".."))) != null:
				found[n] = true
			continue
		for child in n.get_children():
			stack.append(child)
	var out: Array[Node3D] = []
	for n in found:
		out.append(n)
	return out


static func find_cards(source: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var pool := source.get_children()
	if source.get_parent() != null:
		pool.append_array(source.get_parent().get_children())
	for n in pool:
		if n is Node3D and n.has_meta(OctaAtlas.CARD_META) and n.get_node_or_null(n.get_meta(SOURCE_META, NodePath(".."))) == source:
			out.append(n)
	return out


# --- Card overrides ---
static func card_overrides(card: Node) -> Dictionary:
	var out := {}
	var base: OctaBakeSettings = card.atlas.bake_settings if card is OctaImpostor and card.atlas != null else null
	if base == null:
		return out
	if card.quality != base.quality:
		out.quality = card.quality
	if card.lod_mode != base.lod_mode:
		out.lod_mode = card.lod_mode
	var replace: bool = card.get_meta(MODE_META, Mode.DYNAMIC_LOD) == Mode.REPLACE
	if card.lod_mode == LodMode.DISTANCE and not replace and (card.lod_mode != base.lod_mode or not is_equal_approx(card.lod_distance, base.lod_distance)):
		out.lod_distance = card.lod_distance
	if not is_equal_approx(card.screen_percent, base.lod_screen_percent):
		out.screen_percent = card.screen_percent
	if card.fade != base.fade:
		out.fade = card.fade
	if not is_equal_approx(card.fade_margin, base.fade_margin):
		out.fade_margin = card.fade_margin
	if card.fade_real_mesh != base.fade_real_mesh:
		out.fade_real_mesh = card.fade_real_mesh
	if card.tint != Color.WHITE:
		out.tint = card.tint
	if not is_equal_approx(card.depth_multiplier, 1.0):
		out.depth_multiplier = card.depth_multiplier
	if not is_equal_approx(card.wind_strength, base.wind_strength):
		out.wind_strength = card.wind_strength
	return out


static func apply_overrides(card: OctaImpostor, overrides: Dictionary) -> void:
	for p: String in ["lod_mode", "screen_percent", "fade", "fade_margin", "fade_real_mesh"]:
		if overrides.has(p):
			card.set(p, overrides[p])
	if overrides.has("lod_distance") and card.lod_mode == LodMode.DISTANCE:
		card.lod_distance = overrides.lod_distance
	for p: String in ["quality", "tint", "depth_multiplier", "wind_strength"]:
		if overrides.has(p):
			card.set(p, overrides[p])


# --- Screen size and fade ---
static func default_fov() -> float:
	return float(ProjectSettings.get_setting(FOV_SETTING, DEFAULT_FOV))


static func distance_for_screen_size(radius: float, percent: float, fov_deg := -1.0) -> float:
	if percent <= 0.0:
		return 0.0
	var fov := fov_deg if fov_deg > 0.0 else default_fov()
	return radius / (percent / 100.0 * tan(deg_to_rad(fov) * 0.5))


static func screen_size_for_distance(radius: float, distance: float, fov_deg := -1.0) -> float:
	if distance <= 0.0:
		return 100.0
	var fov := fov_deg if fov_deg > 0.0 else default_fov()
	return radius / (distance * tan(deg_to_rad(fov) * 0.5)) * 100.0


static func world_scale(node: Node) -> float:
	var s := 1.0
	var n := node
	while n != null:
		if n is Node3D:
			var sc: Vector3 = (n as Node3D).transform.basis.get_scale().abs()
			s *= maxf(sc.x, maxf(sc.y, sc.z))
		n = n.get_parent()
	return s


static func fade_supported() -> bool:
	if _fade_cache < 0:
		var method := String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")) if Engine.is_editor_hint() else RenderingServer.get_current_rendering_method()
		_fade_cache = 1 if method == "forward_plus" else 0
	return _fade_cache == 1


static func fade_available() -> bool:
	return true


static func fade_kind() -> String:
	return "native" if fade_supported() else "dither"


static func fade_band(distance: float, margin: float) -> Vector2:
	return Vector2(maxf(distance - margin, 0.0), distance + margin)


# --- Helpers ---
static func is_child_card(source: Node, mode: Mode) -> bool:
	return mode == Mode.DYNAMIC_LOD and not source is GeometryInstance3D


static func geometry_below(node: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	if node.has_meta(OctaAtlas.CARD_META):
		return out
	if node is GeometryInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(geometry_below(c))
	return out


static func _restore(source: Node3D, card: Node) -> void:
	for gi in geometry_below(source):
		if gi.get_node_or_null(gi.visibility_parent) == card:
			OctaMeshFade.restore(gi)
			gi.visibility_parent = NodePath()
	if card.get_meta(MODE_META, Mode.DYNAMIC_LOD) == Mode.REPLACE:
		source.visible = true
