extends ActionLeaf


func tick(actor: Node, blackboard: Blackboard) -> int:
    if not (actor is Node2D):
        return FAILURE
    if not ("target" in actor and "orbit_distance" in actor):
        return FAILURE
    var actor_node: Node2D = actor as Node2D

    if not _target_valid(actor.target):
        if actor.has_method("_find_target"):
            actor._find_target()
    if not _target_valid(actor.target):
        blackboard.set_value("target", null)
        return FAILURE

    var target: Node2D = actor.target
    var to_target: Vector2 = target.global_position - actor_node.global_position
    var dist: float = to_target.length()
    if dist <= 0.001:
        return FAILURE

    var dir: Vector2 = to_target / dist
    var shooter_velocity: Vector2 = actor.velocity if "velocity" in actor else Vector2.ZERO
    var target_velocity: Vector2 = target.velocity if "velocity" in target else Vector2.ZERO
    var projectile_speed: float = float(actor.proj_speed) if "proj_speed" in actor else 500.0
    var aim_dir: Vector2 = _solve_intercept_dir(to_target, target_velocity - shooter_velocity, projectile_speed)
    var preferred_range: float = maxf(float(actor.orbit_distance), float(actor.ship_size) * 8.0 if "ship_size" in actor else 180.0)
    var health_ratio: float = 1.0
    if "max_health" in actor and actor.max_health > 0.0:
        health_ratio = float(actor.health) / float(actor.max_health)

    blackboard.set_value("target", target)
    blackboard.set_value("dist", dist)
    blackboard.set_value("dir", dir)
    blackboard.set_value("aim_dir", aim_dir)
    blackboard.set_value("perp", Vector2(-dir.y, dir.x))
    blackboard.set_value("target_angle", aim_dir.angle())
    blackboard.set_value("preferred_range", preferred_range)
    blackboard.set_value("health_ratio", health_ratio)
    blackboard.set_value("behavior", str(actor.behavior) if "behavior" in actor else "orbit")
    blackboard.set_value("orbit_sign", float(actor.orbit_dir) if "orbit_dir" in actor else 1.0)
    return SUCCESS


func _target_valid(target: Variant) -> bool:
    return target is Node2D and is_instance_valid(target)


func _solve_intercept_dir(relative_pos: Vector2, relative_velocity: Vector2, projectile_speed: float) -> Vector2:
    if projectile_speed <= 0.001:
        return relative_pos.normalized()
    var a: float = relative_velocity.dot(relative_velocity) - projectile_speed * projectile_speed
    var b: float = 2.0 * relative_pos.dot(relative_velocity)
    var c: float = relative_pos.dot(relative_pos)
    var intercept_time: float = -1.0
    if absf(a) < 0.0001:
        if absf(b) > 0.0001:
            intercept_time = -c / b
    else:
        var disc: float = b * b - 4.0 * a * c
        if disc >= 0.0:
            var sqrt_disc: float = sqrt(disc)
            var t1: float = (-b - sqrt_disc) / (2.0 * a)
            var t2: float = (-b + sqrt_disc) / (2.0 * a)
            if t1 > 0.0 and t2 > 0.0:
                intercept_time = minf(t1, t2)
            elif t1 > 0.0:
                intercept_time = t1
            elif t2 > 0.0:
                intercept_time = t2
    if intercept_time <= 0.0:
        return relative_pos.normalized()
    var lead_vector: Vector2 = relative_pos + relative_velocity * intercept_time
    if lead_vector.length_squared() <= 0.0001:
        return relative_pos.normalized()
    return lead_vector.normalized()
