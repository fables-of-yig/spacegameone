extends ActionLeaf


func tick(actor: Node, blackboard: Blackboard) -> int:
    if actor == null:
        return FAILURE
    var target: Variant = blackboard.get_value("target", null)
    if not (target is Node2D and is_instance_valid(target)):
        return FAILURE
    if not ("can_fire" in actor and actor.can_fire):
        return FAILURE

    var delta := float(blackboard.get_value("delta", 0.016))
    var dist := float(blackboard.get_value("dist", INF))
    var target_angle := float(blackboard.get_value("target_angle", actor.rotation))
    var style := str(blackboard.get_value("behavior", "orbit"))
    var preferred_range := float(blackboard.get_value("preferred_range", 240.0))

    actor.rotation = lerp_angle(actor.rotation, target_angle, minf(1.0, 11.0 * delta))

    var range_limit := _range_limit(actor, preferred_range)
    if dist > range_limit:
        return FAILURE

    var aim_tolerance := _aim_tolerance(style, actor)
    var aim_error := absf(angle_difference(actor.rotation, target_angle))
    if aim_error > aim_tolerance:
        return FAILURE

    if actor.has_method("_fire"):
        actor._fire()
        actor.can_fire = false
        var cooldown := _cooldown(actor, style)
        actor.get_tree().create_timer(cooldown, true, false, false).timeout.connect(func():
            if is_instance_valid(actor):
                actor.can_fire = true
        )
        return SUCCESS
    return FAILURE


func _range_limit(actor: Node, preferred_range: float) -> float:
    var weapon_type := str(actor.weapon_type) if "weapon_type" in actor else "laser"
    match weapon_type:
        "missile":
            return preferred_range * 6.0
        "heavy":
            return preferred_range * 4.8
        "plasma":
            return preferred_range * 4.2
        "burst":
            return preferred_range * 3.8
        _:
            return preferred_range * 4.0


func _aim_tolerance(style: String, actor: Node) -> float:
    var weapon_type := str(actor.weapon_type) if "weapon_type" in actor else "laser"
    if weapon_type == "missile":
        return 0.9
    match style:
        "aggressive":
            return 0.62
        "strafe", "elite":
            return 0.68
        _:
            return 0.58


func _cooldown(actor: Node, style: String) -> float:
    var base := float(actor.fire_rate) if "fire_rate" in actor else 1.0
    match style:
        "aggressive":
            return base * 0.55
        "strafe":
            return base * 0.65
        "elite":
            return base * 0.4
        "kite":
            return base * 0.8
        _:
            return base * 0.75
