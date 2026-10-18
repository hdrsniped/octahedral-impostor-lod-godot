@tool
class_name OctaJoinedGroup
extends MultiMeshInstance3D

## The atlas this joined group draws from. The group tells it about its wind while it is in the scene tree.
@export var atlas: OctaAtlas:
	set(v):
		if atlas != null and atlas != v:
			atlas.set_wind_user(self, false)
		atlas = v
		_apply_wind()
## Far-field wind sway of the whole group (0 = still). Same effect as OctaImpostor.wind_strength. While it is above 0 and the
## group is in the tree, its atlas uses the wind shader variant; when no group or card is left it returns to the normal shader.
@export_range(0.0, 1.0, 0.01) var wind_strength := 0.0:
	set(v):
		wind_strength = maxf(v, 0.0)
		_apply_wind()

var _winded := false

static var _live := {}


static func live_groups() -> Array[OctaJoinedGroup]:
	var out: Array[OctaJoinedGroup] = []
	for id: int in _live.keys():
		var g: OctaJoinedGroup = _live[id].get_ref()
		if g == null:
			_live.erase(id)
		else:
			out.append(g)
	return out


# --- Wind registration ---
func _enter_tree() -> void:
	_live[get_instance_id()] = weakref(self)
	_apply_wind()


func _exit_tree() -> void:
	_live.erase(get_instance_id())
	if atlas != null:
		atlas.set_wind_user(self, false)


func _apply_wind() -> void:
	if wind_strength > 0.0 or _winded:
		set_instance_shader_parameter("card_wind", wind_strength)
		_winded = wind_strength > 0.0
	if atlas != null and is_inside_tree():
		atlas.set_wind_user(self, wind_strength > 0.0)
