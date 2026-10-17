@tool
@icon("res://addons/octahedral_impostor_lod/icon_impostor.svg")
class_name OctaImpostorGroup
extends Node3D

const PLUGIN_META := &"octa_lod_plugin"

## Bake settings of this group. Precedence, highest first: a card's own properties (lod distance,
## quality, tint, depth, LOD mode, screen size, fade, fade margin) set after baking, then these
## settings, then the bake dialog settings. Baking a group never uses the dialog settings, and a
## re-bake keeps the properties you changed on the cards.
@export var settings: OctaBakeSettings = OctaBakeSettings.new()
## Objects to bake, as paths relative to this node. Empty = every direct child that holds a mesh.
@export var targets: Array[NodePath] = []
## The atlas made by the last bake of this group (one atlas for all its objects).
@export var atlas: OctaAtlas

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
	return out


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
	for g in find_all(root):
		for t in g.target_nodes():
			if t == node or t.is_ancestor_of(node):
				return g
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
