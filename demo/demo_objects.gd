class_name DemoObjects
extends RefCounted


static func rock(seed_value := 1) -> Node3D:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.6
	sphere.radial_segments = 160
	sphere.rings = 100
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.3
	noise.fractal_octaves = 4
	var arr := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		var n := noise.get_noise_3dv(v * 1.0)
		verts[i] = v * (1.0 + n * 0.35)
		var t := clampf(n * 1.5 + 0.5, 0.0, 1.0)
		colors[i] = Color(0.42, 0.36, 0.30).lerp(Color(0.78, 0.70, 0.55), t)
		if v.y > 0.55:
			colors[i] = colors[i].lerp(Color(0.25, 0.55, 0.2), 0.7)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	st.set_material(mat)
	var mi := MeshInstance3D.new()
	mi.name = "RockMesh"
	mi.mesh = st.commit()
	mi.position.y = 0.55
	var root := Node3D.new()
	root.name = "Rock"
	root.add_child(mi)
	return root


static func tree() -> Node3D:
	var root := Node3D.new()
	root.name = "Tree"
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.36, 0.24, 0.14)
	bark.roughness = 0.9
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.14
	cyl.bottom_radius = 0.24
	cyl.height = 2.0
	cyl.radial_segments = 24
	trunk.mesh = cyl
	trunk.position.y = 1.0
	trunk.material_override = bark
	root.add_child(trunk)
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.2, 0.5, 0.2)
	leaf.roughness = 0.8
	for i in 4:
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 1.0 - i * 0.2
		cm.height = 1.1
		cm.radial_segments = 24
		cone.mesh = cm
		cone.position.y = 1.7 + i * 0.6
		cone.material_override = leaf
		root.add_child(cone)
	return root


static func rings() -> Node3D:
	var root := Node3D.new()
	root.name = "Rings"
	var colors := [Color(0.8, 0.15, 0.1), Color(0.95, 0.75, 0.2), Color(0.15, 0.35, 0.85)]
	var axes := [Vector3(0, 0, 0), Vector3(PI / 2.0, 0, 0), Vector3(0, 0, PI / 2.0)]
	for i in 3:
		var t := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.7
		tm.outer_radius = 0.9
		tm.rings = 64
		tm.ring_segments = 24
		t.mesh = tm
		var m := StandardMaterial3D.new()
		m.albedo_color = colors[i]
		m.metallic = 0.6
		m.roughness = 0.3
		t.material_override = m
		t.position.y = 0.9
		t.rotation = axes[i]
		root.add_child(t)
	return root


static func textured() -> Node3D:
	var size := 256
	var albedo := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	var rough := Image.create_empty(size, size, false, Image.FORMAT_L8)
	var metal := Image.create_empty(size, size, false, Image.FORMAT_L8)
	var occlusion := Image.create_empty(size, size, false, Image.FORMAT_L8)
	var glow := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.03
	noise.fractal_octaves = 3
	for y in size:
		for x in size:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var cell := (x / 32 + y / 32) % 2
			var plate := 1.0 if (x % 32 < 3 or y % 32 < 3) else 0.0
			albedo.set_pixel(x, y, Color(0.55, 0.28, 0.12).lerp(Color(0.75, 0.72, 0.65), float(cell)).lerp(Color(0.2, 0.2, 0.22), plate) * (0.7 + 0.3 * n))
			rough.set_pixel(x, y, Color.from_hsv(0.0, 0.0, clampf(0.25 + 0.6 * n + 0.15 * float(cell) - 0.2 * plate, 0.0, 1.0)))
			metal.set_pixel(x, y, Color.from_hsv(0.0, 0.0, 1.0 if (cell == 1 or plate > 0.5) else 0.0))
			occlusion.set_pixel(x, y, Color.from_hsv(0.0, 0.0, 1.0 - 0.6 * plate - 0.2 * (1.0 - n)))
			var d := Vector2(x % 64, y % 64).distance_to(Vector2(32, 32))
			glow.set_pixel(x, y, Color(1.0, 0.55, 0.1) if (d < 7.0 and (x / 64 + y / 64) % 2 == 0) else Color.BLACK)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(albedo)
	mat.roughness_texture = ImageTexture.create_from_image(rough)
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.metallic_texture = ImageTexture.create_from_image(metal)
	mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.ao_enabled = true
	mat.ao_texture = ImageTexture.create_from_image(occlusion)
	mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.emission_enabled = true
	mat.emission_texture = ImageTexture.create_from_image(glow)
	mat.emission_energy_multiplier = 2.0
	mat.uv1_scale = Vector3(3, 2, 1)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	sphere.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.position.y = 1.0
	var root := Node3D.new()
	root.name = "Textured"
	root.add_child(mi)
	return root


static func all() -> Array:
	return [rock(), tree(), rings()]
