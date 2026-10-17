@tool
class_name OctaBakeSettings
extends Resource

enum Compression { LOSSLESS, VRAM }

enum Preset { CUSTOM, MOBILE, BALANCED, HIGH_QUALITY, COMPLEX_SHAPES }

const PRESET_NAMES := ["Custom", "Mobile", "Balanced", "High quality", "Complex shapes"]
const PRESET_TIPS := [
	"Keeps the settings exactly as you edit them.",
	"Low quality, 1024 atlas, VRAM compression, 10x10 views, flat depth (no depth write), half-res material maps, 1 shadow view. Smallest and cheapest.",
	"Medium quality, 2048 atlas, VRAM compression, 12x12 views, depth on, half-res material maps, 1 shadow view.",
	"High quality, 4096 atlas, lossless, 16x16 views, depth on, crossfade (Forward+), full-res material maps, 2 shadow views.",
	"Ultra with split parts, back layer and 12 search steps, 2048 atlas, lossless, depth on, half-res material maps, 1 shadow view. Precise search stays off (2-3x slower on the GPU): turn it on for hero objects.",
]
const COST := [1.0, 3.0, 5.0, 10.0]
const AVERAGED_NOTE := "Material maps are off: roughness and metallic are averaged over each object's materials"

@export_group("Placement")
## Dynamic LOD = real mesh up close, card beyond the LOD distance. Duplicate = card added next to
## the untouched object. Replace = card added and the object hidden.
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

@export_group("Quality")
## Shader quality. Low = 1 view (fastest), Medium = 3 blended views, High = 3 views + depth parallax,
## Ultra = ray search + layer rejection (clean on see-through and interlocking shapes, slowest).
@export var quality := OctaAtlas.Quality.HIGH
## Cards write their real surface depth (needed where cards touch other geometry or each
## other). Off = flat card depth, cheaper on mobile; cards can intersect their surroundings.
@export var write_depth := true

@export_group("Complex shapes")
## Bake every mesh inside the selected object as its own impostor. Fixes most
## see-through and interlocking shapes (rings, frames, gyroscopes).
@export var split_parts := false
## Experimental. Also store where each surface ends, so Ultra can see through
## gaps behind thin parts. +25% video memory, +50% bake time. Not for foliage.
@export var back_layer := false
## Ultra only: search samples along each view ray. More = fewer missed thin parts, slower.
@export_range(2, 32) var search_steps := 8
## Ultra only. Finds thin features (rings, wire, branches) much more reliably at the same step count. About 2-3x slower on the GPU, so use it for hero objects.
@export var precise_search := false
## Ultra only: hides views that disagree about which surface is in front.
## 0 = off. Higher = keeps more views (smoother, but more ghosting).
@export_range(0.0, 1.0, 0.01) var layer_tolerance := 0.15

@export_group("Scene and joining")
## Objects that share the same meshes and materials are baked once and share one atlas entry.
@export var dedupe := true
## Bake Scene pre-ticks objects that cover less than this share of the screen height at the LOD distance.
@export_range(1.0, 100.0, 0.5, "suffix:%") var scene_pick_percent := 10.0
## Joined impostors are grouped in squares this size (meters), so off-screen groups can be skipped.
@export_range(5.0, 500.0, 0.5, "or_greater", "suffix:m") var join_cell := 50.0

@export_group("Atlas")
## Views per side for each object (grid_size² views). More views = smoother
## rotation but fewer pixels per view.
@export_range(2, 32) var grid_size := 12
## Capture only views from above and the side (rocks, trees, buildings): twice
## the detail. Turn off for objects you also see from below (ships, floating things).
@export var hemisphere := true
## Atlas width/height in pixels. Bigger = sharper cards and more video memory.
@export_enum("256:256", "512:512", "1024:1024", "2048:2048", "4096:4096", "8192:8192") var max_atlas_size := 2048
## Also capture roughness, metallic and ambient occlusion per pixel from the source
## materials (one more atlas texture). Off = one roughness/metallic value per object, averaged
## over its materials (objects that mix shiny and rough materials lose that difference).
## The texture is skipped automatically when no material uses a roughness, metallic or
## occlusion texture (the constants are stored per object instead).
@export var material_maps := true
## Also capture glowing parts (emission) when any baked object emits light. The extra
## texture is only made when something actually emits.
@export var emission := true
## Store the material maps (roughness/metallic/occlusion and emission) at half resolution: a
## quarter of the video memory of those textures. Colour and normals stay full size.
@export var half_res_material_maps := true
## Lossless = exact pixels, decompressed to full size in video memory. VRAM = about 4x less video
## memory (Basis Universal, transcoded to the GPU's format on load), slightly blurrier. VRAM is
## editor-only: runtime bakes fall back to Lossless.
@export var compression := Compression.LOSSLESS
## Folder where the editor saves baked atlases.
@export_dir var output_dir := "res://octa_impostors"

@export_group("Shadows")
## Views blended in the shadow pass. 1 is fastest; 3 avoids shadow popping when the light moves (day/night cycles).
@export_range(1, 3) var shadow_views := 1

@export_group("Advanced")
## Pixels per view. 0 = automatic (largest that fits in max_atlas_size).
@export_range(0, 1024) var frame_resolution := 0
## Anti-aliasing of the captured views.
@export var msaa := Viewport.MSAA_4X
## Empty border around every view, in pixels (prevents bleeding between views).
@export_range(0, 16) var padding_px := 2
## How many views render at once while baking. Lower it if baking stalls your PC.
@export_range(1, 256) var batch_size := 64


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
	var base := {split_parts = false, back_layer = false, search_steps = 8, precise_search = false, write_depth = true, fade = OctaLOD.Fade.NONE,
			half_res_material_maps = true, shadow_views = 1}
	var v := {
		Preset.MOBILE: {quality = OctaAtlas.Quality.LOW, max_atlas_size = 1024, compression = Compression.VRAM, grid_size = 10, write_depth = false},
		Preset.BALANCED: {quality = OctaAtlas.Quality.MEDIUM, max_atlas_size = 2048, compression = Compression.VRAM, grid_size = 12},
		Preset.HIGH_QUALITY: {quality = OctaAtlas.Quality.HIGH, max_atlas_size = 4096, compression = Compression.LOSSLESS, grid_size = 16,
				fade = OctaLOD.Fade.CROSSFADE, half_res_material_maps = false, shadow_views = 2},
		Preset.COMPLEX_SHAPES: {quality = OctaAtlas.Quality.ULTRA, max_atlas_size = 2048, compression = Compression.LOSSLESS, grid_size = 12,
				split_parts = true, back_layer = true, search_steps = 12},
	}.get(p, {})
	if v.is_empty():
		return
	v.merge(base)
	for k: String in v:
		set(k, v[k])


func cost_text(sources: Array = []) -> String:
	var extra := ""
	if material_maps or emission:
		extra = " Material maps add 1 texture read per view%s%s." % [" (none when every material is constant)" if material_maps else "", " (emission: one more when something glows)" if emission else ""]
	if precise_search and quality == OctaAtlas.Quality.ULTRA:
		extra += " Precise search: about 2-3x slower on the GPU."
	if shadow_views > 1:
		extra += " %d shadow views: smoother shadows when the light moves, a slower shadow pass." % shadow_views
	if averages_materials(sources):
		extra += " " + AVERAGED_NOTE + "."
	return "Shader cost per pixel: about %dx the Low quality (%s).%s" % [int(COST[quality]), OctaAtlas.Quality.keys()[quality].capitalize(), extra]


func averages_materials(sources: Array) -> bool:
	return not material_maps and not sources.is_empty() and OctaBaker.has_mixed_constants(sources, split_parts)


func describe(count: int, sources: Array = []) -> String:
	var l := layout(count)
	var layer := float(l.side * l.side) * (1.0 if compression == Compression.VRAM else 4.0) * 4.0 / 3.0
	var map_scale := 0.25 if half_res_material_maps else 1.0
	var has_map := material_maps and (sources.is_empty() or OctaBaker.needs_material_map(sources, split_parts))
	var bytes := layer * (2.0 + (0.25 if back_layer else 0.0) + (map_scale if has_map else 0.0))
	var notes := ""
	if material_maps and not has_map:
		notes += " (constant materials: no material map)"
	if emission:
		notes += " (+%.0f MB if something glows)" % (layer * map_scale / 1048576.0)
	if precise_search and quality == OctaAtlas.Quality.ULTRA:
		notes += " (precise ray search)"
	if averages_materials(sources):
		notes += " (%s)" % AVERAGED_NOTE
	return "%d object(s) -> %dx%d atlas, %d px per view, ~%.0f MB of video memory%s" % [count, l.cols * grid_size * l.frame, l.rows * grid_size * l.frame, l.frame, bytes / 1048576.0, notes]
