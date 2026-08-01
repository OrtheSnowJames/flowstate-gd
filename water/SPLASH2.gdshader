shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform float elapsed           : hint_range(0.0, 1.0)  = 0.0;
uniform int   spike_count       : hint_range(2, 16)     = 8;
uniform float spike_sharpness   : hint_range(0.1, 3.0)  = 0.7;
uniform float max_height        : hint_range(0.1, 5.0)  = 2.0;
uniform float outward_flare     : hint_range(0.0, 2.0)  = 1.0;
uniform vec4  foam_color        : source_color = vec4(0.95, 0.99, 1.0,  0.45);
uniform vec4  mid_color         : source_color = vec4(0.55, 0.88, 0.95, 0.35);
uniform vec4  base_shadow_color : source_color = vec4(0.08, 0.38, 0.55, 0.25);

varying float v_h;
varying float v_petal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	float rim_fac = 1.0 - UV.y;   // 1 at rim, 0 at base
	float angle   = atan(VERTEX.x, VERTEX.z);

	// Smooth petals: round valleys AND round peaks, no sqrt-near-zero spike
	float petal = pow(smoothstep(-1.0, 1.0, cos(angle * float(spike_count) * 0.5)), spike_sharpness);

	float crown_t     = clamp((elapsed - 0.28) / 0.72, 0.0, 1.0);
	float ct          = crown_t;
	float s           = sin(pow(ct, 0.8) * 3.14159265);
	float height_anim = s * s;
	float flare_anim  = smoothstep(0.0, 0.7, ct);
	float fold        = smoothstep(0.45, 1.0, ct);

	// Phase 1: whole mesh rises from below water (0 → 0.38)
	float rise = smoothstep(0.0, 0.38, elapsed);
	VERTEX.y  += (rise - 1.0) * max_height;

	vec3 out_dir = normalize(vec3(VERTEX.x, 0.0, VERTEX.z));
	VERTEX.xz   += out_dir.xz * outward_flare * rim_fac * flare_anim;

	float lift     = petal * rim_fac * max_height * height_anim;
	float bow_down = rim_fac * rim_fac * outward_flare * (0.45 * flare_anim + 1.4 * fold);
	VERTEX.y      += lift - bow_down;

	v_h     = clamp(max(height_anim, fold * 0.45) * petal * rim_fac, 0.0, 1.0);
	v_petal = petal;
}

void fragment() {
	float h = v_h;

	float n = vnoise(UV * 5.0) * 0.6 + vnoise(UV * 11.0) * 0.4;
	float noise_shift = (n - 0.5) * 0.22;

	vec3 col = base_shadow_color.rgb;
	col = mix(col, mid_color.rgb,  smoothstep(0.0,  0.75, h));
	col = mix(col, foam_color.rgb, smoothstep(0.55, 1.0,  h));
	col = mix(col, vec3(1.0), smoothstep(0.75 + noise_shift, 1.0, h) * 0.25);
	vec3 light_dir = normalize(vec3(0.5, 0.8, 0.3));
	vec3 half_vec  = normalize(normalize(VIEW) + light_dir);
	float spec     = pow(max(0.0, dot(NORMAL, half_vec)), 28.0);
	col = mix(col, vec3(1.0), spec * 0.85);

	float fresnel = pow(1.0 - abs(dot(normalize(VIEW), NORMAL)), 2.0);
	col = mix(col, vec3(0.88, 0.97, 1.0), fresnel * 0.5);

	float zone_alpha = mix(base_shadow_color.a, mid_color.a,  smoothstep(0.0, 0.75, h));
	zone_alpha       = mix(zone_alpha,           foam_color.a, smoothstep(0.55, 1.0, h));
	zone_alpha      *= 0.22;

	float alpha  = smoothstep(0.0, 0.3,  v_h);
	alpha       *= smoothstep(0.0, 0.45, v_petal);
	alpha       *= zone_alpha;
	alpha       *= smoothstep(0.0, 0.18, elapsed);
	float decay    = smoothstep(0.78, 1.0, elapsed);
	float d_noise  = vnoise(UV * 6.0) * 0.55 + vnoise(UV * 13.0) * 0.45;
	alpha         *= smoothstep(decay - 0.1, decay + 0.1, d_noise);

	ALBEDO = col;
	ALPHA  = alpha;
}
