@tool
@icon("res://addons/octahedral_impostor_lod/icon_impostor.svg")
class_name OctaDebugHUD
extends Control

## Seconds between scans of the scene.
@export_range(0.1, 5.0, 0.1, "suffix:s") var refresh_interval := 0.5
## Press this key to cycle the debug view (None = disabled).
@export var cycle_key: Key = KEY_NONE

const MAX_FILL_INSTANCES := 2000

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
	var fill := {}
	if tree != null and tree.root != null:
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		for n in tree.root.find_children("*", "OctaImpostor", true, false):
			var c := n as OctaImpostor
			cards += 1
			var dist := cam.global_position.distance_to(c.global_position) if cam != null else 0.0
			var active := c.is_visible_in_tree() and dist >= c.visibility_range_begin and (c.visibility_range_end <= 0.0 or dist <= c.visibility_range_end)
			if active:
				impostors += 1
				_add_fill(fill, c.atlas, c.object_index, c.global_position, c.global_transform.basis.get_scale().x, cam)
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
					_add_multimesh_fill(fill, mmi, m, cam)
	var atlases := OctaAtlas.live_atlases()
	var bytes := 0
	for a in atlases:
		bytes += a.vram_bytes()
	var fill_lines := PackedStringArray()
	var fill_pct := {}
	for a: OctaAtlas in fill:
		var w: Vector2 = fill[a]
		fill_pct[a] = w.x / maxf(w.y, 1e-9) * 100.0
		var label := "" if fill.size() == 1 else " (%s)" % (a.resource_path.get_file() if a.resource_path != "" else "atlas %d" % fill_lines.size())
		fill_lines.append("Card fill: %.0f%% of card area is covered%s" % [fill_pct[a], label])
	stats = {cards = cards, impostor_visible = impostors, real_visible = real, multimesh_instances = instances, atlases = atlases.size(), vram_mb = bytes / 1048576.0, card_fill = fill_pct}
	_label.text = "Impostor cards: %d (%d MultiMesh instances)\nImpostors drawn: %d   Real meshes: %d\nAtlases: %d   VRAM about %.1f MB\nDebug view: %s" % [
		cards, instances, impostors, real, atlases.size(), stats.vram_mb, OctaDebug.mode_names()[OctaDebug.mode]]
	for line in fill_lines:
		_label.text += "
" + line
	return stats


# --- Card fill ---
func _add_fill(fill: Dictionary, atlas: OctaAtlas, index: int, pos: Vector3, scale: float, cam: Camera3D) -> void:
	if atlas == null or cam == null or index < 0 or index >= atlas.object_count() or not cam.is_position_in_frustum(pos):
		return
	var screen := pow(atlas.bounds[index].w * scale / maxf(cam.global_position.distance_to(pos), 0.01), 2.0)
	var w: Vector2 = fill.get(atlas, Vector2.ZERO)
	fill[atlas] = w + Vector2(OctaCoverage.mean_covered(atlas, index) * screen, screen)


func _add_multimesh_fill(fill: Dictionary, mmi: MultiMeshInstance3D, m: ShaderMaterial, cam: Camera3D) -> void:
	var atlas: OctaAtlas = null
	for a in OctaAtlas.live_atlases():
		if a.object_data() == m.get_shader_parameter("obj_data"):
			atlas = a
	var mm := mmi.multimesh
	var index := int(mmi.get_instance_shader_parameter("octa_index"))
	for i in mini(mm.instance_count, MAX_FILL_INSTANCES):
		var t := mmi.global_transform * mm.get_instance_transform(i)
		_add_fill(fill, atlas, index, t.origin, t.basis.get_scale().x, cam)
