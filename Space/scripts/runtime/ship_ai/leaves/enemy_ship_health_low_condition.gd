@tool
extends ConditionLeaf


func tick(actor: Node, blackboard: Blackboard) -> int:
    if actor == null:
        return FAILURE
    var threshold := float(_params().get("threshold", 0.25))
    var health_ratio := float(blackboard.get_value("health_ratio", 1.0))
    return SUCCESS if health_ratio <= threshold else FAILURE


func _params() -> Dictionary:
    var raw: Variant = get_meta("params", {})
    return raw if typeof(raw) == TYPE_DICTIONARY else {}
