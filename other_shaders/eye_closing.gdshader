shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Fully open at progress 0, so the lids contribute nothing. Written as a
	// branch around the body rather than an early `return`: Godot rejects
	// `return` inside the fragment processor function outright ("Using 'return'
	// in the 'fragment' processor function is incorrect"), which failed the
	// whole shader to compile -- so the eyelids never drew at all.
	float alpha = 0.0;

	if (progress > 0.0) {
		vec2 uv = UV;

		float opening = 0.5 * (1.0 - progress);

		// Slightly curved eyelids.
		float x = abs(uv.x - 0.5) * 2.0;
		float curve = 0.035 * x * x;

		float top_edge = 0.5 - opening + curve;
		float bottom_edge = 0.5 + opening - curve;

		// Distance outside the visible opening.
		float top_alpha = 1.0 - smoothstep(top_edge, top_edge + 0.05, uv.y);
		float bottom_alpha = smoothstep(bottom_edge - 0.05, bottom_edge, uv.y);

		alpha = max(top_alpha, bottom_alpha);
	}

	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
