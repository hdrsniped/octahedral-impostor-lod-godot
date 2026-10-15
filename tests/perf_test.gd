extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


# --- GPU benchmark ---
func _run() -> void:
	var count: int = 4000
	var mode: String = "mesh"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--count="):
			count = int(arg.trim_prefix("--count="))
		elif arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")

	if "--uncapped" in args:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0

	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY

	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	light.shadow_enabled = true
	root.add_child(light)

	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane_mesh: PlaneMesh = PlaneMesh.new()
	plane_mesh.size = Vector2(600.0, 600.0)
	ground.mesh = plane_mesh
	root.add_child(ground)

	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0.0, 12.0, -20.0)
	camera.far = 600.0
	camera.current = true
	root.add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, 60.0))

	var transforms: Array = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7

	var cols: int = maxi(1, int(ceil(sqrt(float(count)))))
	var rows: int = maxi(1, int(ceil(float(count) / float(cols))))
	var cell_w: float = 300.0 / float(cols)
	var cell_d: float = 300.0 / float(rows)

	for i: int in range(count):
		var col: int = i % cols
		var row: int = i / cols
		var x: float = -150.0 + (float(col) + rng.randf()) * cell_w
		var z: float = 0.0 + (float(row) + rng.randf()) * cell_d
		var yaw: float = rng.randf_range(-PI, PI)
		var s: float = rng.randf_range(0.6, 1.6)
		var basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s)
		transforms.append(Transform3D(basis, Vector3(x, 0.0, z)))

	if mode == "mesh":
		var rock_mi: MeshInstance3D = DemoObjects.rock(1).get_child(0)
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = rock_mi.mesh
		mm.instance_count = transforms.size()
		for i: int in range(transforms.size()):
			var t: Transform3D = transforms[i]
			mm.set_instance_transform(i, t * Transform3D(Basis(), Vector3(0.0, 0.55, 0.0)))
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		root.add_child(mmi)
	else:
		var q: int = {"low": 0, "medium": 1, "high": 2, "ultra": 3}.get(mode, 2)
		var atlas: OctaAtlas = await OctaBaker.bake([DemoObjects.rock(1)], root)
		root.add_child(atlas.create_multimesh(0, transforms, q))

	var rid: RID = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)

	for i: int in range(60):
		await process_frame

	var gpu_times: Array[float] = []
	var cpu_times: Array[float] = []
	var frame_times: Array[float] = []

	var last_time: int = Time.get_ticks_usec()
	for i: int in range(240):
		await process_frame
		var current_time: int = Time.get_ticks_usec()
		var delta_ms: float = float(current_time - last_time) / 1000.0
		last_time = current_time

		var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(rid)
		var cpu_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(rid)

		gpu_times.append(gpu_ms)
		cpu_times.append(cpu_ms)
		frame_times.append(delta_ms)

	var prims: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var draws: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)

	var gpu_sum: float = 0.0
	for val: float in gpu_times:
		gpu_sum += val
	var gpu_ms_avg: float = gpu_sum / float(gpu_times.size())

	var sorted_gpu: Array[float] = gpu_times.duplicate()
	sorted_gpu.sort()
	var p95_idx: int = clampi(int(ceil(0.95 * float(sorted_gpu.size()))) - 1, 0, sorted_gpu.size() - 1)
	var gpu_ms_p95: float = sorted_gpu[p95_idx]

	var cpu_sum: float = 0.0
	for val: float in cpu_times:
		cpu_sum += val
	var cpu_ms_avg: float = cpu_sum / float(cpu_times.size())

	var frame_sum: float = 0.0
	for val: float in frame_times:
		frame_sum += val
	var frame_ms_avg: float = frame_sum / float(frame_times.size())

	var fps: float = 0.0
	if frame_ms_avg > 0.0:
		fps = 1000.0 / frame_ms_avg

	print("PERF mode=%s count=%d gpu_ms_avg=%.2f gpu_ms_p95=%.2f cpu_ms_avg=%.2f frame_ms_avg=%.2f fps=%.2f prims=%d draws=%d" % [
		mode,
		count,
		gpu_ms_avg,
		gpu_ms_p95,
		cpu_ms_avg,
		frame_ms_avg,
		fps,
		prims,
		draws
	])

	DirAccess.make_dir_recursive_absolute("res://tests/out")
	root.get_texture().get_image().save_png("res://tests/out/perf_%s.png" % mode)
	for c in root.get_children():
		c.queue_free()
	await process_frame
	await process_frame
	quit()
