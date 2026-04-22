shader_type canvas_item;

uniform sampler2D ground_atlas : filter_nearest, repeat_enable;
uniform vec2 atlas_size_px = vec2(512.0, 512.0);
uniform float cam_height = 120.0;
uniform float cam_angle = 0.0;
uniform vec2 cam_world_pos = vec2(256.0, 256.0);
uniform float horizon = 0.35;
uniform float fov_scale = 1.5;
uniform vec3 fog_color = vec3(0.05, 0.08, 0.15);
uniform float fog_strength = 2.5;

void fragment() {
	float t = UV.y - horizon;
	if (t <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		float depth = cam_height / t;
		float screen_x = (UV.x - 0.5) * fov_scale;

		float ca = cos(cam_angle);
		float sa = sin(cam_angle);
		float wx = cam_world_pos.x + depth * sa + screen_x * depth * ca;
		float wy = cam_world_pos.y + depth * ca - screen_x * depth * sa;

		vec2 tex_uv = vec2(wx, wy) / atlas_size_px;
		COLOR = texture(ground_atlas, tex_uv);

		float fog = clamp(t * fog_strength, 0.0, 1.0);
		COLOR.rgb = mix(fog_color, COLOR.rgb, fog);
	}
}
