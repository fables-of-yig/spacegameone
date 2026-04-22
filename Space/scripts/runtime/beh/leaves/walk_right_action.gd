@tool
extends ActionLeaf

# Drives actor's horizontal velocity rightward. Explicit direction —
# does NOT update beh_facing.
#
# params:
#   speed: pixels per second. Default 40.


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if not (actor is CharacterBody2D):
        return FAILURE
    var speed_default: float = float(actor.move_speed) if "move_speed" in actor else 40.0
    var speed: float = float(_params().get("speed", speed_default))
    (actor as CharacterBody2D).velocity.x = speed
    return SUCCESS


func _params() -> Dictionary:
    var p: Variant = get_meta("params", {})
    if typeof(p) != TYPE_DICTIONARY:
        return {}
    return p
