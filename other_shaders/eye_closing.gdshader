shader_type canvas_item;

// blacking out driven entirely by progress 0 wide awake 1 gone so the tweens
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// the screen sampled with mipmaps so texturelods lod gives us a cheap blur without
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

group_uniforms cloudiness;
// the murk everything drains into cold and desaturated pure blue reads as a colour
uniform vec3 cloud_color : source_color = vec3(0.29, 0.51, 0.72);
// how far the picture is allowed to wash out into cloud_color at progress 1
uniform float cloud_strength : hint_range(0.0, 1.0) = 0.88;
// fraction of the blackout the murk takes to reach full small on purpose the
uniform float cloud_ramp : hint_range(0.01, 1.0) = 0.12;
// max mip level at full blackout higher soupier
uniform float blur_amount : hint_range(0.0, 6.0) = 3.5;
// how much colour is gone by full blackout before the blue goes on top
uniform float desaturation : hint_range(0.0, 1.0) = 0.85;
// size and drift speed of the blotches rolling through the murk
uniform float cloud_scale : hint_range(0.5, 12.0) = 3.0;
uniform float cloud_drift : hint_range(0.0, 1.0) = 0.09;
// sideways smear in uv sells it as fluid rather than a flat overlay
uniform float wobble : hint_range(0.0, 0.05) = 0.012;

group_uniforms tunnel;
// how hard the edges crush inward before the lids arrive
uniform float vignette_strength : hint_range(0.0, 2.0) = 1.25;
// where the darkening starts as a fraction out from centre
uniform float vignette_start : hint_range(0.0, 1.0) = 0.18;

group_uniforms eyelids;
uniform vec3 lid_color : source_color = vec3(0.0, 0.0, 0.0);
// fraction of progress spent going cloudy before the lids start to move so the
uniform float lid_delay : hint_range(0.0, 0.9) = 0.35;


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p *= 2.02;
		a *= 0.5;
	}
	return v;
}


void fragment() {
	// screen_uv throughout not uv the murk has to line up with the screen it
	vec2 uv = SCREEN_UV;

	// everything is written as a branch around progress 0 rather than an early return
	vec3 col = textureLod(screen_texture, uv, 0.0).rgb;
	float alpha = 0.0;

	if (progress > 0.0) {
		alpha = 1.0;

		// the murk arrives almost immediately and then just sits there it is the first
		float haze = clamp(progress / max(cloud_ramp, 0.001), 0.0, 1.0);

		// drifting murk two fbm samples at different rates so the blotches swim past each
		vec2 drift = vec2(TIME * cloud_drift, TIME * cloud_drift * 0.6);
		float murk = fbm(uv * cloud_scale + drift);
		float murk2 = fbm(uv * cloud_scale * 2.3 - drift * 1.7);
		float blotch = mix(murk, murk2, 0.5);

		// smear the sample around before blurring it fluid in the way not a filter
		vec2 warp = vec2(blotch - 0.5, murk2 - 0.5) * wobble * haze;
		vec3 scene = textureLod(screen_texture, uv + warp, haze * blur_amount).rgb;

		// colour drains out first then the blue goes on keeping the scenes own luminance
		float luma = dot(scene, vec3(0.2126, 0.7152, 0.0722));
		vec3 washed = mix(scene, vec3(luma), desaturation * haze);
		vec3 tint = cloud_color * (0.35 + 0.9 * luma);
		// blotches make the wash uneven so it gathers in patches
		float wash = cloud_strength * haze * (0.72 + 0.55 * blotch);
		col = mix(washed, tint, clamp(wash, 0.0, 1.0));

		// tunnel vision closing in ahead of the lids
		float d = length(uv - vec2(0.5)) * 1.42;
		float vig = smoothstep(vignette_start, 1.0, d) * vignette_strength * haze;
		col = mix(col, lid_color, clamp(vig, 0.0, 1.0));

		// lids last remap progress past lid_delay so they hold open while the murk builds
		float lid_progress = clamp((progress - lid_delay) / max(1.0 - lid_delay, 0.001), 0.0, 1.0);
		if (lid_progress > 0.0) {
			float opening = 0.5 * (1.0 - lid_progress);

			// slightly curved eyelids
			float x = abs(uv.x - 0.5) * 2.0;
			float curve = 0.035 * x * x;

			float top_edge = 0.5 - opening + curve;
			float bottom_edge = 0.5 + opening - curve;

			// distance outside the visible opening
			float top_alpha = 1.0 - smoothstep(top_edge, top_edge + 0.05, uv.y);
			float bottom_alpha = smoothstep(bottom_edge - 0.05, bottom_edge, uv.y);

			col = mix(col, lid_color, clamp(max(top_alpha, bottom_alpha), 0.0, 1.0));
		}
	}

	COLOR = vec4(col, alpha);
}
