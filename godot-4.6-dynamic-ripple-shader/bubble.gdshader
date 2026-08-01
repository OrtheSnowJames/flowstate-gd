shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform float alpha_scale : hint_range(0.0, 1.0) = 1.0;
uniform float water_y = 99999.0;
uniform float surface_fade_range : hint_range(0.1, 2.0) = 0.6;

varying float v_world_y;

void vertex() {
	v_world_y = MODEL_MATRIX[3].y;
}

void fragment() {
	float facing = abs(dot(normalize(VIEW), NORMAL));
	float rim    = 1.0 - facing;
	float bubble = pow(rim, 1.6);

	vec3  light  = normalize(vec3(0.5, 0.8, 0.3));
	vec3  half_v = normalize(normalize(VIEW) + light);
	float spec   = pow(max(0.0, dot(NORMAL, half_v)), 36.0);

	vec3 col = mix(vec3(0.55, 0.55, 0.58), vec3(1.0), spec);

	float surface_fade = 1.0 - smoothstep(water_y - surface_fade_range, water_y, v_world_y);

	ALBEDO = col;
	ALPHA  = clamp(bubble * 0.55 + spec * 0.5, 0.0, 1.0) * alpha_scale * surface_fade;
}
