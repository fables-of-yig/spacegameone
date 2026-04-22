@tool
extends ActionLeaf

# Applies an upward impulse when the actor is on the floor. Returns
# SUCCESS when the jump fires, FAILURE when airborne so a parent
# selector can fall through to the next branch.
#
# params:
#   impulse: jump velocity in px/s (applied as -y). Default 240.


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if not (actor is CharacterBody2D):
        return FAILURE
    var body := actor as CharacterBody2D
    if not body.is_on_floor():
        return FAILURE
    var impulse: float = float(_params().get("impulse", 240.0))
    body.velocity.y = -impulse
    if actor.has_method("ai_request_pose"):
        actor.call("ai_request_pose", "jump", 0.18, false, 1.0)
    return SUCCESS


func _params() -> Dictionary:
    var p: Variant = get_meta("params", {})
    if typeof(p) != TYPE_DICTIONARY:
        return {}
    return p
