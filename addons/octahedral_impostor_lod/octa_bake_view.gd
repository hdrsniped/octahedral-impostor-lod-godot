@tool
class_name OctaBakeView
extends Resource

var settings: OctaBakeSettings

@export_group("Placement")
@export var mode := OctaLOD.Mode.DYNAMIC_LOD:
	get:
		return settings.mode
	set(value):
		settings.mode = value

@export var strip_source := false:
	get:
		return settings.strip_source
	set(value):
		settings.strip_source = value

@export var lod_mode := OctaLOD.LodMode.DISTANCE:
	get:
		return settings.lod_mode
	set(value):
		settings.lod_mode = value

@export_range(1.0, 1000.0, 0.5, "or_greater", "suffix:m") var lod_distance := 40.0:
	get:
		return settings.lod_distance
	set(value):
		settings.lod_distance = value

@export_range(0.1, 100.0, 0.1, "suffix:%") var lod_screen_percent := 5.0:
	get:
		return settings.lod_screen_percent
	set(value):
		settings.lod_screen_percent = value

@export var fade := OctaLOD.Fade.NONE:
	get:
		return settings.fade
	set(value):
		settings.fade = value

@export_range(0.0, 100.0, 0.5, "or_greater", "suffix:m") var fade_margin := 5.0:
	get:
		return settings.fade_margin
	set(value):
		settings.fade_margin = value

@export_group("Bake")
@export var quality := OctaAtlas.Quality.HIGH:
	get:
		return settings.quality
	set(value):
		settings.quality = value

@export var write_depth := true:
	get:
		return settings.write_depth
	set(value):
		settings.write_depth = value

@export_range(2, 32) var grid_size := 12:
	get:
		return settings.grid_size
	set(value):
		settings.grid_size = value

@export_enum("256:256", "512:512", "1024:1024", "2048:2048", "2896:2896", "4096:4096", "8192:8192") var max_atlas_size := 2048:
	get:
		return settings.max_atlas_size
	set(value):
		settings.max_atlas_size = value

@export var compression := OctaBakeSettings.Compression.LOSSLESS:
	get:
		return settings.compression
	set(value):
		settings.compression = value

@export_range(1, 3) var shadow_views := 1:
	get:
		return settings.shadow_views
	set(value):
		settings.shadow_views = value

@export var split_parts := false:
	get:
		return settings.split_parts
	set(value):
		settings.split_parts = value

@export_dir var output_dir := "res://octa_impostors":
	get:
		return settings.output_dir
	set(value):
		settings.output_dir = value
