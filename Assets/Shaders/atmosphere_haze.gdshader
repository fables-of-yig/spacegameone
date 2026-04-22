shader_type canvas_item;
render_mode blend_mix, unshaded;

// Per-scanline atmosphere haze gradient. Generic colored-fog overlay that
// sits in an EffectLayer CanvasLayer above the gameplay. Produces:
//   - 40 solid top scanlines at full alpha
//   - 15 fading bands of 8 scanlines each (decreasing alpha)
//   - Fully transparent below the fade zone
//
// Fade-in is driven by the `intensity` uniform (0..1 over ~16 frames at 60fps).
// Optional alarm pulse mixes the base color toward `alarm_color` at a
// sinusoidal rate driven by `time_sec` — used during escape/emergency states.
//
// Uniforms:
//   base_color   — main haze color
//   intensity    — fade-in alpha (0..1)
//   alarm_pulse  — 0..1, enables alarm color mixing
//   time_sec     — for alarm pulse phase (seconds since attach)
//   alarm_color  — color mixed in when alarm_pulse > 0

uniform vec4 base_color : source_color = vec4(0.78, 0.84, 0.92, 1.0);
uniform float intensity = 1.0;
uniform float alarm_pulse = 0.0;
uniform float time_sec = 0.0;
uniform vec4 alarm_color : source_color = vec4(1.0, 0.18, 0.12, 1.0);

const float SOLID_ROWS = 40.0;
const float FADE_BANDS = 15.0;
const float BAND_HEIGHT = 8.0;
const float SCREEN_H = 224.0;

void fragment() {
    float row = UV.y * SCREEN_H;
    float a;
    if (row < SOLID_ROWS) {
        a = 1.0;
    } else if (row < SOLID_ROWS + FADE_BANDS * BAND_HEIGHT) {
        float band = floor((row - SOLID_ROWS) / BAND_HEIGHT);
        a = 1.0 - (band + 1.0) / FADE_BANDS;
    } else {
        a = 0.0;
    }
    a *= intensity * 0.55;

    vec4 col = base_color;
    if (alarm_pulse > 0.0) {
        float pulse = 0.5 + 0.5 * sin(time_sec * 6.2831);
        col = mix(col, alarm_color, alarm_pulse * pulse);
    }
    COLOR = vec4(col.rgb, a * col.a);
}
