extends ActionLeaf


func tick(actor: Node, blackboard: Blackboard) -> int:
    if actor == null:
        return FAILURE
    var target: Variant = blackboard.get_value("target", null)
    if not (target is Node2D and is_instance_valid(target)):
        return FAILURE

    var dist := float(blackboard.get_value("dist", INF))
    var dir: Vector2 = blackboard.get_value("dir", Vector2.ZERO)
    if dir == Vector2.ZERO:
        return FAILURE
    var target_angle := float(blackboard.get_value("target_angle", dir.angle()))
    var style := str(blackboard.get_value("combat_style", "standard"))
    var aggro_range := float(blackboard.get_value("aggro_range", actor.aggro_range if "aggro_range" in actor else 800.0))

    actor.rotation = lerp_angle(actor.rotation, target_angle, 12.0 * float(blackboard.get_value("delta", 0.016)))

    match style:
        "hit_and_run":
            if actor._hr_phase == actor.HRPhase.ATTACK and _aim_error_ok(actor.rotation, target_angle, 0.75):
                actor._fire_all_weapons()
                return SUCCESS
        _:
            if dist < aggro_range * 1.5 and _aim_error_ok(actor.rotation, target_angle, 0.7):
                actor._fire_all_weapons()
                return SUCCESS
    return FAILURE


func _aim_error_ok(current_angle: float, target_angle: float, tolerance: float) -> bool:
    return absf(angle_difference(current_angle, target_angle)) <= tolerance
