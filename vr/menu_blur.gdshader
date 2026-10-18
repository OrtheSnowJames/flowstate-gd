shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 1.0;

void fragment() {
	vec2 step_uv = 4.0 / vec2(textureSize(screen_texture, 0));
	vec3 color = vec3(0.0);
	float weight_sum = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float weight = exp(-float(x * x + y * y) * 0.4);
			color += textureLod(screen_texture, SCREEN_UV + vec2(float(x), float(y)) * step_uv, 2.0).rgb * weight;
			weight_sum += weight;
		}
	}
	ALBEDO = color / weight_sum * 0.65;
	ALPHA = amount;
}
