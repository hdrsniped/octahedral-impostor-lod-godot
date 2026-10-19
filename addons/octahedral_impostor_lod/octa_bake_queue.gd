class_name OctaBakeQueue
extends Node

signal baked(source: Node3D, card: Node3D)
signal finished

const KEY_PROPERTIES := ["grid_size", "full_sphere", "max_atlas_size", "material_maps", "emission", "half_res_material_maps", "split_parts",
		"back_layer", "search_steps", "layer_tolerance", "frame_resolution", "msaa", "padding_px", "write_depth", "precise_search", "shadow_views", "compression",
		"view_visibility", "coverage_pyramid", "parallax_refine"]

## Milliseconds per frame the queue may spend baking. Lower = smoother frames, slower bakes.
@export_range(0.1, 16.0, 0.1, "or_greater", "suffix:ms") var budget_ms := 2.0
## Most views rendered in one frame (lowered automatically when the measured cost is high).
@export_range(1, 64) var max_views_per_frame := 8
## Identical objects with the same settings share one baked atlas.
@export var dedupe := true
## Most atlases kept for reuse by identical objects. The least recently used one is dropped first.
@export_range(1, 1024) var cache_limit := 32:
	set(v):
		cache_limit = maxi(v, 1)
		_trim_cache()

static var _shared: OctaBakeQueue

var last_frame_usec := 0
var max_frame_usec := 0

var _pending: Array[Dictionary] = []
var _current: Dictionary = {}
var _attach: Array[Dictionary] = []
var _groups := {}
var _cache := {}
var _busy := false
var _per_view_usec := 0.0
var _joining := false


# --- Shared queue ---
static func shared(tree: SceneTree) -> OctaBakeQueue:
	if not is_instance_valid(_shared):
		_shared = OctaBakeQueue.new()
		_shared.name = "OctaBakeQueueShared"
		_shared._joining = true
		tree.root.add_child.call_deferred(_shared)
	return _shared


func _enter_tree() -> void:
	_joining = false


# --- Requests ---
func enqueue(source: Node3D, settings: OctaBakeSettings = null, save_path := "") -> OctaBakeJob:
	var job := OctaBakeJob.new()
	if settings == null:
		settings = OctaBakeSettings.new()
	if source == null or not source.is_inside_tree() or not (is_inside_tree() or _joining):
		push_error("Octahedral Impostor LOD: the queue and the source must be inside the scene tree.")
		_fail(job)
		return job
	var key := ""
	if dedupe:
		key = OctaLOD.signature(source) + "#" + _settings_key(settings) + "#" + save_path
	var req := {job = job, source = source, settings = settings}
	_busy = true
	if dedupe and _cache.has(key):
		var hit: Dictionary = _cache[key]
		_cache.erase(key)
		_cache[key] = hit
		_attach.append({req = req, atlas = hit.atlas})
		return job
	if dedupe and _groups.has(key):
		_groups[key].requests.append(req)
		return job
	var g := {key = key, settings = settings, save_path = save_path, requests = [req], bjob = OctaBakeJob.new(), keep = _keep_alive(source)}
	g.bjob.paced = true
	g.bjob.max_views = mini(2, max_views_per_frame)
	g.bjob.progress.connect(_forward_progress.bind(g))
	if dedupe:
		_groups[key] = g
	_pending.append(g)
	return job


func pending_count() -> int:
	return _pending.size() + (1 if not _current.is_empty() else 0) + _attach.size()


func is_idle() -> bool:
	return pending_count() == 0


func clear_cache() -> void:
	_cache.clear()


func cache_size() -> int:
	return _cache.size()


func reset_stats() -> void:
	last_frame_usec = 0
	max_frame_usec = 0


# --- Frame loop ---
func _process(_delta: float) -> void:
	if not _busy:
		return
	var t0 := Time.get_ticks_usec()
	var limit := int(budget_ms * 1000.0)
	var frame := Engine.get_process_frames()
	_prune()
	var first := true
	while first or Time.get_ticks_usec() - t0 < limit:
		first = false
		var did := true
		if _current.is_empty() and not _pending.is_empty():
			_start_next()
		elif not _current.is_empty() and not (_current.bjob.wait_render and _current.bjob.wait_frame == frame):
			_step()
		elif not _attach.is_empty():
			_attach_one()
		else:
			did = false
		if not did:
			break
	last_frame_usec = Time.get_ticks_usec() - t0
	max_frame_usec = maxi(max_frame_usec, last_frame_usec)
	if is_idle():
		_busy = false
		finished.emit()


func _step() -> void:
	var bj: OctaBakeJob = _current.bjob
	var t := Time.get_ticks_usec()
	bj.resume.emit()
	if bj.last_batch > 0:
		var per := float(Time.get_ticks_usec() - t) / bj.last_batch
		_per_view_usec = per if _per_view_usec <= 0.0 else lerpf(_per_view_usec, per, 0.5)
		bj.max_views = clampi(int(budget_ms * 800.0 / maxf(_per_view_usec, 1.0)), 1, max_views_per_frame)
		bj.last_batch = 0


func _start_next() -> void:
	var g: Dictionary = _pending.pop_front()
	var src: Node3D = null
	for r in g.requests:
		if not r.job.cancelled and is_instance_valid(r.source) and r.source.is_inside_tree():
			src = r.source
			break
	if src == null:
		_finish_group(g, null)
		return
	var sources: Array = OctaLOD.split_parts([src]) if g.settings.split_parts else [src]
	_current = g
	_run(g, sources)


func _run(g: Dictionary, sources: Array) -> void:
	var atlas: OctaAtlas = await OctaBaker.bake(sources, self, g.settings, g.bjob)
	if atlas != null and g.save_path != "":
		atlas = OctaBaker.save_atlas(atlas, g.save_path, g.settings)
	_current = {}
	_finish_group(g, atlas)


func _finish_group(g: Dictionary, atlas: OctaAtlas) -> void:
	for c in g.bjob.progress.get_connections():
		g.bjob.progress.disconnect(c.callable)
	if _groups.get(g.key) == g:
		_groups.erase(g.key)
	for r in g.requests:
		if atlas != null and not r.job.cancelled:
			_attach.append({req = r, atlas = atlas})
		else:
			_fail(r.job)
	if atlas != null and dedupe:
		_cache.erase(g.key)
		_cache[g.key] = {atlas = atlas, keep = g.keep}
		_trim_cache()


func _attach_one() -> void:
	var item: Dictionary = _attach.pop_front()
	var req: Dictionary = item.req
	var atlas: OctaAtlas = item.atlas
	var job: OctaBakeJob = req.job
	var src: Variant = req.source
	if job.cancelled or not is_instance_valid(src) or not src.is_inside_tree():
		_fail(job)
		return
	var s: OctaBakeSettings = req.settings
	var parts: Array = OctaLOD.split_parts([src]) if s.split_parts else [src]
	if parts.size() != atlas.object_count():
		_fail(job)
		return
	var first: Node3D = null
	for i in parts.size():
		var card := OctaLOD.attach_card(parts[i], atlas, i, s.mode, s.lod_distance, s.quality, null, s)
		if first == null:
			first = card
	job.atlas = atlas
	job.card = first
	job.running = false
	job.completed.emit(true)
	baked.emit(src, first)


# --- Cancel and failure ---
func _prune() -> void:
	for g in _pending.duplicate():
		_drop_cancelled(g)
		if g.requests.is_empty():
			_pending.erase(g)
			if _groups.get(g.key) == g:
				_groups.erase(g.key)
	if not _current.is_empty():
		_drop_cancelled(_current)
		if _current.requests.is_empty():
			_current.bjob.cancel()


func _drop_cancelled(g: Dictionary) -> void:
	for r in g.requests.duplicate():
		if r.job.cancelled or not is_instance_valid(r.source):
			g.requests.erase(r)
			_fail(r.job)


func _fail(job: OctaBakeJob) -> void:
	if job.running:
		job.running = false
		job.completed.emit(false)


func _forward_progress(done: int, total: int, text: String, g: Dictionary) -> void:
	for r in g.requests:
		r.job.progress.emit(done, total, text)


# --- Helpers ---
func _settings_key(s: OctaBakeSettings) -> String:
	var values := []
	for p in KEY_PROPERTIES:
		values.append(s.get(p))
	return str(values.hash())


func _trim_cache() -> void:
	while _cache.size() > cache_limit:
		_cache.erase(_cache.keys()[0])


func _keep_alive(source: Node3D) -> Array:
	var keep := []
	for gi in OctaLOD.geometry_below(source):
		if gi is MeshInstance3D and gi.mesh != null:
			keep.append(gi.mesh)
			for s in gi.mesh.get_surface_count():
				keep.append(gi.get_active_material(s))
	return keep
