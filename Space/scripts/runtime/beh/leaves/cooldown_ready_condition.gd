@tool
extends ConditionLeaf

# Named timer check. First tick returns SUCCESS and stores the
# next-available time on the actor's metadata; later ticks return
# FAILURE until the cooldown elapses. Useful for gating rare actions
# (telegraph, special shot) without needing a CooldownDecorator.
#
# params:
#   name:    suffix for the actor-metadata key. Default "cd".
#   seconds: cooldown length. Default 1.0.


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if actor == null:
        return FAILURE
    var params := _params()
    var n: String = str(params.get("name", "cd"))
    var seconds: float = float(params.get("seconds", 1.0))
    var key: String = "beh_cd_%s" % n
    var now: float = float(Time.get_ticks_msec()) / 1000.0
    var next_ok: float = float(actor.get_meta(key, 0.0))
    if now >= next_ok:
        actor.set_meta(key, now + seconds)
        return SUCCESS
    return FAILURE


func _params() -> Dictionary:
    var p: Variant = get_meta("params", {})
    if typeof(p) != TYPE_DICTIONARY:
        return {}
    return p
