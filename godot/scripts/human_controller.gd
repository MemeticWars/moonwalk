extends "res://scripts/elvenpass_controller.gd"

## One unanimated humanoid scene may use all donor clips. Bone map entries are
## source bone name -> target bone name; exact/common names map automatically.
@export_file("*.glb", "*.tscn") var humanoid_model_path := ""
@export var humanoid_bone_map: Dictionary = {}
const MOTIONS = preload("res://scripts/humanoid_motion_library.gd")
const WALK := 0
const RUN := 1
const TURN_LEFT := 2
const TURN_RIGHT := 3
const IDLE := 4
const JUMP := 5
const CLIMB := 6
const LEDGE_FINISH := 7
const CRAWL := 8
const STAND_UP := 9
var stand_up_active := false
var stand_up_elapsed := 0.0
var stand_support_time := 0.0
const STAND_SUPPORT_DELAY := 0.2
## Stand_Up2 itself swings the feet through the crouch-to-standing motion, so
## a foot can sample past a roof's edge (or a parapet/vent) for a frame or two
## even though the standing footprint she settled on is genuinely solid. Only
## bailing back to a crawl after support stays lost for a stretch keeps that
## single-frame flicker from restarting the animation from 0 -- observed in
## play as Stand_Up2 looping forever right on a roof that could support her.
var stand_up_miss_time := 0.0
const STAND_UP_SUPPORT_GRACE := 0.25

func _init() -> void:
	model_paths = MOTIONS.SOURCES.duplicate()
	atlas_path = ""

func _load_character_visual(index: int, path: String) -> Node3D:
	if humanoid_model_path.is_empty(): return super._load_character_visual(index, path)
	var visual := (load(humanoid_model_path) as PackedScene).instantiate() as Node3D
	var result := MOTIONS.attach(visual, path, humanoid_bone_map)
	if not result.is_empty():
		push_error("Humanoid animation %d: %s" % [index, result])
		visual.free()
		return null
	return visual

func _character_visual_height(visual: Node3D) -> float:
	if humanoid_model_path.is_empty(): return super._character_visual_height(visual)
	var bounds := AABB()
	var seeded := false
	for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		var transform := visual.global_transform.affine_inverse() * mesh.global_transform
		var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if skeleton != null and mesh.skin != null and mesh.skin.get_bind_count() > 0:
			var bone := skeleton.find_bone(mesh.skin.get_bind_name(0))
			if bone < 0: bone = mesh.skin.get_bind_bone(0)
			if bone >= 0:
				# A rig may use centimetres while vertices use metres. Skin bind
				# transforms bridge those spaces; the raw mesh AABB alone does not.
				transform = visual.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_rest(bone) * mesh.skin.get_bind_pose(0)
		for corner in 8:
			var point := transform * mesh.mesh.get_aabb().get_endpoint(corner)
			bounds = bounds.expand(point) if seeded else AABB(point, Vector3.ZERO)
			seeded = true
	return bounds.size.y


var jump_active := false
var jump_left_floor := false
var landing_time := -1.0
var jump_phase := 0.08
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
## Curved roofs are traversed using local surface samples until the entire
## standing footprint is supported on a nearly level patch.
var climb_auto_walk := false
var climb_auto_walk_target := Vector3.ZERO
var climb_finish_target := Vector3.ZERO
const CLIMB_AUTO_WALK_SPEED := 0.8
const ROOF_STAND_NORMAL := 0.94 # about 20 degrees
const ROOF_SUPPORT_RADIUS := 0.3




func _ready() -> void:
	super._ready()
	if players.size() != 10:
		enabled = false
		return
	# Physics owns the character translation. Preserve the poses in the source
	# clips while removing their baked hips travel, for the vault and both climb
	# phases alike.
	for index in [5, 6, 7, 8, 9]:
		var clip := players[index].get_animation(players[index].current_animation)
		clip.loop_mode = Animation.LOOP_LINEAR if index in [6, 8] else Animation.LOOP_NONE
		for track in clip.get_track_count():
			if clip.track_get_type(track) == Animation.TYPE_POSITION_3D and String(clip.track_get_path(track)).ends_with(":" + _motion_bone_name(index, "Hips")):
				var origin: Vector3 = clip.track_get_key_value(track, 0)
				for key in clip.track_get_key_count(track):
					var value: Vector3 = clip.track_get_key_value(track, key)
					clip.track_set_key_value(track, key, Vector3(origin.x, value.y if index == 9 else origin.y, origin.z))
	climb_finish_duration = players[7].get_animation(players[7].current_animation).length





func _unhandled_input(event: InputEvent) -> void:
	if enabled and not paused and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Q:
		var consumed := false
		if stand_up_active or climb_finishing:
			consumed = true
		elif climb_active:
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
	super._unhandled_input(event)

func _try_jump() -> void:
	if not is_on_floor() or mode == 4 or jump_active or climb_active or climb_finishing or climb_auto_walk or stand_up_active or climb_approaching: return
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
	var left := MOTIONS.find_bone(skeleton, "LeftFoot", humanoid_bone_map)
	var right := MOTIONS.find_bone(skeleton, "RightFoot", humanoid_bone_map)
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
	if not jump_active and not climb_active and not climb_auto_walk and not climb_finishing and not stand_up_active: super._start_turn(direction)

func _physics_process(delta: float) -> void:
	if not enabled or paused: return
	if stand_up_active:
		_physics_stand_up(delta)
		return
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
	var facing := Vector3(sin(visual_yaw), 0.0, cos(visual_yaw))
	# Do not redirect Q from the doorway to an adjacent jamb or interior wall.
	if _doorway_ahead(facing): return Vector3.ZERO
	# E is an interaction key, so make it forgiving about the last fraction of a
	# turn made while walking up to a facade. Search only the detailed GLB layer;
	# the ordinary box collider is deliberately excluded from these rays.
	var best_direction := Vector3.ZERO
	var best_distance := INF
	for step in 12:
		var angle := visual_yaw + TAU * float(step) / 12.0
		var direction := Vector3(sin(angle), 0.0, cos(angle))
		if _doorway_ahead(direction): continue
		# A hit at 1.34 m alone (near shoulder height) is required before this
		# direction counts as climbable at all -- without it, a knee-high curb,
		# garden wall or foundation ledge that only clips the two lower probes
		# reads as a perfectly good climb target: the climb starts, then
		# cancels on its very first "wall still ahead?" check a moment later
		# (that check is at 1.15 m, close to shoulder height), reading exactly
		# like "climbs for an instant, then straightens up and falls".
		if not _solid_climb_patch(direction, 1.7): continue
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
	if hit.is_empty() or not _roof_can_stand(hit.position): return NAN
	climb_finish_target = hit.position + Vector3.UP * 0.04
	var top_y: float = (hit.position as Vector3).y
	return top_y if top_y >= head_y - 0.08 and top_y <= head_y + 0.38 else NAN

func _try_start_climb() -> bool:
	if jump_active or climb_active or climb_finishing or climb_approaching or climb_auto_walk or stand_up_active or mode == 4: return false
	climb_forward = _nearest_climb_surface()
	if climb_forward.is_zero_approx(): return false
	set_collision_mask_value(2, false)
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
	if _doorway_ahead(climb_forward):
		climb_active = false
		velocity = Vector3.ZERO
		_sync_visual(false, false)
		return
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
			var roof := _roof_probe(global_position + climb_forward * 0.88)
			climb_active = false
			if roof.is_empty() or (roof.normal as Vector3).y < 0.22:
				_sync_visual(false, false)
			else:
				climb_auto_walk = true
				climb_auto_walk_target = roof.position + Vector3.UP * 0.04
				_show_climb(8, 0.0)
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
	var remaining := maxf(climb_finish_duration - climb_finish_elapsed + delta, delta)
	var horizontal := (climb_finish_target - global_position) / remaining
	velocity = Vector3(horizontal.x, (wanted_y - global_position.y) / maxf(delta, 0.001), horizontal.z)
	move_and_slide()
	_show_climb(7, minf(climb_finish_elapsed, climb_finish_duration))
	_update_camera()
	if climb_finish_elapsed >= climb_finish_duration:
		climb_finishing = false
		if not _roof_can_stand(global_position):
			climb_auto_walk = true
			climb_auto_walk_target = climb_finish_target
			_show_climb(8, 0.0)
			return
		velocity = Vector3.ZERO
		set_collision_mask_value(2, true)
		_sync_visual(false, false)

func _roof_probe(point: Vector3, rise: float = 2.7) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * rise, point - Vector3.UP * 0.6)
	query.exclude = [get_rid()]
	query.collision_mask = 2
	return get_world_3d().direct_space_state.intersect_ray(query)

func _roof_can_stand(point: Vector3) -> bool:
	# Both feet and the space around the capsule must remain on the roof.
	# One normal alone cannot distinguish a plateau from the crest of a dome.
	var offsets: Array[Vector3] = [Vector3.ZERO, Vector3.FORWARD * ROOF_SUPPORT_RADIUS, Vector3.BACK * ROOF_SUPPORT_RADIUS, Vector3.LEFT * ROOF_SUPPORT_RADIUS, Vector3.RIGHT * ROOF_SUPPORT_RADIUS]
	if active_visual >= 0 and active_visual < visuals.size():
		var skeleton := MOTIONS.skeleton_in(visuals[active_visual])
		if skeleton != null:
			for foot_name in ["LeftFoot", "RightFoot"]:
				var bone := MOTIONS.find_bone(skeleton, foot_name, humanoid_bone_map)
				if bone >= 0:
					var foot := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin - global_position
					offsets.append(Vector3(foot.x, 0, foot.z))
	for offset in offsets:
		var hit := _roof_probe(point + offset, 0.2)
		if hit.is_empty() or (hit.normal as Vector3).y < ROOF_STAND_NORMAL:
			return false
		if absf((hit.position as Vector3).y - point.y) > 0.18:
			return false
	return true

func _physics_climb_auto_advance(delta: float) -> void:
	var to_target := climb_auto_walk_target - global_position
	if to_target.length() < 0.06:
		if _roof_can_stand(global_position):
			stand_support_time += delta
			velocity = Vector3.ZERO
			if stand_support_time >= STAND_SUPPORT_DELAY:
				climb_auto_walk = false
				stand_up_active = true
				stand_up_elapsed = 0.0
				stand_up_miss_time = 0.0
				_show_climb(STAND_UP, 0.0)
			_update_camera()
			return
		stand_support_time = 0.0
		var standing_patch := _nearby_standing_patch()
		if not is_nan(standing_patch.x):
			climb_auto_walk_target = standing_patch
			to_target = standing_patch - global_position
			velocity = to_target.normalized() * minf(CLIMB_AUTO_WALK_SPEED, to_target.length() / maxf(delta, 0.001))
			global_position += velocity * delta
			_update_camera()
			return
		var roof := _roof_probe(global_position + climb_forward * 0.12, 0.25)
		if roof.is_empty():
			roof = _roof_probe(global_position + climb_forward * 0.12)
		# Stop on missing support instead of advancing across a gap or standing.
		# A curved lip can rise from a decorative ledge to hand height.
		# Allow pulling up within reach, but never crawl down a drop.
		var rise: float = (roof.position as Vector3).y - global_position.y if not roof.is_empty() else INF
		if not roof.is_empty() and (roof.normal as Vector3).y >= 0.22 and rise <= reference_height_m * 0.95 and rise >= -0.3:
			climb_auto_walk_target = roof.position + Vector3.UP * 0.04
		to_target = climb_auto_walk_target - global_position
	# Follow the sampled curve rather than a chord cutting through the roof.
	velocity = to_target.normalized() * minf(CLIMB_AUTO_WALK_SPEED, to_target.length() / maxf(delta, 0.001))
	# The coarse movement box can protrude beyond the visible roof. During
	# this controlled traversal, the detailed ray samples own the position.
	global_position += velocity * delta
	pivot.rotation.y = visual_yaw
	var loop_length := players[8].current_animation_length
	_show_climb(8, fposmod(players[8].current_animation_position + delta, loop_length) if loop_length > 0.0 else 0.0)
	_update_camera()

func _nearby_standing_patch() -> Vector3:
	# Roof trim can interrupt an otherwise level plateau along the exact
	# climbing heading. A small supported sidestep can clear that trim.
	for distance: float in [0.3, 0.6, 0.9]:
		for step in 8:
			var direction := climb_forward.rotated(Vector3.UP, float(step) * TAU / 8.0)
			var hit := _roof_probe(global_position + direction * distance, 0.3)
			if hit.is_empty() or not _roof_can_stand(hit.position): continue
			var target: Vector3 = hit.position + Vector3.UP * 0.04
			var supported := true
			for sample in range(1, 10):
				var point := global_position.lerp(target, float(sample) / 10.0)
				var support := _roof_probe(point, 0.3)
				if support.is_empty() or absf((support.position as Vector3).y - point.y) > 0.2 or (support.normal as Vector3).y < 0.22:
					supported = false
					break
			if supported: return target
	return Vector3(NAN, NAN, NAN)

func _show_climb(index: int, time: float) -> void:
	active_visual = index
	for i in visuals.size():
		visuals[i].visible = i == index
		players[i].speed_scale = 0.0
	players[index].seek(time, true)

func _sync_visual(moving: bool, running: bool) -> void:
	if stand_up_active:
		_show_climb(STAND_UP, stand_up_elapsed)
		return
	if climb_auto_walk:
		_show_climb(8, players[8].current_animation_position)
		return
	if climb_active:
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

func _motion_bone_name(index: int, source_name: String) -> String:
	var skeleton := MOTIONS.skeleton_in(visuals[index])
	if skeleton == null: return source_name
	var bone := MOTIONS.find_bone(skeleton, source_name, humanoid_bone_map)
	return skeleton.get_bone_name(bone) if bone >= 0 else source_name

func _facade_hit(direction: Vector3, height: float, reach: float, side: float = 0.0) -> Dictionary:
	var start := global_position + Vector3.UP * height + direction.cross(Vector3.UP) * side
	var query := PhysicsRayQueryParameters3D.create(start, start + direction * reach, 2, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)

func _solid_climb_patch(direction: Vector3, reach: float) -> bool:
	# Doorway rejection is _doorway_ahead's job (called on this same direction
	# before this patch check runs). A real facade's own relief -- a plinth,
	# a window reveal, a cornice -- can easily shift the hit depth between
	# these probe heights by more than earlier fixed tolerances allowed for,
	# which rejected plain flat walls almost everywhere; this only confirms
	# the whole standing footprint actually meets solid, near-vertical wall.
	for height: float in [0.3, 0.82, 1.34]:
		for side: float in [-collision_radius_m * 0.65, 0.0, collision_radius_m * 0.65]:
			var hit := _facade_hit(direction, height * reference_height_m / 1.8, reach, side)
			if hit.is_empty() or absf((hit.normal as Vector3).y) >= 0.22: return false
	return true

func _doorway_ahead(direction: Vector3) -> bool:
	var facade_depth := INF
	for fraction: float in [0.95, 1.15, 1.35, 1.5]:
		var lintel := _facade_hit(direction, reference_height_m * fraction, 1.7)
		if not lintel.is_empty() and absf((lintel.normal as Vector3).y) < 0.22:
			facade_depth = minf(facade_depth, ((lintel.position as Vector3) - global_position).dot(direction))
	if is_inf(facade_depth): return false
	var open_samples := 0
	for fraction: float in [0.2, 0.45, 0.7]:
		var hit := _facade_hit(direction, reference_height_m * fraction, 1.7)
		if hit.is_empty() or ((hit.position as Vector3) - global_position).dot(direction) > facade_depth + 0.35:
			open_samples += 1
	return open_samples >= 2

func _physics_stand_up(delta: float) -> void:
	velocity = Vector3.ZERO
	if not _roof_can_stand(global_position):
		stand_up_miss_time += delta
		if stand_up_miss_time > STAND_UP_SUPPORT_GRACE:
			stand_up_active = false
			stand_support_time = 0.0
			stand_up_miss_time = 0.0
			climb_auto_walk = true
			climb_auto_walk_target = global_position
			_show_climb(CRAWL, 0.0)
			return
	else:
		stand_up_miss_time = 0.0
	stand_up_elapsed += delta
	var duration := players[STAND_UP].current_animation_length
	_show_climb(STAND_UP, minf(stand_up_elapsed, duration))
	_update_camera()
	if stand_up_elapsed >= duration:
		stand_up_active = false
		stand_support_time = 0.0
		set_collision_mask_value(2, true)
		_sync_visual(false, false)
