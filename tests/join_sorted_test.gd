extends SceneTree

const CELL := 50.0
const SIZE_LIMIT := 20.0
const COUNT_LIMIT := 128
const OBJECTS := 3
const GATE := 0.05

var _fails := 0
var _count := 4000
var _extent := 800.0
var _far := 2500.0
var _dist := "clustered"
var _measure := false
var _rounds := 3
var _size := SIZE_LIMIT
var _per := COUNT_LIMIT
var _fov := 30.0
var _aim := Vector2(0.12, 0.0)
var _clusters := 6
var _background := 0.05
var _sigma := Vector2(20.0, 45.0)
var _cell := CELL
var _atlas: OctaAtlas
var _bounds: Array[Vector4] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


# --- Join sorting, regions and culling ---
func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			_count = int(arg.trim_prefix("--count="))
		elif arg.begins_with("--extent="):
			_extent = float(arg.trim_prefix("--extent="))
		elif arg.begins_with("--far="):
			_far = float(arg.trim_prefix("--far="))
		elif arg.begins_with("--dist="):
			_dist = arg.trim_prefix("--dist=")
		elif arg.begins_with("--size="):
			_size = float(arg.trim_prefix("--size="))
		elif arg.begins_with("--per="):
			_per = int(arg.trim_prefix("--per="))
		elif arg.begins_with("--cell="):
			_cell = float(arg.trim_prefix("--cell="))
		elif arg.begins_with("--fov="):
			_fov = float(arg.trim_prefix("--fov="))
		elif arg.begins_with("--aim="):
			_aim = Vector2(float(arg.trim_prefix("--aim=").get_slice(",", 0)), float(arg.trim_prefix("--aim=").get_slice(",", 1)))
		elif arg.begins_with("--clusters="):
			_clusters = int(arg.trim_prefix("--clusters="))
		elif arg.begins_with("--background="):
			_background = float(arg.trim_prefix("--background="))
		elif arg.begins_with("--sigma="):
			_sigma = Vector2(float(arg.trim_prefix("--sigma=").get_slice(",", 0)), float(arg.trim_prefix("--sigma=").get_slice(",", 1)))
		elif arg.begins_with("--rounds="):
			_rounds = int(arg.trim_prefix("--rounds="))
		elif arg == "--measure=1":
			_measure = true
	print("RENDERER %s" % RenderingServer.get_current_rendering_method())
	root.size = Vector2i(1280, 720)
	for i in 5:
		await process_frame
	_unit()
	await _bake()
	var scene := _scene()
	var fixed := _build(scene, false)
	var adaptive := _build(scene, true)
	_equivalence(scene, fixed, adaptive)
	_fixed_matches_v21(scene, fixed)
	_limits(adaptive)
	_morton(adaptive)
	var cam := _camera()
	var stat_fixed := _stats(fixed, cam)
	var stat_adaptive := _stats(adaptive, cam)
	_report("fixed", stat_fixed)
	_report("adaptive", stat_adaptive)
	var better: bool = stat_adaptive.waste < stat_fixed.waste if _count == 4000 else stat_adaptive.waste <= stat_fixed.waste
	_check(better and stat_adaptive.visible == stat_fixed.visible, "adaptive join submits fewer off-screen instances (%d vs %d, same %d in view)" % [stat_adaptive.waste, stat_fixed.waste, stat_adaptive.visible])
	_free(fixed)
	_free(adaptive)
	if _measure:
		await _timing(scene, cam)
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)


# --- Z-order codes and regions on plain points ---
func _unit() -> void:
	var pts := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 1, 1)])
	var c := OctaJoin.codes(pts)
	_check(c[0] == 0 and c[1] == 0x09249249 and c[2] == 0x12492492 and c[3] == 0x24924924 and c[4] == 0x3FFFFFFF, "Morton codes interleave x, y, z (%s)" % [c])
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var many := PackedVector3Array()
	for i in 500:
		many.append(Vector3(rng.randf() * 90.0, rng.randf() * 3.0, rng.randf() * 90.0))
	var parts := OctaJoin.partition(many, 1000.0, true, 15.0, 16)
	var seen := {}
	var ok := true
	for p: PackedInt32Array in parts:
		for i in p:
			ok = ok and not seen.has(i)
			seen[i] = true
		var box := OctaJoin.bounds(many, p)
		ok = ok and p.size() <= 16 and (box.get_longest_axis_size() <= 15.0 or p.size() < OctaJoin.SIZE_SPLIT_MIN)
	_check(ok and seen.size() == 500, "partition covers every point once, regions within %d points and 15 m (%d regions)" % [16, parts.size()])
	var same := OctaJoin.partition(many, 1000.0, true, 15.0, 16)
	_check(str(parts) == str(same), "partition is deterministic")
	var off := OctaJoin.partition(many, 30.0, false, 15.0, 16)
	var flat := 0
	for p: PackedInt32Array in off:
		flat += p.size()
		for k in range(1, p.size()):
			ok = ok and p[k] > p[k - 1]
	_check(flat == 500 and ok, "adaptive off keeps the cells with the cards in input order")


func _bake() -> void:
	var srcs := [DemoObjects.rock(1), DemoObjects.tree(), DemoObjects.rings()]
	for s: Node3D in srcs:
		root.add_child(s)
	var settings := OctaBakeSettings.new()
	settings.max_atlas_size = 1024
	settings.grid_size = 8
	_atlas = await OctaBaker.bake(srcs, root, settings)
	for s: Node3D in srcs:
		s.free()
	for i in OBJECTS:
		_bounds.append(_atlas.bounds[i])


func _scene() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var xforms: Array = []
	var objects := PackedInt32Array()
	var customs: Array = []
	var centers: Array[Vector3] = []
	var spreads: Array[float] = []
	var clusters := _clusters if _clusters > 0 else maxi(8, _count / 130)
	for i in clusters:
		centers.append(Vector3(rng.randf_range(-0.5, 0.5) * _extent, 0.0, rng.randf_range(-0.5, 0.5) * _extent))
		spreads.append(rng.randf_range(_sigma.x, _sigma.y))
	for i in _count:
		var p := Vector3(rng.randf_range(-0.5, 0.5) * _extent, 0.0, rng.randf_range(-0.5, 0.5) * _extent)
		if _dist == "clustered" and rng.randf() >= _background:
			var k := rng.randi() % clusters
			p = centers[k] + Vector3(rng.randfn(0.0, spreads[k]), 0.0, rng.randfn(0.0, spreads[k]))
		p.y = rng.randf_range(0.0, 6.0)
		var sc := rng.randf_range(0.8, 1.6)
		xforms.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3.ONE * sc), p))
		objects.append(rng.randi() % OBJECTS)
		customs.append(OctaAtlas.joined_custom(Color.from_hsv(rng.randf(), 0.5, 1.0), rng.randf_range(0.5, 1.0)))
	return {xforms = xforms, objects = objects, customs = customs}


func _build(scene: Dictionary, adaptive: bool) -> Array:
	var out := []
	for obj in OBJECTS:
		var xs: Array = []
		var cs: Array = []
		for i in scene.xforms.size():
			if scene.objects[i] == obj:
				xs.append(scene.xforms[i])
				cs.append(scene.customs[i])
		for mmi in _atlas.create_multimeshes(obj, xs, OctaAtlas.Quality.HIGH, cs, _cell, adaptive, _size, _per):
			if mmi.multimesh.instance_count < 2:
				mmi.free()
				continue
			mmi.set_meta("object", obj)
			out.append(mmi)
	return out


func _free(mmis: Array) -> void:
	for m: MultiMeshInstance3D in mmis:
		if m.get_parent() != null:
			m.get_parent().remove_child(m)
		m.free()


func _key(mmi: MultiMeshInstance3D, i: int) -> String:
	var t := mmi.multimesh.get_instance_transform(i)
	var c := mmi.multimesh.get_instance_custom_data(i)
	return "%d|%s|%s" % [mmi.get_meta("object"), t, c]


func _equivalence(scene: Dictionary, fixed: Array, adaptive: Array) -> void:
	var a := []
	var b := []
	var total := 0
	for m: MultiMeshInstance3D in fixed:
		total += m.multimesh.instance_count
		for i in m.multimesh.instance_count:
			a.append(_key(m, i))
	for m: MultiMeshInstance3D in adaptive:
		for i in m.multimesh.instance_count:
			b.append(_key(m, i))
	a.sort()
	b.sort()
	_check(total > 0 and a == b, "adaptive join holds exactly the same %d joined instances (transforms and custom data) as the fixed join, of %d cards" % [total, scene.xforms.size()])
	var pure := true
	for m: MultiMeshInstance3D in adaptive:
		pure = pure and m.material_override == _atlas.get_material(OctaAtlas.Quality.HIGH) and m.get_instance_shader_parameter("octa_index") == m.get_meta("object") and m.multimesh.mesh == _atlas.get_mesh(m.get_meta("object"))
	_check(pure, "every region keeps its atlas, object index, material and mesh")


func _fixed_matches_v21(scene: Dictionary, fixed: Array) -> void:
	var cells := {}
	for i in scene.xforms.size():
		var key := "%d|%s" % [scene.objects[i], Vector3i((scene.xforms[i].origin / _cell).floor())]
		if not cells.has(key):
			cells[key] = []
		cells[key].append(i)
	var by_object := [[], [], []]
	for key in cells:
		if cells[key].size() >= 2:
			by_object[int(str(key).split("|")[0])].append(cells[key])
	var groups := []
	for o in OBJECTS:
		groups.append_array(by_object[o])
	var ok := groups.size() == fixed.size()
	if ok:
		var k := 0
		for m: MultiMeshInstance3D in fixed:
			var g: Array = groups[k]
			k += 1
			ok = ok and m.multimesh.instance_count == g.size()
			for j in mini(g.size(), m.multimesh.instance_count):
				ok = ok and m.multimesh.get_instance_transform(j) == scene.xforms[g[j]]
	_check(ok, "adaptive off: %d groups with instances in card order, as in v2.1" % fixed.size())


func _origins(m: MultiMeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in m.multimesh.instance_count:
		out.append(m.multimesh.get_instance_transform(i).origin)
	return out


func _limits(adaptive: Array) -> void:
	var worst := 0.0
	var most := 0
	for m: MultiMeshInstance3D in adaptive:
		var pts := _origins(m)
		var all := PackedInt32Array()
		for i in pts.size():
			all.append(i)
		if pts.size() >= OctaJoin.SIZE_SPLIT_MIN:
			worst = maxf(worst, OctaJoin.bounds(pts, all).get_longest_axis_size())
		most = maxi(most, pts.size())
	_check(worst <= _size + 0.001 and most <= _per, "every region is within the limits (largest %.1f m of %.1f for regions from %d instances, most instances %d of %d, %d regions)" % [worst, _size, OctaJoin.SIZE_SPLIT_MIN, most, _per, adaptive.size()])


func _morton(adaptive: Array) -> void:
	var ok := true
	for m: MultiMeshInstance3D in adaptive:
		var codes := OctaJoin.codes(_origins(m))
		for i in range(1, codes.size()):
			ok = ok and codes[i] >= codes[i - 1]
	_check(ok, "instances are in Morton order inside every MultiMesh")


# --- Frustum counts ---
func _camera() -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = _fov
	cam.near = 0.5
	cam.far = _far
	root.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(0.0, 30.0, -_extent * 0.5), Vector3(_aim.x * _extent, 10.0, _aim.y * _extent))
	return cam


func _stats(mmis: Array, cam: Camera3D) -> Dictionary:
	var planes := cam.get_frustum()
	var submitted := 0
	var visible := 0
	var regions := 0
	for m: MultiMeshInstance3D in mmis:
		var o: int = m.get_meta("object")
		var b: Vector4 = _bounds[o]
		var c := Vector3(b.x, b.y, b.z)
		var spheres: Array = []
		var box := AABB()
		for i in m.multimesh.instance_count:
			var t := m.multimesh.get_instance_transform(i)
			var ctr := t * c
			var r := b.w * t.basis.get_scale().x
			spheres.append([ctr, r])
			var sb := AABB(ctr - Vector3.ONE * r, Vector3.ONE * r * 2.0)
			box = sb if i == 0 else box.merge(sb)
		var inside := true
		for p: Plane in planes:
			if p.distance_to(box.get_support(-p.normal)) > 0.0:
				inside = false
				break
		if not inside:
			continue
		regions += 1
		submitted += spheres.size()
		for s in spheres:
			var seen := true
			for p: Plane in planes:
				if p.distance_to(s[0]) > s[1]:
					seen = false
					break
			if seen:
				visible += 1
	return {multimeshes = mmis.size(), regions = regions, submitted = submitted, visible = visible, waste = submitted - visible}


func _report(label: String, st: Dictionary) -> void:
	print("CULL %s: %d MultiMeshes, %d reach the frustum, %d instances submitted, %d in view, %d off-screen (%.1f%% of submitted)" % [label, st.multimeshes, st.regions, st.submitted, st.visible, st.waste, 100.0 * st.waste / maxf(st.submitted, 1)])


# --- Timing on the large scene ---
func _timing(scene: Dictionary, cam: Camera3D) -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	root.add_child(env)
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var rows := {fixed = [], adaptive = []}
	for rnd in _rounds:
		for label in ["fixed", "adaptive"]:
			var mmis := _build(scene, label == "adaptive")
			for m in mmis:
				root.add_child(m)
			for i in 90:
				await process_frame
			var gpu := []
			var cpu := []
			for i in 240:
				await process_frame
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
				cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
			gpu.sort()
			cpu.sort()
			var row := {
				gpu = gpu[gpu.size() / 2], cpu = cpu[cpu.size() / 2],
				prims = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
				draws = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				objects = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			}
			rows[label].append(row)
			print("TIMING round %d %s: gpu %.2f ms, cpu %.2f ms, primitives %d, draw calls %d, objects %d" % [rnd, label, row.gpu, row.cpu, row.prims, row.draws, row.objects])
			_free(mmis)
			await process_frame
	for label in rows:
		var g := 0.0
		var c := 0.0
		for r in rows[label]:
			g += r.gpu
			c += r.cpu
		print("MEAN %s: gpu %.2f ms, cpu %.2f ms, primitives %d, draw calls %d" % [label, g / rows[label].size(), c / rows[label].size(), rows[label][0].prims, rows[label][0].draws])
