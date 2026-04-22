class_name CombatRecorder
extends Node
## Attach as a child of the player ship during test fly.
## Captures (state, action) snapshots every physics frame while recording.

var recording: CombatRecording = null
var is_recording: bool = false
var player: Node2D = null
var _target_cache: Node2D = null
var _frames_recorded: int = 0
var _prev_target_hp: float = -1.0

func _ready():
	process_mode = PROCESS_MODE_PAUSABLE
	player = get_parent()
	recording = CombatRecording.new()
	# Snapshot the player ship config at recording start
	if player:
		recording.ship_config = {
			max_speed = player.get("max_speed") if "max_speed" in player else 310.0,
			acceleration = player.get("acceleration") if "acceleration" in player else 460.0,
			max_health = player.get("max_health") if "max_health" in player else 100.0,
			max_shields = player.get("max_shields") if "max_shields" in player else 0.0,
		}

func start_recording():
	is_recording = true
	_frames_recorded = 0
	print("[CombatRecorder] Recording started")

func stop_recording():
	is_recording = false
	print("[CombatRecorder] Recording stopped — %d frames captured" % _frames_recorded)

func _physics_process(_delta: float):
	if not is_recording or not player:
		return

	# Toggle recording with F9
	if Input.is_key_pressed(KEY_F9):
		# Handled in _unhandled_input instead
		pass

	var target = _find_target()
	if target == null:
		_prev_target_hp = -1.0
		return  # Don't record idle frames

	# Track target HP — boost recent frames when we deal damage
	var cur_target_hp: float = 0.0
	if "max_health" in target and target.max_health > 0:
		cur_target_hp = target.health / target.max_health
	if _prev_target_hp >= 0.0 and cur_target_hp < _prev_target_hp - 0.001:
		# Target took damage — boost the last ~45 frames (the actions that led to this hit)
		recording.boost_recent_frames(45, 1.0)
	_prev_target_hp = cur_target_hp

	var state = _build_state(target)
	var action = _build_action(target)
	recording.add_frame(state, action)
	_frames_recorded += 1

func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F9:
			if is_recording:
				stop_recording()
			else:
				start_recording()

func clear_target_cache():
	_target_cache = null

func _find_target() -> Node2D:
	if _target_cache and is_instance_valid(_target_cache):
		return _target_cache
	var best: Node2D = null
	var best_dist: float = INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var d = player.global_position.distance_to(enemy.global_position)
		if d < best_dist:
			best_dist = d
			best = enemy
	_target_cache = best
	return best

func _build_state(target: Node2D) -> Array:
	var rel_pos = (target.global_position - player.global_position).rotated(-player.rotation)
	var dist = rel_pos.length()

	var player_vel: Vector2 = player.velocity if "velocity" in player else Vector2.ZERO
	var target_vel: Vector2 = target.velocity if "velocity" in target else Vector2.ZERO
	var rel_vel = (target_vel - player_vel).rotated(-player.rotation)

	var my_speed = player_vel.length()

	var hp_ratio: float = 0.0
	if "max_health" in player and player.max_health > 0:
		hp_ratio = player.health / player.max_health

	var shield_ratio: float = 0.0
	if "max_shields" in player and player.max_shields > 0:
		shield_ratio = player.shields / player.max_shields

	var target_hp: float = 0.0
	if "max_health" in target and target.max_health > 0:
		target_hp = target.health / target.max_health

	var target_shield: float = 0.0
	if "max_shields" in target and target.max_shields > 0:
		target_shield = target.shields / target.max_shields

	var can_primary: float = 1.0 if ("can_fire" in player and player.can_fire) else 0.0

	var can_secondary: float = 0.0
	if "secondary_cooldowns" in player:
		for k in player.secondary_cooldowns:
			if player.secondary_cooldowns[k] <= 0:
				can_secondary = 1.0
				break

	var can_special: float = 0.0
	if "special_cooldowns" in player:
		for k in player.special_cooldowns:
			if player.special_cooldowns[k] <= 0:
				can_special = 1.0
				break

	var boost_ready: float = 1.0 if ("boost_ready" in player and player.boost_ready) else 0.0
	var harpoon: float = float(player.harpoon_state) if "harpoon_state" in player else 0.0

	return [
		dist,           # S_DIST
		rel_pos.x,      # S_REL_X
		rel_pos.y,      # S_REL_Y
		rel_vel.x,      # S_REL_VX
		rel_vel.y,      # S_REL_VY
		my_speed,       # S_MY_SPEED
		hp_ratio,       # S_HP
		shield_ratio,   # S_SHIELD
		target_hp,      # S_TARGET_HP
		target_shield,  # S_TARGET_SHIELD
		can_primary,    # S_CAN_PRIMARY
		can_secondary,  # S_CAN_SECONDARY
		can_special,    # S_CAN_SPECIAL
		boost_ready,    # S_BOOST_READY
		harpoon,        # S_HARPOON
	]

func _build_action(_target: Node2D) -> Array:
	# Thrust input
	var thrust: float = 0.0
	if Input.is_action_pressed("move_up"):
		thrust = 1.0
	elif Input.is_action_pressed("move_down"):
		thrust = -0.5
	# Controller overlay
	var lstick = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if abs(lstick.y) > 0.1:
		var stick_thrust = -lstick.y
		if stick_thrust < 0:
			stick_thrust *= 0.5
		thrust = stick_thrust if abs(stick_thrust) > abs(thrust) else thrust

	# Turn input
	var turn: float = 0.0
	if Input.is_action_pressed("move_right"):
		turn += 1.0
	if Input.is_action_pressed("move_left"):
		turn -= 1.0
	if abs(lstick.x) > abs(turn):
		turn = lstick.x

	# Aim angle relative to ship rotation
	var aim_local: float = 0.0
	if "aim_angle" in player:
		aim_local = player.aim_angle - player.rotation

	return [
		thrust,                                                    # A_THRUST
		turn,                                                      # A_TURN
		aim_local,                                                 # A_AIM_LOCAL
		1.0 if Input.is_action_pressed("fire_primary") else 0.0,  # A_FIRE_PRIMARY
		1.0 if Input.is_action_pressed("fire_secondary") else 0.0, # A_FIRE_SECONDARY
		1.0 if Input.is_action_pressed("fire_special") else 0.0,  # A_FIRE_SPECIAL
		1.0 if Input.is_action_just_pressed("fire_harpoon") else 0.0, # A_FIRE_HARPOON
		1.0 if Input.is_action_just_pressed("boost") else 0.0,    # A_BOOST
		1.0 if Input.is_action_pressed("handbrake") else 0.0,     # A_HANDBRAKE
		1.0 if Input.is_action_just_pressed("scan") else 0.0,    # A_PARRY
	]

func save_recording(rec_name: String = "") -> bool:
	if recording.get_frame_count() < 300:
		push_warning("CombatRecorder: recording too short (%d frames), not saving" % recording.get_frame_count())
		return false
	if rec_name == "":
		rec_name = "recording_%d" % Time.get_unix_time_from_system()
	recording.recording_name = rec_name
	DirAccess.make_dir_recursive_absolute("user://combat_recordings")
	var path = "user://combat_recordings/%s.json" % rec_name
	var ok = recording.save_to_file(path)
	if ok:
		print("[CombatRecorder] Saved %d frames to %s" % [recording.get_frame_count(), path])
	return ok
