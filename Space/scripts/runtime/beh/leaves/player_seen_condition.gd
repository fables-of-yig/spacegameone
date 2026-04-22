@tool
extends ConditionLeaf

# SUCCESS when a mv_player is within range AND the actor has a clear
# line of sight (no collider between them). Raycast uses the actor's
# own collision_mask so walls that stop the actor also block vision.
#
# params:
#   range: detection radius. Default 150.


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if not (actor is CharacterBody2D):
        return FAILURE
    var body := actor as CharacterBody2D
    var tree := body.get_tree()
    if tree == null:
        return FAILURE
    var world := body.get_world_2d()
    if world == null:
        return FAILURE
    var range_px: float = float(_params().get("range", 150.0))
    var a_pos: Vector2 = body.global_position
    var space := world.direct_space_state
    for p in tree.get_nodes_in_group("mv_player"):
        if not (p is Node2D):
            continue
        var pp: Vector2 = (p as Node2D).global_position
        if pp.distance_to(a_pos) > range_px:
            continue
        var q := PhysicsRayQueryParameters2D.create(a_pos, pp, body.collision_mask, [body.get_rid()])
        var hit: Dictionary = space.intersect_ray(q)
        if hit.is_empty():
            return SUCCESS
    return FAILURE


func _params() -> Dictionary:
    var p: Variant = get_meta("params", {})
    if typeof(p) != TYPE_DICTIONARY:
        return {}
    return p
