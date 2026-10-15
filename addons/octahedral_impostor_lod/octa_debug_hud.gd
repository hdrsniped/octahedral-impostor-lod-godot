@tool
@icon("res://addons/octahedral_impostor_lod/icon_impostor.svg")
class_name OctaDebugHUD
extends Control

## Seconds between scans of the scene.
@export_range(0.1, 5.0, 0.1, "suffix:s") var refresh_interval := 0.5
## Press this key to cycle the debug view (None = disabled).
@export var cycle_key := KEY_NONE

var stats := {}

var _label: Label
var _time := 0.0


# --- Overlay ---
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _ready() -> void:
	position = Vector2(8, 8)
	scan()


func _process(delta: float) -> void:
	_time += delta
	if _time >= refresh_interval:
		_time = 0.0
		scan()


func _unhandled_key_input(event: InputEvent) -> void:
	if cycle_key != KEY_NONE and event is InputEventKey and event.pressed and not event.echo and event.keycode == cycle_key:
		OctaDebug.set_mode(((OctaDebug.mode + 1) % OctaDebug.Mode.size()) as OctaDebug.Mode)
		scan()


# --- Statistics ---
func scan() -> Dictionary:
	var tree := get_tree()
	var cards := 0
	var impostors := 0
	var real := 0
	var instances := 0
	if tree != null and tree.root != null:
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		for n in tree.root.find_children("*", "OctaImpostor", true, false):
			var c := n as OctaImpostor
			cards += 1
			var dist := cam.global_position.distance_to(c.global_position) if cam != null else 0.0
			var active := c.is_visible_in_tree() and dist >= c.visibility_range_begin and (c.visibility_range_end <= 0.0 or dist <= c.visibility_range_end)
			if active:
				impostors += 1
			elif c.get_meta(OctaLOD.MODE_META, OctaLOD.Mode.DYNAMIC_LOD) == OctaLOD.Mode.DYNAMIC_LOD:
				real += 1
		for n in tree.root.find_children("*", "MultiMeshInstance3D", true, false):
			var mmi := n as MultiMeshInstance3D
			var m := mmi.material_override as ShaderMaterial
			if m != null and m.get_shader_parameter("obj_data") != null and mmi.multimesh != null:
				cards += 1
				instances += mmi.multimesh.instance_count
				if mmi.is_visible_in_tree():
					impostors += mmi.multimesh.instance_count
	var atlases := OctaAtlas.live_atlases()
	var bytes := 0
	for a in atlases:
		bytes += a.vram_bytes()
	stats = {cards = cards, impostor_visible = impostors, real_visible = real, multimesh_instances = instances, atlases = atlases.size(), vram_mb = bytes / 1048576.0}
	_label.text = "Impostor cards: %d (%d MultiMesh instances)\nImpostors drawn: %d   Real meshes: %d\nAtlases: %d   VRAM about %.1f MB\nDebug view: %s" % [
		cards, instances, impostors, real, atlases.size(), stats.vram_mb, OctaDebug.mode_names()[OctaDebug.mode]]
	return stats
