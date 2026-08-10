shader_type canvas_item;

// Blacking out, driven entirely by `progress` (0 = wide awake, 1 = gone) so the
// tweens in player.gd's _death()/revive() still drive the whole effect through
// the one parameter they always have.
//
// Three things happen at once, because eyelids closing on their own read as a
// blink rather than losing consciousness:
//   - vision goes cloudy: blurred, desaturated and blotchy, like the fluid in
//     your eye giving up on focusing
//   - everything turns over to a cold blue, the hypoxia/underwater cast
//   - the edges close in before the lids do, so the world tunnels down to a
//     shrinking centre and the lids are the last step, not the whole story
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// The screen, sampled with mipmaps so textureLod's LOD gives us a cheap blur
// without a separate blur pass.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

group_uniforms cloudiness;
// The murk everything drains into. Cold and desaturated -- pure blue reads as a
// colour filter, this reads as water.
uniform vec3 cloud_color : source_color = vec3(0.29, 0.51, 0.72);
// How far the picture is allowed to wash out into cloud_color at progress 1.
// Short of 1.0 so shapes stay faintly readable right up to the lids closing.
uniform float cloud_strength : hint_range(0.0, 1.0) = 0.88;
// Fraction of the blackout the murk takes to reach full. Small on purpose --
// the cloudiness is meant to hit as consciousness starts to go, not fade in
// over the whole slide. 0.12 = fully clouded in the first eighth.
uniform float cloud_ramp : hint_range(0.01, 1.0) = 0.12;
// Max mip level at full blackout. Higher = soupier.
uniform float blur_amount : hint_range(0.0, 6.0) = 3.5;
// How much colour is gone by full blackout, before the blue goes on top.
uniform float desaturation : hint_range(0.0, 1.0) = 0.85;
// Size and drift speed of the blotches rolling through the murk.
uniform float cloud_scale : hint_range(0.5, 12.0) = 3.0;
uniform float cloud_drift : hint_range(0.0, 1.0) = 0.09;
// Sideways smear, in UV. Sells it as fluid rather than a flat overlay.
uniform float wobble : hint_range(0.0, 0.05) = 0.012;

group_uniforms tunnel;
// How hard the edges crush inward before the lids arrive.
uniform float vignette_strength : hint_range(0.0, 2.0) = 1.25;
// Where the darkening starts, as a fraction out from centre.
uniform float vignette_start : hint_range(0.0, 1.0) = 0.18;

group_uniforms eyelids;
uniform vec3 lid_color : source_color = vec3(0.0, 0.0, 0.0);
// Fraction of `progress` spent going cloudy before the lids start to move, so
// the murk leads and the lids finish the job.
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
	// SCREEN_UV throughout, not UV: the murk has to line up with the screen it
	// is sampling, and it makes the whole effect independent of how the host
	// ColorRect happens to be sized and scaled.
	vec2 uv = SCREEN_UV;

	// Everything is written as a branch around progress == 0 rather than an
	// early `return` -- Godot rejects `return` inside fragment() outright and
	// fails the entire shader to compile if you use it.
	vec3 col = textureLod(screen_texture, uv, 0.0).rgb;
	float alpha = 0.0;

	if (progress > 0.0) {
		alpha = 1.0;

		// The murk arrives almost immediately and then just sits there. It is
		// the first sign anything is wrong, so it must not ease in: squaring
		// progress (what this used to do) left it at 8% by the halfway point,
		// which read as vision going fine and then dying all at once at the
		// end. cloud_ramp is the fraction of the blackout it takes to reach
		// full, so at 0.12 the screen is fully clouded in the first eighth and
		// the rest of the time is the lids and the tunnel closing.
		float haze = clamp(progress / max(cloud_ramp, 0.001), 0.0, 1.0);

		// Drifting murk. Two fbm samples at different rates so the blotches
		// swim past each other instead of sliding as one sheet.
		vec2 drift = vec2(TIME * cloud_drift, TIME * cloud_drift * 0.6);
		float murk = fbm(uv * cloud_scale + drift);
		float murk2 = fbm(uv * cloud_scale * 2.3 - drift * 1.7);
		float blotch = mix(murk, murk2, 0.5);

		// Smear the sample around before blurring it -- fluid in the way, not
		// a filter laid over the top.
		vec2 warp = vec2(blotch - 0.5, murk2 - 0.5) * wobble * haze;
		vec3 scene = textureLod(screen_texture, uv + warp, haze * blur_amount).rgb;

		// Colour drains out first, then the blue goes on. Keeping the scene's
		// own luminance in the tint stops it flattening into a solid pane --
		// bright things stay bright through the murk.
		float luma = dot(scene, vec3(0.2126, 0.7152, 0.0722));
		vec3 washed = mix(scene, vec3(luma), desaturation * haze);
		vec3 tint = cloud_color * (0.35 + 0.9 * luma);
		// Blotches make the wash uneven, so it gathers in patches.
		float wash = cloud_strength * haze * (0.72 + 0.55 * blotch);
		col = mix(washed, tint, clamp(wash, 0.0, 1.0));

		// Tunnel vision, closing in ahead of the lids.
		float d = length(uv - vec2(0.5)) * 1.42;
		float vig = smoothstep(vignette_start, 1.0, d) * vignette_strength * haze;
		col = mix(col, lid_color, clamp(vig, 0.0, 1.0));

		// Lids last: remap progress past lid_delay so they hold open while the
		// murk builds, then sweep shut over what's left.
		float lid_progress = clamp((progress - lid_delay) / max(1.0 - lid_delay, 0.001), 0.0, 1.0);
		if (lid_progress > 0.0) {
			float opening = 0.5 * (1.0 - lid_progress);

			// Slightly curved eyelids.
			float x = abs(uv.x - 0.5) * 2.0;
			float curve = 0.035 * x * x;

			float top_edge = 0.5 - opening + curve;
			float bottom_edge = 0.5 + opening - curve;

			// Distance outside the visible opening.
			float top_alpha = 1.0 - smoothstep(top_edge, top_edge + 0.05, uv.y);
			float bottom_alpha = smoothstep(bottom_edge - 0.05, bottom_edge, uv.y);

			col = mix(col, lid_color, clamp(max(top_alpha, bottom_alpha), 0.0, 1.0));
		}
	}

	COLOR = vec4(col, alpha);
}
