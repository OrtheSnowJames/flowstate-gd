shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform vec4  tint       : source_color           = vec4(0.03, 0.18, 0.32, 0.6);
uniform float wave_speed : hint_range(0.0, 10.0)  = 3.0;
uniform float wave_freq  : hint_range(0.0, 20.0)  = 10.0;
uniform float wave_width : hint_range(0.0, 5.0)   = 0.5;
uniform float strength   : hint_range(0.0, 1.0)   = 1.0;

void fragment() {
	vec2 offset;
	offset.x = cos((TIME * wave_speed) + SCREEN_UV.x + SCREEN_UV.y * wave_freq * 2.0) * wave_width * 0.01 * strength;
	offset.y = sin((TIME * wave_speed) + SCREEN_UV.y + SCREEN_UV.x * wave_freq)       * wave_width * 0.01 * strength;

	vec3 screen = texture(SCREEN_TEXTURE, SCREEN_UV + offset).rgb;
	vec3 col    = mix(screen, screen * tint.rgb, tint.a * strength);
	COLOR = vec4(col, 1.0);
}
