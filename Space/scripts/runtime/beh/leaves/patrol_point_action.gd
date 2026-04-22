@tool
extends ActionLeaf

# Walks the actor toward a world-space target_x. Flips beh_facing when
# within tolerance so a parent sequence (or next tick) can pick a new
# target, or so a pair of patrol_point leaves in a sequence_star
# bounce between two points.
#
# params:
#   target_x:  world-space target. Default actor's current x (no-op).
#   speed:     pixels per second. Default 40.
#   tolerance: reach radius. Default 4.


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if not (actor is CharacterBody2D):
        return FAILURE
    var body := actor as CharacterBody2D
    var params := _params()
    var speed_default: float = float(actor.move_speed) if "move_speed" in actor else 40.0
    var speed: float = float(params.get("speed", speed_default))
    var tolerance: float = float(params.get("tolerance", 4.0))
    var my_x: float = body.global_position.x
    var target_x: float = float(params.get("target_x", my_x))
    var delta_x: float = target_x - my_x
    if abs(delta_x) <= tolerance:
        if "beh_facing" in actor:
            actor.beh_facing = -int(actor.beh_facing)
        body.velocity.x = 0.0
        if actor.has_method("ai_request_pose"):
            actor.call("ai_request_pose", "idle", 0.1, true, 1.0)
        return SUCCESS
    var dir: float = 1.0 if delta_x > 0.0 else -1.0
    body.velocity.x = dir * speed
    if actor.has_method("ai_face_dir"):
        actor.call("ai_face_dir", dir)
    elif "beh_facing" in actor:
        actor.beh_facing = int(dir)
    if actor.has_method("ai_request_pose"):
        actor.call("ai_request_pose", "move", 0.1, true, 1.0)
    return RUNNING


func _params() -> Dictionary:
    var p: Variant = get_meta("params", {})
    if typeof(p) != TYPE_DICTIONARY:
        return {}
    return p
