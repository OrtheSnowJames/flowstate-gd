shader_type canvas_item;

// Full-screen blur for the menu's Transition autoload (see transition.gd) --
// the same cheap mipmap-LOD blur technique as
// other_shaders/eye_closing.gdshader, split out with none of that shader's
// vignette/murk/eyelid logic: this is purely "blur (and slightly darken) the
// scene behind this ColorRect," driven by a single `amount` param so one
// tween can bring the whole effect in and out, same idiom as eye_closing's
// `progress`.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// 0 = invisible, no blur; 1 = fully blurred and darkened. This is the one
// thing Transition actually tweens.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// Mip level sampled at amount = 1. Same 0..6 range as eye_closing's own
// blur_amount for a comparable feel.
uniform float max_blur : hint_range(0.0, 6.0) = 4.0;
// Flat darkening mixed in on top of the blurred scene, scaled by amount --
// keeps status text (see transition.gd's Label) readable against whatever
// happens to be behind it.
uniform vec3 darken_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float darken_amount : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	// SCREEN_UV, not UV -- keeps the blur aligned with the actual screen
	// regardless of how this ColorRect is sized/anchored, same reasoning as
	// eye_closing.gdshader.
	vec3 scene = textureLod(screen_texture, SCREEN_UV, amount * max_blur).rgb;
	vec3 col = mix(scene, darken_color, darken_amount * amount);
	// alpha = amount: at 0 the ColorRect is fully transparent (blur_amount=0
	// would look identical to the real screen anyway, but this also skips
	// drawing it at all), at 1 it fully covers whatever's behind it.
	COLOR = vec4(col, amount);
}
