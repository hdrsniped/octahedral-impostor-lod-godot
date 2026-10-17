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
const MIN_JOINED_DEPTH := 0.001
const DEFAULT_SURFACE := Vector4(0.9, 0.0, 0.5, 0.0)
const DEFAULT_MATERIAL := Vector4(1.0, 0.0, 1.0, 0.0)

@export var format_version := 1
@export var albedo: Texture2D
@export var normal_depth: Texture2D
@export var back_depth: Texture2D
@export var orm: Texture2D
@export var emission: Texture2D
@export var grid_size := 12
@export var hemisphere := true
@export var parent_space := false
@export var tiles := Vector2i.ONE
@export var frame_resolution := 128
@export var frame_scale := 1.0
@export var write_depth := true:
	set(v):
		write_depth = v
		for q in materials.size():
			if materials[q] != null:
				materials[q].shader = shader_for(q, write_depth, -1, precise_search)
@export var precise_search := false:
	set(v):
		precise_search = v
		for q in materials.size():
			if materials[q] != null:
				materials[q].shader = shader_for(q, write_depth, -1, precise_search)
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
@export var materials: Array[ShaderMaterial] = [null, null, null, null]
@export var meshes: Array[Mesh] = []
@export var bake_settings: OctaBakeSettings

var _obj_data: ImageTexture

static var _variants := {}
static var _live: Array[WeakRef] = []


# --- Materials, meshes and cards ---
static func shader_for(quality: int, depth: bool = true, debug: int = -1, precise: bool = false) -> Shader:
	if debug < 0:
		debug = OctaDebug.mode
	precise = precise and quality == Quality.ULTRA
	if depth and debug == 0 and not precise:
		return SHADERS[quality]
	var key := quality * 100 + (10 if depth else 0) + debug + (1000 if precise else 0)
	if not _variants.has(key):
		var s := Shader.new()
		s.code = "shader_type spatial;\n#define QUALITY %d\n%s%s#define DEBUG_MODE %d\n#include \"%s\"\n" % [quality, "" if depth else "#define NO_DEPTH_WRITE\n", "#define PRECISE_SEARCH\n" if precise else "", debug, SHADER_INCLUDE]
		_variants[key] = s
	return _variants[key]


static func live_atlases() -> Array[OctaAtlas]:
	var keep: Array[WeakRef] = []
	var out: Array[OctaAtlas] = []
	for w in _live:
		var a := w.get_ref() as OctaAtlas
		if a != null:
			keep.append(w)
			out.append(a)
	_live = keep
	return out


static func refresh_all_materials() -> void:
	for a in live_atlases():
		for q in a.materials.size():
			if a.materials[q] != null:
				a.materials[q].shader = shader_for(q, a.write_depth, -1, a.precise_search)


func vram_bytes() -> int:
	var total := 0.0
	for t: Texture2D in [albedo, normal_depth, orm, emission]:
		total += _map_bytes(t, 4.0)
	total += _map_bytes(back_depth, 1.0)
	return int(total)


func has_half_res_maps() -> bool:
	for t: Texture2D in [orm, emission]:
		if t != null and albedo != null and t.get_width() < albedo.get_width():
			return true
	return false


static func _map_bytes(t: Texture2D, bytes_per_pixel: float) -> float:
	return 0.0 if t == null else t.get_width() * t.get_height() * bytes_per_pixel * 4.0 / 3.0


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
	if not _live.any(func(w: WeakRef) -> bool: return w.get_ref() == self):
		_live.append(weakref(self))
	var want := shader_for(quality, write_depth, -1, precise_search)
	if materials[quality].shader != want:
		materials[quality].shader = want
	_apply_params(materials[quality])
	return materials[quality]


func _apply_params(m: ShaderMaterial) -> void:
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
	if m.shader == shader_for(Quality.ULTRA, write_depth, -1, precise_search):
		m.set_shader_parameter("back_atlas", back_depth)
		m.set_shader_parameter("use_back_layer", back_depth != null)


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


func create_multimesh(index: int, transforms: Array, quality: Quality = Quality.HIGH, customs: Array = []) -> MultiMeshInstance3D:
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
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "ImpostorMultiMesh"
	mmi.multimesh = mm
	mmi.material_override = get_material(quality)
	mmi.set_instance_shader_parameter("octa_index", index)
	return mmi


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
