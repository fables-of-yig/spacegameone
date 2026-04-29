@tool
extends ActionLeaf


func tick(actor: Node, blackboard: Blackboard) -> int:
    if actor == null:
        return FAILURE
    if not ("combat_target" in actor):
        return FAILURE
    if not (actor is Node2D):
        return FAILURE
    var actor_node: Node2D = actor as Node2D

    var target: Variant = actor.combat_target
    if not _target_valid(target):
        if actor.is_law_enforcement:
            actor._scan_for_hostiles()
        else:
            var players = actor.get_tree().get_nodes_in_group("player")
            if not players.is_empty():
                actor.combat_target = players[0]
        target = actor.combat_target

    if not _target_valid(target):
        blackboard.set_value("target", null)
        return FAILURE

    var target_node: Node2D = target as Node2D
    var to_target: Vector2 = target_node.global_position - actor_node.global_position
    var dist: float = to_target.length()
    if dist <= 0.001:
        return FAILURE

    var dir: Vector2 = to_target / dist
    var shooter_velocity: Vector2 = actor.velocity if "velocity" in actor else Vector2.ZERO
    var target_velocity: Vector2 = target_node.velocity if "velocity" in target_node else Vector2.ZERO
    var projectile_speed: float = _projectile_speed_for_actor(actor)
    var aim_dir: Vector2 = _solve_intercept_dir(to_target, target_velocity - shooter_velocity, projectile_speed)
    blackboard.set_value("target", target_node)
    blackboard.set_value("dist", dist)
    blackboard.set_value("dir", dir)
    blackboard.set_value("aim_dir", aim_dir)
    blackboard.set_value("target_angle", aim_dir.angle())
    blackboard.set_value("perp", Vector2(-dir.y, dir.x))
    blackboard.set_value("combat_style", str(actor.combat_style))
    blackboard.set_value("aggro_range", float(actor.aggro_range))
    blackboard.set_value("orbit_distance", float(actor.orbit_distance))
    return SUCCESS


func _target_valid(target: Variant) -> bool:
    return target is Node2D and is_instance_valid(target)


func _projectile_speed_for_actor(actor: Node) -> float:
    if "projectile_speed" in actor:
        return float(actor.projectile_speed)
    if "_npc_weapons" in actor and actor._npc_weapons is Array and not actor._npc_weapons.is_empty():
        var speed_v: Variant = actor._npc_weapons[0].get("speed", 450.0)
        return float(speed_v)
    return 450.0


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
