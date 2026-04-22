@tool
extends ActionLeaf

# Drives the actor's horizontal velocity from authored params.
# params:
#   dir:   +1 walks right, -1 walks left. Default: actor.beh_facing if
#          present, else +1. turn_around_action flips beh_facing so a
#          sequence (wall_ahead -> turn_around) -> walk swaps sides.
#   speed: pixels per second. Default 40.
#
# Always succeeds — pair with a condition/decorator (wall_ahead,
# player_near, cooldown) in the parent to decide when to stop walking.


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if not (actor is CharacterBody2D):
        return FAILURE
    var params := _params()
    var dir_default: float = 1.0
    if "beh_facing" in actor and float(actor.beh_facing) != 0.0:
        dir_default = float(actor.beh_facing)
    var dir: float = float(params.get("dir", dir_default))
    var speed_default: float = float(actor.move_speed) if "move_speed" in actor else 40.0
    var speed: float = float(params.get("speed", speed_default))
    (actor as CharacterBody2D).velocity.x = dir * speed
    if actor.has_method("ai_face_dir"):
        actor.call("ai_face_dir", dir)
    if actor.has_method("ai_request_pose"):
        actor.call("ai_request_pose", "move", 0.1, true, 1.0)
    return SUCCESS


func _params() -> Dictionary:
    var p: Variant = get_meta("params", {})
    if typeof(p) != TYPE_DICTIONARY:
        return {}
    return p
