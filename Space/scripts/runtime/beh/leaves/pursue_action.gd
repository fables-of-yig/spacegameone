@tool
extends ActionLeaf

# Sets horizontal velocity toward the nearest mv_player. Mirror of
# flee_action. Returns FAILURE if no player is found.
#
# params:
#   speed: pixels per second. Default 80.


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if not (actor is CharacterBody2D):
        return FAILURE
    var tree := actor.get_tree()
    if tree == null:
        return FAILURE
    var best: Node2D = _nearest_player(actor, tree)
    if best == null:
        return FAILURE
    var speed_default: float = float(actor.move_speed) if "move_speed" in actor else 80.0
    var speed: float = float(_params().get("speed", speed_default))
    var dx: float = best.global_position.x - (actor as Node2D).global_position.x
    var dir: float = 1.0 if dx >= 0.0 else -1.0
    (actor as CharacterBody2D).velocity.x = dir * speed
    if actor.has_method("ai_face_dir"):
        actor.call("ai_face_dir", dir)
    elif "beh_facing" in actor:
        actor.beh_facing = int(dir)
    if actor.has_method("ai_request_pose"):
        actor.call("ai_request_pose", "move", 0.1, true, 1.0)
    return SUCCESS


func _nearest_player(actor: Node, tree: SceneTree) -> Node2D:
    var a_pos: Vector2 = (actor as Node2D).global_position
    var best: Node2D = null
    var best_d: float = INF
    for p in tree.get_nodes_in_group("mv_player"):
        if not (p is Node2D):
            continue
        var d: float = (p as Node2D).global_position.distance_to(a_pos)
        if d < best_d:
            best_d = d
            best = p
    return best


func _params() -> Dictionary:
    var p: Variant = get_meta("params", {})
    if typeof(p) != TYPE_DICTIONARY:
        return {}
    return p
