#[compute]
#version 450

// =============================================================================
// sph.glsl — GPU Smoothed-Particle-Hydrodynamics fluid step.
//
// A genuine SPH solver (Müller et al. 2003 kernels). Neighbour search is
// brute-force O(N^2) on purpose: it has no spatial-hash bookkeeping to get
// wrong, and the GPU eats a few thousand particles squared without noticing.
//
// Run twice per substep via the `stage` push constant:
//   stage 0 -> density + pressure for every particle
//   stage 1 -> pressure/viscosity/gravity forces, integrate, collide
// A memory barrier between the two guarantees every density is written before
// any force reads it.
// =============================================================================

layout(local_size_x = 64) in;

struct Particle {
	vec4 pos;   // xyz position (+w pad)
	vec4 vel;   // xyz velocity (+w pad)
	vec4 aux;   // x = density, y = pressure, zw unused
};

layout(set = 0, binding = 0, std430) restrict buffer Particles {
	Particle p[];
} P;

layout(set = 0, binding = 1, std430) restrict buffer Params {
	float dt;
	float count;
	float h;             // smoothing radius
	float rest_density;
	float stiffness;     // pressure stiffness (gas constant)
	float viscosity;
	float mass;
	float _pad0;
	vec4 gravity;        // xyz
	vec4 bmin;           // box lower corner (local space) + w pad
	vec4 bmax;           // box upper corner (local space) + w pad
	vec4 player;         // xyz = player centre (local), w = radius (0 disables)
} U;

layout(push_constant, std430) uniform Push {
	int stage;
	int _p1;
	int _p2;
	int _p3;
} pc;

const float PI = 3.14159265358979;

void main() {
	uint i = gl_GlobalInvocationID.x;
	uint N = uint(U.count);
	if (i >= N) return;

	float h  = U.h;
	float h2 = h * h;

	if (pc.stage == 0) {
		// -------- density & pressure --------------------------------------
		vec3 xi = P.p[i].pos.xyz;
		float poly6 = 315.0 / (64.0 * PI * pow(h, 9.0));
		float density = 0.0;
		for (uint j = 0u; j < N; j++) {
			vec3 rij = xi - P.p[j].pos.xyz;
			float r2 = dot(rij, rij);
			if (r2 < h2) {
				float d = h2 - r2;
				density += U.mass * poly6 * d * d * d;
			}
		}
		density = max(density, U.rest_density * 0.05);
		float pressure = max(U.stiffness * (density - U.rest_density), 0.0);
		P.p[i].aux.x = density;
		P.p[i].aux.y = pressure;
	} else {
		// -------- forces, integrate, collide ------------------------------
		vec3 xi = P.p[i].pos.xyz;
		vec3 vi = P.p[i].vel.xyz;
		float di = max(P.p[i].aux.x, 1e-4);
		float pi = P.p[i].aux.y;

		float spiky_grad = -45.0 / (PI * pow(h, 6.0));
		float visc_lap   =  45.0 / (PI * pow(h, 6.0));

		vec3 f_press = vec3(0.0);
		vec3 f_visc  = vec3(0.0);

		for (uint j = 0u; j < N; j++) {
			if (j == i) continue;
			vec3 rij = xi - P.p[j].pos.xyz;
			float r2 = dot(rij, rij);
			if (r2 < h2 && r2 > 1e-9) {
				float r = sqrt(r2);
				vec3 dir = rij / r;
				float dj = max(P.p[j].aux.x, 1e-4);
				float pj = P.p[j].aux.y;
				float term = (h - r);
				// symmetric pressure force
				f_press += -dir * U.mass * (pi + pj) / (2.0 * dj) * spiky_grad * term * term;
				// viscosity force
				f_visc  += U.viscosity * U.mass * (P.p[j].vel.xyz - vi) / dj * visc_lap * term;
			}
		}

		vec3 force = f_press + f_visc + U.gravity.xyz * di;
		vec3 accel = force / di;
		vi += accel * U.dt;

		// clamp speed so a bad frame can't launch a particle to infinity
		float vmax = 40.0;
		float sp = length(vi);
		if (sp > vmax) vi *= vmax / sp;

		// --- player collision: shove particles out of the body sphere -----
		if (U.player.w > 0.0) {
			vec3 pr = xi - U.player.xyz;
			float pd = length(pr);
			if (pd < U.player.w && pd > 1e-5) {
				vec3 nrm = pr / pd;
				xi = U.player.xyz + nrm * U.player.w;
				float vn = dot(vi, nrm);
				if (vn < 0.0) vi -= nrm * vn * 1.6;   // bounce outward
			}
		}

		xi += vi * U.dt;

		// --- box boundaries with restitution + a little friction ----------
		float rest = 0.35;
		if (xi.x < U.bmin.x) { xi.x = U.bmin.x; vi.x = abs(vi.x) * rest; vi.yz *= 0.98; }
		if (xi.x > U.bmax.x) { xi.x = U.bmax.x; vi.x = -abs(vi.x) * rest; vi.yz *= 0.98; }
		if (xi.y < U.bmin.y) { xi.y = U.bmin.y; vi.y = abs(vi.y) * rest; vi.xz *= 0.98; }
		if (xi.y > U.bmax.y) { xi.y = U.bmax.y; vi.y = -abs(vi.y) * rest; vi.xz *= 0.98; }
		if (xi.z < U.bmin.z) { xi.z = U.bmin.z; vi.z = abs(vi.z) * rest; vi.xy *= 0.98; }
		if (xi.z > U.bmax.z) { xi.z = U.bmax.z; vi.z = -abs(vi.z) * rest; vi.xy *= 0.98; }

		P.p[i].vel.xyz = vi;
		P.p[i].pos.xyz = xi;
	}
}
