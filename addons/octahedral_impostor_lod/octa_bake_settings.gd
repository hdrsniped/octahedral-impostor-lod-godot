@tool
class_name OctaBakeSettings
extends Resource

enum Compression { LOSSLESS, VRAM }

enum Preset { CUSTOM, MINIMAL, FAST, QUALITY, MAX }

const PRESET_NAMES := ["Custom", "Minimal", "Fast", "Quality", "Max"]
const PRESET_TIPS := [
	"Keeps the settings exactly as you edit them.",
	"The fastest this addon gets: Low quality, 8x8 views on a 1024 atlas, VRAM compression, no material maps, flat depth (the card does not cast or self-shadow), 1 shadow view.",
	"For many props at once: High quality, 10x10 views on a 2048 atlas, VRAM compression, half-res material maps, 1 shadow view.",
	"The best quality without trading much performance: High quality, 16x16 views on a 4096 atlas, lossless, full-res material maps, 2 shadow views.",
	"Maximum quality at any cost: every side of the object (full sphere), Ultra with precise search, 32 search steps, split parts, back layer, 32x32 views on a 4096 atlas, lossless, full-res material maps, 3 shadow views, 8x MSAA capture.",
]
const COST := [1.0, 3.0, 5.0, 10.0]
const AVERAGED_NOTE := "Material maps are off: roughness and metallic are averaged over each object's materials"
const SHORT_HINTS := {
	"mode": "How the card is placed: Dynamic LOD, Duplicate or Replace.",
	"strip_source": "Replace mode: delete the real object after baking.",
	"lod_mode": "When the card takes over: distance or screen size.",
	"lod_distance": "Distance in meters where the card replaces the mesh.",
	"lod_screen_percent": "Screen height where the card takes over.",
	"fade": "Dither the card in instead of popping.",
	"fade_margin": "Width of the crossfade band around the distance.",
	"fade_real_mesh": "Also fade the real mesh out.",
	"quality": "Shader cost and accuracy: Low, Medium, High, Ultra.",
	"write_depth": "Card writes depth (needed for its shadow).",
	"split_parts": "Bake each mesh part separately (odd shapes).",
	"back_layer": "Extra depth map for see-through shapes.",
	"search_steps": "Ultra only: ray steps per view.",
	"precise_search": "Ultra only: smarter search, 2-3x slower.",
	"layer_tolerance": "Ultra only: how thick a surface counts as solid.",
	"view_visibility": "Weight views by how much of the object they show.",
	"coverage_pyramid": "Bake a coarse coverage map for the pyramid search.",
	"parallax_refine": "Low/Medium: 3 depth samples instead of 1.",
	"dedupe": "Skip objects that already have a card.",
	"scene_pick_percent": "Bake Scene: only objects smaller than this.",
	"join_cell": "Join: one MultiMesh per cell of this size.",
	"join_adaptive": "Join: split crowded cells into small regions.",
	"join_region_size": "Adaptive join: maximum region size.",
	"join_region_count": "Adaptive join: maximum instances per region.",
	"grid_size": "Views per side. More views, less detail per view.",
	"max_atlas_size": "Atlas texture size in pixels.",
	"output_dir": "Where baked atlases are saved.",
	"full_sphere": "Also views from below (twice the views, half the pixels each).",
	"material_maps": "Bake roughness, metallic and AO.",
	"emission": "Bake emission where something glows.",
	"half_res_material_maps": "Material maps at half resolution (less memory).",
	"compression": "VRAM compression (smaller, lossy) or lossless.",
	"shadow_views": "Views blended in the shadow pass (1-3).",
	"wind_strength": "Sway amount for foliage cards.",
	"frame_resolution": "View size in pixels; 0 picks it from the atlas.",
	"msaa": "Capture antialiasing.",
	"padding_px": "Empty border around each view.",
	"batch_size": "Views rendered per pass (memory).",
}

var _scan_sig := 0
var _scan_has_map := false
var _scan_mixed := false

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
## Crossfade dithers the card in over the real mesh instead of popping. Works on every renderer
## (Godot's own fade on Forward+, a screen-space dither in the card shader on Mobile and
## Compatibility). Not used by Replace mode.
@export var fade := OctaLOD.Fade.NONE
## Crossfade only: the transition runs from the LOD distance minus this margin to the LOD distance
## plus this margin.
@export_range(0.0, 100.0, 0.5, "or_greater", "suffix:m") var fade_margin := 5.0
## Crossfade on Mobile and Compatibility only: also dither the real mesh out over the same band, using
## material copies (your own materials stay untouched). Materials that cannot fade (shaders, own
## distance fade) keep the overlap: the card fades in, then the real mesh switches off behind it.
@export var fade_real_mesh := true

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
## Low/Medium/High only: fades out views that disagree about the depth of a pixel (thin-part ghosting). Off = the shipped shaders.
@export var view_visibility := false
## Ultra only: bakes a max-coverage map and uses it to skip empty space in the ray search (conservative, so thin parts are not stepped over). Off = the shipped Ultra search.
@export var coverage_pyramid := false
## Low and Medium only (High already uses 3 samples): give them the 3-sample parallax loop.
## follows the baked depth, which fixes most of the skew at the silhouette. Up to 48% fewer
## wrong pixels at Medium (+3% GPU at Low, +9% at Medium). Off = the shipped shaders.
@export var parallax_refine := false

@export_group("Scene and joining")
## Objects that share the same meshes and materials are baked once and share one atlas entry.
@export var dedupe := true
## Bake Scene pre-ticks objects that cover less than this share of the screen height at the LOD distance.
@export_range(1.0, 100.0, 0.5, "suffix:%") var scene_pick_percent := 10.0
## Joined impostors are grouped in squares this size (meters), so off-screen groups can be skipped.
@export_range(5.0, 500.0, 0.5, "or_greater", "suffix:m") var join_cell := 50.0
## Split each Join Cell into smaller regions (a median split until a region is within the size and count limits) and order the instances of every group along a Z-order curve. Each joined group gets a small bounding box, so off-screen regions are skipped as a whole. Off = one group per cell in the order of the cards.
@export var join_adaptive := false
## Adaptive join: a region is split until its instances span at most this size on every axis (meters, measured between the card centers).
@export_range(2.0, 200.0, 0.5, "or_greater", "suffix:m") var join_region_size := 20.0
## Adaptive join: a region is split until it holds at most this many instances.
@export_range(4, 4096, 1, "or_greater") var join_region_count := 128

@export_group("Atlas")
## Views per side for each object (grid_size² views). More views = smoother
## rotation but fewer pixels per view.
@export_range(2, 32) var grid_size := 12
## Also capture views from below (twice the views, so each view gets half the
## pixels at the same atlas size). Only needed for objects you can look up at, such as
## ships and floating things. Off = top and side views only, twice the detail.
@export var full_sphere := false
## Atlas width/height in pixels. Bigger = sharper cards and more video memory.
## 4096 is the largest that bakes reliably; 8192 atlases crash the capture.
@export_enum("256:256", "512:512", "1024:1024", "2048:2048", "2896:2896", "4096:4096") var max_atlas_size := 2048:
	set(v):
		max_atlas_size = mini(v, 4096)
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

@export_group("Wind")
## Far-field wind sway given to every new card (0 = off, the default; 1 = the top leans downwind by 20% of the object's radius). For foliage only: the base stays fixed and the top moves, done in texture space with no bigger bounds. Atlases without wind keep the normal shader. Set direction and speed with OctaWind.set_wind(). Adds about 4-10% to the card shader time while it is on (measured on an iGPU, noisy).
@export_range(0.0, 1.0, 0.01) var wind_strength := 0.0

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
	while frame * maxi(grid_size, 1) % OctaAtlas.COVERAGE_BLOCK != 0:
		frame += 1
	return {cols = cols, rows = rows, frame = frame, side = maxi(cols, rows) * grid_size * frame}


# --- Presets and estimates ---
static func preset_values(p: Preset) -> Dictionary:
	var v := {
		Preset.MINIMAL: {quality = OctaAtlas.Quality.LOW, grid_size = 8, max_atlas_size = 1024, compression = Compression.VRAM,
				write_depth = false, material_maps = false, emission = false, search_steps = 2},
		Preset.FAST: {quality = OctaAtlas.Quality.HIGH, grid_size = 10, max_atlas_size = 2048, compression = Compression.VRAM},
		Preset.QUALITY: {quality = OctaAtlas.Quality.HIGH, grid_size = 16, max_atlas_size = 4096, compression = Compression.LOSSLESS,
				half_res_material_maps = false, shadow_views = 2},
		Preset.MAX: {quality = OctaAtlas.Quality.ULTRA, grid_size = 32, max_atlas_size = 4096, compression = Compression.LOSSLESS,
				split_parts = true, back_layer = true, precise_search = true, search_steps = 32, full_sphere = true,
				half_res_material_maps = false, shadow_views = 3, msaa = Viewport.MSAA_8X},
	}.get(p, {})
	if v.is_empty():
		return v
	v.merge({split_parts = false, back_layer = false, search_steps = 8, precise_search = false, write_depth = true,
			material_maps = true, emission = true, half_res_material_maps = true, shadow_views = 1,
			parallax_refine = false, coverage_pyramid = false, view_visibility = false, fade = OctaLOD.Fade.CROSSFADE})
	return v


func apply_preset(p: Preset) -> void:
	var v := preset_values(p)
	for k: String in v:
		set(k, v[k])


func cost_text(sources: Array = []) -> String:
	var extra := ""
	if material_maps or emission:
		extra = " Material maps add 1 texture read per view%s%s." % [" (none when every material is constant)" if material_maps else "", " (emission: one more when something glows)" if emission else ""]
	if precise_search and quality == OctaAtlas.Quality.ULTRA:
		extra += " Precise search: about 2-3x slower on the GPU."
	if parallax_refine and quality < OctaAtlas.Quality.HIGH:
		extra += " Parallax refine: 3 depth samples per view instead of 1, up to +9% GPU."
	if shadow_views > 1:
		extra += " %d shadow views: smoother shadows when the light moves, a slower shadow pass." % shadow_views
	if averages_materials(sources):
		extra += " " + AVERAGED_NOTE + "."
	return "Shader cost per pixel: about %dx the Low quality (%s).%s" % [int(COST[quality]), OctaAtlas.Quality.keys()[quality].capitalize(), extra]


func averages_materials(sources: Array) -> bool:
	_scan(sources)
	return not material_maps and not sources.is_empty() and _scan_mixed


func needs_material_map(sources: Array) -> bool:
	_scan(sources)
	return _scan_has_map


func _scan(sources: Array) -> void:
	var sig := hash(split_parts)
	for n in sources:
		sig += int(n.get_instance_id())
	if sig == _scan_sig:
		return
	_scan_sig = sig
	_scan_has_map = OctaBaker.needs_material_map(sources, split_parts)
	_scan_mixed = OctaBaker.has_mixed_constants(sources, split_parts)


func describe(count: int, sources: Array = [], with_warnings := true) -> String:
	var l := layout(count)
	var layer := float(l.side * l.side) * (1.0 if compression == Compression.VRAM else 4.0) * 4.0 / 3.0
	var map_scale := 0.25 if half_res_material_maps else 1.0
	var has_map := material_maps and (sources.is_empty() or needs_material_map(sources))
	var bytes := layer * (2.0 + (0.25 if back_layer else 0.0) + (map_scale if has_map else 0.0))
	var notes := ""
	if material_maps and not has_map:
		notes += " (constant materials: no material map)"
	if emission:
		notes += " (+%.0f MB if something glows)" % (layer * map_scale / 1048576.0)
	if precise_search and quality == OctaAtlas.Quality.ULTRA:
		notes += " (precise ray search)"
	if parallax_refine and quality < OctaAtlas.Quality.HIGH:
		notes += " (parallax refine)"
	if averages_materials(sources):
		notes += " (%s)" % AVERAGED_NOTE
	var warnings := PackedStringArray()
	if with_warnings and precise_search and quality < OctaAtlas.Quality.ULTRA:
		warnings.append("Precise search is ignored below Ultra.")
	if with_warnings and coverage_pyramid and precise_search:
		warnings.append("Coverage pyramid is baked but unused while precise search is on.")
	if with_warnings and parallax_refine and quality >= OctaAtlas.Quality.HIGH:
		warnings.append("Parallax refine only applies below High.")
	if with_warnings and not write_depth:
		warnings.append("Depth writing is off: the card does not cast or self-shadow.")
	if with_warnings and l.frame < 32:
		warnings.append("Atlas is crowded at %d px per view: raise max_atlas_size or bake fewer objects." % l.frame)
	var text := "%d object(s) -> %dx%d atlas, %d px per view, ~%.0f MB of video memory%s" % [count, l.cols * grid_size * l.frame, l.rows * grid_size * l.frame, l.frame, bytes / 1048576.0, notes]
	if not warnings.is_empty():
		text += " " + " ".join(warnings)
	return text
