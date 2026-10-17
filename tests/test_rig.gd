class_name TestRig
extends RefCounted

const SIZE := 256


# --- Render rig and image comparison ---
static func make(parent: Node, shadows := false) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(vp)
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
	return {vp = vp, world = world, cam = cam, sun = sun}


static func shoot(rig: Dictionary, from: Vector3, at: Vector3, up := Vector3.UP) -> void:
	rig.cam.look_at_from_position(from, at, up)
	rig.vp.render_target_update_mode = SubViewport.UPDATE_ONCE


static func grab(rig: Dictionary) -> Image:
	var im: Image = rig.vp.get_texture().get_image()
	im.convert(Image.FORMAT_RGBA8)
	return im


static func compare(a: Image, b: Image) -> Dictionary:
	var inter := 0
	var uni := 0
	var err := 0.0
	var bad := 0
	for y in SIZE:
		for x in SIZE:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var ia := ca.a > 0.5
			var ib := cb.a > 0.5
			if ia or ib:
				uni += 1
			if ia and ib:
				inter += 1
				var d := (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
				err += d
				if d > 0.15:
					bad += 1
	return {iou = float(inter) / maxf(uni, 1), mae = err / maxf(inter, 1) * 255.0, bad = float(bad + uni - inter) / maxf(uni, 1) * 100.0}


static func difference(a: Image, b: Image) -> float:
	var err := 0.0
	var n := 0
	for y in SIZE:
		for x in SIZE:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if ca.a > 0.5 or cb.a > 0.5:
				err += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
				n += 1
	return err / maxf(n, 1) * 255.0


static func interior_difference(a: Image, b: Image) -> float:
	var err := 0.0
	var n := 0
	for y in SIZE:
		for x in SIZE:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if ca.a > 0.99 and cb.a > 0.99:
				err += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
				n += 1
	return err / maxf(n, 1) * 255.0
