// --- Bake pass: normal and depth ---
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color = vec4(1.0);
uniform float alpha_cut = -1.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform float cam_dist = 3.0;
uniform float radius = 1.0;

varying vec2 v_uv;

void vertex() {
	v_uv = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	if (alpha_cut >= 0.0 && texture(albedo_tex, v_uv).a * albedo_color.a < alpha_cut) {
		discard;
	}
	vec3 n = normalize(NORMAL);
	float depth = clamp((-VERTEX.z - (cam_dist - radius)) / (2.0 * radius), 0.0, 1.0);
	ALBEDO = vec3(n.xy * 0.5 + 0.5, depth);
}
