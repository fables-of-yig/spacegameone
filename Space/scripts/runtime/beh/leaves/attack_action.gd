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
# Returns SUCCESS when a player is in range (cooldown advanced even if
# invuln blocks the hit), FAILURE when nobody is close or the cooldown
# is still counting down.

var _next_ok_at: float = 0.0


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if not (actor is Node2D):
        return FAILURE
    var now: float = float(Time.get_ticks_msec()) / 1000.0
    if now < _next_ok_at:
        return FAILURE
    var tree := actor.get_tree()
    if tree == null:
        return FAILURE
    var params := _params()
    var range_px: float = float(params.get("range", 24.0))
    var cooldown: float = float(params.get("cooldown", 0.8))
    var dmg_default: int = 1
    if "attack_damage" in actor:
        dmg_default = int(actor.attack_damage)
    var dmg: int = int(params.get("damage", dmg_default))
    var a_pos: Vector2 = (actor as Node2D).global_position
    for p in tree.get_nodes_in_group("mv_player"):
        if not (p is Node2D):
            continue
        var player := p as Node2D
        var player_pos: Vector2 = player.global_position
        if player_pos.distance_to(a_pos) > range_px:
            continue
        var dir: float = 1.0 if player_pos.x >= a_pos.x else -1.0
        if actor.has_method("ai_face_dir"):
            actor.call("ai_face_dir", dir)
        if actor.has_method("ai_request_pose"):
            actor.call("ai_request_pose", "attack", maxf(0.12, cooldown * 0.35), false, 1.0)
        if p.has_method("take_damage"):
            p.take_damage(dmg, "enemy", a_pos)
        _next_ok_at = now + cooldown
        return SUCCESS
    return FAILURE


func _params() -> Dictionary:
    var p: Variant = get_meta("params", {})
    if typeof(p) != TYPE_DICTIONARY:
        return {}
    return p
