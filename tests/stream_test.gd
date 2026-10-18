extends SceneTree

var _fails := 0
var _got: MultiMeshInstance3D = null


func _initialize() -> void:
	_run.call_deferred()


func _on_loaded(key: String, node: MultiMeshInstance3D) -> void:
	_got = node
	print("SIGNAL loaded %s" % key)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


# --- Chunk streaming: threaded load, sliced upload, unload ---
func _run() -> void:
	var src := DemoObjects.rock(1)
	root.add_child(src)
	var s := OctaBakeSettings.new()
	s.grid_size = 8
	s.max_atlas_size = 512
	var path := "user://stream_test.res"
	DirAccess.make_dir_recursive_absolute("user://")
	var atlas := await OctaBaker.bake([src], root, s)
	_check(atlas != null, "atlas baked")
	var err := ResourceSaver.save(atlas, path, ResourceSaver.FLAG_COMPRESS)
	_check(err == OK, "atlas saved to %s" % path)

	var st := OctaChunkStreamer.new()
	st.budget_ms = 0.1
	st.instances_per_frame = 100
	root.add_child(st)
	var xforms: Array = []
	for i in 500:
		xforms.append(Transform3D(Basis(), Vector3(i % 20, 0, i / 20)))
	st.loaded.connect(_on_loaded)
	st.request("a", path, xforms, 0, OctaAtlas.Quality.HIGH)
	_check(st.is_pending("a") and not st.is_loaded("a"), "a chunk starts out pending")
	var frames := 0
	while not st.is_loaded("a") and frames < 300:
		await process_frame
		frames += 1
	_check(st.is_loaded("a") and _got != null, "the chunk loads within %d frames" % frames)
	_check(frames >= 2, "the upload is spread over several frames (%d)" % frames)
	if _got == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		print("RESULT FAIL (1 failure)")
		quit(1)
		return
	_check(_got.multimesh != null and _got.multimesh.instance_count == 500, "all instances are uploaded (%d)" % (_got.multimesh.instance_count if _got != null else -1))
	_check(_got.get_parent() != null and _got.multimesh.mesh != null, "the chunk node is in the tree with a card mesh")
	_check(_got.multimesh.instance_count > 0 and _got.multimesh.get_instance_transform(0) == xforms[0] and _got.multimesh.get_instance_transform(499) == xforms[499], "instance transforms are exact")

	st.request("b", path, xforms.slice(0, 120), 0, OctaAtlas.Quality.HIGH)
	frames = 0
	while not st.is_loaded("b") and frames < 600:
		await process_frame
		frames += 1
	_check(st.is_loaded("b") and st.atlas_count() == 1, "a second chunk of the same atlas reuses the loaded one")

	var node_a: MultiMeshInstance3D = st.node_for("a")
	_check(st.release("a") and not st.is_pending("a"), "release drops the chunk")
	await process_frame
	await process_frame
	_check(not is_instance_valid(node_a), "the released node is freed")
	_check(st.atlas_count() == 1, "the atlas stays while another chunk uses it")
	st.release("b")
	_check(st.chunk_keys().is_empty() and st.atlas_count() == 1, "keep_atlases keeps the atlas after the last chunk")

	st.keep_atlases = false
	st.request("c", path, xforms.slice(0, 50), 0, OctaAtlas.Quality.HIGH)
	frames = 0
	while not st.is_loaded("c") and frames < 600:
		await process_frame
		frames += 1
	st.release("c")
	_check(st.atlas_count() == 0, "without keep_atlases the atlas is dropped with the last chunk")

	var bad := []
	st.failed.connect(func(k: String, e: String) -> void: bad.append(e))
	st.request("d", "user://not_an_atlas.res", xforms, 0, OctaAtlas.Quality.HIGH)
	frames = 0
	while bad.is_empty() and frames < 300:
		await process_frame
		frames += 1
	_check(not bad.is_empty(), "a missing file fails cleanly (%s)" % (bad[0] if not bad.is_empty() else "no signal"))
	st.request("e", "", xforms, 0, OctaAtlas.Quality.HIGH)
	_check(not st.is_pending("e") and bad.size() >= 2, "an empty path fails immediately")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	for c in root.get_children():
		c.queue_free()
	await process_frame
	await process_frame
	quit(1 if _fails else 0)
