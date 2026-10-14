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

@export_group("Placement")
## How the card is added next to each baked object.
@export var mode := OctaLOD.Mode.DYNAMIC_LOD
## Dynamic LOD only: distance in meters beyond which the card replaces the real mesh.
@export_range(1.0, 1000.0, 0.5, "or_greater", "suffix:m") var lod_distance := 40.0
## Shader quality. Low = 1 view (fastest), Medium = 3 blended views, High = 3 views + depth parallax.
@export var quality := OctaAtlas.Quality.HIGH

@export_group("Atlas")
## Views per side for each object (grid_size² views). More views = smoother
## rotation but fewer pixels per view.
@export_range(2, 32) var grid_size := 12
## Capture only views from above and the side (rocks, trees, buildings): twice
## the detail. Turn off for objects you also see from below (ships, floating things).
@export var hemisphere := true
## Atlas width/height in pixels. Bigger = sharper cards and more video memory.
@export_enum("256:256", "512:512", "1024:1024", "2048:2048", "4096:4096", "8192:8192") var max_atlas_size := 2048
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


## One-line estimate shown in the bake dialog.
func describe(count: int) -> String:
	var l := layout(count)
	var bytes := float(l.side * l.side) * (1.0 if compression == Compression.VRAM else 4.0) * 4.0 / 3.0 * 2.0
	return "%d object(s) -> %dx%d atlas, %d px per view, ~%.0f MB of video memory" % [count, l.cols * grid_size * l.frame, l.rows * grid_size * l.frame, l.frame, bytes / 1048576.0]
