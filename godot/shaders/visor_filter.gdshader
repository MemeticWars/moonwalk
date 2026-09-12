shader_type canvas_item;
// First-person stand-in for the visor: a gold darkening that hangs from the top of
// the view and creeps in from both sides, fading before the centre so the HUD and
// the forward view stay readable. `shade` is the same smoothed value that drives
// the 3D visor.
uniform float shade : hint_range(0.0, 1.0) = 0.0;
uniform vec3 gold : source_color = vec3(0.22, 0.13, 0.02);
uniform float reach = 0.6;
uniform float sides = 0.28;
uniform float strength = 0.72;
void fragment() {
    float top = smoothstep(reach, 0.0, UV.y);
    float side = smoothstep(sides, 0.0, min(UV.x, 1.0 - UV.x));
    COLOR = vec4(gold, max(top, side) * strength * shade);
}
