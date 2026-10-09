shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_nearest;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;

uniform vec4  color_shallow : source_color = vec4(0.10, 0.72, 0.62, 0.15);
uniform vec4  color_deep    : source_color = vec4(0.01, 0.28, 0.50, 0.90);
uniform vec4  color_foam    : source_color = vec4(1.00, 1.00, 1.00, 1.00);

uniform float wave_scale        : hint_range(0.5,  8.0, 0.1)   = 3.0;
uniform float wave_speed        : hint_range(0.0,  3.0, 0.01)  = 0.5;
uniform float water_world_scale : hint_range(0.1, 10.0, 0.1)   = 1.0;
uniform float noise_seed        : hint_range(0.0,100.0, 0.1)   = 0.0;
uniform float chop_scale        : hint_range(0.01, 0.5, 0.01)  = 0.08;
uniform float chop_drift        : hint_range(0.0,  0.1, 0.005) = 0.02;
uniform float chop_contrast     : hint_range(0.0,  1.0, 0.05)  = 0.2;
uniform float chop_max          : hint_range(0.0,  1.0, 0.05)  = 0.8;
uniform float normal_strength   : hint_range(0.0,  8.0, 0.1)   = 4.0;
uniform float wave_height       : hint_range(0.0,  2.0, 0.01)  = 0.25;
uniform float wave_frequency    : hint_range(0.01, 1.0, 0.01)  = 0.25;
uniform float wave_time_scale   : hint_range(0.01, 2.0, 0.01)  = 0.60;
// shared wave clock driven by ocean gd so cpu buoyancy matches the gpu surface
uniform float wave_time = 0.0;
// global scale on the swell amplitude buoyancy reads this too so waves and bobbing
uniform float wave_amp_scale : hint_range(0.0, 3.0, 0.05) = 1.0;
uniform float caustic_scale     : hint_range(0.5,  8.0, 0.1)   = 2.5;
uniform float caustic_speed     : hint_range(0.0,  2.0, 0.01)  = 0.25;
uniform float caustic_strength  : hint_range(0.0,  3.0, 0.05)  = 0.8;

uniform vec3  trail_pos[128];
uniform float trail_age[128];
uniform int   trail_count : hint_range(16, 128, 16) = 48;
uniform float player_radius : hint_range(0.0, 10.0, 0.05) = 1.2;
uniform float ripple_freq   : hint_range(1.0, 200.0, 0.5) = 40.0;
uniform float ripple_speed  : hint_range(0.1, 20.0, 0.1)  = 2.0;
uniform float ripple_radius : hint_range(1.0, 200.0, 1.0) = 50.0;
uniform float ripple_decay  : hint_range(0.01, 10.0, 0.01) = 2.0;
uniform float ripple_str    : hint_range(0.0,  2.0, 0.05) = 0.4;
uniform vec4  color_ripple  : source_color = vec4(1.0, 1.0, 1.0, 0.35);

uniform float foam_distance : hint_range(0.0, 4.0, 0.05) = 0.5;
uniform float foam_strength : hint_range(0.0, 1.0, 0.05) = 0.8;

uniform vec3  sun_dir        = vec3(0.5, 0.8, 0.3);
uniform vec4  shimmer_color  : source_color = vec4(1.0, 0.97, 0.82, 1.0);
uniform float shimmer_str    : hint_range(0.0, 20.0, 0.1)  = 8.0;
uniform float shininess      : hint_range(1.0, 512.0, 1.0) = 80.0;
uniform float opacity        : hint_range(0.0,   1.0, 0.01) = 1.0;

varying vec3 v_world_pos;
varying vec2 v_wave_grad;

float hash(vec2 p) {
	p = fract(p * vec2(127.1 + noise_seed, 311.7 + noise_seed));
	p += dot(p, p + 17.5);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i+vec2(1,0)), f.x),
	           mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y);
}

float choppiness(vec2 p, float t) {
	vec2 s = p * chop_scale + vec2(t * chop_drift, t * chop_drift * 0.75);
	return smoothstep(chop_contrast, chop_max, (noise(s) + noise(s * 1.7 + 3.4)) * 0.5);
}

vec2 surface_normal(vec2 p, float t) {
	float e = 0.1;
	float chop = mix(0.15, 1.0, choppiness(p, t));
	float n0  = noise(p        + vec2(t*0.4,  t*0.3));
	float nx  = noise(p+vec2(e,0) + vec2(t*0.4,  t*0.3));
	float ny  = noise(p+vec2(0,e) + vec2(t*0.4,  t*0.3));
	float n1  = noise(p*2.3    + vec2(-t*0.5, t*0.2));
	float nx1 = noise(p*2.3+vec2(e,0) + vec2(-t*0.5, t*0.2));
	float ny1 = noise(p*2.3+vec2(0,e) + vec2(-t*0.5, t*0.2));
	return vec2((nx-n0)+(nx1-n1), (ny-n0)+(ny1-n1)) / e * chop;
}

float caustics(vec2 p, float t) {
	float a = noise(p       + vec2(sin(t*0.7), cos(t*0.5)) * 0.3);
	float b = noise(p * 1.7 + vec2(cos(t*0.9), sin(t*0.8)) * 0.3);
	return pow(min(a, b), 2.5);
}


float ripple_from(vec2 xz, int i, float t) {
	if (trail_pos[i].x > 9000.0) return 0.0;
	float dist  = max(length(xz - trail_pos[i].xz) - player_radius, 0.0);
	float age   = trail_age[i];
	float front = age * ripple_speed;
	float delta = dist - front;
	float fade  = exp(-age * ripple_decay)
	            * (1.0 - smoothstep(ripple_radius * 0.6, ripple_radius, dist));
	// main ring at wavefront 2 harmonic rings trailing behind it
	float r0 = exp(-delta * delta * ripple_freq);
	float r1 = exp(-(delta + 0.8) * (delta + 0.8) * ripple_freq) * 0.6;
	float r2 = exp(-(delta + 1.6) * (delta + 1.6) * ripple_freq) * 0.35;
	float r3 = exp(-(delta + 2.4) * (delta + 2.4) * ripple_freq) * 0.2;
	return (r0 + r1 + r2 + r3) * fade;
}

float total_ripple(vec2 xz, float t) {
	float v = 0.0;
	for (int i = 0; i < trail_count; i += 2) v += ripple_from(xz, i, t);
	return v * ripple_str;
}

// one directional wave sum of sines heightfield returns its height and accumulates its horizontal
float wave_term(vec2 p, vec2 d, float wl, float amp, float sp, inout vec2 grad) {
	d = normalize(d);
	float w  = 6.2831853 / wl;
	float ph = w * dot(d, p) + wave_time * sp * w;
	grad += amp * w * cos(ph) * d;
	return amp * sin(ph);
}

// world space swell a few layered directional waves small amplitudes for a pool identical
float wave_h(vec2 p, out vec2 grad) {
	grad = vec2(0.0);
	float h = 0.0;
	h += wave_term(p, vec2( 1.0,  0.6),  6.0, 0.060, 1.2, grad);
	h += wave_term(p, vec2(-0.7,  1.0),  3.5, 0.040, 1.5, grad);
	h += wave_term(p, vec2( 0.3, -1.0),  2.0, 0.025, 1.9, grad);
	h += wave_term(p, vec2( 1.0,  0.25), 1.2, 0.015, 2.4, grad);
	grad *= wave_amp_scale;
	return h * wave_amp_scale;
}

void vertex() {
	vec2 xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec2 grad;
	VERTEX.y += wave_h(xz, grad);
	v_wave_grad = grad;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t   = TIME;
	vec2  xz  = v_world_pos.xz;
	vec2  sxz = xz / water_world_scale;

	float rip = total_ripple(xz, t);

	// ripple normals 2 samples instead of 4 reuse rip as base
	float e = 0.2;
	float rip_dx = total_ripple(xz + vec2(e, 0.0), t) - rip;
	float rip_dz = total_ripple(xz + vec2(0.0, e), t) - rip;

	vec2 wn = surface_normal(sxz / wave_scale, t * wave_speed);
	wn += vec2(rip_dx, rip_dz) * 2.5;
	wn += v_wave_grad * 4.0; // big swell tilts the normals so waves catch light

	float chop    = choppiness(sxz / wave_scale, t * wave_speed);
	vec3  col     = mix(color_deep.rgb, color_shallow.rgb, chop);
	col = mix(col, color_ripple.rgb, clamp(rip * color_ripple.a, 0.0, 1.0));

	// edge foam shore distortion rings
	float raw_depth  = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4  view_pos   = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	view_pos.xyz    /= view_pos.w;
	float scene_depth = -view_pos.z;
	float surf_depth  = -VERTEX.z;
	float depth_diff  = scene_depth - surf_depth;
	float edge_foam   = 1.0 - smoothstep(0.0, foam_distance, depth_diff);
	col = mix(col, color_foam.rgb, edge_foam * foam_strength);

	// shore distortion rings multiple rings expanding from waterline into water
	float shore_reach = foam_distance * 2.0;
	float shore_mask  = smoothstep(shore_reach, 0.0, depth_diff);
	float sd  = depth_diff * 4.0 - t * 1.5;
	float s0  = pow(abs(sin(sd)),       6.0);
	float s1  = pow(abs(sin(sd - 1.2)), 6.0) * 0.65;
	float s2  = pow(abs(sin(sd - 2.4)), 6.0) * 0.4;
	float s3  = pow(abs(sin(sd - 3.6)), 6.0) * 0.2;
	float shore_distort = (s0 + s1 + s2 + s3) * shore_mask * 8.0;
	wn += vec2(shore_distort, shore_distort);

	NORMAL_MAP       = normalize(vec3(wn * normal_strength, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	float caus = caustics(sxz / caustic_scale, t * caustic_speed);
	col = clamp(col + vec3(caus * caustic_strength * 0.15), 0.0, 1.0);

	// sun shimmer sharp specular highlight that dances with the animated water normals
	vec3  sun      = normalize(sun_dir);
	vec3  w_norm   = normalize(vec3(wn.x, 1.0 / max(normal_strength, 0.01), wn.y));
	vec3  half_v   = normalize(sun + VIEW);
	float sun_spec = pow(max(0.0, dot(w_norm, half_v)), shininess);

	EMISSION  = shimmer_color.rgb * sun_spec * shimmer_str;

	ALBEDO    = col;
	ROUGHNESS = 0.0;
	SPECULAR  = 0.9;
	METALLIC  = 0.0;
	ALPHA     = mix(0.75, 0.92, chop) * opacity;
}
