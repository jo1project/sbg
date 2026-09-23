shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.5;
uniform float radius : hint_range(0.0, 1.5) = 0.75;

void fragment() {
	float d = distance(UV, vec2(0.5)) * 1.414; // 0 中心 .. 1 角落
	COLOR = vec4(0.0, 0.0, 0.0, smoothstep(radius * 0.5, radius * 1.2, d) * strength);
}
