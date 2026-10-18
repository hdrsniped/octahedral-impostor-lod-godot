@tool
class_name OctaWind
extends RefCounted

const DEFAULT_SPEED := 4.0
const DEFAULT_GUST := 0.3
const DEFAULT_FREQUENCY := 0.05

static var direction := Vector2.RIGHT
static var speed := DEFAULT_SPEED
static var gust := DEFAULT_GUST
static var frequency := DEFAULT_FREQUENCY


# --- Global wind ---
static func set_wind(new_direction: Vector2, new_speed: float = DEFAULT_SPEED, new_gust: float = DEFAULT_GUST, new_frequency: float = DEFAULT_FREQUENCY) -> void:
	if new_direction.length_squared() > 1e-8:
		direction = new_direction.normalized()
	speed = maxf(new_speed, 0.0)
	gust = clampf(new_gust, 0.0, 1.0)
	frequency = clampf(new_frequency, 0.001, 1.0)
	for a in OctaAtlas.live_atlases():
		a.apply_wind()


static func apply_to(m: ShaderMaterial) -> void:
	m.set_shader_parameter("wind_dir", direction)
	m.set_shader_parameter("wind_speed", speed)
	m.set_shader_parameter("wind_gust", gust)
	m.set_shader_parameter("wind_frequency", frequency)


static func reset() -> void:
	direction = Vector2.RIGHT
	speed = DEFAULT_SPEED
	gust = DEFAULT_GUST
	frequency = DEFAULT_FREQUENCY
	for a in OctaAtlas.live_atlases():
		a.apply_wind()
