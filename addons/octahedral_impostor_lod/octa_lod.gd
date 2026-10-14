@tool
class_name OctaLOD
extends RefCounted

enum Mode {
	DYNAMIC_LOD,
	DUPLICATE,
	REPLACE,
}

const SOURCE_META := &"octa_source"
const MODE_META := &"octa_mode"


# --- Generate and attach ---
static func generate(sources: Array, host: Node, settings: OctaBakeSettings = null, save_path := "") -> OctaAtlas:
	if settings == null:
		settings = OctaBakeSettings.new()
	var atlas: OctaAtlas
	if save_path.is_empty():
		atlas = await OctaBaker.bake(sources, host, settings)
	else:
		atlas = await OctaBaker.bake_to_file(sources, host, save_path, settings)
	if atlas != null:
		for i in sources.size():
			attach_card(sources[i], atlas, i, settings.mode, settings.lod_distance, settings.quality)
	return atlas


static func attach_card(source: Node3D, atlas: OctaAtlas, index: int, mode := Mode.DYNAMIC_LOD,
		lod_distance := 40.0, quality := OctaAtlas.Quality.HIGH, owner: Node = null) -> MeshInstance3D:
	var card := atlas.create_card(index, quality)
	if is_child_card(source, mode):
		source.add_child(card, true)
	else:
		card.name = String(source.name) + "_OctaImpostor"
		card.transform = source.transform
		source.get_parent().add_child(card, true)
	card.set_meta(SOURCE_META, card.get_path_to(source))
	card.set_meta(MODE_META, mode)
	if mode == Mode.DYNAMIC_LOD:
		card.visibility_range_begin = lod_distance
		card.visibility_range_begin_margin = 1.0
		for gi in geometry_below(source):
			gi.visibility_parent = gi.get_path_to(card)
	elif mode == Mode.REPLACE:
		source.visible = false
	if owner != null:
		card.owner = owner
	return card


# --- Remove ---
static func remove_cards(source: Node3D) -> void:
	for card in find_cards(source):
		_restore(source, card)
		card.get_parent().remove_child(card)
		card.queue_free()


static func find_cards(source: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var pool := source.get_children()
	if source.get_parent() != null:
		pool.append_array(source.get_parent().get_children())
	for n in pool:
		if n is Node3D and n.has_meta(OctaAtlas.CARD_META) and n.get_node_or_null(n.get_meta(SOURCE_META, NodePath(".."))) == source:
			out.append(n)
	return out


# --- Helpers ---
static func is_child_card(source: Node, mode: Mode) -> bool:
	return mode == Mode.DYNAMIC_LOD and not source is GeometryInstance3D


static func geometry_below(node: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	if node.has_meta(OctaAtlas.CARD_META):
		return out
	if node is GeometryInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(geometry_below(c))
	return out


static func _restore(source: Node3D, card: Node) -> void:
	for gi in geometry_below(source):
		if gi.get_node_or_null(gi.visibility_parent) == card:
			gi.visibility_parent = NodePath()
	if card.get_meta(MODE_META, Mode.DYNAMIC_LOD) == Mode.REPLACE:
		source.visible = true
