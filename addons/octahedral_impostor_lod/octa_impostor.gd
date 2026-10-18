@tool
@icon("res://addons/octahedral_impostor_lod/icon_impostor.svg")
class_name OctaImpostor
extends MeshInstance3D

## The baked atlas this card draws from.
@export var atlas: OctaAtlas:
	set(v):
		if atlas != null and atlas != v:
			atlas.set_wind_user(self, false)
		atlas = v
		_refresh()
## Which object of the atlas this card shows (0 = the first baked object).
@export_range(0, 1023) var object_index := 0:
	set(v):
		object_index = maxi(v, 0)
		_refresh()
## Shader quality for this card. Each quality shares one material per atlas.
@export var quality := OctaAtlas.Quality.HIGH:
	set(v):
		quality = v
		_refresh()
## Distance = fixed meters. Screen size = the card takes over below a share of the screen height.
@export var lod_mode := OctaLOD.LodMode.DISTANCE:
	set(v):
		lod_mode = v
		_apply_lod()
		notify_property_list_changed()
## Distance in meters where this card replaces the real mesh (0 = always shown).
## Calculated from the screen size in Screen size mode.
@export_range(0.0, 1000.0, 0.5, "or_greater", "suffix:m") var lod_distance := 0.0:
	get:
		return visibility_range_begin if is_inside_tree() else _lod_distance
	set(v):
		_set_begin(v)
		_apply_fade()
## Screen size mode: the card replaces the real mesh when the object covers less than this share
## of the screen height (uses the reference field of view, default 75 degrees).
@export_range(0.1, 100.0, 0.1, "suffix:%") var screen_percent := 5.0:
	set(v):
		screen_percent = maxf(v, 0.01)
		_apply_lod()
## Crossfade dithers the card in over the real mesh instead of popping. Works on every renderer:
## Godot's own fade on Forward+, a screen-space dither in the card shader on Mobile and
## Compatibility. Not for Replace mode.
@export var fade := OctaLOD.Fade.NONE:
	set(v):
		fade = v
		_apply_fade()
		notify_property_list_changed()
## The crossfade runs from the LOD distance minus this margin to the LOD distance plus this margin.
@export_range(0.0, 100.0, 0.5, "or_greater", "suffix:m") var fade_margin := 5.0:
	set(v):
		fade_margin = maxf(v, 0.0)
		_apply_fade()
## Mobile and Compatibility only: also dither the real mesh out across the same band (material
## copies, your own materials stay untouched). Off, or for materials that cannot fade (shaders, own
## distance fade), the card fades in over the real mesh and the mesh switches off behind it.
@export var fade_real_mesh := true:
	set(v):
		fade_real_mesh = v
		_apply_fade()

@export_group("Per-card look")
## Multiplies the shared tint of this card only.
@export var tint := Color.WHITE:
	set(v):
		tint = v
		set_instance_shader_parameter("card_tint", v)
## Multiplies the shared depth of this card only (0 = flat, 1 = as baked).
@export_range(0.0, 3.0, 0.01) var depth_multiplier := 1.0:
	set(v):
		depth_multiplier = v
		set_instance_shader_parameter("card_depth", v)
## Far-field wind sway of this card (0 = still, the default). At 1 the top of the object leans downwind
## by 20% of its radius (more in gusts) while the base stays fixed. Done in texture space: no vertex
## displacement and no bigger bounds. The first card above 0 switches its atlas to the wind shader
## variant; with every card at 0 the atlas keeps the normal shader. Direction and speed: OctaWind.set_wind().
@export_range(0.0, 1.0, 0.01) var wind_strength := 0.0:
	set(v):
		wind_strength = maxf(v, 0.0)
		_apply_wind()

@export_group("Tools")
@export_tool_button("Check Quality", "Search") var check_quality_action := _check_quality
@export_tool_button("Select Source", "ArrowUp") var select_source_action := _select_source
@export_tool_button("Edit Shared Look", "ShaderMaterial") var edit_shared_action := _edit_shared


var _batch := false
var _lod_distance := 0.0
var _checking := false
var _dithered := false
var _meshes_faded := false
var _winded := false

static var _live := {}


static func live_cards() -> Array[OctaImpostor]:
	var out: Array[OctaImpostor] = []
	for id: int in _live.keys():
		var c: OctaImpostor = _live[id].get_ref()
		if c == null:
			_live.erase(id)
		else:
			out.append(c)
	return out


# --- Card setup ---
func _init() -> void:
	set_meta(OctaAtlas.CARD_META, true)


func _enter_tree() -> void:
	_live[get_instance_id()] = weakref(self)
	if lod_mode == OctaLOD.LodMode.DISTANCE:
		visibility_range_begin = _lod_distance
	if lod_mode == OctaLOD.LodMode.SCREEN_SIZE or fade != OctaLOD.Fade.NONE:
		_apply_lod()
	_refresh()
	_apply_wind()


func _ready() -> void:
	if fade != OctaLOD.Fade.NONE:
		_apply_fade.call_deferred()


func _exit_tree() -> void:
	_live.erase(get_instance_id())
	_lod_distance = visibility_range_begin
	_checking = false
	if atlas != null:
		atlas.set_wind_user(self, false)
	_apply_real_mesh(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_apply_real_mesh(false)
	elif what == NOTIFICATION_EDITOR_POST_SAVE and fade != OctaLOD.Fade.NONE:
		_apply_fade()


func _validate_property(property: Dictionary) -> void:
	if property.name == "lod_distance" and lod_mode == OctaLOD.LodMode.SCREEN_SIZE:
		property.usage |= PROPERTY_USAGE_READ_ONLY
	elif property.name == "screen_percent" and lod_mode == OctaLOD.LodMode.DISTANCE:
		property.usage = PROPERTY_USAGE_STORAGE
	elif (property.name == "fade_margin" or property.name == "fade_real_mesh") and fade == OctaLOD.Fade.NONE:
		property.usage = PROPERTY_USAGE_STORAGE


func _refresh() -> void:
	if not is_inside_tree():
		return
	if atlas == null or object_index >= atlas.object_count():
		return
	mesh = atlas.get_mesh(object_index)
	material_override = atlas.get_material(quality)
	set_instance_shader_parameter("octa_index", object_index)
	if fade != OctaLOD.Fade.NONE:
		_apply_fade()
	_apply_wind()


# --- LOD and fade ---
func configure(s: OctaBakeSettings, world_scale: float) -> void:
	_batch = true
	lod_mode = s.lod_mode
	screen_percent = s.lod_screen_percent
	fade = s.fade
	fade_margin = s.fade_margin
	fade_real_mesh = s.fade_real_mesh
	wind_strength = s.wind_strength
	_batch = false
	if get_meta(OctaLOD.MODE_META, OctaLOD.Mode.DYNAMIC_LOD) == OctaLOD.Mode.DYNAMIC_LOD:
		if lod_mode == OctaLOD.LodMode.DISTANCE:
			_set_begin(s.lod_distance)
			visibility_range_begin_margin = 1.0
		_apply_lod(world_scale)
	else:
		_apply_fade()


func set_lod(mode: int, distance: float, percent: float) -> void:
	_batch = true
	lod_mode = mode
	screen_percent = percent
	_batch = false
	if mode == OctaLOD.LodMode.DISTANCE:
		_set_begin(distance)
	_apply_lod()
	notify_property_list_changed()


func card_radius(world_scale := -1.0) -> float:
	if atlas == null or object_index >= atlas.object_count():
		return 0.0
	return atlas.bounds[object_index].w * (world_scale if world_scale > 0.0 else OctaLOD.world_scale(self))


func _apply_lod(world_scale := -1.0) -> void:
	if _batch:
		return
	if lod_mode == OctaLOD.LodMode.SCREEN_SIZE and get_meta(OctaLOD.MODE_META, OctaLOD.Mode.DYNAMIC_LOD) != OctaLOD.Mode.REPLACE and (world_scale > 0.0 or is_inside_tree()):
		var r := card_radius(world_scale)
		if r > 0.0:
			_set_begin(OctaLOD.distance_for_screen_size(r, screen_percent))
	_apply_fade()


func _set_begin(distance: float) -> void:
	_lod_distance = maxf(distance, 0.0)
	visibility_range_begin = _lod_distance


func _apply_fade() -> void:
	if _batch:
		return
	var usable: bool = fade == OctaLOD.Fade.CROSSFADE and visibility_range_begin > 0.0 and OctaLOD.fade_available() and get_meta(OctaLOD.MODE_META, OctaLOD.Mode.DYNAMIC_LOD) != OctaLOD.Mode.REPLACE
	if usable:
		visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		visibility_range_begin_margin = fade_margin
	elif visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED:
		visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		visibility_range_begin_margin = 1.0
	_apply_dither(usable)
	_apply_real_mesh(usable and fade_real_mesh)


func refresh_fade() -> void:
	_apply_fade()


func _apply_dither(usable: bool) -> void:
	if usable and not OctaLOD.fade_supported() and atlas != null:
		atlas.card_fade = true
		set_instance_shader_parameter("card_fade", OctaLOD.fade_band(visibility_range_begin, fade_margin))
		_dithered = true
	elif _dithered:
		set_instance_shader_parameter("card_fade", Vector2.ZERO)
		_dithered = false


# --- Wind ---
func _apply_wind() -> void:
	if wind_strength > 0.0 or _winded:
		set_instance_shader_parameter("card_wind", wind_strength)
		_winded = wind_strength > 0.0
	if atlas != null and is_inside_tree():
		atlas.set_wind_user(self, wind_strength > 0.0)


func _apply_real_mesh(on: bool) -> void:
	on = on and not OctaLOD.fade_supported()
	if not on and not _meshes_faded:
		return
	var src := source()
	if src == null:
		return
	var band := OctaLOD.fade_band(visibility_range_begin, fade_margin)
	var any := false
	for gi in OctaLOD.geometry_below(src):
		if gi.visibility_parent.is_empty() or gi.get_node_or_null(gi.visibility_parent) != self:
			continue
		if on:
			any = OctaMeshFade.apply(gi, band) > 0 or any
		else:
			OctaMeshFade.restore(gi)
	_meshes_faded = any


func source() -> Node3D:
	if not is_inside_tree():
		return null
	var n := get_node_or_null(get_meta(OctaLOD.SOURCE_META, NodePath("..")))
	return n as Node3D


# --- Inspector tools ---
func _editor() -> Object:
	return Engine.get_singleton("EditorInterface") if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface") else null


func _check_quality() -> bool:
	var ei := _editor()
	var src := source()
	if _checking or ei == null or src == null:
		return false
	_checking = true
	var r: Dictionary = await OctaQuality.measure(src, ei.get_base_control())
	_checking = false
	var msg: String = r.error if r.has("error") else "%s: shape match %.0f%% (worst view %.0f%%), wrong pixels %.1f%%. %s" % [r.name, r.iou * 100.0, r.worst_iou * 100.0, r.bad_pct, r.suggestion]
	print("Octahedral Impostor LOD quality check - ", msg)
	ei.get_editor_toaster().push_toast(msg, 0 if r.get("good", false) else 1)
	return true


func _select_source() -> void:
	var ei := _editor()
	var src := source()
	if ei != null and src != null:
		ei.get_selection().clear()
		ei.get_selection().add_node(src)


func _edit_shared() -> void:
	var ei := _editor()
	if ei != null and material_override != null:
		ei.edit_resource(material_override)
