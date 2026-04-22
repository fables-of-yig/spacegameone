@tool
extends ConditionLeaf

# SUCCESS when the actor's hp is at or below a threshold. Threshold
# values <=1.0 are interpreted as a fraction of max_hp; values >1 are
# absolute hp.
#
# params:
#   threshold: fraction (0.0..1.0) or absolute hp. Default 0.3.


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if not ("hp" in actor):
        return FAILURE
    var threshold: float = float(_params().get("threshold", 0.3))
    var hp: int = int(actor.hp)
    if threshold <= 1.0:
        var max_hp: int = 1
        if "max_hp" in actor:
            max_hp = maxi(1, int(actor.max_hp))
        return SUCCESS if float(hp) <= float(max_hp) * threshold else FAILURE
    return SUCCESS if hp <= int(threshold) else FAILURE


func _params() -> Dictionary:
    var p: Variant = get_meta("params", {})
    if typeof(p) != TYPE_DICTIONARY:
        return {}
    return p
