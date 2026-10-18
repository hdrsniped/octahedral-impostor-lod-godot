@tool
class_name OctaAtlas
extends Resource

enum Quality { LOW, MEDIUM, HIGH, ULTRA }

const SHADERS := [
	preload("res://addons/octahedral_impostor_lod/shaders/octa_low.gdshader"),
	preload("res://addons/octahedral_impostor_lod/shaders/octa_medium.gdshader"),
	preload("res://addons/octahedral_impostor_lod/shaders/octa_high.gdshader"),
	preload("res://addons/octahedral_impostor_lod/shaders/octa_ultra.gdshader"),
]
const SHADER_INCLUDE := "res://addons/octahedral_impostor_lod/shaders/octa_core.gdshaderinc"
const MAX_OBJECTS := 1024
const FORMAT_VERSION := 4
const CARD_META := &"octa_card"
const CHUNK_META := &"octa_chunk"
const COVERAGE_BLOCK := 4
const MIN_JOINED_DEPTH := 0.001
const DEFAULT_SURFACE := Vector4(0.9, 0.0, 0.5, 0.0)
const DEFAULT_MATERIAL := Vector4(1.0, 0.0, 1.0, 0.0)
const V_PRECISE := 1
const V_FADE := 2
const V_WIND := 4
const V_VISIBILITY := 8
const V_PYRAMID := 16
const V_PARALLAX := 32

@export var format_version := 1
@export var albedo: Texture2D
@export var normal_depth: Texture2D
@export var back_depth: Texture2D
@export var orm: Texture2D
@export var emission: Texture2D
@export var max_coverage: Texture2D
@export var grid_size := 12
@export var hemisphere := true
@export var parent_space := false
@export var tiles := Vector2i.ONE
@export var frame_resolution := 128
@export var frame_scale := 1.0
@export var write_depth := true:
	set(v):
		write_depth = v
		_update_shaders()
@export var precise_search := false:
	set(v):
		precise_search = v
		_update_shaders()

@export var view_visibility := false:
	set(v):
		view_visibility = v
		_update_shaders()

@export var pyramid_search := false:
	set(v):
		pyramid_search = v
		_update_shaders()

@export var parallax_refine := false:
	set(v):
		parallax_refine = v
		_update_shaders()

@export_range(1, 3) var shadow_views := 1:
	set(v):
		shadow_views = v
		for m in materials:
			if m != null:
				m.set_shader_parameter("shadow_views", shadow_views)
@export var object_names := PackedStringArray()
@export var bounds := PackedVector4Array()
@export var surface_params := PackedVector4Array()
@export var material_params := PackedVector4Array()
var materials: Array[ShaderMaterial] = []
@export var meshes: Array[Mesh] = []
@export var bake_settings: OctaBakeSettings

var card_fade := false:
	set(v):
		if card_fade == v:
			return
		card_fade = v
		_update_shaders()

var _obj_data: ImageTexture
var _wind_users := {}
var _wind_on := false
var _stamp := 0
var _param_stamp := {}

static var _variants := {}
static var _live := {}


# --- Materials, meshes and cards ---
static func shader_for(quality: int, depth: bool = true, debug: int = -1, precise: bool = false, fade: bool = false, wind: bool = false, visibility: bool = false, pyramid: bool = false, parallax: bool = false) -> Shader:
	var flags := 0
	if precise:
		flags |= V_PRECISE
	if fade:
		flags |= V_FADE
	if wind:
		flags |= V_WIND
	if visibility:
		flags |= V_VISIBILITY
	if pyramid:
		flags |= V_PYRAMID
	if parallax:
		flags |= V_PARALLAX
	return shader_variant(quality, depth, debug, flags)


static func shader_variant(quality: int, depth: bool = true, debug: int = -1, flags: int = 0) -> Shader:
	if debug < 0:
		debug = OctaDebug.mode
	if quality != Quality.ULTRA:
		flags &= ~(V_PRECISE | V_PYRAMID)
	else:
		flags &= ~V_VISIBILITY
	if quality >= Quality.HIGH:
		flags &= ~V_PARALLAX
	if depth and debug == 0 and flags == 0:
		return SHADERS[quality]
	var key := quality * 100 + (10 if depth else 0) + debug + (1000 if flags & V_PRECISE else 0) + (2000 if flags & V_FADE else 0) + (4000 if flags & V_WIND else 0) + (8000 if flags & V_VISIBILITY else 0) + (16000 if flags & V_PYRAMID else 0) + (32000 if flags & V_PARALLAX else 0)
	if not _variants.has(key):
		var defs := PackedStringArray()
		if not depth:
			defs.append("#define NO_DEPTH_WRITE\n")
		if flags & V_PRECISE:
			defs.append("#define PRECISE_SEARCH\n")
		if flags & V_FADE:
			defs.append("#define CARD_FADE\n")
		if flags & V_WIND:
			defs.append("#define CARD_WIND\n")
		if flags & V_VISIBILITY:
			defs.append("#define VIEW_VISIBILITY\n")
		if flags & V_PYRAMID:
			defs.append("#define PYRAMID_SEARCH\n")
		if flags & V_PARALLAX:
			defs.append("#define PARALLAX_REFINE\n")
		var s := Shader.new()
		s.code = "shader_type spatial;\n#define QUALITY %d\n%s#define DEBUG_MODE %d\n#include \"%s\"\n" % [quality, "".join(defs), debug, SHADER_INCLUDE]
		_variants[key] = s
	return _variants[key]


static func live_atlases() -> Array[OctaAtlas]:
	var out: Array[OctaAtlas] = []
	for id: int in _live.keys():
		var a: OctaAtlas = _live[id].get_ref()
		if a == null:
			_live.erase(id)
		else:
			out.append(a)
	return out


static func refresh_all_materials() -> void:
	for a in live_atlases():
		a._update_shaders()


# --- Wind users ---
func set_wind_user(user: Object, on: bool) -> void:
	var before := _wind_on
	if on:
		_wind_users[user.get_instance_id()] = true
	else:
		_wind_users.erase(user.get_instance_id())
	_wind_on = not _wind_users.is_empty()
	if on:
		_track()
	if _wind_on != before:
		_update_shaders()


func wind_active() -> bool:
	return _wind_on


func wind_counts() -> Vector2i:
	var cards := 0
	var groups := 0
	for id: int in _wind_users.keys():
		if not is_instance_id_valid(id):
			_wind_users.erase(id)
		elif instance_from_id(id) is OctaJoinedGroup:
			groups += 1
		else:
			cards += 1
	_wind_on = not _wind_users.is_empty()
	return Vector2i(cards, groups)


func apply_wind() -> void:
	if not wind_active():
		return
	for m in materials:
		if m != null:
			OctaWind.apply_to(m)


func save_file() -> void:
	if resource_path.begins_with("res://") and not resource_path.contains("::"):
		ResourceSaver.save(self)


func _update_shaders() -> void:
	_stamp += 1
	for q in materials.size():
		if materials[q] != null:
			materials[q].shader = _shader(q)
			_apply_params(materials[q])
	apply_wind()


func refresh_materials() -> void:
	_stamp += 1
	for m in materials:
		if m != null:
			_apply_params(m)


func _track() -> void:
	_live[get_instance_id()] = weakref(self)


func vram_bytes() -> int:
	var total := 0.0
	var bpp := 1.0 if albedo is PortableCompressedTexture2D else 4.0
	for t: Texture2D in [albedo, normal_depth, orm, emission]:
		total += _map_bytes(t, bpp)
	total += _map_bytes(back_depth, 1.0)
	total += _map_bytes(max_coverage, 1.0, 1.0)
	total += float(maxi(object_count(), 1)) * 64.0
	return int(total)


func has_half_res_maps() -> bool:
	for t: Texture2D in [orm, emission]:
		if t != null and albedo != null and t.get_width() < albedo.get_width():
			return true
	return false


static func _map_bytes(t: Texture2D, bytes_per_pixel: float, mip_factor := 4.0 / 3.0) -> float:
	return 0.0 if t == null else t.get_width() * t.get_height() * bytes_per_pixel * mip_factor


func card_coverage(object_index: int) -> Dictionary:
	return OctaCoverage.measure(self, object_index)


func object_count() -> int:
	return bounds.size()


func index_of(object_name: String) -> int:
	return object_names.find(object_name)


func get_material(quality: Quality = Quality.HIGH) -> ShaderMaterial:
	if materials.size() < SHADERS.size():
		materials.resize(SHADERS.size())
	if materials[quality] == null:
		materials[quality] = ShaderMaterial.new()
	_track()
	var want := _shader(quality)
	if materials[quality].shader != want:
		materials[quality].shader = want
	_apply_params(materials[quality])
	return materials[quality]


func _apply_params(m: ShaderMaterial) -> void:
	var id := m.get_instance_id()
	if _param_stamp.get(id, -1) == _stamp:
		return
	m.set_shader_parameter("albedo_atlas", albedo)
	m.set_shader_parameter("normal_atlas", normal_depth)
	m.set_shader_parameter("grid_size", grid_size)
	m.set_shader_parameter("hemisphere", hemisphere)
	m.set_shader_parameter("frame_scale", frame_scale)
	m.set_shader_parameter("shadow_views", shadow_views)
	m.set_shader_parameter("obj_data", object_data())
	m.set_shader_parameter("orm_atlas", orm)
	m.set_shader_parameter("use_orm", orm != null)
	m.set_shader_parameter("emission_atlas", emission)
	m.set_shader_parameter("use_emission", emission != null)
	m.set_shader_parameter("max_coverage", max_coverage)
	if m.shader == _shader(Quality.ULTRA):
		m.set_shader_parameter("back_atlas", back_depth)
		m.set_shader_parameter("use_back_layer", back_depth != null)
	if bake_settings != null and m.shader == _shader(Quality.ULTRA):
		m.set_shader_parameter("search_steps", bake_settings.search_steps)
		m.set_shader_parameter("layer_tolerance", bake_settings.layer_tolerance)
	if wind_active():
		OctaWind.apply_to(m)
	_param_stamp[id] = _stamp


func _shader(quality: int) -> Shader:
	return shader_for(quality, write_depth, -1, precise_search, card_fade and not OctaLOD.fade_supported(), wind_active(), view_visibility, pyramid_search, parallax_refine)


func object_data() -> ImageTexture:
	if _obj_data != null and _obj_data.get_height() == maxi(object_count(), 1):
		return _obj_data
	var img := Image.create_empty(4, maxi(object_count(), 1), false, Image.FORMAT_RGBAF)
	var cols := maxi(tiles.x, 1)
	var cell := Vector2.ONE / Vector2(maxi(tiles.x, 1), maxi(tiles.y, 1))
	for i in object_count():
		var b := bounds[i]
		var sp := surface_params[i] if i < surface_params.size() else DEFAULT_SURFACE
		var mp := material_params[i] if i < material_params.size() else DEFAULT_MATERIAL
		if format_version < 4:
			mp = Vector4(mp.x, mp.y, 1.0, 0.0)
		var at := Vector2(i % cols, i / cols) * cell
		img.set_pixel(0, i, Color(b.x, b.y, b.z, b.w))
		img.set_pixel(1, i, Color(sp.x, sp.y, sp.z, sp.w))
		img.set_pixel(2, i, Color(at.x, at.y, cell.x, cell.y))
		img.set_pixel(3, i, Color(mp.x, mp.y, mp.z, mp.w))
	_obj_data = ImageTexture.create_from_image(img)
	_stamp += 1
	return _obj_data


func card_transform(source: Node3D) -> Transform3D:
	return Transform3D(Basis.IDENTITY, source.position) if parent_space else source.transform


func get_mesh(index: int) -> Mesh:
	if meshes.size() != object_count():
		meshes.resize(object_count())
	if meshes[index] == null:
		var q := QuadMesh.new()
		q.size = Vector2(2, 2)
		var b := bounds[index]
		var c := Vector3(b.x, b.y, b.z)
		q.custom_aabb = AABB(c - Vector3.ONE * b.w, Vector3.ONE * b.w * 2.0)
		meshes[index] = q
	return meshes[index]


func create_card(index: int, quality: Quality = Quality.HIGH) -> OctaImpostor:
	var card := OctaImpostor.new()
	card.name = "OctaImpostor"
	card.quality = quality
	card.object_index = index
	card.atlas = self
	return card


static func joined_custom(tint: Color, depth: float) -> Color:
	var lin := tint.srgb_to_linear()
	return Color(lin.r, lin.g, lin.b, maxf(depth, MIN_JOINED_DEPTH))


func create_multimesh(index: int, transforms: Array, quality: Quality = Quality.HIGH, customs: Array = [], lod_distance := 0.0, fade_margin := 0.0, wind_strength := 0.0) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = not customs.is_empty()
	mm.mesh = get_mesh(index)
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		if mm.use_custom_data:
			var c: Color = customs[i]
			mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, maxf(c.a, MIN_JOINED_DEPTH)))
	var mmi := OctaJoinedGroup.new()
	mmi.name = "ImpostorMultiMesh"
	mmi.multimesh = mm
	mmi.atlas = self
	mmi.material_override = get_material(quality)
	mmi.set_instance_shader_parameter("octa_index", index)
	mmi.wind_strength = wind_strength
	if lod_distance > 0.0 and fade_margin > 0.0 and not OctaLOD.fade_supported():
		card_fade = true
		mmi.set_instance_shader_parameter("card_fade", OctaLOD.fade_band(lod_distance, fade_margin))
	return mmi


func create_multimeshes(index: int, transforms: Array, quality: Quality = Quality.HIGH, customs: Array = [], join_cell := 50.0, adaptive := true, region_size := 20.0, region_count := 128, lod_distance := 0.0, fade_margin := 0.0, wind_strength := 0.0) -> Array[MultiMeshInstance3D]:
	var points := PackedVector3Array()
	for t: Transform3D in transforms:
		points.append(t.origin)
	var out: Array[MultiMeshInstance3D] = []
	for region: PackedInt32Array in OctaJoin.partition(points, join_cell, adaptive, region_size, region_count):
		var xs: Array = []
		var cs: Array = []
		for i in region:
			xs.append(transforms[i])
			if not customs.is_empty():
				cs.append(customs[i])
		out.append(create_multimesh(index, xs, quality, cs, lod_distance, fade_margin, wind_strength))
	return out


# --- View directions (same math as the shader) ---
static func oct_decode(p: Vector2) -> Vector3:
	var n := Vector3(p.x, 1.0 - absf(p.x) - absf(p.y), p.y)
	if n.y < 0.0:
		var sx := 1.0 if n.x >= 0.0 else -1.0
		var sz := 1.0 if n.z >= 0.0 else -1.0
		var nx := (1.0 - absf(n.z)) * sx
		n.z = (1.0 - absf(n.x)) * sz
		n.x = nx
	return n.normalized()


static func hemi_decode(p: Vector2) -> Vector3:
	var x := (p.x + p.y) * 0.5
	var z := (p.x - p.y) * 0.5
	return Vector3(x, 1.0 - absf(x) - absf(z), z).normalized()


static func frame_dir(frame: Vector2i, grid: int, hemi: bool) -> Vector3:
	var last := maxf(grid - 1.0, 1.0)
	var p := Vector2(frame) / last * 2.0 - Vector2.ONE
	return hemi_decode(p) if hemi else oct_decode(p)


static func frame_basis(d: Vector3) -> Basis:
	var up := Vector3(0, 0, -1) if absf(d.y) > 0.999 else Vector3.UP
	var x := up.cross(d).normalized()
	var y := d.cross(x)
	return Basis(x, y, d)
