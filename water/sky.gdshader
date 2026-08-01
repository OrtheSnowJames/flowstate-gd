// WindWakerSky_final.gdshader

shader_type sky;
render_mode use_half_res_pass;

// ─── Sky Colors ───────────────────────────────────────────────────────────
uniform vec4 sky_top      : source_color = vec4(0.349, 0.651, 0.804, 1.0);
uniform vec4 sky_bottom   : source_color = vec4(0.529, 0.773, 0.875, 1.0);

// ─── Cloud Colors ─────────────────────────────────────────────────────────
uniform vec4 cloud_light  : source_color = vec4(0.937, 0.957, 0.973, 1.0);
uniform vec4 cloud_mid    : source_color = vec4(0.851, 0.902, 0.933, 1.0);
uniform vec4 cloud_shadow : source_color = vec4(0.741, 0.820, 0.875, 1.0);

// ─── Cloud Shape ──────────────────────────────────────────────────────────
uniform float cloud_scale_x  = 2.5;
uniform float cloud_scale_y  = 1.2;
uniform float cloud_coverage = 0.52;
uniform float toon_steps    = 3.0;
uniform float scroll_speed  = 0.015;
uniform float horizon_blend = 0.12;

// ─── Brightness ───────────────────────────────────────────────────────────
uniform float brightness        : hint_range(0.0, 3.0) = 1.0;
uniform float sky_brightness_mix : hint_range(0.0, 1.0) = 0.25;

// ─── 3D Noise ─────────────────────────────────────────────────────────────
float hash3(vec3 p) {
    p = fract(p * vec3(127.1, 311.7, 74.7));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y * p.z);
}

float noise3(vec3 p) {
    vec3 i = floor(p); vec3 f = fract(p);
    vec3 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash3(i),               hash3(i+vec3(1,0,0)), u.x),
            mix(hash3(i+vec3(0,1,0)), hash3(i+vec3(1,1,0)), u.x), u.y),
        mix(mix(hash3(i+vec3(0,0,1)), hash3(i+vec3(1,0,1)), u.x),
            mix(hash3(i+vec3(0,1,1)), hash3(i+vec3(1,1,1)), u.x), u.y),
        u.z);
}

float fbm3(vec3 p) {
    float v = 0.0; float a = 0.5;
    for (int i = 0; i < 2; i++) {
        v += a * noise3(p);
        p  = p * 2.1 + vec3(1.7, 9.2, 3.5);
        a *= 0.5;
    }
    return v;
}

void sky() {
    vec3 dir = normalize(EYEDIR);
    float lat = dir.y;

    // Smooth sky gradient — no step(), just a clean mix
    vec4 sky = mix(sky_bottom, sky_top, clamp(lat, 0.0, 1.0));

    float t = TIME * scroll_speed;
    vec3 cp = vec3(
        dir.x * cloud_scale_x + t,
        dir.y * cloud_scale_y,
        dir.z * cloud_scale_x
    );

    float above = smoothstep(0.0, horizon_blend, lat);

    float raw        = fbm3(cp) * above;
    float raw_shadow = fbm3(cp + vec3(0.0, 0.18, 0.0)) * above;

    // Hard cloud edges — no glow
    float cloud  = step(cloud_coverage, raw);
    float shadow = step(cloud_coverage + 0.08, raw_shadow) * cloud;

    // Flat composite
    vec4 col = sky;
    if (cloud  > 0.5) col = cloud_light;
    if (shadow > 0.5) col = cloud_shadow;

    // Single brightness: full on ground, partial on sky
    float ground_factor = clamp(1.0 - lat, 0.0, 1.0);
    float b = mix(1.0, brightness, mix(sky_brightness_mix, 1.0, ground_factor));

    COLOR = col.rgb * b;
}
