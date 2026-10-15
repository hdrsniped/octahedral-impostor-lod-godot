extends SceneTree

var _fails := 0
var _baked_count := 0

const ATLAS_SIZE := 1024


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _on_baked(_source: Node3D, _card: Node3D) -> void:
	_baked_count += 1


# --- Time-sliced runtime bake queue ---
func _run() -> void:
	var queue := OctaBakeQueue.new()
	queue.budget_ms = 2.0
	queue.max_views_per_frame = 8
	root.add_child(queue)
	queue.baked.connect(_on_baked)
	var world := Node3D.new()
	root.add_child(world)
	for i in 5:
		await process_frame

	var kinds: Array[Node3D] = [_kind(SphereMesh.new(), Color(0.8, 0.2, 0.2)), _kind(BoxMesh.new(), Color(0.2, 0.7, 0.3)),
			_kind(CapsuleMesh.new(), Color(0.2, 0.3, 0.9)), _kind(TorusMesh.new(), Color(0.9, 0.8, 0.2)), DemoObjects.rock(2)]
	var cfg := OctaBakeSettings.new()
	cfg.max_atlas_size = ATLAS_SIZE
	var cancel_victim := _kind(PrismMesh.new(), Color(0.5, 0.5, 0.5))
	var free_victim := _kind(CylinderMesh.new(), Color(0.9, 0.5, 0.1))
	world.add_child(cancel_victim)
	world.add_child(free_victim)
	var cancel_job := queue.enqueue(cancel_victim, cfg)
	var free_job := queue.enqueue(free_victim, cfg)
	var objects: Array[Node3D] = []
	var jobs: Array[OctaBakeJob] = []
	for i in 20:
		var o: Node3D = kinds[i % 5].duplicate()
		o.position = Vector3(i * 2.0, 0, 0)
		world.add_child(o)
		objects.append(o)
		jobs.append(queue.enqueue(o, cfg))
	var dup_before := queue.pending_count()
	_check(dup_before > 0 and cancel_job.running and not queue.is_idle(), "20 + 2 requests queued without baking synchronously")

	var frames := 0
	var max_wall := 0
	var wall_prev := Time.get_ticks_usec()
	var cancelled := false
	var freed := false
	var samples: Array[int] = []
	queue.reset_stats()
	while not queue.is_idle() and frames < 4000:
		await process_frame
		var now := Time.get_ticks_usec()
		max_wall = maxi(max_wall, now - wall_prev)
		wall_prev = now
		frames += 1
		samples.append(queue.last_frame_usec)
		if frames == 4 and not cancelled:
			cancel_job.cancel()
			cancelled = true
		if cancelled and not freed and not queue._current.is_empty() and queue._current.requests.size() > 0 and queue._current.requests[0].source == free_victim and queue._current.bjob.wait_frame > 0:
			free_victim.free()
			freed = true
			print("freed a source while its bake ran")
	await process_frame
	_check(queue.is_idle(), "queue drained in %d frames" % frames)
	print("QUEUE per-frame main-thread cost: max %.2f ms, last %.2f ms (budget %.1f ms); max wall frame %.2f ms" % [queue.max_frame_usec / 1000.0, queue.last_frame_usec / 1000.0, queue.budget_ms, max_wall / 1000.0])
	samples.sort()
	var p95: int = samples[int(samples.size() * 0.95)]
	var over := samples.filter(func(v: int) -> bool: return v > 2.0 * queue.budget_ms * 1000.0).size()
	print("QUEUE %d frames: p50 %.2f ms, p95 %.2f ms, %d frames above 2x budget (atlas %d px)" % [samples.size(), samples[samples.size() / 2] / 1000.0, p95 / 1000.0, over, ATLAS_SIZE])
	_check(samples[samples.size() / 2] < 1.5 * queue.budget_ms * 1000.0 and p95 < 4.0 * queue.budget_ms * 1000.0 and queue.max_frame_usec < 40000, "max %.2f ms, p95 %.2f ms stay near the %.1f ms budget (p50 under 1.5x, p95 under 4x, max under 40 ms)" % [queue.max_frame_usec / 1000.0, p95 / 1000.0, queue.budget_ms])

	var all_cards := true
	var all_done := true
	for i in 20:
		all_cards = all_cards and OctaLOD.find_cards(objects[i]).size() == 1 and jobs[i].card != null
		all_done = all_done and not jobs[i].running
	_check(all_cards and all_done, "all 20 objects got exactly one card")
	_check(_baked_count == 20, "baked signal fired %d times" % _baked_count)
	var atlases := {}
	var share_ok := true
	for i in 20:
		atlases[jobs[i].atlas] = true
		share_ok = share_ok and jobs[i].atlas == jobs[i % 5].atlas
	_check(atlases.size() == 5 and share_ok, "5 distinct shapes made %d atlases; duplicates share their atlas" % atlases.size())
	_check(not cancel_job.running and cancel_job.card == null and OctaLOD.find_cards(cancel_victim).is_empty(), "cancelled job produced no card")
	_check(freed and not free_job.running and free_job.card == null, "freeing a source mid-bake completed its job as failed (freed: %s)" % freed)

	var late: Node3D = kinds[2].duplicate()
	world.add_child(late)
	var late_job := queue.enqueue(late, cfg)
	while not queue.is_idle():
		await process_frame
	await process_frame
	_check(late_job.atlas == jobs[2].atlas and OctaLOD.find_cards(late).size() == 1, "later duplicate reuses the cached atlas without baking")

	var s2 := OctaBakeSettings.new()
	s2.max_atlas_size = ATLAS_SIZE
	s2.mode = OctaLOD.Mode.DUPLICATE
	s2.fade = OctaLOD.Fade.CROSSFADE
	s2.quality = OctaAtlas.Quality.MEDIUM
	var other := _kind(SphereMesh.new(), Color.WHITE)
	world.add_child(other)
	var oj := queue.enqueue(other, s2, "")
	while not queue.is_idle():
		await process_frame
	await process_frame
	_check(oj.card != null and oj.card.get_parent() == world and oj.card.get_meta(OctaLOD.MODE_META) == OctaLOD.Mode.DUPLICATE, "settings choose LOD mode (DUPLICATE sibling card)")
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	queue.clear_cache()
	for k in kinds:
		k.free()
	await _clean_quit(1 if _fails else 0)


func _kind(mesh: Mesh, color: Color) -> Node3D:
	var n := Node3D.new()
	n.name = "Obj"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	n.add_child(mi)
	return n


func _clean_quit(code: int) -> void:
	for c in root.get_children():
		c.queue_free()
	await process_frame
	await process_frame
	quit(code)
