@tool
extends ActionLeaf

# Sets velocity toward the nearest player in both axes. Intended for
# hover/fly enemies whose parent runtime suppresses gravity and keeps
# them aloft between explicit vertical steering ticks.
#
# params:
#   speed: pixels per second. Default reads actor.move_speed, else 80.


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if not (actor is CharacterBody2D):
        return FAILURE
    var tree := actor.get_tree()
    if tree == null:
        return FAILURE
    var best := _nearest_player(actor, tree)
    if best == null:
        return FAILURE
    var speed_default: float = float(actor.move_speed) if "move_speed" in actor else 80.0
    var speed: float = float(_params().get("speed", speed_default))
    var delta: Vector2 = best.global_position - (actor as Node2D).global_position
    if delta.length_squared() <= 0.0001:
        return FAILURE
    var dir := delta.normalized()
    (actor as CharacterBody2D).velocity = dir * speed
    if actor.has_method("ai_set_vertical_drive"):
        actor.call("ai_set_vertical_drive", true)
    if actor.has_method("ai_face_dir"):
        actor.call("ai_face_dir", dir.x if absf(dir.x) > 0.01 else 1.0)
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
