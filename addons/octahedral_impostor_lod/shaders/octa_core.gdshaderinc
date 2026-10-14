// --- Octahedral impostor runtime shader ---
render_mode cull_disabled, depth_draw_opaque;

#ifndef QUALITY
#define QUALITY 1
#endif
#define MAX_OBJECTS 256
#if QUALITY == 0
#define NUM_FRAMES 1
#else
#define NUM_FRAMES 3
#endif
#if QUALITY >= 2
#define PARALLAX_STEPS 3
#else
#define PARALLAX_STEPS 1
#endif

// --- Uniforms ---
group_uniforms atlas;
uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_atlas : filter_linear_mipmap, repeat_disable;
uniform int grid_size = 12;
uniform ivec2 tiles = ivec2(1, 1);
uniform bool hemisphere = true;
uniform float frame_scale = 1.0;
uniform vec4 obj_bounds[MAX_OBJECTS];
uniform vec4 obj_surface[MAX_OBJECTS];

group_uniforms look;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform float normal_strength : hint_range(0.0, 1.0) = 1.0;
uniform float depth_scale : hint_range(0.0, 2.0) = 1.0;
uniform float quad_offset : hint_range(0.0, 1.0) = 1.0;
uniform float shadow_bias : hint_range(0.0, 0.5) = 0.04;
group_uniforms;

instance uniform int octa_index = 0;

varying vec3 v_ray;
varying vec3 v_pos;
varying flat vec3 v_w;
varying flat vec4 v_f01;
varying flat vec2 v_f2;
varying flat vec4 v_bounds;
varying flat vec4 v_surf;
varying flat vec2 v_tile;
varying flat mat3 v_nmat;

// --- View direction math ---
vec2 sign_nz(vec2 v) {
	return vec2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0);
}

vec2 oct_encode(vec3 n) {
	n /= (abs(n.x) + abs(n.y) + abs(n.z));
	vec2 p = n.xz;
	if (n.y < 0.0) {
		p = (1.0 - abs(p.yx)) * sign_nz(p);
	}
	return p;
}

vec3 oct_decode(vec2 p) {
	vec3 n = vec3(p.x, 1.0 - abs(p.x) - abs(p.y), p.y);
	if (n.y < 0.0) {
		n.xz = (1.0 - abs(n.zx)) * sign_nz(n.xz);
	}
	return normalize(n);
}

vec2 hemi_encode(vec3 n) {
	n.y = max(n.y, 0.0);
	n /= (abs(n.x) + abs(n.y) + abs(n.z));
	return vec2(n.x + n.z, n.x - n.z);
}

vec3 hemi_decode(vec2 p) {
	float x = (p.x + p.y) * 0.5;
	float z = (p.x - p.y) * 0.5;
	return normalize(vec3(x, 1.0 - abs(x) - abs(z), z));
}

vec3 frame_dir(vec2 frame) {
	float last = max(float(grid_size) - 1.0, 1.0);
	vec2 p = frame / last * 2.0 - 1.0;
	return hemisphere ? hemi_decode(p) : oct_decode(p);
}

void frame_basis(vec3 d, out vec3 x, out vec3 y) {
	vec3 up = abs(d.y) > 0.999 ? vec3(0.0, 0.0, -1.0) : vec3(0.0, 1.0, 0.0);
	x = normalize(cross(up, d));
	y = cross(d, x);
}

vec2 frame_uv(vec3 p, vec3 x, vec3 y) {
	return vec2(dot(p, x), -dot(p, y)) / frame_scale * 0.5 + 0.5;
}

vec2 atlas_uv(vec2 frame, vec2 uv) {
	return (v_tile + (frame + clamp(uv, 0.0, 1.0)) / float(grid_size)) / vec2(tiles);
}

// --- Vertex: face the camera, pick the 3 nearest views ---
void vertex() {
	int idx = clamp(octa_index, 0, MAX_OBJECTS - 1);
	vec4 b = obj_bounds[idx];
	float r = max(b.w, 1e-5);
	mat4 inv_model = inverse(MODEL_MATRIX);
	v_nmat = transpose(mat3(inv_model));
	bool ortho = PROJECTION_MATRIX[3][3] != 0.0;

	vec3 cam_l = ((inv_model * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz - b.xyz) / r;
	vec3 view_dir = ortho ? normalize(mat3(inv_model) * INV_VIEW_MATRIX[2].xyz) : normalize(cam_l);
	vec3 bx;
	vec3 by;
	frame_basis(view_dir, bx, by);

	float off = quad_offset;
	float s = 1.0;
	if (!ortho) {
		float dist = length(cam_l);
		off = clamp(off, 0.0, max(dist - 0.02, 0.0));
		s = dist > 1.001 ? (dist - off) / sqrt(dist * dist - 1.0) : 8.0;
		s = min(s, 8.0);
	}
	vec3 pos_l = view_dir * off + (bx * VERTEX.x + by * VERTEX.y) * s;
	v_pos = pos_l;
	v_ray = ortho ? -view_dir : pos_l - cam_l;
	VERTEX = b.xyz + pos_l * r;
	NORMAL = view_dir;
	TANGENT = bx;
	BINORMAL = by;

	float n = float(grid_size);
	vec2 enc = hemisphere ? hemi_encode(view_dir) : oct_encode(view_dir);
	vec2 g = clamp((enc * 0.5 + 0.5) * (n - 1.0), vec2(0.0), vec2(n - 1.0));
#if QUALITY == 0
	vec2 f0 = round(g);
	v_f01 = vec4(f0, f0);
	v_f2 = f0;
	v_w = vec3(1.0, 0.0, 0.0);
#else
	vec2 base = min(floor(g), vec2(max(n - 2.0, 0.0)));
	vec2 fr = g - base;
	vec2 f1;
	if (fr.x >= fr.y) {
		f1 = base + vec2(1.0, 0.0);
		v_w = vec3(1.0 - fr.x, fr.x - fr.y, fr.y);
	} else {
		f1 = base + vec2(0.0, 1.0);
		v_w = vec3(1.0 - fr.y, fr.y - fr.x, fr.x);
	}
	vec2 f2 = base + vec2(1.0);
	if (v_w.y > v_w.x && v_w.y >= v_w.z) {
		vec2 t = base; base = f1; f1 = t;
		v_w = v_w.yxz;
	} else if (v_w.z > v_w.x && v_w.z > v_w.y) {
		vec2 t = base; base = f2; f2 = t;
		v_w = v_w.zyx;
	}
	v_f01 = vec4(base, f1);
	v_f2 = f2;
#endif
	v_bounds = vec4(b.xyz, r);
	v_surf = obj_surface[idx];
	v_tile = vec2(float(idx % tiles.x), float(idx / tiles.x));
}

// --- Fragment: blend views, parallax, per-pixel depth ---
float baked_height(vec4 nd) {
	return nd.a > 0.01 ? (1.0 - 2.0 * nd.b / nd.a) * depth_scale : 0.0;
}

void fragment() {
	vec3 rd = normalize(v_ray);
	vec3 ro = v_pos;
	vec2 fr[3] = vec2[3](v_f01.xy, v_f01.zw, v_f2);
	float wt[3] = float[3](v_w.x, v_w.y, v_w.z);
	if (IN_SHADOW_PASS) {
		wt = float[3](1.0, 0.0, 0.0);
	}

	vec3 fx[3];
	vec3 fy[3];
	vec3 fd[3];
	vec2 uv[3];
	float denom[3];
	float rod[3];
	for (int i = 0; i < NUM_FRAMES; i++) {
		fd[i] = frame_dir(fr[i]);
		frame_basis(fd[i], fx[i], fy[i]);
		denom[i] = min(dot(rd, fd[i]), -1e-4);
		rod[i] = dot(ro, fd[i]);
		uv[i] = frame_uv(ro - rd * (rod[i] / denom[i]), fx[i], fy[i]);
	}
	vec2 to_atlas = 1.0 / (float(grid_size) * vec2(tiles));
	vec2 gx = dFdx(uv[0]) * to_atlas;
	vec2 gy = dFdy(uv[0]) * to_atlas;

	vec4 nd[3];
	float coarse = 0.0;
	for (int i = 0; i < NUM_FRAMES; i++) {
		nd[i] = vec4(0.0);
		if (wt[i] > 0.0001) {
			nd[i] = textureGrad(normal_atlas, atlas_uv(fr[i], uv[i]), gx * 8.0, gy * 8.0);
			coarse += nd[i].a * wt[i];
		}
	}
	if (coarse < 0.001) {
		discard;
	}

	vec4 acc_a = vec4(0.0);
	vec3 acc_n = vec3(0.0);
	vec3 acc_p = vec3(0.0);
	float acc_cov = 0.0;
	for (int i = 0; i < NUM_FRAMES; i++) {
		if (wt[i] <= 0.0001) {
			continue;
		}
		vec2 u = uv[i];
		vec4 n4 = nd[i];
		for (int s = 0; s < PARALLAX_STEPS; s++) {
			u = frame_uv(ro + rd * ((baked_height(n4) - rod[i]) / denom[i]), fx[i], fy[i]);
			n4 = textureGrad(normal_atlas, atlas_uv(fr[i], u), gx, gy);
		}
		float w = wt[i] * float(all(greaterThanEqual(u, vec2(0.0))) && all(lessThanEqual(u, vec2(1.0))));
		float cov = n4.a * w;
		acc_cov += cov;
		acc_p += (ro + rd * ((baked_height(n4) - rod[i]) / denom[i])) * cov;
		if (!IN_SHADOW_PASS) {
			acc_a += textureGrad(albedo_atlas, atlas_uv(fr[i], u), gx, gy) * w;
			vec2 nxy = n4.a > 0.0 ? n4.xy / n4.a * 2.0 - 1.0 : vec2(0.0);
			acc_n += (fx[i] * nxy.x + fy[i] * nxy.y + fd[i] * sqrt(max(1.0 - dot(nxy, nxy), 0.0))) * cov;
		}
	}
	if (acc_cov < max(alpha_cut, 1e-4)) {
		discard;
	}
	ALBEDO = acc_a.rgb / max(acc_a.a, 1e-4) * tint.rgb;
	vec3 n_view = normalize(mat3(VIEW_MATRIX) * normalize(v_nmat * acc_n));
	NORMAL = normalize(mix(NORMAL, n_view, normal_strength));
	ROUGHNESS = v_surf.x;
	METALLIC = v_surf.y;
	SPECULAR = v_surf.z;
	vec3 p_l = acc_p / acc_cov;
	if (IN_SHADOW_PASS) {
		p_l += rd * shadow_bias;
	}
	vec3 p_obj = v_bounds.xyz + p_l * v_bounds.w;
	vec4 p_view = VIEW_MATRIX * (MODEL_MATRIX * vec4(p_obj, 1.0));
	vec4 clip = PROJECTION_MATRIX * p_view;
	DEPTH = clip.z / clip.w;
	LIGHT_VERTEX = p_view.xyz;
}
