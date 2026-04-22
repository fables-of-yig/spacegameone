@tool
extends ConditionLeaf

# Returns SUCCESS when any node in the "mv_player" group is within
# params.range pixels of the actor. Falls back to 80 px when no range
# is authored. Uses groups instead of a hardcoded scene path so this
# leaf works across any level.


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if not (actor is Node2D):
        return FAILURE
    var tree := actor.get_tree()
    if tree == null:
        return FAILURE
    var range_px: float = float(_params().get("range", 80.0))
    var actor_pos: Vector2 = (actor as Node2D).global_position
    for p in tree.get_nodes_in_group("mv_player"):
        if p is Node2D:
            if (p as Node2D).global_position.distance_to(actor_pos) <= range_px:
                return SUCCESS
    return FAILURE


func _params() -> Dictionary:
    var p: Variant = get_meta("params", {})
    if typeof(p) != TYPE_DICTIONARY:
        return {}
    return p
