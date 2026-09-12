extends "res://scripts/human_controller.gd"

var helmets: Array[Node3D] = []
var visor_shade := false        # discrete target; H flips it at once
var visor_shade_amount := 0.0   # smoothed value the visor and FPP filter follow
var visor_filter: ColorRect

const VISOR_SHADE_FADE := 0.32

func _init() -> void:
	humanoid_model_path = ""
	character_name = "Agnes"
	reference_height_m = 1.8
	collision_radius_m = 0.27
	eye_height_m = 1.575
	atlas_path = "res://assets/agnes/suit_0b5bab3bba27.png"
	model_paths = [
		"res://assets/agnes/fitted/agnes_suit_Animation_Spear_Walk_withSkin.glb",
		"res://assets/agnes/fitted/agnes_suit_Animation_Running_withSkin.glb",
		"res://assets/agnes/fitted/agnes_suit_turn_left_Animation_Idle_Turn_Left_withSkin.glb",
		"res://assets/agnes/fitted/agnes_suit_turn_right_Animation_Idle_Turn_Right_withSkin.glb",
		"res://assets/agnes/fitted/agnes_suit_Animation_Idle_5_withSkin.glb",
		"res://assets/agnes/fitted/agnes_suit_Animation_Jump_Over_Obstacle_2_withSkin.glb",
		"res://assets/agnes/fitted/agnes_suit_Animation_climbing_up_wall_withSkin.glb",
		"res://assets/agnes/fitted/agnes_suit_Animation_Ladder_Climb_Finish_withSkin.glb",
		"res://assets/agnes/fitted/agnes_suit_Animation_Crawl_and_Look_Back_withSkin.glb",
		"res://assets/agnes/fitted/agnes_suit_Animation_Stand_Up2_withSkin.glb",
	]

func _ready() -> void:
	super._ready()
	for visual in visuals:
		helmets.append(preload("res://scripts/agnes_helmet.gd").attach(visual))
	# The common base scale measures the body mesh before accessories are attached.
	# Fit once more after adding the helmet so the complete suited silhouette,
	# shared by all six animation clips, is exactly the requested height.
	var suited_height := _visual_mesh_bounds(visuals[0], pivot.transform).size.y
	if suited_height > 0.01:
		pivot.scale *= reference_height_m / suited_height
	var filter_layer := CanvasLayer.new()
	filter_layer.layer = 0
	add_child(filter_layer)
	visor_filter = ColorRect.new()
	visor_filter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visor_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var filter_material := ShaderMaterial.new()
	filter_material.shader = preload("res://shaders/visor_filter.gdshader")
	visor_filter.material = filter_material
	filter_layer.add_child(visor_filter)
	visor_filter.hide()
	_apply_visor_shade()

func set_visor_shade(value: bool) -> void:
	visor_shade = value
	_apply_visor_shade()

func _apply_visor_shade() -> void:
	for helmet in helmets: helmet.set_shade(visor_shade_amount)
	if visor_filter == null: return
	visor_filter.visible = enabled and mode == 3 and (visor_shade or visor_shade_amount > 0.001)
	visor_filter.material.set_shader_parameter("shade", visor_shade_amount)

func set_camera_mode(index: int) -> void:
	super.set_camera_mode(index)
	_apply_visor_shade()

func _process(delta: float) -> void:
	super._process(delta)
	var target := 1.0 if visor_shade else 0.0
	if visor_shade_amount != target:
		visor_shade_amount = move_toward(visor_shade_amount, target, delta / VISOR_SHADE_FADE)
	_apply_visor_shade()

func _unhandled_input(event: InputEvent) -> void:
	if enabled and not paused and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_H:
		set_visor_shade(not visor_shade)
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)
