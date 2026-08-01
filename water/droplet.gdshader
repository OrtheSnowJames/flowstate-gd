shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

// Vivid water-blue droplet. Reads the per-particle COLOR so the process
// material's color_ramp can fade each droplet out over its life via COLOR.a.
void fragment() {
	float facing = abs(dot(normalize(VIEW), NORMAL));

	vec3 deep  = vec3(0.05, 0.35, 0.95); // core blue
	vec3 light = vec3(0.45, 0.78, 1.0);  // lighter blue toward the center
	vec3 col = mix(deep, light, pow(facing, 1.4));

	// Bright wet rim so droplets read as glossy water beads.
	float rim = pow(1.0 - facing, 2.0);
	col = mix(col, vec3(0.85, 0.95, 1.0), rim * 0.55);

	ALBEDO = col * COLOR.rgb;
	ALPHA  = clamp(COLOR.a, 0.0, 1.0);
}
