shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;
#define BACK_PASS
#include "res://addons/octahedral_impostor_lod/shaders/capture_normal_depth.gdshaderinc"
