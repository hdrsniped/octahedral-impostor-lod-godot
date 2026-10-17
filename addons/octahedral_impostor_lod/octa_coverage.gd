@tool
class_name OctaCoverage
extends RefCounted

const COVERED := 0.5
const SIMPLIFY_EPS := 1e-6

static var _mean_cache := {}


# --- Coverage of one object ---
static func measure(atlas: OctaAtlas, index: int, full := true) -> Dictionary:
	var out := {}
	if atlas == null or atlas.normal_depth == null or index < 0 or index >= atlas.object_count():
		return out
	var img := atlas.normal_depth.get_image()
	if img == null:
		return out
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var width := img.get_width()
	var n := atlas.grid_size
	var fr := atlas.frame_resolution
	var cols := maxi(atlas.tiles.x, 1)
	var tile := Vector2i(index % cols, index / cols)
	var pad := (fr - fr / atlas.frame_scale) * 0.5
	var lo := ceili(pad - 0.001)
	var hi := floori(fr - pad + 0.001)
	var quad_px := float(hi - lo) * float(hi - lo)
	var union := PackedByteArray()
	union.resize(fr * fr)
	var view_sum := 0.0
	var thr := int(COVERED * 255.0)
	for f in n * n:
		var at := (tile * n + Vector2i(f % n, f / n)) * fr
		var count := 0
		for y in range(lo, hi):
			var row := ((at.y + y) * width + at.x) * 4 + 3
			for x in range(lo, hi):
				if data[row + x * 4] >= thr:
					count += 1
					union[y * fr + x] = 1
		view_sum += count / quad_px
	var mean_view := view_sum / float(n * n)
	out.mean_view = mean_view
	_mean_cache[_key(atlas, index)] = mean_view
	if not full:
		return out

	var pts := PackedVector2Array()
	var union_px := 0
	var min_p := Vector2(1e9, 1e9)
	var max_p := Vector2(-1e9, -1e9)
	for y in range(lo, hi):
		var first := -1
		var last := -1
		for x in range(lo, hi):
			if union[y * fr + x] == 1:
				union_px += 1
				if first < 0:
					first = x
				last = x
		if first >= 0:
			pts.append(Vector2(first, y))
			pts.append(Vector2(first, y + 1))
			pts.append(Vector2(last + 1, y))
			pts.append(Vector2(last + 1, y + 1))
			min_p = min_p.min(Vector2(first, y))
			max_p = max_p.max(Vector2(last + 1, y + 1))
	out.quad_area = 1.0
	out.union = union_px / quad_px
	if pts.is_empty():
		out.rect = 0.0
		out.hull = 0.0
		out.poly8 = 0.0
		out.poly6 = 0.0
		out.hull_points = PackedVector2Array()
		return out
	var hull := _hull(pts)
	var p8 := _clip(_simplify(hull, 8), lo, hi)
	var p6 := _clip(_simplify(hull, 6), lo, hi)
	out.rect = (max_p.x - min_p.x) * (max_p.y - min_p.y) / quad_px
	out.hull = _area(hull) / quad_px
	out.poly8 = _area(p8) / quad_px
	out.poly6 = _area(p6) / quad_px
	out.hull_points = _to_quad(hull, fr, atlas.frame_scale)
	out.poly8_points = _to_quad(p8, fr, atlas.frame_scale)
	out.poly6_points = _to_quad(p6, fr, atlas.frame_scale)
	return out


static func mean_covered(atlas: OctaAtlas, index: int) -> float:
	var key := _key(atlas, index)
	if not _mean_cache.has(key):
		var m := measure(atlas, index, false)
		return m.get("mean_view", 1.0)
	return _mean_cache[key]


static func clear_cache() -> void:
	_mean_cache.clear()


# --- Geometry ---
static func _key(atlas: OctaAtlas, index: int) -> int:
	return atlas.get_instance_id() * 4096 + index


static func _to_quad(poly: PackedVector2Array, fr: int, frame_scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(((p / float(fr)) - Vector2(0.5, 0.5)) * 2.0 * frame_scale)
	return out


static func _cross(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)


static func _hull(points: PackedVector2Array) -> PackedVector2Array:
	var pts: Array = Array(points)
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	var h: Array[Vector2] = []
	for p: Vector2 in pts:
		while h.size() >= 2 and _cross(h[h.size() - 2], h[h.size() - 1], p) <= 0.0:
			h.pop_back()
		h.append(p)
	var lower := h.size() + 1
	for i in range(pts.size() - 2, -1, -1):
		var p: Vector2 = pts[i]
		while h.size() >= lower and _cross(h[h.size() - 2], h[h.size() - 1], p) <= 0.0:
			h.pop_back()
		h.append(p)
	h.pop_back()
	return PackedVector2Array(h)


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


static func _simplify(hull: PackedVector2Array, target: int) -> PackedVector2Array:
	var poly: Array[Vector2] = []
	poly.append_array(hull)
	while poly.size() > maxi(target, 3):
		var m := poly.size()
		var best := -1
		var best_area := INF
		var best_x := Vector2.ZERO
		for i in m:
			var p0 := poly[(i + m - 1) % m]
			var p1 := poly[i]
			var p2 := poly[(i + 1) % m]
			var p3 := poly[(i + 2) % m]
			var d1 := p1 - p0
			var d2 := p3 - p2
			var den := d1.cross(d2)
			if den <= SIMPLIFY_EPS:
				continue
			var e := p2 - p1
			var t := e.cross(d2) / den
			var s := e.cross(d1) / den
			if t < 0.0 or s > 0.0:
				continue
			var x := p1 + d1 * t
			var added := absf(_cross(p1, x, p2)) * 0.5
			if added < best_area:
				best_area = added
				best = i
				best_x = x
		if best < 0:
			break
		var j := (best + 1) % m
		poly[best] = best_x
		poly.remove_at(j)
	return PackedVector2Array(poly)


static func _clip(poly: PackedVector2Array, lo: float, hi: float) -> PackedVector2Array:
	var cur: Array[Vector2] = []
	cur.append_array(poly)
	for side in 4:
		if cur.is_empty():
			break
		var nxt: Array[Vector2] = []
		for i in cur.size():
			var a := cur[i]
			var b := cur[(i + 1) % cur.size()]
			var da := _signed(a, side, lo, hi)
			var db := _signed(b, side, lo, hi)
			if da >= 0.0:
				nxt.append(a)
			if (da >= 0.0) != (db >= 0.0):
				nxt.append(a + (b - a) * (da / (da - db)))
		cur = nxt
	return PackedVector2Array(cur)


static func _signed(p: Vector2, side: int, lo: float, hi: float) -> float:
	match side:
		0:
			return p.x - lo
		1:
			return hi - p.x
		2:
			return p.y - lo
	return hi - p.y
