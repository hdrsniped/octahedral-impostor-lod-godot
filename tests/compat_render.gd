class_name CompatRender
extends RefCounted

const SIZE := 128
const VIEWS := [Vector3(15.0, 20.0, 3.5), Vector3(40.0, 130.0, 3.5), Vector3(70.0, 250.0, 4.0)]


static func ref_name(set_name: String) -> String:
	return "v2_plain" if set_name == "v2_fmt2" else set_name


static func qualities(set_name: String) -> Array:
	return [0, 1, 2] if set_name.begins_with("v1") else [0, 1, 2, 3]


# --- Render every object at every quality into one sheet ---
static func sheet(atlas: OctaAtlas, host: Node, set_name: String) -> Image:
	var shadows := false
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(vp)
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
	sun.shadow_enabled = shadows
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	world.add_child(cam)
	cam.current = true
	var qs := qualities(set_name)
	var out := Image.create_empty(SIZE * VIEWS.size(), SIZE * atlas.object_count() * qs.size(), false, Image.FORMAT_RGBA8)
	var row := 0
	for oi in atlas.object_count():
		var b := atlas.bounds[oi]
		var c := Vector3(b.x, b.y, b.z)
		for q in qs:
			var card := atlas.create_card(oi, q)
			world.add_child(card)
			for vi in VIEWS.size():
				var v: Vector3 = VIEWS[vi]
				var e := deg_to_rad(v.x)
				var az := deg_to_rad(v.y)
				var dir := Vector3(cos(e) * sin(az), sin(e), cos(e) * cos(az))
				cam.look_at_from_position(c + dir * b.w * v.z, c, Vector3.UP)
				vp.render_target_update_mode = SubViewport.UPDATE_ONCE
				await RenderingServer.frame_post_draw
				var im: Image = vp.get_texture().get_image()
				im.convert(Image.FORMAT_RGBA8)
				out.blit_rect(im, Rect2i(0, 0, SIZE, SIZE), Vector2i(vi * SIZE, row * SIZE))
			card.free()
			row += 1
	vp.queue_free()
	return out
