shader_type spatial;
render_mode unshaded, blend_mix, cull_back;

void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 2.0);
	vec3 tint = mix(vec3(0.18, 0.7, 0.95), vec3(0.85, 1.0, 1.0), rim);
	ALBEDO = tint;
	EMISSION = tint * rim * 0.5;
	ALPHA = 0.08 + rim * 0.85;
}
