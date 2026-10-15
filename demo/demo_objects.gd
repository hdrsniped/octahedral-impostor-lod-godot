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


static func all() -> Array:
	return [rock(), tree(), rings()]
