shader_type canvas_item;

// full screen blur for the menus transition autoload see transition gd the same cheap
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// 0 invisible no blur 1 fully blurred and darkened this is the one thing
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// mip level sampled at amount 1 same 0 6 range as eye_closings own blur_amount
uniform float max_blur : hint_range(0.0, 6.0) = 4.0;
// flat darkening mixed in on top of the blurred scene scaled by amount keeps
uniform vec3 darken_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float darken_amount : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	// screen_uv not uv keeps the blur aligned with the actual screen regardless of how
	vec3 scene = textureLod(screen_texture, SCREEN_UV, amount * max_blur).rgb;
	vec3 col = mix(scene, darken_color, darken_amount * amount);
	// alpha amount at 0 the colorrect is fully transparent blur_amount 0 would look identical
	COLOR = vec4(col, amount);
}
