extends Node3D
## A small ornamental fish (prepared by tools/prepare_tycho_fish.py) that
## wanders within an elliptical roam area -- a pond, or a long thin ellipse
## standing in for a stream's narrow channel. No skeletal swim animation
## shipped with the source model; movement is a simple seek-and-retarget
## steer plus a gentle vertical bob, which reads fine at pond-watching
## distance.
const ASSETS := "res://assets/colonies/tycho/modules/"
var center: Vector2
var radii: Vector2
var water_y: float
var speed: float
var rng := RandomNumberGenerator.new()
var target: Vector2
var bob_phase: float
var bob_speed: float

func _ready() -> void:
	rng.randomize()
	bob_phase = rng.randf() * TAU
	bob_speed = rng.randf_range(1.0, 1.6)
	speed = rng.randf_range(0.35, 0.55)
	var body := load(ASSETS + "fish.glb").instantiate() as Node3D
	body.name = "Body"
	add_child(body)
	target = center
	position = Vector3(center.x, water_y, center.y)
	_pick_target()

func _pick_target() -> void:
	var angle := rng.randf() * TAU
	var r := sqrt(rng.randf())
	target = center + Vector2(cos(angle) * radii.x * r, sin(angle) * radii.y * r)

func _process(delta: float) -> void:
	var here := Vector2(position.x, position.z)
	var to_target := target - here
	var dist := to_target.length()
	if dist < 0.25:
		_pick_target()
		return
	var direction := to_target / dist
	here += direction * speed * delta
	bob_phase += delta * bob_speed
	position = Vector3(here.x, water_y + sin(bob_phase) * 0.03, here.y)
	var yaw := atan2(direction.x, direction.y)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 2.5, 0.0, 1.0))
