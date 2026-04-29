@tool
extends ActionLeaf


func tick(actor: Node, blackboard: Blackboard) -> int:
    if actor == null:
        return FAILURE
    var delta := float(blackboard.get_value("delta", 0.016))
    actor.velocity *= pow(0.98, delta * 60.0)
    actor._apply_star_avoidance(delta)
    return RUNNING
