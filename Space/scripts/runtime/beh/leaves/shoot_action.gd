@tool
extends ActionLeaf

# Spawns an MvProjectile aimed at either the nearest mv_player or
# along the actor's beh_facing. Self-throttles with cooldown so repeat
# ticks don't flood the scene.
#
# params:
#   speed:    projectile speed px/s. Default 180.
#   damage:   damage on hit. Default 1.
#   lifetime: seconds before despawn. Default 2.
#   aim:      "facing" or "player". Default "facing".
#   cooldown: seconds between shots. Default 1.2.

const MvProjectile = preload("res://MV/scripts/projectile.gd")

var _next_ok_at: float = 0.0


func tick(actor: Node, _blackboard: Blackboard) -> int:
    if not (actor is Node2D):
        return FAILURE
    var now: float = float(Time.get_ticks_msec()) / 1000.0
    if now < _next_ok_at:
        return FAILURE
    var params := _params()
    var dir: Vector2 = _aim_dir(actor, params)
    if dir == Vector2.ZERO:
        return FAILURE
    var speed_default: float = float(actor.projectile_speed) if "projectile_speed" in actor else 180.0
    var damage_default: int = int(actor.projectile_damage) if "projectile_damage" in actor else 1
    var shot_speed := float(params.get("speed", speed_default))
    var shot_damage := int(params.get("damage", damage_default))
    var shot_lifetime := float(params.get("lifetime", 2.0))
    if actor.has_method("ai_face_dir"):
        actor.call("ai_face_dir", dir.x if absf(dir.x) > 0.01 else 1.0)
    if actor.has_method("ai_request_pose"):
        actor.call("ai_request_pose", "attack", maxf(0.14, float(params.get("cooldown", 1.2)) * 0.3), false, 1.0)
    if actor.has_method("fire_projectile"):
        if not bool(actor.call("fire_projectile", dir, shot_speed, shot_damage, shot_lifetime)):
            return FAILURE
    else:
        var parent := actor.get_parent()
        if parent == null:
            return FAILURE
        var proj = MvProjectile.new()
        proj.direction = dir
        proj.speed = shot_speed
        proj.damage = shot_damage
        proj.lifetime = shot_lifetime
        proj.global_position = (actor as Node2D).global_position
        parent.add_child(proj)
    _next_ok_at = now + float(params.get("cooldown", 1.2))
    return SUCCESS


func _aim_dir(actor: Node, params: Dictionary) -> Vector2:
    var aim: String = str(params.get("aim", "facing"))
    if aim == "player":
        var tree := actor.get_tree()
        if tree == null:
            return Vector2.ZERO
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
        if best == null:
            return Vector2.ZERO
        var v: Vector2 = best.global_position - a_pos
        return v.normalized() if v.length_squared() > 0.001 else Vector2.RIGHT
    var facing_x: float = 1.0
    if "beh_facing" in actor:
        facing_x = float(actor.beh_facing)
    if facing_x == 0.0:
        facing_x = 1.0
    return Vector2(facing_x, 0.0)


func _params() -> Dictionary:
    var p: Variant = get_meta("params", {})
    if typeof(p) != TYPE_DICTIONARY:
        return {}
    return p
