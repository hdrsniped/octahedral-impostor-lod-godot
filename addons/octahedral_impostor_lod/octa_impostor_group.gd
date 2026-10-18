@tool
@icon("res://addons/octahedral_impostor_lod/icon_impostor.svg")
class_name OctaImpostorGroup
extends Node3D

const PLUGIN_META := &"octa_lod_plugin"
const END_META := &"octa_chunk_end"

## Bake settings of this group. Precedence, highest first: a card's own properties (lod distance,
## quality, tint, depth, LOD mode, screen size, fade, fade margin) set after baking, then these
## settings, then the bake dialog settings. Baking a group never uses the dialog settings, and a
## re-bake keeps the properties you changed on the cards.
@export var settings: OctaBakeSettings = OctaBakeSettings.new()
## Objects to bake, as paths relative to this node. Empty = every direct child that holds a mesh.
@export var targets: Array[NodePath] = []
## The atlas made by the last bake of this group (one atlas for all its objects).
@export var atlas: OctaAtlas

@export_group("Chunk LOD")
## Distance in meters beyond which the whole group is drawn as ONE card instead of one card per
## object (0 = off). The chunk card is baked from the group's real meshes by "Bake Group" (or
## "Re-bake Group"); the object cards stop at this distance. Keep chunks compact: a card is a
## camera-facing quad.
@export var chunk_lod_distance := 0.0
## Shader quality of the chunk card (its atlas is baked with the group's settings).
@export var chunk_quality := OctaAtlas.Quality.HIGH
## The atlas of the chunk card, saved next to the group's own atlas.
@export var chunk_atlas: OctaAtlas

@export_group("Tools")
@export_tool_button("Bake Group", "Play") var bake_action := _bake
@export_tool_button("Re-bake Group", "Reload") var rebake_action := _rebake


# --- Targets ---
func target_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if targets.is_empty():
		for c in get_children():
			if c is Node3D and not c is OctaImpostorGroup and not c.has_meta(OctaAtlas.CARD_META) and _has_mesh(c):
				out.append(c)
		return out
	for p in targets:
		var n := get_node_or_null(p) as Node3D
		if n != null and n != self and not n.has_meta(OctaAtlas.CARD_META) and not out.has(n):
			out.append(n)
	return out


func cards() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for t in target_nodes():
		for c in OctaLOD.find_cards_below(t):
			if not out.has(c):
				out.append(c)
	for c in get_children():
		if c.has_meta(OctaAtlas.CARD_META) and not out.has(c):
			out.append(c)
	return out


func chunk_card() -> Node3D:
	for c in get_children():
		if c.has_meta(OctaAtlas.CHUNK_META):
			return c
	return null


# --- Chunk LOD ---
func attach_chunk(atlas_res: OctaAtlas, s: OctaBakeSettings, distance: float) -> Node3D:
	detach_chunk()
	chunk_atlas = atlas_res
	var card := atlas_res.create_card(0, chunk_quality)
	card.name = "OctaChunk"
	card.set_meta(OctaAtlas.CHUNK_META, true)
	card.set_meta(OctaLOD.SOURCE_META, NodePath(".."))
	card.set_meta(OctaLOD.MODE_META, OctaLOD.Mode.DYNAMIC_LOD)
	add_child(card)
	if owner != null:
		card.owner = owner
	card.configure(s, OctaLOD.world_scale(self))
	for c in cards():
		if c != card:
			if not c.has_meta(END_META):
				c.set_meta(END_META, c.visibility_range_end)
			c.visibility_range_end = distance
	return card


func detach_chunk() -> void:
	var old := chunk_card()
	for c in cards():
		if c != old:
			if c.has_meta(END_META):
				c.visibility_range_end = float(c.get_meta(END_META))
				c.remove_meta(END_META)
			elif is_equal_approx(c.visibility_range_end, chunk_lod_distance):
				c.visibility_range_end = 0.0
	if old != null:
		if old.get_parent() != null:
			old.get_parent().remove_child(old)
		old.queue_free()


func chunk_settings() -> OctaBakeSettings:
	var s := effective_settings().duplicate()
	s.mode = OctaLOD.Mode.DYNAMIC_LOD
	s.lod_mode = OctaLOD.LodMode.DISTANCE
	s.lod_distance = chunk_lod_distance
	s.fade = OctaLOD.Fade.NONE
	s.quality = chunk_quality
	return s


func effective_settings() -> OctaBakeSettings:
	return settings if settings != null else OctaBakeSettings.new()


func info() -> String:
	var nodes := target_nodes()
	return "Group %s: %d object(s), %d card(s) baked.\n%s" % [name, nodes.size(), cards().size(), effective_settings().describe(nodes.size(), nodes)]


static func find_all(root: Node) -> Array[OctaImpostorGroup]:
	var out: Array[OctaImpostorGroup] = []
	if root is OctaImpostorGroup:
		out.append(root)
	for c in root.get_children():
		out.append_array(find_all(c))
	return out


static func group_of(node: Node, root: Node) -> OctaImpostorGroup:
	return group_in(node, claimed_nodes(root))


static func group_in(node: Node, claimed: Dictionary) -> OctaImpostorGroup:
	if node is OctaImpostorGroup:
		return node
	var n := node
	while n != null:
		if claimed.has(n):
			return claimed[n] as OctaImpostorGroup
		n = n.get_parent()
	return null


static func claimed_nodes(root: Node) -> Dictionary:
	var out := {}
	for g in find_all(root):
		for t in g.target_nodes():
			out[t] = g
	return out


static func _has_mesh(node: Node) -> bool:
	return OctaLOD.geometry_below(node).any(func(g: Node) -> bool: return g is MeshInstance3D and g.mesh != null)


# --- Inspector tools ---
func _plugin() -> Object:
	return Engine.get_meta(PLUGIN_META, null) if Engine.is_editor_hint() else null


func _bake() -> void:
	var p := _plugin()
	if p != null:
		p.bake_group(self, false)


func _rebake() -> void:
	var p := _plugin()
	if p != null:
		p.bake_group(self, true)
