extends Node3D
## A small ornamental fish (prepared by tools/prepare_tycho_fish.py) that
## wanders within an elliptical roam area. The source model has no skeleton,
## so its swim cycle is procedural: the vertex shader sends a travelling wave
## through the tail while this controller adds body roll, pitch and a gentle
## vertical bob. The head remains stable enough that steering stays readable.
const ASSETS := "res://assets/colonies/tycho/modules/"
const SWIM_SHADER := preload("res://shaders/pond_fish.gdshader")
var center: Vector2
var radii: Vector2
var water_y: float
var speed: float
var cruise_speed: float
var rng := RandomNumberGenerator.new()
var target: Vector2
var bob_phase: float
var bob_speed: float
var swim_phase: float
var body: Node3D
var visual_meshes: Array[MeshInstance3D] = []

func _ready() -> void:
	rng.randomize()
	bob_phase = rng.randf() * TAU
	bob_speed = rng.randf_range(1.0, 1.6)
	swim_phase = rng.randf() * TAU
	cruise_speed = rng.randf_range(0.35, 0.55)
	speed = cruise_speed
	body = load(ASSETS + "fish.glb").instantiate() as Node3D
	body.name = "Body"
	add_child(body)
	_install_swim_materials()
	target = center
	position = Vector3(center.x, water_y, center.y)
	_pick_target()

func _install_swim_materials() -> void:
	visual_meshes.assign(body.find_children("*", "MeshInstance3D", true, false))
	for mesh in visual_meshes:
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var animated := ShaderMaterial.new()
			animated.shader = SWIM_SHADER
			animated.set_shader_parameter("albedo_texture", source.albedo_texture)
			animated.set_shader_parameter("normal_texture", source.normal_texture)
			animated.set_shader_parameter("metallic_texture", source.metallic_texture)
			animated.set_shader_parameter("albedo_tint", source.albedo_color)
			animated.set_shader_parameter("metallic", source.metallic)
			animated.set_shader_parameter("roughness", source.roughness)
			mesh.set_surface_override_material(surface, animated)
		mesh.set_instance_shader_parameter("swim_phase", swim_phase)
		mesh.set_instance_shader_parameter("swim_rate", rng.randf_range(4.2, 5.8))
		mesh.set_instance_shader_parameter("swim_strength", rng.randf_range(0.82, 1.12))

func _pick_target() -> void:
	var angle := rng.randf() * TAU
	var r := sqrt(rng.randf())
	target = center + Vector2(cos(angle) * radii.x * r, sin(angle) * radii.y * r)
	if cruise_speed > 0.0:
		speed = cruise_speed * rng.randf_range(1.12, 1.32)

func _process(delta: float) -> void:
	var here := Vector2(position.x, position.z)
	var to_target := target - here
	var dist := to_target.length()
	if dist < 0.25:
		_pick_target()
		return
	var direction := to_target / dist
	# Briefly accelerate after choosing a destination, then settle back into a
	# varied cruise. This keeps a group from looking mechanically synchronized.
	speed = move_toward(speed, cruise_speed, delta * 0.18)
	here += direction * speed * delta
	bob_phase += delta * bob_speed
	position = Vector3(here.x, water_y + sin(bob_phase) * 0.03, here.y)
	# The model's head points along local -X (not Godot's conventional -Z).
	var yaw := atan2(direction.y, -direction.x)
	var turn_error := wrapf(yaw - rotation.y, -PI, PI)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 2.5, 0.0, 1.0))
	body.rotation.x = lerpf(body.rotation.x, sin(bob_phase * 1.7 + swim_phase) * 0.07 + turn_error * 0.10, clampf(delta * 3.0, 0.0, 1.0))
	body.rotation.z = lerpf(body.rotation.z, cos(bob_phase + swim_phase) * 0.035, clampf(delta * 2.0, 0.0, 1.0))
