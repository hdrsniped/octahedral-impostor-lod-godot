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
#if DEBUG_MODE == 5
#define WASTE_PIXEL wasted = true;
#ifndef NO_DEPTH_WRITE
#define NO_DEPTH_WRITE
#endif
#else
#define WASTE_PIXEL discard;
#endif
// --- Thresholds ---
const float COARSE_MIN = 0.001;
const float PIXEL_VALID = 0.01;
const float PIXEL_SOLID = 0.5;
const float WEIGHT_MIN = 0.0001;
const float MAX_CARD_SCALE = 8.0;
const float COARSE_LOD_SCALE = 8.0;
const float MIN_CAMERA_GAP = 0.02;
const float SPHERE_EDGE = 1.001;
const float POLE_DOT = 0.999;
#if QUALITY >= 2 || defined(PARALLAX_REFINE)
#define PARALLAX_STEPS 3
#else
#define PARALLAX_STEPS 1
#endif
#define SHADOW_STEPS 2
#ifdef CARD_FADE
const vec3 FADE_NOISE = vec3(0.06711056, 0.00583715, 52.9829189);
const float FADE_CAP = 0.001;
#endif
#ifdef VIEW_VISIBILITY
const float VIS_TOLERANCE = 0.5;
#endif
#ifdef CARD_WIND
const float WIND_SWAY = 0.2;
const float WIND_LIMIT = 0.5;
const float TAU_F = 6.2831853;
#define WIND_SHIFT + wind_w
#else
#define WIND_SHIFT
#endif
#if QUALITY == 3 && defined(PRECISE_SEARCH)
#define SEARCH_SUB 4
const float PROBE_MIN = 0.05;
const float PROBE_SOLID = 0.95;
const float PROBE_MAX_LOD = 5.0;
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
#if QUALITY == 3 && defined(PYRAMID_SEARCH)
uniform sampler2D max_coverage : filter_nearest, repeat_disable;
const float PYR_SKIP = 0.02;
#endif

group_uniforms look;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform float normal_strength : hint_range(0.0, 1.0) = 1.0;
uniform float depth_scale : hint_range(0.0, 2.0) = 1.0;
uniform float quad_offset : hint_range(0.0, 1.0) = 1.0;
uniform float shadow_bias : hint_range(0.0, 0.5) = 0.04;
uniform int shadow_views : hint_range(1, 3) = 1;
#if QUALITY == 3
group_uniforms complex_shapes;
uniform int search_steps : hint_range(2, 32) = 8;
uniform int refine_steps : hint_range(0, 8) = 3;
uniform float layer_tolerance : hint_range(0.0, 1.0) = 0.15;
uniform float min_thickness : hint_range(0.0, 1.0) = 0.1;
#endif
group_uniforms;
#ifdef CARD_WIND
group_uniforms wind;
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float wind_speed : hint_range(0.0, 100.0) = 4.0;
uniform float wind_frequency : hint_range(0.001, 1.0) = 0.05;
uniform float wind_gust : hint_range(0.0, 1.0) = 0.3;
group_uniforms;
#endif

instance uniform int octa_index = 0;
instance uniform vec4 card_tint : source_color = vec4(1.0);
instance uniform float card_depth = 1.0;
#ifdef CARD_FADE
instance uniform vec2 card_fade = vec2(0.0);
varying flat float v_fade;
#endif
#ifdef CARD_WIND
instance uniform float card_wind = 0.0;
varying flat vec3 v_wind;
#endif

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
	vec3 up = abs(d.y) > POLE_DOT ? vec3(0.0, 0.0, -1.0) : vec3(0.0, 1.0, 0.0);
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
		off = clamp(off, 0.0, max(dist - MIN_CAMERA_GAP, 0.0));
		s = dist > SPHERE_EDGE ? (dist - off) / sqrt(dist * dist - 1.0) : MAX_CARD_SCALE;
		s = min(s, MAX_CARD_SCALE);
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
#ifdef CARD_WIND
	v_wind = vec3(0.0);
	if (card_wind > 0.0) {
		vec2 wp = (MODEL_MATRIX * vec4(b.xyz, 1.0)).xz;
		vec2 side_dir = vec2(-wind_dir.y, wind_dir.x);
		float k = wind_frequency * TAU_F;
		float clock = TIME * wind_speed * k;
		float along = dot(wp, wind_dir) * k;
		float across = dot(wp, side_dir) * k;
		float swell = 0.6 * sin(along - clock) + 0.4 * sin(across * 1.19 + along * 0.6 - clock * 1.3 + 1.7);
		float gust = wind_gust * max(sin(along * 0.35 - clock * 0.4 + across * 0.2), 0.0);
		float flutter = 0.25 * sin(along * 2.3 - clock * 2.1 + across);
		vec2 w2 = wind_dir * (0.6 + 0.4 * swell + gust) + side_dir * flutter;
		vec3 wl = mat3(inv_model) * vec3(w2.x, 0.0, w2.y) * length(MODEL_MATRIX[1].xyz);
		v_wind = wl * (card_wind * WIND_SWAY);
		float wl_len = length(v_wind);
		if (wl_len > WIND_LIMIT) {
			v_wind *= WIND_LIMIT / wl_len;
		}
	}
#endif
#ifdef CARD_FADE
	float fade_dist = length((VIEW_MATRIX * (MODEL_MATRIX * vec4(b.xyz, 1.0))).xyz);
	v_fade = card_fade.y <= 0.0 ? 1.0 : (card_fade.y > card_fade.x ? smoothstep(card_fade.x, card_fade.y, fade_dist) : step(card_fade.y, fade_dist));
#endif
}

// --- Fragment helpers ---
float baked_height(vec4 nd) {
	return nd.a > PIXEL_VALID ? (1.0 - 2.0 * nd.b / nd.a) * v_depth : 0.0;
}

#if QUALITY == 3
bool in_frame(vec2 u) {
	return all(greaterThanEqual(u, vec2(0.0))) && all(lessThanEqual(u, vec2(1.0)));
}

bool is_inside(vec3 p, vec3 d, float hf, float hb) {
	float ph = dot(p, d);
	return ph <= hf && ph >= hb;
}

bool crossed_slab(vec3 p, vec3 p_prev, vec3 d, float hf, float hb) {
	return dot(p_prev, d) > hf && dot(p, d) < hb;
}
#endif

// --- Shadow pass: coverage and depth from one baked view ---
float shadow_view(vec2 frame, vec3 d, vec3 bx, vec3 by, vec3 ro, vec3 rd, vec2 gx, vec2 gy, out vec3 pos) {
	float den = min(dot(rd, d), -1e-4);
	float rod = dot(ro, d);
	vec2 u = frame_uv(ro - rd * (rod / den), bx, by);
	vec4 n4 = textureGrad(normal_atlas, atlas_uv(frame, u), gx * COARSE_LOD_SCALE, gy * COARSE_LOD_SCALE);
	for (int s = 0; s < SHADOW_STEPS; s++) {
		u = frame_uv(ro + rd * ((baked_height(n4) - rod) / den), bx, by);
		n4 = textureGrad(normal_atlas, atlas_uv(frame, u), gx, gy);
	}
	pos = ro + rd * ((baked_height(n4) - rod) / den);
	return n4.a * float(all(greaterThanEqual(u, vec2(0.0))) && all(lessThanEqual(u, vec2(1.0))));
}

// --- Fragment: blend views, parallax, per-pixel depth ---
void fragment() {
#ifdef CARD_FADE
	if (!IN_SHADOW_PASS && v_fade < 1.0) {
		float gap = 1.0 - v_fade;
		float noise = fract(FADE_NOISE.z * fract(dot(FRAGCOORD.xy, FADE_NOISE.xy)));
		if (gap >= FADE_CAP && noise <= gap) {
			discard;
		}
	}
#endif
	vec3 rd = normalize(v_ray);
	vec3 ro = v_pos;
#ifdef CARD_WIND
	vec3 wind_w = vec3(0.0);
	if (dot(v_wind, v_wind) > 0.0) {
		float lift = clamp((ro - rd * dot(ro, rd)).y * 0.5 + 0.5, 0.0, 1.0);
		wind_w = v_wind * (lift * lift);
		ro -= wind_w;
	}
#endif
	vec2 fr[3] = vec2[3](v_f01.xy, v_f01.zw, v_f2);
	float wt[3] = float[3](v_w.x, v_w.y, v_w.z);
	if (IN_SHADOW_PASS) {
		vec2 to_a = v_rect.zw / float(grid_size);
		vec3 d0 = frame_dir(fr[0]);
		vec3 bx0;
		vec3 by0;
		frame_basis(d0, bx0, by0);
		vec2 u0 = frame_uv(ro - rd * (dot(ro, d0) / min(dot(rd, d0), -1e-4)), bx0, by0);
		vec2 sgx = dFdx(u0) * to_a;
		vec2 sgy = dFdy(u0) * to_a;
		vec3 pos_sum;
		float cov_sum = shadow_view(fr[0], d0, bx0, by0, ro, rd, sgx, sgy, pos_sum);
		if (shadow_views > 1) {
			cov_sum *= wt[0];
			pos_sum *= cov_sum;
			for (int i = 1; i < min(shadow_views, NUM_FRAMES); i++) {
				if (wt[i] <= WEIGHT_MIN) {
					continue;
				}
				vec3 d = frame_dir(fr[i]);
				vec3 bx;
				vec3 by;
				frame_basis(d, bx, by);
				vec3 p;
				float cv = shadow_view(fr[i], d, bx, by, ro, rd, sgx, sgy, p) * wt[i];
				cov_sum += cv;
				pos_sum += p * cv;
			}
			pos_sum /= max(cov_sum, 1e-4);
		}
		if (cov_sum < max(alpha_cut, 1e-4)) {
			discard;
		}
		vec3 ps = pos_sum WIND_SHIFT + rd * shadow_bias;
#ifndef NO_DEPTH_WRITE
		vec4 sclip = PROJECTION_MATRIX * (VIEW_MATRIX * (MODEL_MATRIX * vec4(v_bounds.xyz + ps * v_bounds.w, 1.0)));
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		DEPTH = sclip.z / sclip.w * 0.5 + 0.5;
#else
		DEPTH = sclip.z / sclip.w;
#endif
#endif
	} else {
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
#if DEBUG_MODE == 5
		bool wasted = false;
#endif

		vec4 nd[3];
		float coarse = 0.0;
		for (int i = 0; i < NUM_FRAMES; i++) {
			nd[i] = vec4(0.0);
			if (wt[i] > WEIGHT_MIN) {
				nd[i] = textureGrad(normal_atlas, atlas_uv(fr[i], uv[i]), gx * COARSE_LOD_SCALE, gy * COARSE_LOD_SCALE);
				coarse += nd[i].a * wt[i];
			}
		}
		if (coarse < COARSE_MIN) {
			WASTE_PIXEL
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
			WASTE_PIXEL
		}
		float t_in = -bq - sqrt(disc);
		float t_out = -bq + sqrt(disc);
		float dt = (t_out - t_in) / float(max(search_steps, 1));
#if defined(PRECISE_SEARCH)
		vec2 atlas_px = vec2(textureSize(normal_atlas, 0));
		float screen_lod = log2(max(max(length(gx * atlas_px), length(gy * atlas_px)), 1.0));
#endif
		float th[3] = float[3](0.0, 0.0, 0.0);
		float hit[3] = float[3](0.0, 0.0, 0.0);
		vec4 nh[3];
		vec2 uh[3];
		float t_ref = -1e9;
		for (int i = 0; i < NUM_FRAMES; i++) {
			nh[i] = vec4(0.0);
			uh[i] = vec2(0.0);
			if (wt[i] <= WEIGHT_MIN) {
				continue;
			}
			float lo = t_in;
			float hi = t_in;
			bool front_only = false;
#if defined(PRECISE_SEARCH)
			for (int s = 0; s <= search_steps; s++) {
				float t0 = t_in + dt * float(s - 1);
				int fine = 1;
				if (s > 0) {
					vec2 u0 = frame_uv(ro + rd * t0, fx[i], fy[i]);
					vec2 u1 = frame_uv(ro + rd * (t0 + dt), fx[i], fy[i]);
					float reach = length((u1 - u0) * to_atlas * atlas_px);
					float probe_lod = max(min(ceil(log2(max(reach, 1.0))), PROBE_MAX_LOD), screen_lod);
					float cover = textureLod(normal_atlas, atlas_uv(fr[i], (u0 + u1) * 0.5), probe_lod).a;
					fine = cover < PROBE_MIN ? 0 : (cover >= PROBE_SOLID ? 1 : SEARCH_SUB);
				}
				float sub = dt / float(max(fine, 1));
				for (int k = 1; k <= fine; k++) {
					float t = s == 0 ? t_in : t0 + sub * float(k);
					vec3 p = ro + rd * t;
					vec2 u = frame_uv(p, fx[i], fy[i]);
					vec2 a = atlas_uv(fr[i], u);
					vec4 n4 = textureGrad(normal_atlas, a, gx, gy);
					float bk = use_back_layer ? textureGrad(back_atlas, a, gx, gy).r : 0.0;
					bool in_fr = in_frame(u);
					bool solid = n4.a >= PIXEL_SOLID;
					float hf = 0.0;
					float hb = -2.0;
					if (in_fr && solid) {
						hf = baked_height(n4);
						if (use_back_layer) {
							hb = min((1.0 - 2.0 * bk / n4.a) * v_depth, hf - min_thickness);
						}
					}
					bool crossed = s > 0 && in_fr && solid && use_back_layer && crossed_slab(p, p - rd * sub, fd[i], hf, hb);
					if (crossed || (in_fr && solid && is_inside(p, fd[i], hf, hb))) {
						front_only = crossed;
						hit[i] = 1.0;
						lo = s == 0 ? t : t - sub;
						hi = t;
						nh[i] = n4;
						uh[i] = u;
						break;
					}
				}
				if (hit[i] > 0.5) {
					break;
				}
			}
#else
			for (int s = 0; s <= search_steps; s++) {
				float t = t_in + dt * float(s);
				vec3 p = ro + rd * t;
				vec2 u = frame_uv(p, fx[i], fy[i]);
				vec2 a = atlas_uv(fr[i], u);
#if defined(PYRAMID_SEARCH)
				if (s > 0) {
					vec2 up = frame_uv(ro + rd * (t_in + dt * float(s - 1)), fx[i], fy[i]);
					if (texture(max_coverage, atlas_uv(fr[i], (up + u) * 0.5)).r < PYR_SKIP) {
						lo = t;
						continue;
					}
				}
#endif
				vec4 n4 = textureGrad(normal_atlas, a, gx, gy);
				float bk = use_back_layer ? textureGrad(back_atlas, a, gx, gy).r : 0.0;
				bool in_fr = in_frame(u);
				bool solid = n4.a >= PIXEL_SOLID;
				float hf = 0.0;
				float hb = -2.0;
				if (in_fr && solid) {
					hf = baked_height(n4);
					if (use_back_layer) {
						hb = min((1.0 - 2.0 * bk / n4.a) * v_depth, hf - min_thickness);
					}
				}
				bool crossed = s > 0 && in_fr && solid && use_back_layer && crossed_slab(p, p - rd * dt, fd[i], hf, hb);
				if (crossed || (in_fr && solid && is_inside(p, fd[i], hf, hb))) {
					front_only = crossed;
					hit[i] = 1.0;
					hi = t;
					nh[i] = n4;
					uh[i] = u;
					break;
				}
				lo = t;
			}
#endif
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
				bool in_fr = in_frame(u);
				bool solid = n4.a >= PIXEL_SOLID;
				float hf = 0.0;
				float hb = -2.0;
				if (in_fr && solid) {
					hf = baked_height(n4);
					if (use_back_layer && !front_only) {
						hb = min((1.0 - 2.0 * bk / n4.a) * v_depth, hf - min_thickness);
					}
				}
				if (in_fr && solid && is_inside(p, fd[i], hf, hb)) {
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
			if (wt[i] <= WEIGHT_MIN) {
				continue;
			}
			float w = wt[i];
			if (hit[i] > 0.5 && layer_tolerance > 0.0) {
				w *= 1.0 - smoothstep(layer_tolerance * 0.5, layer_tolerance, t_ref - th[i]);
			}
			wsum += w;
			if (hit[i] < 0.5 || w <= WEIGHT_MIN) {
				continue;
			}
			float cov = nh[i].a * w;
			acc_cov += cov;
			acc_p += (ro + rd * th[i]) * cov;
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
		if (acc_cov / max(wsum, 1e-4) < max(alpha_cut, 1e-4)) {
			WASTE_PIXEL
		}
#else
		float ti[3];
		float wv[3];
		vec4 nv[3];
		vec2 uv2[3];
		for (int i = 0; i < NUM_FRAMES; i++) {
			ti[i] = -1e9;
			wv[i] = 0.0;
			nv[i] = vec4(0.0);
			uv2[i] = uv[i];
			if (wt[i] <= WEIGHT_MIN || nd[i].a <= COARSE_MIN) {
				continue;
			}
			vec2 u = uv[i];
			vec4 n4 = nd[i];
			for (int s = 0; s < PARALLAX_STEPS; s++) {
				u = frame_uv(ro + rd * ((baked_height(n4) - rod[i]) / denom[i]), fx[i], fy[i]);
				n4 = textureGrad(normal_atlas, atlas_uv(fr[i], u), gx, gy);
			}
			ti[i] = (baked_height(n4) - rod[i]) / denom[i];
			wv[i] = wt[i] * float(all(greaterThanEqual(u, vec2(0.0))) && all(lessThanEqual(u, vec2(1.0))));
			nv[i] = n4;
			uv2[i] = u;
		}
		float t_ref = 1e9;
		for (int i = 0; i < NUM_FRAMES; i++) {
			if (wv[i] > 0.0 && nv[i].a > PIXEL_VALID) {
				t_ref = min(t_ref, ti[i]);
			}
		}
		for (int i = 0; i < NUM_FRAMES; i++) {
			if (wv[i] <= 0.0) {
				continue;
			}
			float w = wv[i];
#ifdef VIEW_VISIBILITY
			if (nv[i].a > PIXEL_VALID && t_ref < 1e8) {
				w *= 1.0 - smoothstep(VIS_TOLERANCE * 0.5, VIS_TOLERANCE, max(ti[i] - t_ref, 0.0));
			}
#endif
			float cov = nv[i].a * w;
			acc_cov += cov;
			acc_p += (ro + rd * ti[i]) * cov;
			acc_a += textureGrad(albedo_atlas, atlas_uv(fr[i], uv2[i]), gx, gy) * w;
			if (use_orm) {
				acc_o += textureGrad(orm_atlas, atlas_uv(fr[i], uv2[i]), gx, gy) * w;
			}
			if (use_emission) {
				acc_e += textureGrad(emission_atlas, atlas_uv(fr[i], uv2[i]), gx, gy) * w;
			}
			vec2 nxy = nv[i].a > 0.0 ? nv[i].xy / nv[i].a * 2.0 - 1.0 : vec2(0.0);
			acc_n += (fx[i] * nxy.x + fy[i] * nxy.y + fd[i] * sqrt(max(1.0 - dot(nxy, nxy), 0.0))) * cov;
		}
		if (acc_cov < max(alpha_cut, 1e-4)) {
			WASTE_PIXEL
		}
#endif
		ALBEDO = acc_a.rgb / max(acc_a.a, 1e-4) * v_tint;
#ifdef CARD_WIND
		vec3 lean = normalize(acc_n);
		acc_n = lean + cross(cross(vec3(0.0, 1.0, 0.0), v_wind), lean);
#endif
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
		} else {
			AO = v_mat.z;
		}
		if (use_emission) {
			EMISSION = acc_e.rgb / max(acc_e.a, 1e-4) * v_mat.x;
		}
		vec3 p_l = acc_p / acc_cov WIND_SHIFT;
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
		EMISSION = use_orm ? acc_o.rgb / max(acc_o.a, 1e-4) : vec3(v_mat.z, v_surf.x, v_surf.y);
#elif DEBUG_MODE == 5
		ALBEDO = vec3(0.0);
		SPECULAR = 0.0;
		NORMAL = vec3(0.0, 0.0, 1.0);
		EMISSION = wasted ? vec3(1.0, 0.0, 1.0) : vec3(0.35);
		ALPHA = wasted ? 0.6 : 1.0;
#endif
#if DEBUG_MODE != 5
		LIGHT_VERTEX = p_view.xyz;
#endif
	}
}
