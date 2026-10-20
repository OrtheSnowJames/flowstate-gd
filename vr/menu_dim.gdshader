shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never;

uniform float amount = 1.0;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = clamp(amount, 0.0, 1.0) * 0.35;
}
