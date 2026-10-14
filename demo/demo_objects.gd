class_name DemoObjects
extends RefCounted


# --- Procedural test objects ---
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
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.22
	cyl.height = 2.2
	cyl.radial_segments = 48
	trunk.mesh = cyl
	trunk.position.y = 1.1
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.40, 0.26, 0.15)
	trunk.material_override = bark
	root.add_child(trunk)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.22, 0.55, 0.18)
	leaf_mat.roughness = 0.7
	var blobs := [Vector3(0, 2.4, 0), Vector3(0.55, 2.0, 0.2), Vector3(-0.5, 2.1, -0.25), Vector3(0.1, 2.0, -0.55), Vector3(-0.15, 1.9, 0.55)]
	for i in blobs.size():
		var b := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.55 - i * 0.04
		s.height = s.radius * 2.0
		s.radial_segments = 64
		s.rings = 32
		b.mesh = s
		b.position = blobs[i]
		b.material_override = leaf_mat
		root.add_child(b)
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var u := (x - 32) / 32.0
			var v := y / 64.0
			var inside := absf(u) < (1.0 - v) * 0.6 * (0.6 + 0.4 * sin(v * 40.0))
			img.set_pixel(x, y, Color(0.35, 0.7, 0.2, 1.0 if inside else 0.0))
	var frond_mat := StandardMaterial3D.new()
	frond_mat.albedo_texture = ImageTexture.create_from_image(img)
	frond_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	frond_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 3:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.9, 0.9)
		q.mesh = qm
		q.material_override = frond_mat
		q.position = Vector3(0, 0.45, 0)
		q.rotation.y = i * PI / 3.0
		root.add_child(q)
	return root


static func rings() -> Node3D:
	var root := Node3D.new()
	root.name = "Rings"
	var colors := [Color(0.8, 0.15, 0.1), Color(0.95, 0.75, 0.2), Color(0.15, 0.35, 0.85)]
	for i in 3:
		var t := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.55
		tm.outer_radius = 0.8
		tm.rings = 96
		tm.ring_segments = 32
		t.mesh = tm
		var m := StandardMaterial3D.new()
		m.albedo_color = colors[i]
		m.metallic = 0.6
		m.roughness = 0.35
		t.material_override = m
		t.position.y = 0.9
		t.rotation = Vector3(PI / 2.0, i * PI / 3.0, 0)
		root.add_child(t)
	return root


static func all() -> Array:
	return [rock(), tree(), rings()]
