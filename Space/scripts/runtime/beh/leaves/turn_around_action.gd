@tool
extends ActionLeaf

# Flips beh_facing on the actor. Walk leaves without an explicit dir
# read beh_facing so the next tick will drive the other way. Throttles
# itself via params.cooldown so a trigger that stays true for several
# ticks (wall_ahead, edge_ahead) doesn't oscillate the actor every frame.
#
# params:
#   cooldown: seconds between allowed flips. Default 0.4.

var _next_ok_at: float = 0.0


func tick(actor: Node, _blackboard: Blackboard) -> int:
    var now: float = float(Time.get_ticks_msec()) / 1000.0
    var cooldown: float = float(_params().get("cooldown", 0.4))
    if now < _next_ok_at:
        return SUCCESS
    if "beh_facing" in actor:
        actor.beh_facing = -int(actor.beh_facing)
    _next_ok_at = now + cooldown
    return SUCCESS


func _params() -> Dictionary:
    var p: Variant = get_meta("params", {})
    if typeof(p) != TYPE_DICTIONARY:
        return {}
    return p
