// =============================================================================
// water_surface.gdshader
// Renders the simulated heightfield as real 3D geometry:
//   * vertex displacement (height + horizontal "chop" so crests pinch)
//   * normals derived analytically from the height gradient
//   * screen-space refraction with Beer–Lambert depth absorption
//   * foam from wave energy (sim velocity channel), crests and shorelines
//   * procedural micro-ripple detail so calm water still looks alive
// Requires Forward+ (or Mobile) renderer for depth/screen textures.
// =============================================================================
shader_type spatial;
render_mode depth_draw_always, cull_back, specular_schlick_ggx;

uniform sampler2D height_tex : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex  : hint_depth_texture, filter_nearest, repeat_disable;

uniform vec2  texel       = vec2(0.00390625);
uniform vec2  world_size  = vec2(10.0, 10.0);
uniform float amplitude   : hint_range(0.0, 2.0)  = 0.35;  // metres at full sim value
uniform float chop        : hint_range(0.0, 2.0)  = 0.7;   // horizontal crest pinch

uniform vec4  shallow_color : source_color = vec4(0.10, 0.42, 0.45, 1.0);
uniform vec4  deep_color    : source_color = vec4(0.035, 0.14, 0.21, 1.0);
uniform float absorption    : hint_range(0.0, 4.0) = 0.05;  // Beer–Lambert coefficient (low = translucent)
uniform float refraction_strength : hint_range(0.0, 0.3) = 0.07;

uniform vec4  foam_color : source_color = vec4(0.92, 0.96, 0.98, 1.0);
uniform float foam_crest_start : hint_range(0.0, 0.5) = 0.10; // metres of height
uniform float foam_energy      : hint_range(0.0, 40.0) = 14.0; // foam from wave motion
uniform float shore_foam_depth : hint_range(0.0, 1.0) = 0.18;  // metres

uniform float detail_scale    : hint_range(0.1, 20.0) = 4.0;
uniform float detail_strength : hint_range(0.0, 1.0)  = 0.18;

varying float v_h;       // decoded height (sim units)
varying vec2  v_uv;

float decode_h(vec2 uv) {
	return textureLod(height_tex, uv, 0.0).r - 0.5;
}

void vertex() {
	v_uv = UV;
	float h  = decode_h(UV);
	float hl = decode_h(UV - vec2(texel.x, 0.0));
	float hr = decode_h(UV + vec2(texel.x, 0.0));
	float hu = decode_h(UV - vec2(0.0, texel.y));
	float hd = decode_h(UV + vec2(0.0, texel.y));
	v_h = h;

	VERTEX.y += h * amplitude;
	// Gerstner-style chop: pull vertices horizontally toward crests so wave
	// fronts sharpen instead of staying sinusoidal blobs.
	vec2 grad = vec2(hr - hl, hd - hu) / (2.0 * texel * world_size);
	VERTEX.xz -= grad * amplitude * chop * 0.12;
}

// --- tiny value noise for micro-ripples & foam breakup ----------------------
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	// --- Normal from the simulated height gradient ---------------------------
	float hl = texture(height_tex, v_uv - vec2(texel.x, 0.0)).r - 0.5;
	float hr = texture(height_tex, v_uv + vec2(texel.x, 0.0)).r - 0.5;
	float hu = texture(height_tex, v_uv - vec2(0.0, texel.y)).r - 0.5;
	float hd = texture(height_tex, v_uv + vec2(0.0, texel.y)).r - 0.5;
	vec2 dx = 2.0 * texel * world_size;
	vec2 slope = vec2((hr - hl) * amplitude / dx.x, (hd - hu) * amplitude / dx.y);

	// procedural micro-ripples (two drifting noise layers)
	vec2 wp = v_uv * world_size * detail_scale;
	float e = 0.35;
	vec2 d1 = wp + TIME * vec2(0.55, 0.20);
	vec2 d2 = wp * 1.7 - TIME * vec2(0.23, 0.61);
	vec2 dgrad =
		vec2(vnoise(d1 + vec2(e, 0.0)) - vnoise(d1 - vec2(e, 0.0)),
		     vnoise(d1 + vec2(0.0, e)) - vnoise(d1 - vec2(0.0, e))) +
		0.6 * vec2(vnoise(d2 + vec2(e, 0.0)) - vnoise(d2 - vec2(e, 0.0)),
		           vnoise(d2 + vec2(0.0, e)) - vnoise(d2 - vec2(0.0, e)));
	slope += dgrad * detail_strength;

	vec3 n_model = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(mat3(MODEL_MATRIX) * n_model), 0.0)).xyz);

	// --- Water depth from the scene depth buffer -----------------------------
	float draw = texture(depth_tex, SCREEN_UV).r;
	vec4 vpos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, draw, 1.0);
	vpos.xyz /= vpos.w;
	float depth_m = clamp(-vpos.z - (-VERTEX.z), 0.0, 200.0);

	// --- Refraction (offset shrinks in shallow water so edges don't smear) ---
	vec2 ruv = SCREEN_UV + NORMAL.xy * refraction_strength * clamp(depth_m, 0.0, 1.0);
	vec3 refr = texture(screen_tex, ruv).rgb;

	// --- Beer–Lambert absorption --------------------------------------------
	float transmit = exp(-absorption * depth_m);
	vec3 col = mix(deep_color.rgb, refr * mix(vec3(1.0), shallow_color.rgb, 0.55), transmit);
	// Subtle crest brightening (cheap subsurface scattering read) -- was
	// unconditionally added on TOP of the depth-based mix above, uncapped and
	// unscaled by transmit. With amplitude at 1.2 (see ocean1.tscn) and an
	// interactively-rippled pool, wave crests are up most of the time, so
	// this was regularly adding over half of shallow_color's own brightness
	// on top of everything else -- washing the whole surface toward a flat
	// tint no matter what absorption/depth said underneath, which is why
	// changing absorption had no visible effect at all. 0.9 -> 0.18 keeps a
	// highlight at crests without it swamping the actual translucency.
	col += shallow_color.rgb * max(v_h, 0.0) * amplitude * 0.18;

	// --- Foam ----------------------------------------------------------------
	float energy = abs(texture(height_tex, v_uv).g - 0.5); // sim velocity channel
	float crest  = smoothstep(foam_crest_start, foam_crest_start * 2.2 + 0.02, v_h * amplitude);
	float churn  = smoothstep(0.35, 1.0, energy * foam_energy);
	float shore  = 1.0 - smoothstep(0.0, shore_foam_depth, depth_m);
	float fnoise = vnoise(wp * 2.3 + TIME * 0.35) * 0.6 + vnoise(wp * 5.1 - TIME * 0.2) * 0.4;
	float foam = clamp(crest + churn * 0.9 + shore * 0.8, 0.0, 1.0);
	foam = smoothstep(0.25, 0.8, foam * (0.55 + fnoise * 0.7));

	ALBEDO    = mix(col, foam_color.rgb, foam);
	ROUGHNESS = mix(0.03, 0.45, foam);
	METALLIC  = 0.0;
	SPECULAR  = 0.6;
	// Forces the transparent pipeline so screen/depth textures are valid;
	// depth_draw_always keeps correct sorting against splashes.
	ALPHA = 1.0;
}
