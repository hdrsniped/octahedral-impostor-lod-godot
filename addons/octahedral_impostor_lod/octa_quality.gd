@tool
class_name OctaQuality
extends RefCounted

const SIZE := 192
const VIEWS := [
	Vector3(5, 0, 3.5), Vector3(20, 60, 3.5), Vector3(35, 130, 3.5), Vector3(50, 200, 3.5),
	Vector3(15, 250, 3.5), Vector3(65, 310, 3.5), Vector3(25, 160, 6.0), Vector3(40, 20, 6.0),
]
const BAD_LIMIT := 10.0


# --- Measure ---
static func measure(source: Node3D, host: Node) -> Dictionary:
	var cards := OctaLOD.find_cards_below(source)
	if cards.is_empty():
		return {error = "'%s' has no impostors to check." % source.name}
	var bounds: Vector4 = OctaBaker._collect(source).bounds
	if bounds.w <= 0.0:
		return {error = "'%s' has no visible mesh." % source.name}
	var rig := Node.new()
	rig.name = "_OctaQualityRig"
	host.add_child(rig)
	var real := _make_view(rig)
	var fake := _make_view(rig)
	var dup: Node3D = source.duplicate()
	dup.transform = Transform3D.IDENTITY
	dup.visible = true
	for n in dup.find_children("*", "", true, false):
		if n.has_meta(OctaAtlas.CARD_META):
			n.get_parent().remove_child(n)
			n.free()
	for gi in OctaLOD.geometry_below(dup):
		gi.visibility_parent = NodePath()
		gi.visibility_range_end = 0.0
		gi.visibility_range_begin = 0.0
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if gi is Node3D:
			gi.visible = true
	real.world.add_child(dup)
	var inv := source.global_transform.affine_inverse()
	for card: Node3D in cards:
		var c: Node3D = card.duplicate()
		c.visible = true
		fake.world.add_child(c)
		c.visibility_range_begin = 0.0
		c.visibility_range_begin_margin = 0.0
		c.visibility_range_end = 0.0
		c.visibility_range_end_margin = 0.0
		c.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		c.transform = inv * card.global_transform

	var center := Vector3(bounds.x, bounds.y, bounds.z)
	var per_view: Array[Dictionary] = []
	for v: Vector3 in VIEWS:
		var e := deg_to_rad(v.x)
		var az := deg_to_rad(v.y)
		var dir := Vector3(cos(e) * sin(az), sin(e), cos(e) * cos(az))
		for view in [real, fake]:
			view.cam.look_at_from_position(center + dir * bounds.w * v.z, center, Vector3.UP)
			view.vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_instance_valid(rig):
			return {error = "Quality check cancelled."}
		per_view.append(_compare(real.vp.get_texture().get_image(), fake.vp.get_texture().get_image()))
	rig.queue_free()

	var iou := 0.0
	var bad := 0.0
	var worst := 1.0
	for r in per_view:
		iou += r.iou
		bad += r.bad
		worst = minf(worst, r.iou)
	iou /= per_view.size()
	bad = bad / per_view.size() * 100.0
	return {name = String(source.name), cards = cards.size(), iou = iou, worst_iou = worst, bad_pct = bad,
		good = bad <= BAD_LIMIT and worst >= 0.85, suggestion = _suggest(bad, worst, cards)}


static func _suggest(bad: float, worst: float, cards: Array) -> String:
	if bad <= BAD_LIMIT and worst >= 0.85:
		return "Looks good."
	var mat: ShaderMaterial = (cards[0] as GeometryInstance3D).material_override
	var ultra: bool = cards[0] is OctaImpostor and cards[0].quality == OctaAtlas.Quality.ULTRA
	if cards.size() == 1:
		return "Re-bake with Complex shapes > Split parts on and Quality = Ultra." if not ultra else "Re-bake with Complex shapes > Split parts on."
	if not ultra:
		return "Switch Quality to Ultra."
	return "Try Complex shapes > Back layer, a bigger atlas, or a larger LOD distance."


# --- Helpers ---
static func _make_view(rig: Node) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	rig.add_child(vp)
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
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.01
	world.add_child(cam)
	cam.current = true
	return {vp = vp, world = world, cam = cam}


static func _compare(a: Image, b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	var da := a.get_data()
	var db := b.get_data()
	var inter := 0
	var uni := 0
	var bad := 0
	for i in range(0, da.size(), 4):
		var ia: bool = da[i + 3] > 127
		var ib: bool = db[i + 3] > 127
		if ia or ib:
			uni += 1
		if ia and ib:
			inter += 1
			var d := (absi(da[i] - db[i]) + absi(da[i + 1] - db[i + 1]) + absi(da[i + 2] - db[i + 2])) / 3.0
			if d > 38.25:
				bad += 1
	return {iou = float(inter) / maxf(uni, 1), bad = float(bad + uni - inter) / maxf(uni, 1)}
