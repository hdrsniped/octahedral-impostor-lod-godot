@tool
class_name OctaAtlas
extends Resource

enum Quality { LOW, MEDIUM, HIGH }

const SHADERS := [
	preload("res://addons/octahedral_impostor_lod/shaders/octa_low.gdshader"),
	preload("res://addons/octahedral_impostor_lod/shaders/octa_medium.gdshader"),
	preload("res://addons/octahedral_impostor_lod/shaders/octa_high.gdshader"),
]
const MAX_OBJECTS := 256
const CARD_META := &"octa_card"

@export var albedo: Texture2D
@export var normal_depth: Texture2D
@export var grid_size := 12
@export var hemisphere := true
@export var tiles := Vector2i.ONE
@export var frame_resolution := 128
@export var frame_scale := 1.0
@export var object_names := PackedStringArray()
@export var bounds := PackedVector4Array()
@export var surface_params := PackedVector4Array()
@export var materials: Array[ShaderMaterial] = [null, null, null]
@export var meshes: Array[Mesh] = []


# --- Materials, meshes and cards ---
func object_count() -> int:
	return bounds.size()


func index_of(object_name: String) -> int:
	return object_names.find(object_name)


func get_material(quality: Quality = Quality.HIGH) -> ShaderMaterial:
	if materials.size() < 3:
		materials.resize(3)
	if materials[quality] == null:
		var m := ShaderMaterial.new()
		m.shader = SHADERS[quality]
		materials[quality] = m
	_apply_params(materials[quality])
	return materials[quality]


func _apply_params(m: ShaderMaterial) -> void:
	m.set_shader_parameter("albedo_atlas", albedo)
	m.set_shader_parameter("normal_atlas", normal_depth)
	m.set_shader_parameter("grid_size", grid_size)
	m.set_shader_parameter("tiles", tiles)
	m.set_shader_parameter("hemisphere", hemisphere)
	m.set_shader_parameter("frame_scale", frame_scale)
	m.set_shader_parameter("obj_bounds", bounds)
	m.set_shader_parameter("obj_surface", surface_params)


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


func create_card(index: int, quality: Quality = Quality.HIGH) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "OctaImpostor"
	mi.set_meta(CARD_META, true)
	mi.mesh = get_mesh(index)
	mi.material_override = get_material(quality)
	mi.set_instance_shader_parameter("octa_index", index)
	return mi


func create_multimesh(index: int, transforms: Array, quality: Quality = Quality.HIGH) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = get_mesh(index)
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
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
