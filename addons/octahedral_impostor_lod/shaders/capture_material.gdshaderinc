// --- Bake pass: roughness, metallic, AO and emission ---
uniform int map_mode = 0;
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color = vec4(1.0);
uniform float alpha_cut = -1.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 rough_ch = vec4(1.0, 0.0, 0.0, 0.0);
uniform sampler2D metal_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metal_ch = vec4(1.0, 0.0, 0.0, 0.0);
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 ao_ch = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec3 emission_color = vec3(0.0);
uniform sampler2D emission_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float emission_mul = 1.0;
uniform bool emission_add = true;

varying vec2 v_uv;

void vertex() {
	v_uv = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	if (alpha_cut >= 0.0 && texture(albedo_tex, v_uv).a * albedo_color.a < alpha_cut) {
		discard;
	}
	if (map_mode == 0) {
		float ao = dot(texture(ao_tex, v_uv), ao_ch);
		float r = roughness * dot(texture(rough_tex, v_uv), rough_ch);
		float m = metallic * dot(texture(metal_tex, v_uv), metal_ch);
		ALBEDO = clamp(vec3(ao, r, m), 0.0, 1.0);
	} else {
		vec3 t = texture(emission_tex, v_uv).rgb;
		vec3 e = (emission_add ? emission_color + t : emission_color * t) * emission_mul;
		ALBEDO = clamp(e, 0.0, 1.0);
	}
}
