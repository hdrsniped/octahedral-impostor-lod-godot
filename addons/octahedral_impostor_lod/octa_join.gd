class_name OctaJoin
extends RefCounted

const MIN_REGION_COUNT := 4
const SIZE_SPLIT_MIN := 16
const MORTON_BITS := 10
const INDEX_BITS := 24
const KEY_BITS := 30


# --- Z-order (Morton) codes ---
static func _spread(v: int) -> int:
	v &= 0x3FF
	v = (v | (v << 16)) & 0x030000FF
	v = (v | (v << 8)) & 0x0300F00F
	v = (v | (v << 4)) & 0x030C30C3
	v = (v | (v << 2)) & 0x09249249
	return v


static func morton(p: Vector3, origin: Vector3, extent: float) -> int:
	if extent <= 0.0:
		return 0
	var cells := float((1 << MORTON_BITS) - 1)
	var q := ((p - origin) / extent * cells).floor()
	return _spread(clampi(int(q.x), 0, int(cells))) | (_spread(clampi(int(q.y), 0, int(cells))) << 1) | (_spread(clampi(int(q.z), 0, int(cells))) << 2)


static func bounds(points: PackedVector3Array, indices: PackedInt32Array) -> AABB:
	if indices.is_empty():
		return AABB()
	var lo := points[indices[0]]
	var hi := lo
	for i in indices:
		lo = lo.min(points[i])
		hi = hi.max(points[i])
	return AABB(lo, hi - lo)


static func codes(points: PackedVector3Array) -> PackedInt64Array:
	var all := PackedInt32Array()
	all.resize(points.size())
	for i in points.size():
		all[i] = i
	var box := bounds(points, all)
	var out := PackedInt64Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = morton(points[i], box.position, box.get_longest_axis_size())
	return out


static func order(points: PackedVector3Array, indices: PackedInt32Array) -> PackedInt32Array:
	var box := bounds(points, indices)
	var extent := box.get_longest_axis_size()
	var keys := PackedInt64Array()
	keys.resize(indices.size())
	for k in indices.size():
		keys[k] = (morton(points[indices[k]], box.position, extent) << INDEX_BITS) | k
	keys.sort()
	var out := PackedInt32Array()
	out.resize(indices.size())
	var mask := (1 << INDEX_BITS) - 1
	for k in keys.size():
		out[k] = indices[keys[k] & mask]
	return out


# --- Adaptive regions (median split on the longest axis) ---
static func subdivide(points: PackedVector3Array, indices: PackedInt32Array, size_limit: float, count_limit: int) -> Array:
	var out := []
	_split(points, indices, maxf(size_limit, 0.01), maxi(count_limit, MIN_REGION_COUNT), out)
	return out


static func _split(points: PackedVector3Array, indices: PackedInt32Array, size_limit: float, count_limit: int, out: Array) -> void:
	var n := indices.size()
	var box := bounds(points, indices)
	var axis := box.get_longest_axis_index()
	if n < 2 or (n <= count_limit and (box.size[axis] <= size_limit or n < SIZE_SPLIT_MIN)):
		out.append(order(points, indices))
		return
	var lo := box.position[axis]
	var span := maxf(box.size[axis], 1e-6)
	var scale := float((1 << KEY_BITS) - 1) / span
	var keys := PackedInt64Array()
	keys.resize(n)
	for k in n:
		keys[k] = (int((points[indices[k]][axis] - lo) * scale) << INDEX_BITS) | k
	keys.sort()
	var mask := (1 << INDEX_BITS) - 1
	var half := n / 2
	var left := PackedInt32Array()
	var right := PackedInt32Array()
	left.resize(half)
	right.resize(n - half)
	for k in n:
		var idx := indices[keys[k] & mask]
		if k < half:
			left[k] = idx
		else:
			right[k - half] = idx
	_split(points, left, size_limit, count_limit, out)
	_split(points, right, size_limit, count_limit, out)


# --- Coarse cells, then regions ---
static func partition(points: PackedVector3Array, cell: float, adaptive: bool, size_limit: float, count_limit: int) -> Array:
	var cells := {}
	for i in points.size():
		var key := Vector3i((points[i] / cell).floor())
		if not cells.has(key):
			cells[key] = PackedInt32Array()
		cells[key].append(i)
	var out := []
	for key in cells:
		if adaptive:
			out.append_array(subdivide(points, cells[key], size_limit, count_limit))
		else:
			out.append(cells[key])
	return out
