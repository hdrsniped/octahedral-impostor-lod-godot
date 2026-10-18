uniform int octa_bake_mode = 0;
uniform float octa_bake_scale = 1.0;

#define OCTA_BAKE_OUTPUT(col, rough, metal, ao, emit) \
	if (octa_bake_mode == 1) { ALBEDO = clamp(vec3(ao, rough, metal), 0.0, 1.0); ALPHA = 1.0; } \
	else if (octa_bake_mode == 2) { ALBEDO = clamp(emit / max(octa_bake_scale, 1.0), 0.0, 1.0); ALPHA = 1.0; }
