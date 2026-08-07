# FluidBox — interactive 3D water for Godot 4

A real-time heightfield fluid: a genuine 2D wave-equation simulation running on
the GPU, rendered as displaced 3D geometry. Not a scrolling-normal-map fake —
waves propagate, reflect off pool walls, interfere, and diffract. Rigidbodies
splash, carve wakes and push bow waves scaled by **mass × velocity**, and a
gameplay API lets you inject directed "water attack" waves from code.

**Requires:** Godot **4.2+**, **Forward+** renderer (Mobile also works;
Compatibility lacks the depth texture the surface shader uses).

## Quick start

1. Copy the `godot_fluid_water` folder into your project root (`res://godot_fluid_water`).
2. Open and run `demo/demo.tscn`.
   - **LMB** throw a light ball · **MMB** heavy cannonball (compare the splashes)
   - **F** water push attack — a travelling wave fired from the cursor
   - **RMB drag** orbit · **wheel** zoom

## Using it in your game

```gdscript
var water := preload("res://godot_fluid_water/fluid_box.gd").new()
water.size = Vector3(12, 2, 8)     # x/z = surface extent, y = depth below surface
add_child(water)
water.global_position = Vector3(0, 1.8, 0)   # node origin = the rest surface
```

That's it. Any `RigidBody3D` (or `CharacterBody3D` with a `velocity`) that
enters the volume automatically produces:

- **Entry splash** — impulse depth and particle count/size/speed scale with
  momentum `mass · speed` (via `sqrt`, so an anvil ≫ a pebble without blowing up).
- **Wake + bow wave** — while moving horizontally, the body carves a depression
  and pushes a **dipole wave ahead of itself** that keeps travelling after the
  body slows. Move fast through the water and you shove a wave forward — for free.
- **Bobbing ripples** and a small **exit splash** when jumping out.

The water never modifies the bodies (no buoyancy forces) — it only reacts.

## Gameplay API (pool-fighting hooks)

```gdscript
# Directed attack wave: crest travels along `dir`. dipole=1 makes it travel,
# elongation stretches the point into a wave FRONT.
water.add_impulse(hit_pos, 0.3, 0.6, attack_dir, 1.0, 2.0)

# Symmetric poke (negative = press down, positive = raise):
water.add_impulse(explosion_pos, -0.4, 1.5)

# Cosmetic splash + ripple (bullet hits, spells). power ≈ mass·speed:
water.splash_at(hit_pos, 80.0, 0.3)

# Wave height for gameplay (set enable_height_queries = true first):
var h := water.get_height_at(player.global_position)

# React to impacts:
water.body_splashed.connect(func(body, power): print(body, " hit at ", power))
```

For a charged attack, scale `strength` (0.05 weak → 0.45 max) and `elongation`
(0 = jab, 3 = wide sweeping front). For a shockwave, call `add_impulse` with a
large radius and no direction.

## How it works (why it looks real)

- **Simulation** (`shaders/water_sim.gdshader`): the discrete 2D wave equation
  `∂²h/∂t² = c²∇²h` with damping, ping-ponged between two `SubViewport`s
  (RGBA16F). Clamped boundaries mean waves **reflect off the pool walls** —
  correct behaviour for a pool, and it makes fights messy in a good way.
  Impulses are injected as elliptical Gaussians in **world metres**; the
  dipole term (derivative of the Gaussian along the motion direction) is what
  produces physically-shaped travelling bow waves.
- **Surface** (`shaders/water_surface.gdshader`): a subdivided plane displaced
  in the vertex shader (plus Gerstner-style horizontal chop so crests pinch),
  normals computed analytically from the height gradient, screen-space
  refraction, Beer–Lambert depth absorption against the scene depth buffer,
  and foam driven by the sim's *velocity* channel (agitated water foams, still
  water doesn't) plus crests and shorelines.
- **Splashes**: a pool of one-shot `GPUParticles3D`; amount, scale, launch
  speed and lifetime are lerped by clamped momentum.
- **Robustness**: sim values are clamped every step (can't explode), impulses
  are capped at 16/frame keeping the strongest, freed/teleported bodies are
  handled, and non-square pools get aspect-corrected sim grids so waves travel
  at the same speed in every direction.

## Tuning cheat-sheet

| Property | Effect |
|---|---|
| `sim_resolution` | Ripple detail. 192 cheap, 256 default, 320+ crisp. |
| `wave_transfer` | Wave speed. Keep ≤ 0.5 (stability limit of the scheme). |
| `wave_damping` | 0.999 = ocean swell that lingers; 0.99 = thick, calm pool. |
| `edge_damping` | 0 = mirror walls (dramatic reflections); 1 = soft absorbing rim. |
| `amplitude` | Physical wave height in metres. |
| `splash_strength` / `wake_strength` | Global gain on body interactions. |
| `min_splash_speed` | Below this entry speed, no particle burst (just ripples). |
| Surface material | Colours, absorption, foam thresholds, micro-ripple detail. |

## Performance

The sim is one fullscreen pass over a ~256×176 fp16 texture per frame —
well under 0.1 ms on any discrete GPU. The main cost is the surface mesh
(`mesh_resolution`, default 160 ≈ 26k verts) and refraction. Leave
`enable_height_queries` off unless needed: GPU→CPU readback stalls ~0.3–1 ms
every `readback_interval` frames.

## Notes & extensions

- The surface is culled from below (`cull_back`); underwater camera rendering
  is a separate effect (fog volume + flipped surface) if you need it.
- Want buoyancy later? `get_height_at()` gives you wave height; apply
  `force = ρ·g·submerged_volume` upward per body — the sim side needs no changes.
- Multiple FluidBoxes in one scene are fine; each owns its own sim.
