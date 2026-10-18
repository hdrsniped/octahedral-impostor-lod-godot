class_name OctaChunkStreamer
extends Node

signal loaded(key: String, node: MultiMeshInstance3D)
signal failed(key: String, error: String)
signal unloaded(key: String)

enum State { LOADING, UPLOADING, READY }

@export_range(0.1, 16.0, 0.1, "or_greater", "suffix:ms") var budget_ms := 2.0
@export_range(64, 65536, 64, "or_greater") var instances_per_frame := 2048
## Keep loaded atlases in memory after their last chunk is released (call drop_atlases() to free them).
@export var keep_atlases := true

var _chunks := {}
var _pending := {}
var _atlases := {}
var _users := {}
var _drain: Array[String] = []


# --- Loading and unloading chunks ---
func request(key: String, atlas_path: String, transforms: Array, object_index := 0, quality: int = OctaAtlas.Quality.HIGH) -> void:
	if key.is_empty() or atlas_path.is_empty() or transforms.is_empty():
		failed.emit(key, "empty key, path or transform list")
		return
	release(key)
	var cached := _atlases.has(atlas_path)
	if not cached:
		var err := ResourceLoader.load_threaded_request(atlas_path)
		if err != OK:
			failed.emit(key, "cannot start loading %s (%d)" % [atlas_path, err])
			return
	_chunks[key] = {path = atlas_path, transforms = transforms, index = object_index, quality = quality,
			state = State.UPLOADING if cached else State.LOADING, atlas = _atlases.get(atlas_path, null),
			node = null, cursor = 0}
	_pending[key] = true
	_users[atlas_path] = int(_users.get(atlas_path, 0)) + 1
	set_process(true)


func release(key: String) -> bool:
	if not _chunks.has(key):
		return false
	var c: Dictionary = _chunks[key]
	if c.node != null and is_instance_valid(c.node):
		if c.node.get_parent() != null:
			c.node.get_parent().remove_child(c.node)
		c.node.queue_free()
	_chunks.erase(key)
	_pending.erase(key)
	var path: String = c.path
	var left := int(_users.get(path, 1)) - 1
	if left <= 0:
		_users.erase(path)
		if c.state == State.LOADING:
			_drain_load(path)
		if not keep_atlases:
			_atlases.erase(path)
	else:
		_users[path] = left
	unloaded.emit(key)
	return true


func release_all() -> void:
	for key in _chunks.keys():
		release(key)


func is_loaded(key: String) -> bool:
	return _chunks.has(key) and _chunks[key].state == State.READY


func is_pending(key: String) -> bool:
	return _chunks.has(key) and _chunks[key].state != State.READY


func node_for(key: String) -> MultiMeshInstance3D:
	return _chunks[key].node if _chunks.has(key) else null


func chunk_keys() -> Array:
	return _chunks.keys()


func atlas_count() -> int:
	return _atlases.size()


func drop_atlases() -> void:
	_atlases.clear()


func _drain_load(path: String) -> void:
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		ResourceLoader.load_threaded_get(path)
	elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and not _drain.has(path):
		_drain.append(path)


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	for i in range(_drain.size() - 1, -1, -1):
		var path := _drain[i]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(path)
		_drain.remove_at(i)
	for key in _pending:
		var c: Dictionary = _chunks[key]
		if c.state == State.LOADING:
			var status := ResourceLoader.load_threaded_get_status(c.path)
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				continue
			if status != ResourceLoader.THREAD_LOAD_LOADED:
				_fail(key, "loading %s failed" % c.path)
				continue
			var atlas := ResourceLoader.load_threaded_get(c.path) as OctaAtlas
			if atlas == null:
				_fail(key, "%s is not an impostor atlas" % c.path)
				continue
			_atlases[c.path] = atlas
			c.atlas = atlas
			c.state = State.UPLOADING
			c.cursor = 0
		if c.state == State.UPLOADING:
			if c.node == null:
				c.node = c.atlas.create_multimesh(c.index, [], c.quality)
				c.node.name = "OctaChunk_%s" % key
				c.node.multimesh.instance_count = c.transforms.size()
				c.node.multimesh.visible_instance_count = 0
				add_child(c.node)
			var count: int = mini(instances_per_frame, c.transforms.size() - c.cursor)
			for i in count:
				c.node.multimesh.set_instance_transform(c.cursor + i, c.transforms[c.cursor + i])
			c.cursor += count
			c.node.multimesh.visible_instance_count = c.cursor
			if c.cursor >= c.transforms.size():
				c.state = State.READY
				_pending.erase(key)
				loaded.emit(key, c.node)
		if Time.get_ticks_usec() - t0 > budget_ms * 1000.0:
			break
	set_process(not _pending.is_empty() or not _drain.is_empty())


func _fail(key: String, why: String) -> void:
	var c: Dictionary = _chunks[key]
	if c.node != null and is_instance_valid(c.node):
		c.node.queue_free()
	_chunks.erase(key)
	_pending.erase(key)
	var path: String = c.path
	var left := int(_users.get(path, 1)) - 1
	if left <= 0:
		_users.erase(path)
		if not keep_atlases:
			_atlases.erase(path)
	else:
		_users[path] = left
	failed.emit(key, why)
