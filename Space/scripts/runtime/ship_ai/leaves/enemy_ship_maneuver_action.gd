@tool
extends ActionLeaf


func tick(actor: Node, blackboard: Blackboard) -> int:
    if actor == null:
        return FAILURE
    var dir: Vector2 = blackboard.get_value("dir", Vector2.ZERO)
    if dir == Vector2.ZERO:
        return FAILURE
    var dist := float(blackboard.get_value("dist", 0.0))
    var preferred_range := float(blackboard.get_value("preferred_range", 260.0))
    var delta := float(blackboard.get_value("delta", 0.016))
    var style := str(blackboard.get_value("behavior", "orbit"))
    var orbit_sign := float(blackboard.get_value("orbit_sign", 1.0))
    var desired := Vector2.ZERO
    var speed_mult := 1.0
    var accel_mult := 1.25

    actor.strafe_timer += delta
    actor.dodge_timer = maxf(actor.dodge_timer - delta, 0.0)
    match style:
        "kite":
            if dist < preferred_range * 1.1:
                desired = (-dir * 1.15 + Vector2(-dir.y, dir.x) * orbit_sign * 0.7).normalized()
            else:
                desired = _ring_dir(dir, dist, preferred_range * 1.7, orbit_sign, 1.0, 1.1)
            speed_mult = 1.05
        "tank":
            desired = _ring_dir(dir, dist, preferred_range * 0.9, orbit_sign, 0.25, 1.0)
            speed_mult = 0.9
            accel_mult = 1.0
        "approach":
            desired = _attack_run_dir(actor, dir, dist, preferred_range, orbit_sign, 0.65, 0.95)
            speed_mult = 1.1
            accel_mult = 1.4
        "aggressive":
            desired = _attack_run_dir(actor, dir, dist, preferred_range * 1.1, orbit_sign, 0.95, 1.15)
            speed_mult = 1.2
            accel_mult = 1.6
        "strafe":
            desired = _ring_dir(dir, dist, preferred_range * 1.3, orbit_sign, 1.25, 0.65)
            speed_mult = 1.15
            accel_mult = 1.5
        "elite":
            desired = _elite_dir(actor, dir, dist, preferred_range, orbit_sign)
            speed_mult = 1.2
            accel_mult = 1.65
        _:
            desired = _ring_dir(dir, dist, preferred_range, orbit_sign, 1.0, 0.75)
            speed_mult = 1.0

    if actor.strafe_timer > _flip_period(style):
        actor.strafe_timer = 0.0
        if randf() < 0.65:
            actor.orbit_dir *= -1.0
            blackboard.set_value("orbit_sign", float(actor.orbit_dir))

    _apply_motion(actor, desired, delta, accel_mult, speed_mult)
    return RUNNING


func _ring_dir(dir: Vector2, dist: float, preferred_range: float, orbit_sign: float, tangent_weight: float, radial_weight: float) -> Vector2:
    var tangent := Vector2(-dir.y, dir.x) * orbit_sign
    if dist < preferred_range * 0.7:
        return (-dir * 1.1 + tangent * 0.55).normalized()
    if dist > preferred_range * 1.6:
        return (dir * 1.1 + tangent * 0.25).normalized()
    var radial_error := clampf((dist - preferred_range) / maxf(preferred_range, 1.0), -1.2, 1.2)
    return (tangent * tangent_weight + dir * radial_error * radial_weight).normalized()


func _attack_run_dir(actor: Node, dir: Vector2, dist: float, preferred_range: float, orbit_sign: float, tangent_bias: float, close_bias: float) -> Vector2:
    if actor._lock_timer > 0.0 and actor._locked_dir.length_squared() > 0.01:
        return actor._locked_dir.normalized()
    if dist < preferred_range * 1.15 or actor.dodge_timer <= 0.0:
        actor.dodge_timer = randf_range(1.0, 1.8)
        var pass_perp := Vector2(-dir.y, dir.x) * orbit_sign
        actor._locked_dir = (dir * close_bias + pass_perp * tangent_bias).normalized()
        actor._lock_timer = randf_range(0.9, 1.7)
        return actor._locked_dir
    return (dir * 1.0 + Vector2(-dir.y, dir.x) * orbit_sign * 0.25).normalized()


func _elite_dir(actor: Node, dir: Vector2, dist: float, preferred_range: float, orbit_sign: float) -> Vector2:
    if actor._lock_timer > 0.0 and actor._locked_dir.length_squared() > 0.01:
        return actor._locked_dir.normalized()
    if actor.dodge_timer <= 0.0:
        actor.dodge_timer = randf_range(0.6, 1.1)
        var roll := randf()
        if roll < 0.34:
            actor._locked_dir = dir
        elif roll < 0.68:
            actor._locked_dir = Vector2(-dir.y, dir.x) * orbit_sign
        else:
            actor._locked_dir = -dir
        actor._lock_timer = randf_range(0.55, 1.0)
        return actor._locked_dir.normalized()
    if dist < preferred_range * 0.8:
        return (-dir * 0.8 + Vector2(-dir.y, dir.x) * orbit_sign).normalized()
    return (Vector2(-dir.y, dir.x) * orbit_sign + dir * 0.45).normalized()


func _apply_motion(actor: Node, desired_dir: Vector2, delta: float, accel_mult: float, speed_mult: float) -> void:
    if desired_dir == Vector2.ZERO:
        return
    var accel := float(actor.acceleration) * accel_mult
    var target_vel := desired_dir.normalized() * float(actor.max_speed) * speed_mult
    actor.velocity = actor.velocity.move_toward(target_vel, accel * delta)


func _flip_period(style: String) -> float:
    match style:
        "elite":
            return 0.9
        "aggressive":
            return 1.4
        "strafe":
            return 1.2
        "kite":
            return 1.8
        _:
            return 2.2
