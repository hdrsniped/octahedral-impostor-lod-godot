@tool
class_name OctaBakeSettings
extends Resource
## All options for baking impostors. Used by the editor's bake dialog and by
## OctaLOD.generate() / OctaBaker.bake() in code.

enum Compression {
	## Small file, exact pixels; decompressed to full size in video memory.
	LOSSLESS,
	## ~4x less video memory (Basis Universal, transcoded to the GPU's format on
	## load). Slightly blurrier. Editor-only: runtime bakes fall back to LOSSLESS.
	VRAM,
}

enum Preset { CUSTOM, MOBILE, BALANCED, HIGH_QUALITY, COMPLEX_SHAPES }

const PRESET_NAMES := ["Custom", "Mobile", "Balanced", "High quality", "Complex shapes"]
const COST := [1.0, 3.0, 5.0, 10.0]

@export_group("Placement")
## How the card is added next to each baked object.
@export var mode := OctaLOD.Mode.DYNAMIC_LOD
## Replace mode only. Deletes the real object after it is baked. Undo brings it back.
@export var strip_source := false
## Distance = the card replaces the real mesh beyond a fixed distance. Screen size =
## beyond the distance where the object covers less than the percentage below of the screen height.
@export var lod_mode := OctaLOD.LodMode.DISTANCE
## Dynamic LOD only: distance in meters beyond which the card replaces the real mesh.
@export_range(1.0, 1000.0, 0.5, "or_greater", "suffix:m") var lod_distance := 40.0
## Screen size mode: the card takes over when the object covers less than this share of the screen
## height. Converted to a distance for each object with the camera field of view (project setting
## octa_lod/reference_fov, default 75 degrees).
@export_range(0.1, 100.0, 0.1, "suffix:%") var lod_screen_percent := 5.0
## Crossfade dithers the real mesh into the card over the fade distance instead of popping.
## Forward+ only; Mobile and Compatibility pop (Godot does not fade there). Not used by Replace mode.
@export var fade := OctaLOD.Fade.NONE
## Crossfade only: how many meters the transition takes after the LOD distance.
@export_range(0.0, 100.0, 0.5, "or_greater", "suffix:m") var fade_margin := 5.0
## Cards write their real surface depth (needed where cards touch other geometry or each
## other). Off = flat card depth, cheaper on mobile; cards can intersect their surroundings.
@export var write_depth := true
## Shader quality. Low = 1 view (fastest), Medium = 3 blended views, High = 3 views + depth parallax,
## Ultra = ray search + layer rejection (clean on see-through and interlocking shapes, slowest).
@export var quality := OctaAtlas.Quality.HIGH

@export_group("Complex shapes")
## Bake every mesh inside the selected object as its own impostor. Fixes most
## see-through and interlocking shapes (rings, frames, gyroscopes).
@export var split_parts := false
## Experimental. Also store where each surface ends, so Ultra can see through
## gaps behind thin parts. +25% video memory, +50% bake time. Not for foliage.
@export var back_layer := false
## Ultra only: search samples along each view ray. More = fewer missed thin parts, slower.
@export_range(2, 32) var search_steps := 8
## Ultra only: hides views that disagree about which surface is in front.
## 0 = off. Higher = keeps more views (smoother, but more ghosting).
@export_range(0.0, 1.0, 0.01) var layer_tolerance := 0.15

@export_group("Scene and joining")
## Bake Scene pre-ticks objects that cover less than this share of the screen height at the LOD distance.
@export_range(1.0, 100.0, 0.5, "suffix:%") var scene_pick_percent := 10.0
## Joined impostors are grouped in squares this size (meters), so off-screen groups can be skipped.
@export_range(5.0, 500.0, 0.5, "or_greater", "suffix:m") var join_cell := 50.0

@export_group("Atlas")
## Objects that share the same meshes and materials are baked once and share one atlas entry.
@export var dedupe := true
## Views per side for each object (grid_size² views). More views = smoother
## rotation but fewer pixels per view.
@export_range(2, 32) var grid_size := 12
## Capture only views from above and the side (rocks, trees, buildings): twice
## the detail. Turn off for objects you also see from below (ships, floating things).
@export var hemisphere := true
## Atlas width/height in pixels. Bigger = sharper cards and more video memory.
@export_enum("256:256", "512:512", "1024:1024", "2048:2048", "4096:4096", "8192:8192") var max_atlas_size := 2048
## Also capture roughness, metallic and ambient occlusion per pixel from the source
## materials (one more atlas texture). Off = one roughness/metallic value per object.
@export var material_maps := true
## Also capture glowing parts (emission) when any baked object emits light. The extra
## texture is only made when something actually emits.
@export var emission := true
## How the saved atlas textures are stored.
@export var compression := Compression.LOSSLESS
## Folder where the editor saves baked atlases.
@export_dir var output_dir := "res://octa_impostors"

@export_group("Advanced")
## Pixels per view. 0 = automatic (largest that fits in max_atlas_size).
@export_range(0, 1024) var frame_resolution := 0
## Anti-aliasing of the captured views.
@export var msaa := Viewport.MSAA_4X
## Empty border around every view, in pixels (prevents bleeding between views).
@export_range(0, 16) var padding_px := 2
## How many views render at once while baking. Lower it if baking stalls your PC.
@export_range(1, 256) var batch_size := 64


## Atlas grid for `count` objects: {cols, rows, frame (px per view), side (px)}.
# --- Atlas layout ---
func layout(count: int) -> Dictionary:
	var cols := ceili(sqrt(maxi(count, 1)))
	var rows := ceili(float(maxi(count, 1)) / cols)
	var frame := frame_resolution
	if frame <= 0:
		frame = max_atlas_size / (maxi(cols, rows) * grid_size)
	frame = maxi(frame, 8)
	return {cols = cols, rows = rows, frame = frame, side = maxi(cols, rows) * grid_size * frame}


# --- Presets and estimates ---
func apply_preset(p: Preset) -> void:
	var v := {
			Preset.MOBILE: [OctaAtlas.Quality.LOW, 1024, Compression.VRAM, 10, false, false, 8, false, OctaLOD.Fade.NONE],
		Preset.BALANCED: [OctaAtlas.Quality.MEDIUM, 2048, Compression.VRAM, 12, false, false, 8, true, OctaLOD.Fade.NONE],
		Preset.HIGH_QUALITY: [OctaAtlas.Quality.HIGH, 4096, Compression.LOSSLESS, 16, false, false, 8, true, OctaLOD.Fade.CROSSFADE],
		Preset.COMPLEX_SHAPES: [OctaAtlas.Quality.ULTRA, 2048, Compression.LOSSLESS, 12, true, true, 12, true, OctaLOD.Fade.NONE],
	}.get(p, [])
	if v.is_empty():
		return
	quality = v[0]
	max_atlas_size = v[1]
	compression = v[2]
	grid_size = v[3]
	split_parts = v[4]
	back_layer = v[5]
	search_steps = v[6]
	write_depth = v[7]
	fade = v[8]


func cost_text() -> String:
	var extra := ""
	if material_maps or emission:
		extra = " Material maps add 1 texture read per view%s." % (" (emission: one more when something glows)" if emission else "")
	return "Shader cost per pixel: about %dx the Low quality (%s).%s" % [int(COST[quality]), OctaAtlas.Quality.keys()[quality].capitalize(), extra]


## One-line estimate shown in the bake dialog.
func describe(count: int) -> String:
	var l := layout(count)
	var bytes := float(l.side * l.side) * (1.0 if compression == Compression.VRAM else 4.0) * 4.0 / 3.0 * (2.0 + (0.25 if back_layer else 0.0) + (1.0 if material_maps else 0.0))
	return "%d object(s) -> %dx%d atlas, %d px per view, ~%.0f MB of video memory%s" % [count, l.cols * grid_size * l.frame, l.rows * grid_size * l.frame, l.frame, bytes / 1048576.0, " (+1 texture if something glows)" if emission else ""]
