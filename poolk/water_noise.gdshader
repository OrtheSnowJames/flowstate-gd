shader_type canvas_item;
render_mode blend_disabled, unshaded;

const float GRID_SIZE = 1024.0;

float hash21(vec2 p) {
	return fract(sin(dot(mod(p, vec2(GRID_SIZE)), vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// cache the four corners of each noise cell once
	vec2 cell = floor(UV * GRID_SIZE);
	COLOR = vec4(hash21(cell), hash21(cell + vec2(1.0, 0.0)),
		hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0, 1.0)));
}
