extends "res://scripts/elvenpass_controller.gd"

var jump_active := false
var jump_left_floor := false
var landing_time := -1.0
var jump_phase := 0.08
var helmets: Array[Node3D] = []
var visor_shade := false        # discrete target; H flips it at once
var visor_shade_amount := 0.0   # smoothed value the visor and FPP filter follow
var visor_filter: ColorRect
var last_stamped_foot := ""
var climb_active := false
var climb_finishing := false
var climb_finish_elapsed := 0.0
var climb_finish_duration := 0.75
var climb_forward := Vector3.FORWARD
var climb_finish_start_y := 0.0
var climb_finish_top_y := 0.0
## Q's interaction search reaches 1.7 m, but a building's foundation plinth
## or an oversized coarse collision box can hold her back from the facade
## itself at that range -- climbing immediately failed its first "wall still
## ahead?" check from there. Walk her in first, like a normal approach,
## instead of starting (and instantly cancelling) the climb pose.
var climb_approaching := false
var climb_approach_time := 0.0
const CLIMB_APPROACH_TIMEOUT := 3.0
var climb_wall_miss_time := 0.0
const CLIMB_WALL_MISS_GRACE := 0.35
## A facade that curves into a dome or vaulted roof, instead of ending in a
## clean horizontal lip, loses the "wall still ahead?" ray over the curve long
## before any flat surface is reached -- _nearby_ledge_top() never finds a lip
## at head height because the true flat roof is further out along the same
## heading. Rather than stranding her partway up the curve when the climb
## would otherwise give up, walk her the rest of the way onto it.
var climb_auto_walk := false
var climb_auto_walk_target := Vector3.ZERO
const CLIMB_AUTO_WALK_SPEED := 1.8
const CLIMB_AUTO_WALK_REACH := 6.0

const VISOR_SHADE_FADE := 0.32  # seconds for a full clear <-> shaded sweep

func _init() -> void:
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
	]

func _ready() -> void:
	super._ready()
	if not InputMap.has_action("climb"):
		InputMap.add_action("climb")
		var climb_key := InputEventKey.new()
		climb_key.physical_keycode = KEY_E
		InputMap.action_add_event("climb", climb_key)
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
	# Physics owns the character translation. Preserve the poses in the source
	# clips while removing their baked hips travel, for the vault and both climb
	# phases alike.
	for index in [5, 6, 7]:
		var clip := players[index].get_animation(players[index].current_animation)
		clip.loop_mode = Animation.LOOP_LINEAR if index == 6 else Animation.LOOP_NONE
		for track in clip.get_track_count():
			if clip.track_get_type(track) == Animation.TYPE_POSITION_3D and String(clip.track_get_path(track)).ends_with(":Hips"):
				var origin: Vector3 = clip.track_get_key_value(track, 0)
				for key in clip.track_get_key_count(track):
					clip.track_set_key_value(track, key, origin)
	climb_finish_duration = players[7].get_animation(players[7].current_animation).length

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
	if enabled and not paused and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Q:
		var consumed := false
		if climb_active:
			climb_active = false
			_sync_visual(false, false)
			consumed = true
		elif climb_approaching:
			climb_approaching = false
			_sync_visual(false, false)
			consumed = true
		elif climb_auto_walk:
			climb_auto_walk = false
			_sync_visual(false, false)
			consumed = true
		else:
			consumed = _try_start_climb()
		# Away from a wall Q retains the Elvenpass "run forward" behaviour in
		# the alternate control profile.
		if consumed:
			get_viewport().set_input_as_handled()
			return
	if enabled and not paused and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_H:
		set_visor_shade(not visor_shade)
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

func _try_jump() -> void:
	if not is_on_floor() or mode == 4 or jump_active: return
	super._try_jump()
	turn_direction = 0
	jump_active = true
	jump_left_floor = false
	landing_time = -1.0
	jump_phase = 0.08
	_show_jump()

func _foot_position_for_stamp() -> Vector3:
	if active_visual < 0 or active_visual >= visuals.size(): return super._foot_position_for_stamp()
	var skeletons := visuals[active_visual].find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty(): return super._foot_position_for_stamp()
	var skeleton := skeletons[0] as Skeleton3D
	var left := skeleton.find_bone("LeftFoot")
	var right := skeleton.find_bone("RightFoot")
	if left < 0 or right < 0: return super._foot_position_for_stamp()
	var left_position := skeleton.global_transform * skeleton.get_bone_global_pose(left).origin
	var right_position := skeleton.global_transform * skeleton.get_bone_global_pose(right).origin
	var left_ground: float = terrain.height_at(left_position.x, left_position.z)
	var right_ground: float = terrain.height_at(right_position.x, right_position.z)
	var choose_left: bool = left_position.y - left_ground < right_position.y - right_ground
	if absf((left_position.y - left_ground) - (right_position.y - right_ground)) < 0.025:
		choose_left = last_stamped_foot != "left"
	last_stamped_foot = "left" if choose_left else "right"
	foot_side = 1.0 if choose_left else -1.0
	return left_position if choose_left else right_position

func _start_turn(direction: int) -> void:
	if not jump_active: super._start_turn(direction)

func _physics_process(delta: float) -> void:
	if not enabled or paused: return
	if climb_approaching:
		_physics_climb_approach(delta)
		return
	if climb_active:
		_physics_climb(delta)
		return
	if climb_auto_walk:
		_physics_climb_auto_advance(delta)
		return
	if climb_finishing:
		_physics_climb_finish(delta)
		return
	super._physics_process(delta)
	if not jump_active: return
	if not is_on_floor(): jump_left_floor = true
	if jump_left_floor and is_on_floor():
		landing_time = maxf(0.0, landing_time) + delta
		jump_phase = lerpf(0.78, 1.0, minf(landing_time / 0.25, 1.0))
		if landing_time >= 0.25:
			jump_active = false
			_sync_visual(Vector2(velocity.x, velocity.z).length() > 0.1, Vector2(velocity.x, velocity.z).length() > 3.0)
			return
	else:
		# About 3.2 seconds in lunar gravity instead of the source's 0.93 seconds.
		# Hold the late-flight pose on longer falls; land only on physical contact.
		jump_phase = lerpf(0.08, 0.42, clampf(1.0 - velocity.y / 2.6, 0, 1)) if velocity.y >= 0 else lerpf(0.42, 0.78, clampf(-velocity.y / 2.6, 0, 1))
	_show_jump()

func _show_jump() -> void:
	active_visual = 5
	for i in visuals.size():
		visuals[i].visible = i == 5
		players[i].speed_scale = 0.0
	players[5].seek(players[5].current_animation_length * jump_phase, true)

func _wall_ahead(at_height: float, reach: float = 1.35) -> bool:
	return _wall_ahead_from(climb_forward, at_height, reach)

func _wall_ahead_from(direction: Vector3, at_height: float, reach: float) -> bool:
	var from := global_position + Vector3.UP * at_height
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * reach)
	query.exclude = [get_rid()]
	query.collision_mask = 2 # detailed facade triangles; layer 1 is the coarse movement box
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return false
	# Floors and slopes are not walls. A climb target must have a near-horizontal
	# normal, which also keeps the key from triggering against lunar terrain.
	return absf((hit.normal as Vector3).y) < 0.22

func _nearest_climb_surface() -> Vector3:
	# E is an interaction key, so make it forgiving about the last fraction of a
	# turn made while walking up to a facade. Search only the detailed GLB layer;
	# the ordinary box collider is deliberately excluded from these rays.
	var best_direction := Vector3.ZERO
	var best_distance := INF
	for step in 12:
		var angle := visual_yaw + TAU * float(step) / 12.0
		var direction := Vector3(sin(angle), 0.0, cos(angle))
		# A hit at 1.34 m alone (near shoulder height) is required before this
		# direction counts as climbable at all -- without it, a knee-high curb,
		# garden wall or foundation ledge that only clips the two lower probes
		# reads as a perfectly good climb target: the climb starts, then
		# cancels on its very first "wall still ahead?" check a moment later
		# (that check is at 1.15 m, close to shoulder height), reading exactly
		# like "climbs for an instant, then straightens up and falls".
		if not _wall_ahead_from(direction, 1.34, 1.7): continue
		for height: float in [0.30, 0.82, 1.34]:
			var from: Vector3 = global_position + Vector3.UP * height
			var query := PhysicsRayQueryParameters3D.create(from, from + direction * 1.7)
			query.exclude = [get_rid()]
			query.collision_mask = 2
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or absf((hit.normal as Vector3).y) >= 0.22: continue
			var point: Vector3 = hit.position
			var horizontal_distance := Vector2(point.x - global_position.x, point.z - global_position.z).length()
			if horizontal_distance < best_distance:
				best_distance = horizontal_distance
				best_direction = Vector3(point.x - global_position.x, 0.0, point.z - global_position.z).normalized()
	return best_direction

func _nearby_ledge_top() -> float:
	# The finish is intentionally tied to Agnes's head, rather than her torso.
	# Cast down just beyond the wall to find a horizontal lip that is within a
	# hand's reach above the helmet.
	var head_y := global_position.y + reference_height_m * 0.95
	if _wall_ahead(reference_height_m * 0.95 + 0.28): return NAN
	var from := global_position + climb_forward * 0.88 + Vector3.UP * (reference_height_m + 0.7)
	var query := PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * (reference_height_m + 1.2))
	query.exclude = [get_rid()]
	query.collision_mask = 2
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.65: return NAN
	var top_y: float = (hit.position as Vector3).y
	return top_y if top_y >= head_y - 0.08 and top_y <= head_y + 0.38 else NAN

func _try_start_climb() -> bool:
	if jump_active or climb_active or climb_finishing or climb_approaching or mode == 4: return false
	climb_forward = _nearest_climb_surface()
	if climb_forward.is_zero_approx(): return false
	visual_yaw = atan2(climb_forward.x, climb_forward.z)
	pivot.rotation.y = visual_yaw
	turn_direction = 0
	climb_wall_miss_time = 0.0
	if _wall_ahead(1.15):
		climb_active = true
		velocity = Vector3.ZERO
		_show_climb(6, 0.0)
	else:
		climb_approaching = true
		climb_approach_time = 0.0
	return true

func _physics_climb_approach(delta: float) -> void:
	climb_approach_time += delta
	# _nearest_climb_surface() is re-run every tick (not just once at the
	# start) so she keeps tracking the wall as she walks in, the same way
	# ordinary movement re-evaluates input every frame.
	var direction: Vector3 = _nearest_climb_surface()
	if direction.is_zero_approx() or climb_approach_time > CLIMB_APPROACH_TIMEOUT:
		climb_approaching = false
		_sync_visual(false, false)
		return
	climb_forward = direction
	_move_classic_body(delta, direction, false)
	_update_camera()
	if _wall_ahead(1.15):
		climb_approaching = false
		climb_active = true
		climb_wall_miss_time = 0.0
		velocity = Vector3.ZERO
		turn_direction = 0
		_show_climb(6, 0.0)

func _physics_climb(delta: float) -> void:
	# A single E press starts the climb. The dedicated finish pose is reserved
	# for the actual lip of the climbed object; a second E press cancels safely.
	var ledge_top := _nearby_ledge_top()
	if not is_nan(ledge_top):
		# Start the finish while the top of the helmet is close to the lip. The
		# body is raised across the clip duration, so her feet settle on the top
		# exactly as the animation completes.
		climb_active = false
		climb_finishing = true
		climb_finish_elapsed = 0.0
		climb_finish_start_y = global_position.y
		climb_finish_top_y = ledge_top + 0.04
		velocity = Vector3.ZERO
		_show_climb(7, 0.0)
		return
	if _wall_ahead(1.15):
		climb_wall_miss_time = 0.0
	else:
		# A window, door or recess in the detailed per-triangle facade
		# collision can leave a short vertical gap in the "is the wall still
		# there?" ray -- measured directly: climbing 4 ticks (~0.07 m) past a
		# real facade before hitting exactly this kind of gap, well below any
		# building's actual top. Tolerate a brief continuous absence instead
		# of cancelling on the very first miss, so a real window doesn't end
		# the climb.
		climb_wall_miss_time += delta
		if climb_wall_miss_time > CLIMB_WALL_MISS_GRACE:
			var distant_roof := _find_distant_flat_roof()
			climb_active = false
			if is_nan(distant_roof.x):
				_sync_visual(false, false)
			else:
				climb_auto_walk = true
				climb_auto_walk_target = distant_roof + climb_forward * CLIMB_AUTO_WALK_LANDING_MARGIN
			return
	velocity = climb_forward * 0.08 + Vector3.UP * 1.05
	move_and_slide()
	pivot.rotation.y = visual_yaw
	var loop_length := players[6].current_animation_length
	_show_climb(6, fposmod(players[6].current_animation_position + delta, loop_length) if loop_length > 0.0 else 0.0)
	_update_camera()

func _physics_climb_finish(delta: float) -> void:
	climb_finish_elapsed += delta
	var phase := clampf(climb_finish_elapsed / maxf(climb_finish_duration, 0.01), 0.0, 1.0)
	var wanted_y := lerpf(climb_finish_start_y, climb_finish_top_y, phase)
	velocity = climb_forward * 0.44 + Vector3.UP * ((wanted_y - global_position.y) / maxf(delta, 0.001))
	move_and_slide()
	_show_climb(7, minf(climb_finish_elapsed, climb_finish_duration))
	_update_camera()
	if climb_finish_elapsed >= climb_finish_duration:
		climb_finishing = false
		# The animation lands her right at the lip -- nudge her forward onto
		# solid roof so she isn't left balanced on the edge (where is_on_floor()
		# doesn't reliably register).
		position += climb_forward * 0.4
		velocity = Vector3.ZERO
		_sync_visual(false, false)

## How far past a first flat sample must keep reading flat, near the same
## height, before it counts as an actual plateau rather than a single sample
## caught mid-transition on the last bit of curve. Landing right on that
## transition still leaves her standing on a slope-ish edge, close enough to
## the curve that ordinary gravity/slide handling slides her back off it.
const CLIMB_AUTO_WALK_CONFIRM_REACH := 1.2
## Extra distance walked past the confirmed plateau point so she ends up
## solidly inside the flat area instead of right at its edge.
const CLIMB_AUTO_WALK_LANDING_MARGIN := 1.0

func _flat_roof_probe(distance: float) -> Vector3:
	var probe := global_position + climb_forward * distance
	var from := probe + Vector3.UP * 4.0
	var query := PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * 8.0)
	query.exclude = [get_rid()]
	query.collision_mask = 2
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.85 or absf((hit.position as Vector3).y - global_position.y) >= 3.0:
		return Vector3(NAN, NAN, NAN)
	return hit.position

func _find_distant_flat_roof() -> Vector3:
	# Probe outward along the heading she was climbing, looking for the first
	# point where the surface actually flattens out (a dome or vaulted roof's
	# true top), rather than the curved section the wall-ahead ray just lost.
	var distance := 0.5
	while distance <= CLIMB_AUTO_WALK_REACH:
		var hit_point := _flat_roof_probe(distance)
		if not is_nan(hit_point.x):
			var confirm_point := _flat_roof_probe(distance + CLIMB_AUTO_WALK_CONFIRM_REACH)
			if not is_nan(confirm_point.x) and absf(confirm_point.y - hit_point.y) < 0.3:
				return confirm_point
		distance += 0.3
	return Vector3(NAN, NAN, NAN)

func _physics_climb_auto_advance(delta: float) -> void:
	var to_target := climb_auto_walk_target - global_position
	if to_target.length() < 0.12:
		climb_auto_walk = false
		global_position = climb_auto_walk_target
		velocity = Vector3.ZERO
		_sync_visual(false, false)
		return
	velocity = to_target.normalized() * CLIMB_AUTO_WALK_SPEED
	move_and_slide()
	pivot.rotation.y = visual_yaw
	var loop_length := players[6].current_animation_length
	_show_climb(6, fposmod(players[6].current_animation_position + delta, loop_length) if loop_length > 0.0 else 0.0)
	_update_camera()

func _show_climb(index: int, time: float) -> void:
	active_visual = index
	for i in visuals.size():
		visuals[i].visible = i == index
		players[i].speed_scale = 0.0
	players[index].seek(time, true)

func _sync_visual(moving: bool, running: bool) -> void:
	if climb_active or climb_auto_walk:
		_show_climb(6, players[6].current_animation_position)
		return
	if climb_finishing:
		_show_climb(7, climb_finish_elapsed)
		return
	if jump_active:
		_show_jump()
		return
	super._sync_visual(moving, running)
	if not moving and (turn_direction == 0 or mode == 4):
		active_visual = 4
		for i in visuals.size():
			visuals[i].visible = i == active_visual
			players[i].speed_scale = 1.0 if i == 4 and is_on_floor() else 0.0
