# Poolk

From pool + toolk

Poolk is the water toolkit made and used in Flowstate. It contains the water surface, body ripples, splashes, and an optional wave simulation. The toolkit does not need Flowstate's players, networking, settings, or autoloads.

## Add it to another project

1. Copy the entire `poolk` folder into your Godot project and let Godot import it. Keep the files together; internal resource paths are relative, so the folder can also live inside another folder.
2. Drag `poolk/water.tscn` from the FileSystem dock into your 3D scene.
3. Select the Water node and set **Volume > Size**. X and Z are the surface width and length; Y is the water depth.
4. Move the node to the desired water level. Its origin is the center of the surface, and its detection volume extends downward.
5. Set the water's collision mask to include the layers used by your characters and rigid bodies.
6. Add a camera, lighting, and your pool geometry, then run the scene. The water mesh and detection shape are created at runtime, so they do not appear in the editor preview.

Use the node's **Size**, not its scale, to resize the water. Keep it level and unrotated. Configure size before running; changing size after the water has been built does not rebuild its collision shape.

Poolk uses Godot > 4.6.3. Forward+ and Mobile are the only tested renderers. Compatability rendering is unsupported, but you could probably get it to work with some optimizations.

## Try the demo

Run `poolk/demo.tscn` with F6. It builds a pool, camera, lights, and the current ocean-style water without any other project files.

- Left mouse: throw a light ball
- Middle mouse: throw a heavy ball
- F: inject a water ripple
- Right mouse drag: orbit
- Mouse wheel: zoom

## Create water from code

```gdscript
var water = preload("res://poolk/water.tscn").instantiate() # or poolk path
water.size = Vector3(12, 2, 8)
water.position = Vector3(0, 1.8, 0)
add_child(water)
```

Disclaimer: rigid bodies and character bodies with a `velocity` property produce ripples and splashes when they move through the water. Water reacts to bodies but does not apply buoyancy, swimming, damage, or movement forces. Add those in your own gameplay scripts. Pool walls and floors also need their own collision bodies.

## Appearance

`water.tscn` enables **Ocean Surface** and uses a mesh resolution of 140, matching Flowstate's current surface setup.

Edit `ocean_material.tres` to change its default look:

| Shader parameter | Controls |
|---|---|
| `color_shallow`, `color_deep` | Water colors and opacity |
| `color_foam` | Foam color |
| `normal_strength` | Surface normal detail |
| `wave_scale`, `wave_speed`, `water_world_scale` | Surface pattern scale and movement |
| `wave_height` | Background swell height |
| `ripple_radius`, `ripple_speed`, `ripple_freq` | Body ripple appearance |
| `trail_count` | Ripple history slots; keep it even and between 2 and 128 |

Each water instance duplicates the material, keeping its ripple history separate. `ocean_surface.gd` advances the wave clock and tracks body trails. `ocean.gdshader` renders the surface. The default material has background swell disabled with `wave_height = 0`.

**Mesh Resolution** controls surface subdivisions. The simulation settings, **Simple Surface**, **Refraction Strength**, **Detail Strength**, and **Surface Material Override** belong to the older simulated surface; they do not tune the ocean material.

## Ripples and splashes from code

Positions passed to these methods are world positions.

```gdscript
# add a ripple at an impact
water.add_impulse(hit_position, 0.3, 0.6)

# add a ripple and spray particles
water.splash_at(hit_position, 80.0, 0.3)

# listen for body entry splashes
water.body_splashed.connect(func(body, power):
    print(body.name, " splash power ", power))
```

In ocean mode, `add_impulse` adds a shader ripple. Its strength, radius, direction, dipole, and elongation arguments do not shape that ripple. Those controls apply to the simulated surface. `splash_at` still uses its power and radius for particles.

## Optional wave simulation

Turn **Ocean Surface** off before running to use the original (bad) heightfield simulation. In this mode, waves propagate across the surface and reflect at its rectangular edges.

| Property | Controls |
|---|---|
| `sim_resolution` | Simulation grid detail; default 256 |
| `sim_steps_per_second` | Simulation rate; default 30, separate from render FPS |
| `wave_transfer` | Wave propagation; keep at or below 0.5 |
| `wave_damping` | Energy retained per simulation step |
| `edge_damping` | How strongly the edges absorb waves |
| `amplitude` | Surface displacement scale |
| `simple_surface` | Simplifies the simulated surface rendering |
| `splash_strength`, `wake_strength` | Body interaction strength |

A directed impulse is available in this mode:

```gdscript
water.add_impulse(hit_position, 0.3, 0.6, attack_direction, 1.0, 2.0)
```

With **Enable Height Queries** enabled, `get_height_at(world_position)` returns the simulated height offset above the resting surface. Add `water.global_position.y` to get a world height. Queries use GPU readback, so leave them off unless needed. Ocean mode has no heightfield readback and returns zero.

To switch surface modes at runtime, use `water.apply_quality({"ocean_surface": false})`. This rebuilds the visual surface and resets its ripples without replacing the detection volume. Set size before initialization instead of passing it to this method.

## Flowstate integration

Flowstate's `water/ocean_fluid_bridge.gd` extends `poolk/fluid_box.gd` and adds game-specific attacks. `water/pool_scene_toggles.gd` selects the ocean surface for the arena. Those scripts stay outside the toolkit and are not needed in another project.

The scoreboard, bathroom, and diving board scenes live in `water/props`. They are game assets rather than water dependencies.
