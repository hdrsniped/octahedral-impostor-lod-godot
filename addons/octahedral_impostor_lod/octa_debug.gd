@tool
class_name OctaDebug
extends RefCounted

enum Mode { OFF, TINT_BY_LOD, VIEW_INDEX, DEPTH, ORM, OVERDRAW }

static var mode := Mode.OFF


# --- Debug view ---
static func set_mode(m: Mode) -> void:
	if m == mode:
		return
	mode = m
	OctaAtlas.refresh_all_materials()


static func mode_names() -> PackedStringArray:
	return PackedStringArray(["Off", "Tint by quality", "View index", "Depth", "Material (ORM)", "Overdraw"])
