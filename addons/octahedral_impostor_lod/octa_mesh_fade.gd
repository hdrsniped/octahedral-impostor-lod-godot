@tool
class_name OctaMeshFade
extends RefCounted

const RECORD_META := &"octa_fade_original"

static var _copies := {}


# --- Fade a real mesh out with material copies ---
static func apply(gi: GeometryInstance3D, band: Vector2) -> int:
	restore(gi)
	var record := {}
	var count := 0
	if gi.material_override != null:
		var copy := copy_for(gi.material_override, band)
		if copy != null:
			record.override = [gi.material_override, copy]
			gi.material_override = copy
			count += 1
	elif gi is MeshInstance3D and gi.mesh != null:
		var surfaces := {}
		for s in gi.mesh.get_surface_count():
			var copy := copy_for(gi.get_active_material(s), band)
			if copy != null:
				surfaces[s] = [gi.get_surface_override_material(s), copy]
				gi.set_surface_override_material(s, copy)
				count += 1
		if not surfaces.is_empty():
			record.surfaces = surfaces
	if not record.is_empty():
		gi.set_meta(RECORD_META, record)
	return count


static func restore(gi: GeometryInstance3D) -> bool:
	if not is_instance_valid(gi) or not gi.has_meta(RECORD_META):
		return false
	var record: Dictionary = gi.get_meta(RECORD_META)
	gi.remove_meta(RECORD_META)
	if record.has("override") and gi.material_override == record.override[1]:
		gi.material_override = record.override[0]
	if record.has("surfaces") and gi is MeshInstance3D:
		for s: int in record.surfaces:
			if s < gi.get_surface_override_material_count() and gi.get_surface_override_material(s) == record.surfaces[s][1]:
				gi.set_surface_override_material(s, record.surfaces[s][0])
	return true


static func is_faded(gi: GeometryInstance3D) -> bool:
	return gi.has_meta(RECORD_META)


static func fadeable(m: Material) -> bool:
	return m is BaseMaterial3D and m.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED and m.next_pass == null


static func copy_for(m: Material, band: Vector2) -> Material:
	if m == null or not fadeable(m):
		return null
	var key := "%d|%.3f|%.3f" % [m.get_instance_id(), band.x, band.y]
	var entry: Dictionary = _copies.get(key, {})
	if entry.is_empty() or entry.source.get_ref() != m or not is_instance_valid(entry.copy):
		_prune()
		var c: BaseMaterial3D = m.duplicate()
		c.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_OBJECT_DITHER
		c.distance_fade_min_distance = band.y
		c.distance_fade_max_distance = band.x
		entry = {source = weakref(m), copy = c}
		_copies[key] = entry
	return entry.copy


static func copy_count() -> int:
	_prune()
	return _copies.size()


static func _prune() -> void:
	for key: String in _copies.keys():
		if _copies[key].source.get_ref() == null:
			_copies.erase(key)
