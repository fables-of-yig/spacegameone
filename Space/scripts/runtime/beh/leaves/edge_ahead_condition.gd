@tool
extends ConditionLeaf

# SUCCESS when there is NO floor a short distance ahead of the actor's
# facing — useful to stop a patroller before walking off a ledge.
# Probes with a single downward raycast at (facing * ahead_px) relative
# to the body center.
#
# params:
#   ahead_px: horizontal probe offset. Default 10.
#   drop_px:  downward probe depth. Default 16.


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if not (actor is CharacterBody2D):
        return FAILURE
    var body := actor as CharacterBody2D
    var params := _params()
    var ahead: float = float(params.get("ahead_px", 10.0))
    var drop: float = float(params.get("drop_px", 16.0))
    var facing: float = 1.0
    if "beh_facing" in actor:
        facing = float(actor.beh_facing)
    if facing == 0.0:
        facing = 1.0
    var world := body.get_world_2d()
    if world == null:
        return FAILURE
    var space := world.direct_space_state
    var from: Vector2 = body.global_position + Vector2(ahead * facing, 0.0)
    var to: Vector2 = from + Vector2(0.0, drop)
    var q := PhysicsRayQueryParameters2D.create(from, to, body.collision_mask, [body.get_rid()])
    var hit: Dictionary = space.intersect_ray(q)
    return FAILURE if not hit.is_empty() else SUCCESS


func _params() -> Dictionary:
    var p: Variant = get_meta("params", {})
    if typeof(p) != TYPE_DICTIONARY:
        return {}
    return p
