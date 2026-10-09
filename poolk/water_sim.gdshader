// water_sim gdshader gpu heightfield fluid simulation discrete 2d wave equation ping ponged between two
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D prev_tex : filter_linear, repeat_disable;

uniform vec2  texel      = vec2(0.00390625); // 1 sim resolution
uniform vec2  world_size = vec2(10.0, 10.0); // metres covered by the sim
// c dt dx of the discrete scheme must stay 0 5 or the sim
uniform float transfer   : hint_range(0.02, 0.5) = 0.3;
uniform float damping    : hint_range(0.90, 1.0) = 0.996; // velocity kept per step
uniform float edge_damping : hint_range(0.0, 1.0) = 0.35; // 0 perfect mirror walls
uniform float edge_width : hint_range(0.005, 0.2) = 0.04; // rim band uv
uniform bool  reset      = false;

// impulses injected this frame by fluidbox gd all units are metres
uniform int  impulse_count = 0;
// impulses i xy centre metres from sim corner z radius m w strength signed
uniform vec4 impulses[16];
// impulse_dirs i xy unit direction z elongation stretch along dir w dipole mix 0
uniform vec4 impulse_dirs[16];

float height_at(vec2 uv) {
	// clamped sampling reflective boundary condition
	uv = clamp(uv, texel * 0.5, vec2(1.0) - texel * 0.5);
	return texture(prev_tex, uv).r - 0.5;
}

void fragment() {
	if (reset) {
		COLOR = vec4(0.5, 0.5, 0.0, 1.0);
	} else {
		vec2 uv = UV;
		vec4 prev = texture(prev_tex, uv);
		float h = prev.r - 0.5;
		float v = prev.g - 0.5;

		// wave equation acceleration c laplacian h
		float lap = height_at(uv - vec2(texel.x, 0.0))
		          + height_at(uv + vec2(texel.x, 0.0))
		          + height_at(uv - vec2(0.0, texel.y))
		          + height_at(uv + vec2(0.0, texel.y))
		          - 4.0 * h;
		v += lap * transfer;

		// damping energy loss viscosity
		v *= damping;

		// extra damping in a thin band at the rim softens wall reflections a touch
		float rim = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
		float rim_f = 1.0 - smoothstep(0.0, edge_width, rim);
		v *= 1.0 - rim_f * edge_damping * 0.15;

		h += v;

		// impulse injection in world metres so shapes are undistorted even when the pool is
		vec2 pos_m = uv * world_size;
		for (int i = 0; i < impulse_count; i++) {
			vec2  c    = impulses[i].xy;
			float rad  = max(impulses[i].z, 0.01);
			float str  = impulses[i].w;
			vec2  dir  = impulse_dirs[i].xy;
			float elon = impulse_dirs[i].z;
			float dip  = impulse_dirs[i].w;

			vec2 off = pos_m - c;
			float along = dot(off, dir);
			vec2  perp  = off - dir * along;
			// elliptical gaussian stretched along the motion direction
			float a  = along / (rad * (1.0 + elon));
			float b  = length(perp) / rad;
			float d2 = a * a + b * b;
			if (d2 < 6.0) {
				float g = exp(-d2 * 4.0);
				// monopole symmetric poke entry splash depression dipole crest pushed ahead trough behind travelling wave
				float shape = mix(g, 2.0 * a * g, dip);
				h += str * shape;
			}
		}

		// safety clamps keep the sim un explodable no matter what gameplay code throws at
		h = clamp(h, -0.5, 0.5);
		v = clamp(v, -0.25, 0.25);

		COLOR = vec4(h + 0.5, v + 0.5, 0.0, 1.0);
	}
}
