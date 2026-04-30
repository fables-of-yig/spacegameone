@tool
extends ActionLeaf

# Deals melee damage to the nearest mv_player within range. Reads the
# actor's attack_damage field by default (set by MvEnemy from the
# entity dict); override in params for per-behavior tuning. Self-
# throttles with a per-leaf cooldown.
#
# params:
#   range:    hit distance in pixels. Default 24.
#   damage:   override damage. Default reads actor.attack_damage (else 1).
#   cooldown: seconds between hits. Default 0.8.
#
# Returns SUCCESS when a player is in range, even while the internal
# cooldown is still counting down. This prevents selector-based melee
# brains from immediately falling through to pursue/walk every frame and
# jittering into the player between swings.

var _next_ok_at: float = 0.0


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if not (actor is Node2D):
        return FAILURE
    var now: float = float(Time.get_ticks_msec()) / 1000.0
    var tree := actor.get_tree()
    if tree == null:
        return FAILURE
    var params := _params()
    var range_default: float = 24.0
    if actor.has_method("default_melee_range"):
        range_default = float(actor.call("default_melee_range"))
    var range_px: float = float(params.get("range", range_default))
    var cooldown: float = float(params.get("cooldown", 0.8))
    var dmg_default: int = 1
    if "attack_damage" in actor:
        dmg_default = int(actor.attack_damage)
    var dmg: int = int(params.get("damage", dmg_default))
    var a_pos: Vector2 = _combat_origin(actor)
    for p in tree.get_nodes_in_group("mv_player"):
        if not (p is Node2D):
            continue
        var player_pos: Vector2 = _combat_origin(p)
        if player_pos.distance_to(a_pos) > range_px:
            continue
        var dir: float = 1.0 if player_pos.x >= a_pos.x else -1.0
        if actor.has_method("ai_face_dir"):
            actor.call("ai_face_dir", dir)
        if now < _next_ok_at:
            return SUCCESS
        if actor.has_method("queue_melee_attack"):
            actor.call("queue_melee_attack", p, range_px, dmg)
        elif p.has_method("take_damage"):
            p.take_damage(dmg, "enemy", a_pos)
        _next_ok_at = now + cooldown
        return SUCCESS
    return FAILURE


func _params() -> Dictionary:
    var p: Variant = get_meta("params", {})
    if typeof(p) != TYPE_DICTIONARY:
        return {}
    return p


func _combat_origin(node: Node) -> Vector2:
    if node != null and node.has_method("combat_origin"):
        var origin_v: Variant = node.call("combat_origin")
        if typeof(origin_v) == TYPE_VECTOR2:
            return origin_v
    return (node as Node2D).global_position if node is Node2D else Vector2.ZERO
