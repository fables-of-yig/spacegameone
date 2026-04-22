extends ActionLeaf


func tick(actor: Node, blackboard: Blackboard) -> int:
    if actor == null:
        return FAILURE
    var delta := float(blackboard.get_value("delta", 0.016))
    var accel := float(actor.acceleration) if "acceleration" in actor else 300.0
    actor.velocity = actor.velocity.move_toward(Vector2.ZERO, accel * 0.6 * delta)
    return RUNNING
