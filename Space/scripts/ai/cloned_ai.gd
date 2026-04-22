class_name ClonedAI
extends RefCounted
## Behavioral cloning AI controller for enemy ships.
## Finds the best matching point in a combat recording, then plays
## the sequence forward for a chunk of frames before re-querying.
## This produces smooth, coherent behavior instead of jittery averaging.

var recording: CombatRecording = null
var _playback_idx: int = -1        # current frame index in recording
var _frames_remaining: int = 0     # frames left before next re-query
var _chunk_size: int = 45          # play ~0.75 seconds before re-query (at 60fps)
var _drift_threshold: float = 500.0 # re-query early if distance to target drifts too far from recording
var _speed_scale: float = 1.0

# Self-play recording: captures the clone's own actions and outcomes
var self_recording: CombatRecording = null
var _last_action: Array = []       # cache last action for self-recording

func setup(rec: CombatRecording, enemy_max_speed: float = 220.0):
    recording = rec
    var rec_speed = rec.ship_config.get("max_speed", 310.0)
    _speed_scale = enemy_max_speed / maxf(rec_speed, 1.0)
    self_recording = CombatRecording.new()
    self_recording.ship_config = rec.ship_config.duplicate()

## Called by enemy_ship._physics_process instead of the hardcoded AI.
## Returns true if it handled the frame, false to fall back to default AI.
func decide(ship: Node2D, target: Node2D, delta: float) -> bool:
    if recording == null or recording.get_frame_count() < 10:
        return false
    if target == null or not is_instance_valid(target):
        return false

    # Check if we need to re-query
    if _frames_remaining <= 0 or _playback_idx < 0 or _playback_idx >= recording.get_frame_count():
        _playback_idx = _find_best_start(ship, target)
        _frames_remaining = _chunk_size
        if _playback_idx < 0:
            return false

    # Check for drift — if our situation is wildly different from what
    # the recording expected at this frame, re-query early
    if _frames_remaining < _chunk_size - 10:  # give at least 10 frames before drift check
        var drift_frame = recording.frames[_playback_idx]
        var s = drift_frame.s
        if s.size() >= CombatRecording.STATE_SIZE:
            var actual_dist = ship.global_position.distance_to(target.global_position)
            var recorded_dist = s[CombatRecording.S_DIST]
            if absf(actual_dist - recorded_dist) > _drift_threshold:
                _playback_idx = _find_best_start(ship, target)
                _frames_remaining = _chunk_size
                if _playback_idx < 0:
                    return false

    # Play the current frame's action
    var frame = recording.frames[_playback_idx]
    _apply_action(ship, target, frame.a, delta)

    # Record the clone's own state and action for self-play learning
    if self_recording:
        var self_state = _build_state(ship, target)
        _last_action = frame.a.duplicate()
        self_recording.add_frame(self_state, _last_action)

    # Advance playback
    _playback_idx += 1
    _frames_remaining -= 1

    # Wrap around if we hit the end
    if _playback_idx >= recording.get_frame_count():
        _playback_idx = 0
        _frames_remaining = 0  # force re-query at wrap

    return true

func _find_best_start(ship: Node2D, target: Node2D) -> int:
    var query = _build_state(ship, target)
    var dist_val = query[CombatRecording.S_DIST]

    # Get candidates from nearby distance buckets
    var candidates = recording.get_nearby_buckets(dist_val)
    if candidates.is_empty():
        # Broaden search to adjacent buckets
        var b = int(dist_val / CombatRecording.BUCKET_SIZE)
        for offset in [-2, 2, -3, 3]:
            var key = b + offset
            if recording._buckets.has(key):
                candidates.append_array(recording._buckets[key])
    if candidates.is_empty():
        return 0  # fallback to start

    # Find the single best matching frame (no averaging)
    var best_idx: int = -1
    var best_dist: float = INF

    for idx in candidates:
        var frame = recording.frames[idx]
        var s = frame.s
        if s.size() < CombatRecording.STATE_SIZE:
            continue
        # Also skip frames too close to the end — we want room to play forward
        if idx > recording.get_frame_count() - 30:
            continue

        var d: float = 0.0
        for j in CombatRecording.STATE_SIZE:
            var w = CombatRecording.STATE_WEIGHTS[j]
            if w < 0.01:
                continue
            var diff = query[j] - s[j]
            d += diff * diff * w

        # Skip frames below quality threshold
        var q: float = frame.get("q", 0.0)
        if recording.quality_threshold > 0.0 and q < recording.quality_threshold:
            continue
        # Penalize negative-quality frames (clone took damage / died doing this)
        if q < 0.0:
            d *= (1.0 + absf(q) * 2.0)
        # Quality bonus: high-quality frames (from confirmed hits) get reduced distance
        elif q > 0.0:
            d /= (1.0 + q * recording.aggression_bias)

        if d < best_dist:
            best_dist = d
            best_idx = idx

    return best_idx if best_idx >= 0 else 0

func _build_state(ship: Node2D, target: Node2D) -> Array:
    var rel_pos = (target.global_position - ship.global_position).rotated(-ship.rotation)
    var dist = rel_pos.length()

    var ship_vel: Vector2 = ship.velocity if "velocity" in ship else Vector2.ZERO
    var target_vel: Vector2 = target.velocity if "velocity" in target else Vector2.ZERO
    var rel_vel = (target_vel - ship_vel).rotated(-ship.rotation)

    var my_speed = ship_vel.length()

    var hp_ratio: float = 0.0
    if "max_health" in ship and ship.max_health > 0:
        hp_ratio = ship.health / ship.max_health

    var shield_ratio: float = 0.0
    if "max_shields" in ship and ship.max_shields > 0:
        shield_ratio = ship.shields / ship.max_shields

    var target_hp: float = 0.0
    if "max_health" in target and target.max_health > 0:
        target_hp = target.health / target.max_health

    var target_shield: float = 0.0
    if "max_shields" in target and target.max_shields > 0:
        target_shield = target.shields / target.max_shields

    var can_fire: float = 1.0 if ("can_fire" in ship and ship.can_fire) else 0.0

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
        can_fire,       # S_CAN_PRIMARY
        0.0,            # S_CAN_SECONDARY
        0.0,            # S_CAN_SPECIAL
        0.0,            # S_BOOST_READY
        0.0,            # S_HARPOON
    ]

func _apply_action(ship: Node2D, target: Node2D, a: Array, delta: float):
    if a.size() < CombatRecording.ACTION_SIZE:
        return

    # --- Movement ---
    var thrust = a[CombatRecording.A_THRUST]
    var turn = a[CombatRecording.A_TURN]

    # Apply turn directly from recording
    var turn_rate: float = ship.turn_rate if "turn_rate" in ship else 3.0
    ship.rotation += turn * turn_rate * delta

    # Apply thrust
    var accel: float = ship.acceleration if "acceleration" in ship else 400.0
    var max_spd: float = ship.max_speed if "max_speed" in ship else 220.0
    var facing = Vector2.from_angle(ship.rotation)
    ship.velocity += facing * thrust * accel * delta
    ship.velocity = ship.velocity.limit_length(max_spd * 1.6)

    # Friction when over max speed
    if ship.velocity.length() > max_spd:
        ship.velocity = ship.velocity.move_toward(
            ship.velocity.normalized() * max_spd, accel * 0.3 * delta
        )

    # Apply position — skip for player_ship (its _process already moves by velocity)
    if not ("ai_controlled" in ship and ship.ai_controlled):
        ship.position += ship.velocity * delta

    # Knockback decay
    if "knockback_vel" in ship and ship.knockback_vel.length_squared() > 1.0:
        if not ("ai_controlled" in ship and ship.ai_controlled):
            ship.position += ship.knockback_vel * delta
        ship.knockback_vel *= exp(-4.0 * delta)

    # --- Target-tracking correction ---
    # Recorded turns are the primary rotation driver, but gently nudge
    # back toward the target when facing too far away to prevent disengagement.
    var dir_to_target = (target.global_position - ship.global_position).normalized()
    var target_angle = dir_to_target.angle()
    var angle_error = angle_difference(ship.rotation, target_angle)
    if absf(angle_error) > PI * 0.3:
        ship.rotation = lerp_angle(ship.rotation, target_angle, 1.5 * delta)

    # --- Aim and firing ---
    # Use the recorded aim direction, but also aim directly at target for firing
    var aim_at_target = target_angle
    if "aim_angle" in ship:
        # Blend: use recorded aim when it's reasonable, snap to target otherwise
        var recorded_aim = ship.rotation + a[CombatRecording.A_AIM_LOCAL]
        var rec_aim_err = absf(angle_difference(recorded_aim, target_angle))
        ship.aim_angle = recorded_aim if rec_aim_err < 0.8 else aim_at_target

    # Fire opportunistically — if aim is on target and weapon is ready, shoot.
    # Don't wait for the recording to say fire; the player holds LMB in combat.
    var aim_error = absf(angle_difference(ship.aim_angle, target_angle))
    if aim_error < 0.8:
        if "can_fire" in ship and ship.can_fire:
            if ship.has_method("_fire"):
                ship._fire()

    # Secondary: fire opportunistically when aimed at target, like primary.
    # Beam weapons need to be called every frame to deal continuous damage.
    # Clear beam_end_positions each frame so _beam_tick_damage repopulates them
    if "beam_end_positions" in ship:
        ship.beam_end_positions.clear()
    var fired_secondary: bool = false
    if aim_error < 0.8 and ship.has_method("_fire_secondary_weapon"):
        if "secondary_weapons" in ship and not ship.secondary_weapons.is_empty():
            ship._fire_secondary_weapon()
            fired_secondary = true

    # Manage beam_active state so beam visuals/audio work for AI ships
    if "beam_active" in ship:
        var was_beam = ship.beam_active
        ship.beam_active = false
        if fired_secondary and "secondary_group_keys" in ship and not ship.secondary_group_keys.is_empty():
            var gidx = clampi(ship.active_secondary_idx if "active_secondary_idx" in ship else 0, 0, ship.secondary_group_keys.size() - 1)
            if ship.secondary_group_keys[gidx] == "beam":
                ship.beam_active = true
        if ship.beam_active and not was_beam:
            AudioManager.beam_start(0.7)
        elif not ship.beam_active and was_beam:
            AudioManager.beam_stop_immediate()

    # Special: still use recording (these are situational)
    if a[CombatRecording.A_FIRE_SPECIAL] > 0.5:
        if ship.has_method("_fire_special_weapon"):
            ship._fire_special_weapon()

    # Parry / shield supercharger: use recording + tactical activation
    _handle_parry(ship, target, a)

## Called when the clone deals damage to the player — boost recent self-play frames
func on_dealt_damage():
    if self_recording:
        self_recording.boost_recent_frames(45, 1.5)

## Called when the clone takes damage — penalize recent self-play frames
func on_took_damage():
    if self_recording == null:
        return
    var start = maxi(self_recording.frames.size() - 30, 0)
    for i in range(start, self_recording.frames.size()):
        self_recording.frames[i].q = minf(self_recording.frames[i].q, -0.5)

## Called when the clone dies — heavily penalize the last chunk of self-play frames
func on_died():
    if self_recording == null:
        return
    var start = maxi(self_recording.frames.size() - 90, 0)
    for i in range(start, self_recording.frames.size()):
        self_recording.frames[i].q = minf(self_recording.frames[i].q, -1.0)

func _handle_parry(ship: Node2D, target: Node2D, a: Array):
    if not ("parry_active" in ship and "parry_cooldown" in ship):
        return
    # Already parrying or on cooldown — let the ship's own _process handle the timer
    if ship.parry_active or ship.parry_cooldown > 0:
        return
    # Check if the ship has a shield supercharger module
    if not _has_supercharger(ship):
        return

    var should_parry: bool = false

    # 1. Recording says to parry
    if a.size() > CombatRecording.A_PARRY and a[CombatRecording.A_PARRY] > 0.5:
        should_parry = true

    # 2. Tactical: incoming projectiles are close
    if not should_parry:
        var ship_size: float = ship.ship_size if "ship_size" in ship else 20.0
        var danger_radius: float = ship_size * 4.0
        for proj in ship.get_tree().get_nodes_in_group("projectiles"):
            if not is_instance_valid(proj):
                continue
            if "source" in proj and proj.source == "enemy":
                continue  # don't parry our own team's projectiles
            var dist = ship.global_position.distance_to(proj.global_position)
            if dist < danger_radius:
                # Check if projectile is heading toward us
                var to_ship = (ship.global_position - proj.global_position).normalized()
                var proj_dir = Vector2.from_angle(proj.rotation)
                if to_ship.dot(proj_dir) > 0.3:
                    should_parry = true
                    break

    # 3. Tactical: target is very close and charging in (crash scenario)
    if not should_parry:
        var dist_to_target = ship.global_position.distance_to(target.global_position)
        if dist_to_target < 200.0:
            var closing_speed = (target.velocity - ship.velocity).dot(
                (ship.global_position - target.global_position).normalized()
            ) if "velocity" in target and "velocity" in ship else 0.0
            if closing_speed > 100.0:
                should_parry = true

    if should_parry:
        ship.parry_active = true
        ship.parry_timer = ship.parry_duration
        ship.parry_spin_angle = 0.0
        ship.parry_reflected_count = 0
        ship.parry_hp = ship.parry_max_hp
        AudioManager.play_sfx("shield_up", 0.8, 0.0)

func _has_supercharger(ship: Node2D) -> bool:
    if not ("ship_layout" in ship):
        return false
    for mod in ship.ship_layout:
        if mod.get("type", "") == "shield_supercharger":
            return true
    return false
