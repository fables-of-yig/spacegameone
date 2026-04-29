@tool
extends ActionLeaf


func tick(actor: Node, blackboard: Blackboard) -> int:
    if actor == null:
        return FAILURE
    var dir: Vector2 = blackboard.get_value("dir", Vector2.ZERO)
    if dir == Vector2.ZERO:
        return FAILURE

    var delta := float(blackboard.get_value("delta", 0.016))
    var dist := float(blackboard.get_value("dist", 0.0))
    var aggro_range := float(blackboard.get_value("aggro_range", actor.aggro_range if "aggro_range" in actor else 800.0))
    var orbit_distance := float(blackboard.get_value("orbit_distance", actor.orbit_distance if "orbit_distance" in actor else 200.0))
    var style := str(blackboard.get_value("combat_style", "standard"))

    match style:
        "hit_and_run":
            _tick_hit_and_run(actor, dir, dist, delta, aggro_range, orbit_distance)
        _:
            _tick_standard(actor, dir, dist, delta, aggro_range, orbit_distance)

    actor._apply_star_avoidance(delta)
    return RUNNING


func _tick_standard(actor: Node, dir: Vector2, dist: float, delta: float, aggro_range: float, orbit_distance: float) -> void:
    var perp: Vector2 = Vector2(-dir.y, dir.x) * float(actor._juke_dir)
    var accel: float = float(actor.acceleration) * 1.4

    actor._juke_timer -= delta
    if actor._juke_timer <= 0.0:
        actor._juke_timer = randf_range(0.4, 1.2)
        if randf() < 0.6:
            actor._juke_dir *= -1.0
            perp = Vector2(-dir.y, dir.x) * actor._juke_dir

    actor._mode_timer -= delta
    if actor._mode_timer <= 0.0:
        actor._combat_mode = randi() % 3
        match actor._combat_mode:
            0:
                actor._mode_timer = randf_range(2.0, 4.0)
            1:
                actor._mode_timer = randf_range(1.0, 2.5)
            _:
                actor._mode_timer = randf_range(1.5, 3.0)

    if dist > aggro_range * 2.5:
        actor.velocity += dir * accel * delta
        actor.velocity = actor.velocity.limit_length(actor.max_speed)
        return

    match actor._combat_mode:
        0:
            actor.velocity += perp * accel * 0.9 * delta
            if dist > orbit_distance * 1.2:
                actor.velocity += dir * accel * 0.7 * delta
            elif dist < orbit_distance * 0.5:
                actor.velocity -= dir * accel * 0.4 * delta
            actor.velocity = actor.velocity.limit_length(actor.max_speed)
        1:
            actor.velocity += dir * accel * 1.3 * delta
            actor.velocity += perp * accel * 0.25 * sin(actor._juke_timer * 8.0) * delta
            actor.velocity = actor.velocity.limit_length(actor.max_speed * 1.15)
        _:
            actor.velocity -= dir * accel * 0.5 * delta
            actor.velocity += perp * accel * 1.1 * delta
            actor.velocity = actor.velocity.limit_length(actor.max_speed * 1.05)


func _tick_hit_and_run(actor: Node, dir: Vector2, dist: float, delta: float, aggro_range: float, orbit_distance: float) -> void:
    var accel: float = float(actor.acceleration) * 1.4
    actor._juke_timer += delta

    match actor._hr_phase:
        actor.HRPhase.APPROACH:
            actor.velocity += dir * accel * 1.5 * delta
            var weave: Vector2 = Vector2(-dir.y, dir.x) * sin(actor._juke_timer * 6.0) * 0.3
            actor.velocity += weave * accel * delta
            actor.velocity = actor.velocity.limit_length(actor.max_speed * 1.2)
            if dist < aggro_range * 0.9:
                actor._hr_phase = actor.HRPhase.ATTACK
                actor._hr_attack_timer = actor.HR_ATTACK_WINDOW
                actor._juke_dir = [-1.0, 1.0][randi() % 2]
        actor.HRPhase.ATTACK:
            actor._hr_attack_timer -= delta
            var perp: Vector2 = Vector2(-dir.y, dir.x) * float(actor._juke_dir)
            actor.velocity += perp * accel * 1.0 * delta
            if dist > orbit_distance * 1.5:
                actor.velocity += dir * accel * 0.7 * delta
            elif dist < orbit_distance * 0.4:
                actor.velocity -= dir * accel * 0.6 * delta
            actor.velocity = actor.velocity.limit_length(actor.max_speed * 1.1)
            if actor._hr_attack_timer <= 0.0 or actor._all_rails_on_cooldown():
                actor._hr_phase = actor.HRPhase.DISENGAGE
                actor._hr_disengage_timer = actor.HR_DISENGAGE_TIME
                actor._juke_dir = [-1.0, 1.0][randi() % 2]
        actor.HRPhase.DISENGAGE:
            actor._hr_disengage_timer -= delta
            var flee_perp: Vector2 = Vector2(-dir.y, dir.x) * float(actor._juke_dir)
            actor.velocity -= dir * accel * 1.2 * delta
            actor.velocity += flee_perp * accel * 0.6 * delta
            actor.velocity = actor.velocity.limit_length(actor.max_speed * actor.HR_DISENGAGE_SPEED_MULT)
            if actor._hr_disengage_timer <= 0.0:
                actor._hr_phase = actor.HRPhase.APPROACH
