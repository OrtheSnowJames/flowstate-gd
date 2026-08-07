shader_type spatial;
render_mode cull_disabled, blend_mix;

// Translucent water wave: refracts the world behind it, tints blue with depth,
// and whitens into foam along the crest and grazing edges.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float refraction : hint_range(0.0, 0.2) = 0.05;
uniform float alpha_mul = 1.0;                                  // fade in/out
uniform vec3 deep_color : source_color = vec3(0.03, 0.25, 0.55);
uniform vec3 shallow_color : source_color = vec3(0.25, 0.60, 0.85);

void fragment() {
	float h = clamp(UV.y, 0.0, 1.0);              // 0 at base, 1 at the crest

	// Refraction: sample the background pushed sideways by the surface normal.
	vec2 suv = SCREEN_UV + NORMAL.xy * refraction;
	vec3 behind = texture(screen_tex, suv).rgb;

	vec3 water = mix(shallow_color, deep_color, h);
	float fres = pow(1.0 - clamp(abs(dot(normalize(VIEW), NORMAL)), 0.0, 1.0), 3.0);
	float foam = smoothstep(0.72, 1.0, h);

	// Translucent water over the refracted background, whitened by foam + rim.
	vec3 col = mix(behind, water, 0.25);
	col = mix(col, vec3(1.0), clamp(foam + fres * 0.35, 0.0, 1.0));

	ALBEDO    = col;
	ROUGHNESS = 0.15;
	ALPHA     = clamp((0.5 + h * 0.35 + foam * 0.5) * alpha_mul, 0.0, 1.0);
}
