class_name FadeRender
extends RefCounted

const SIZE := 128
const LOD := 40.0
const MARGIN := 10.0
const CASES := {
	none = {fade = false, distances = [30.0, 38.0, 42.0, 52.0]},
	native = {fade = true, distances = [32.0, 40.0, 46.0, 52.0]},
}


# --- A real mesh and its card at several distances, one sheet ---
static func sheet(atlas: OctaAtlas, host: Node, case_name: String) -> Image:
	var spec: Dictionary = CASES[case_name]
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
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 25.0
	cam.near = 0.05
	cam.far = 200.0
	world.add_child(cam)
	cam.current = true
	var rock := DemoObjects.rock(3)
	rock.scale = Vector3.ONE * 3.0
	world.add_child(rock)
	var s := OctaBakeSettings.new()
	s.lod_distance = LOD
	s.fade = OctaLOD.Fade.CROSSFADE if spec.fade else OctaLOD.Fade.NONE
	s.fade_margin = MARGIN
	OctaLOD.attach_card(rock, atlas, 0, OctaLOD.Mode.DYNAMIC_LOD, LOD, OctaAtlas.Quality.HIGH, null, s)
	var b := atlas.bounds[0]
	var c := rock.global_transform * Vector3(b.x, b.y, b.z)
	var out := Image.create_empty(SIZE * spec.distances.size(), SIZE, false, Image.FORMAT_RGBA8)
	for i in spec.distances.size():
		var d: float = spec.distances[i]
		cam.look_at_from_position(c + Vector3(0.0, 0.15, 1.0).normalized() * d, c, Vector3.UP)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var im: Image = vp.get_texture().get_image()
		im.convert(Image.FORMAT_RGBA8)
		out.blit_rect(im, Rect2i(0, 0, SIZE, SIZE), Vector2i(i * SIZE, 0))
	vp.queue_free()
	return out
