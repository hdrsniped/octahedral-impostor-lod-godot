// --- Octahedral impostor runtime shader ---
render_mode cull_disabled, depth_draw_opaque;

#ifndef QUALITY
#define QUALITY 1
#endif
#if QUALITY == 0
#define NUM_FRAMES 1
#else
#define NUM_FRAMES 3
#endif
#ifndef DEBUG_MODE
#define DEBUG_MODE 0
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
uniform sampler2D obj_data : filter_nearest, repeat_disable;
uniform sampler2D orm_atlas : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D emission_atlas : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform bool use_orm = false;
uniform bool use_emission = false;
uniform int grid_size = 12;
uniform bool hemisphere = true;
uniform float frame_scale = 1.0;
#if QUALITY == 3
uniform sampler2D back_atlas : filter_linear_mipmap, repeat_disable;
uniform bool use_back_layer = false;
#endif

group_uniforms look;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform float normal_strength : hint_range(0.0, 1.0) = 1.0;
uniform float depth_scale : hint_range(0.0, 2.0) = 1.0;
uniform float quad_offset : hint_range(0.0, 1.0) = 1.0;
uniform float shadow_bias : hint_range(0.0, 0.5) = 0.04;
#if QUALITY == 3
group_uniforms complex_shapes;
uniform int search_steps : hint_range(2, 32) = 8;
uniform int refine_steps : hint_range(0, 8) = 3;
uniform float layer_tolerance : hint_range(0.0, 1.0) = 0.15;
uniform float min_thickness : hint_range(0.0, 1.0) = 0.1;
#endif
group_uniforms;

instance uniform int octa_index = 0;
instance uniform vec4 card_tint : source_color = vec4(1.0);
instance uniform float card_depth = 1.0;

varying vec3 v_ray;
varying vec3 v_pos;
varying flat vec3 v_w;
varying flat vec4 v_f01;
varying flat vec2 v_f2;
varying flat vec4 v_bounds;
varying flat vec4 v_surf;
varying flat vec4 v_rect;
varying flat vec4 v_mat;
varying flat mat3 v_nmat;
varying flat vec3 v_tint;
varying flat float v_depth;

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
	return v_rect.xy + (frame + clamp(uv, 0.0, 1.0)) / float(grid_size) * v_rect.zw;
}

// --- Vertex: face the camera, pick the 3 nearest views ---
void vertex() {
	int idx = max(octa_index, 0);
	vec4 b = texelFetch(obj_data, ivec2(0, idx), 0);
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
	v_surf = texelFetch(obj_data, ivec2(1, idx), 0);
	v_rect = texelFetch(obj_data, ivec2(2, idx), 0);
	v_mat = texelFetch(obj_data, ivec2(3, idx), 0);
	bool joined = INSTANCE_CUSTOM.a > 0.0;
	v_tint = tint.rgb * (joined ? INSTANCE_CUSTOM.rgb : card_tint.rgb);
	v_depth = depth_scale * (joined ? INSTANCE_CUSTOM.a : card_depth);
}

// --- Fragment helpers ---
float baked_height(vec4 nd) {
	return nd.a > 0.01 ? (1.0 - 2.0 * nd.b / nd.a) * v_depth : 0.0;
}

#if QUALITY == 3
bool in_frame(vec2 u) {
	return all(greaterThanEqual(u, vec2(0.0))) && all(lessThanEqual(u, vec2(1.0)));
}

bool is_inside(vec3 p, vec3 d, vec2 u, vec4 nd, float back, bool front_only) {
	if (!in_frame(u) || nd.a < 0.5) {
		return false;
	}
	float hf = (1.0 - 2.0 * nd.b / nd.a) * v_depth;
	float hb = -2.0;
	if (use_back_layer && !front_only) {
		hb = min((1.0 - 2.0 * back / nd.a) * v_depth, hf - min_thickness);
	}
	float ph = dot(p, d);
	return ph <= hf && ph >= hb;
}

bool crossed_slab(vec3 p, vec3 p_prev, vec3 d, vec2 u, vec4 nd, float back) {
	if (!use_back_layer || !in_frame(u) || nd.a < 0.5) {
		return false;
	}
	float hf = (1.0 - 2.0 * nd.b / nd.a) * v_depth;
	float hb = min((1.0 - 2.0 * back / nd.a) * v_depth, hf - min_thickness);
	return dot(p_prev, d) > hf && dot(p, d) < hb;
}
#endif

// --- Fragment: blend views, parallax, per-pixel depth ---
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
	vec2 to_atlas = v_rect.zw / float(grid_size);
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
	vec4 acc_o = vec4(0.0);
	vec4 acc_e = vec4(0.0);
	vec3 acc_n = vec3(0.0);
	vec3 acc_p = vec3(0.0);
	float acc_cov = 0.0;
#if QUALITY == 3
	float bq = dot(ro, rd);
	float disc = bq * bq - dot(ro, ro) + 1.0;
	if (disc <= 0.0) {
		discard;
	}
	float t_in = -bq - sqrt(disc);
	float t_out = -bq + sqrt(disc);
	float dt = (t_out - t_in) / float(max(search_steps, 1));
	float th[3] = float[3](0.0, 0.0, 0.0);
	float hit[3] = float[3](0.0, 0.0, 0.0);
	vec4 nh[3];
	vec2 uh[3];
	float t_ref = -1e9;
	for (int i = 0; i < NUM_FRAMES; i++) {
		nh[i] = vec4(0.0);
		uh[i] = vec2(0.0);
		if (wt[i] <= 0.0001) {
			continue;
		}
		float lo = t_in;
		float hi = t_in;
		bool front_only = false;
		for (int s = 0; s <= search_steps; s++) {
			float t = t_in + dt * float(s);
			vec3 p = ro + rd * t;
			vec2 u = frame_uv(p, fx[i], fy[i]);
			vec2 a = atlas_uv(fr[i], u);
			vec4 n4 = textureGrad(normal_atlas, a, gx, gy);
			float bk = use_back_layer ? textureGrad(back_atlas, a, gx, gy).r : 0.0;
			bool crossed = s > 0 && crossed_slab(p, p - rd * dt, fd[i], u, n4, bk);
			if (crossed || is_inside(p, fd[i], u, n4, bk, false)) {
				front_only = crossed;
				hit[i] = 1.0;
				hi = t;
				nh[i] = n4;
				uh[i] = u;
				break;
			}
			lo = t;
		}
		if (hit[i] < 0.5) {
			continue;
		}
		for (int r = 0; r < refine_steps; r++) {
			float t = (lo + hi) * 0.5;
			vec3 p = ro + rd * t;
			vec2 u = frame_uv(p, fx[i], fy[i]);
			vec2 a = atlas_uv(fr[i], u);
			vec4 n4 = textureGrad(normal_atlas, a, gx, gy);
			float bk = use_back_layer ? textureGrad(back_atlas, a, gx, gy).r : 0.0;
			if (is_inside(p, fd[i], u, n4, bk, front_only)) {
				hi = t;
				nh[i] = n4;
				uh[i] = u;
			} else {
				lo = t;
			}
		}
		th[i] = hi;
		t_ref = max(t_ref, hi);
	}
	float wsum = 0.0;
	for (int i = 0; i < NUM_FRAMES; i++) {
		if (wt[i] <= 0.0001) {
			continue;
		}
		float w = wt[i];
		if (hit[i] > 0.5 && layer_tolerance > 0.0) {
			w *= 1.0 - smoothstep(layer_tolerance * 0.5, layer_tolerance, t_ref - th[i]);
		}
		wsum += w;
		if (hit[i] < 0.5 || w <= 0.0001) {
			continue;
		}
		float cov = nh[i].a * w;
		acc_cov += cov;
		acc_p += (ro + rd * th[i]) * cov;
		if (!IN_SHADOW_PASS) {
			acc_a += textureGrad(albedo_atlas, atlas_uv(fr[i], uh[i]), gx, gy) * w;
			if (use_orm) {
				acc_o += textureGrad(orm_atlas, atlas_uv(fr[i], uh[i]), gx, gy) * w;
			}
			if (use_emission) {
				acc_e += textureGrad(emission_atlas, atlas_uv(fr[i], uh[i]), gx, gy) * w;
			}
			vec2 nxy = nh[i].xy / nh[i].a * 2.0 - 1.0;
			acc_n += (fx[i] * nxy.x + fy[i] * nxy.y + fd[i] * sqrt(max(1.0 - dot(nxy, nxy), 0.0))) * cov;
		}
	}
	if (acc_cov / max(wsum, 1e-4) < max(alpha_cut, 1e-4)) {
		discard;
	}
#else
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
			if (use_orm) {
				acc_o += textureGrad(orm_atlas, atlas_uv(fr[i], u), gx, gy) * w;
			}
			if (use_emission) {
				acc_e += textureGrad(emission_atlas, atlas_uv(fr[i], u), gx, gy) * w;
			}
			vec2 nxy = n4.a > 0.0 ? n4.xy / n4.a * 2.0 - 1.0 : vec2(0.0);
			acc_n += (fx[i] * nxy.x + fy[i] * nxy.y + fd[i] * sqrt(max(1.0 - dot(nxy, nxy), 0.0))) * cov;
		}
	}
	if (acc_cov < max(alpha_cut, 1e-4)) {
		discard;
	}
#endif
	ALBEDO = acc_a.rgb / max(acc_a.a, 1e-4) * v_tint;
	vec3 n_view = normalize(mat3(VIEW_MATRIX) * normalize(v_nmat * acc_n));
	NORMAL = normalize(mix(NORMAL, n_view, normal_strength));
	ROUGHNESS = v_surf.x;
	METALLIC = v_surf.y;
	SPECULAR = v_surf.z;
	if (use_orm) {
		vec3 orm = acc_o.rgb / max(acc_o.a, 1e-4);
		AO = orm.r;
		AO_LIGHT_AFFECT = v_mat.y;
		ROUGHNESS = orm.g;
		METALLIC = orm.b;
	}
	if (use_emission) {
		EMISSION = acc_e.rgb / max(acc_e.a, 1e-4) * v_mat.x;
	}
	vec3 p_l = acc_p / acc_cov;
	if (IN_SHADOW_PASS) {
		p_l += rd * shadow_bias;
	}
	vec3 p_obj = v_bounds.xyz + p_l * v_bounds.w;
	vec4 p_view = VIEW_MATRIX * (MODEL_MATRIX * vec4(p_obj, 1.0));
#ifndef NO_DEPTH_WRITE
	vec4 clip = PROJECTION_MATRIX * p_view;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	DEPTH = clip.z / clip.w * 0.5 + 0.5;
#else
	DEPTH = clip.z / clip.w;
#endif
#endif
#if DEBUG_MODE == 1
	vec3 lod_color = QUALITY == 0 ? vec3(1.0, 0.2, 0.2) : (QUALITY == 1 ? vec3(1.0, 0.65, 0.1) : (QUALITY == 2 ? vec3(0.2, 1.0, 0.3) : vec3(0.2, 0.8, 1.0)));
	ALBEDO = mix(ALBEDO, lod_color, 0.6);
#elif DEBUG_MODE == 2
	float hue = fract(v_f01.x * 0.618034 + v_f01.y * 0.381966);
	vec3 view_color = clamp(abs(fract(hue + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	ALBEDO = vec3(0.0);
	EMISSION = view_color;
#elif DEBUG_MODE == 3
	ALBEDO = vec3(0.0);
	EMISSION = vec3(clamp(dot(p_l, -rd) * 0.5 + 0.5, 0.0, 1.0));
#elif DEBUG_MODE == 4
	ALBEDO = vec3(0.0);
	EMISSION = use_orm ? acc_o.rgb / max(acc_o.a, 1e-4) : vec3(1.0, v_surf.x, v_surf.y);
#endif
	LIGHT_VERTEX = p_view.xyz;
}
