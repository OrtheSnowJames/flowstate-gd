shader_type particles;

uniform float ring_radius     : hint_range(0.1, 5.0)  = 0.9;
uniform float velocity_up_min : hint_range(0.0, 20.0) = 6.0;
uniform float velocity_up_max : hint_range(0.0, 20.0) = 10.0;
uniform float velocity_out_min : hint_range(0.0, 10.0) = 3.0;
uniform float velocity_out_max : hint_range(0.0, 10.0) = 6.0;
uniform vec3  gravity = vec3(0.0, -14.0, 0.0);
uniform float scale_min : hint_range(0.1, 5.0) = 1.0;
uniform float scale_max : hint_range(0.1, 5.0) = 2.0;

uint uhash(uint x) {
	x ^= x >> 16u;
	x *= 0x45d9f3bu;
	x ^= x >> 16u;
	return x;
}

float frand(uint seed) {
	return float(uhash(seed)) / 4294967295.0;
}

void start() {
	uint s = NUMBER * 1973u ^ 9277u;

	float angle = frand(s) * 6.28318530718;
	vec3 outward = vec3(cos(angle), 0.0, sin(angle));

	// Place on ring
	float sc = mix(scale_min, scale_max, frand(s + 1u));
	TRANSFORM[0] = vec4(sc,  0.0, 0.0, 0.0);
	TRANSFORM[1] = vec4(0.0, sc,  0.0, 0.0);
	TRANSFORM[2] = vec4(0.0, 0.0, sc,  0.0);
	TRANSFORM[3] = vec4(outward * ring_radius, 1.0);

	// Radially outward + upward velocity — this is the WW crown lean
	float v_up  = mix(velocity_up_min,  velocity_up_max,  frand(s + 2u));
	float v_out = mix(velocity_out_min, velocity_out_max, frand(s + 3u));
	VELOCITY = outward * v_out + vec3(0.0, v_up, 0.0);

	COLOR    = vec4(1.0, 1.0, 1.0, 1.0);
	CUSTOM.z = 0.0;
	ACTIVE   = true;
}

void process() {
	CUSTOM.z += DELTA;
	float t = clamp(CUSTOM.z / LIFETIME, 0.0, 1.0);

	VELOCITY      += gravity * DELTA;
	TRANSFORM[3]   = vec4(TRANSFORM[3].xyz + VELOCITY * DELTA, 1.0);

	// Hold full opacity, then fade out in the last 30%
	COLOR.a = 1.0 - smoothstep(0.7, 1.0, t);
}
