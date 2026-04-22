extends ActionLeaf


func tick(actor: Node, blackboard: Blackboard) -> int:
    if actor == null:
        return FAILURE
    var dir: Vector2 = blackboard.get_value("dir", Vector2.ZERO)
    if dir == Vector2.ZERO:
        return FAILURE
    var delta := float(blackboard.get_value("delta", 0.016))
    var orbit_sign := float(blackboard.get_value("orbit_sign", 1.0))
    var desired := (-dir * 1.25 + Vector2(-dir.y, dir.x) * orbit_sign * 0.35).normalized()
    _apply_motion(actor, desired, delta, 1.8, 1.1)
    return RUNNING


func _apply_motion(actor: Node, desired_dir: Vector2, delta: float, accel_mult: float, speed_mult: float) -> void:
    if desired_dir == Vector2.ZERO:
        return
    var accel := float(actor.acceleration) * accel_mult
    var target_vel := desired_dir.normalized() * float(actor.max_speed) * speed_mult
    actor.velocity = actor.velocity.move_toward(target_vel, accel * delta)
