class_name MvProjectile
extends Area2D

const _MvBulletImpactFx := preload("res://MV/scripts/bullet_impact_fx.gd")

# Simple physics-less projectile used by enemy shoot leaves. Moves at
# constant velocity, damages mv_player or mv_player_hurt on overlap,
# self-destroys on lifetime expiry or on any player hit. Passes through
# walls — use lifetime to bound travel.
#
# Set `direction`, `speed`, `damage`, `lifetime` before add_child.

@export var speed: float = 180.0
@export var damage: int = 1
@export var lifetime: float = 2.0

var direction: Vector2 = Vector2.RIGHT

var _age: float = 0.0
var _shape: CollisionShape2D = null
var _initial_overlap_scan_pending: bool = true
const HIT_RADIUS: float = 4.0


func _ready() -> void:
    add_to_group("mv_projectile")
    monitoring = true
    monitorable = true
    if _shape == null:
        _shape = CollisionShape2D.new()
        var circle := CircleShape2D.new()
        circle.radius = HIT_RADIUS
        _shape.shape = circle
        add_child(_shape)
    body_entered.connect(_on_body_entered)
    area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
    var mv_game := _mv_game()
    if mv_game != null and bool(mv_game.get("simulation_paused")):
        return
    _age += delta
    if _age >= lifetime:
        queue_free()
        return
    if _initial_overlap_scan_pending:
        _initial_overlap_scan_pending = false
        _apply_initial_overlaps()
        if is_queued_for_deletion():
            return
    var next_pos := global_position + direction * speed * delta
    var world_hit := _first_world_collision(global_position, next_pos)
    if bool(world_hit.get("hit", false)):
        global_position = world_hit.get("point", global_position)
        _spawn_impact_fx(global_position, -direction)
        queue_free()
        return
    global_position = next_pos
    _apply_geometry_hits()


func _on_body_entered(body: Node) -> void:
    if body == null:
        return
    if body.is_in_group("mv_player") and body.has_method("take_damage"):
        body.take_damage(damage, "enemy_projectile", global_position)
        _spawn_impact_fx(global_position, _impact_normal_toward(body))
        queue_free()


func _on_area_entered(area: Area2D) -> void:
    if area == null or not area.is_in_group("mv_player_hurt"):
        return
    var player: Node = area.get_meta("player", null)
    if player == null:
        player = area.get_parent()
    if player != null and player.has_method("take_damage"):
        player.take_damage(damage, "enemy_projectile", global_position)
        _spawn_impact_fx(global_position, _impact_normal_toward(player))
        queue_free()


func _apply_initial_overlaps() -> void:
    for body in get_overlapping_bodies():
        _on_body_entered(body)
        if is_queued_for_deletion():
            return
    for area in get_overlapping_areas():
        _on_area_entered(area)
        if is_queued_for_deletion():
            return


func _apply_geometry_hits() -> void:
    var hit_rect := Rect2(global_position - Vector2(HIT_RADIUS, HIT_RADIUS), Vector2(HIT_RADIUS * 2.0, HIT_RADIUS * 2.0))
    for player in get_tree().get_nodes_in_group("mv_player"):
        if not is_instance_valid(player):
            continue
        if player.has_method("hurtbox_intersects_rect"):
            if bool(player.call("hurtbox_intersects_rect", hit_rect)):
                if player.has_method("take_damage"):
                    player.call("take_damage", damage, "enemy_projectile", global_position)
                    queue_free()
                    return
        elif player is Node2D and hit_rect.has_point((player as Node2D).global_position):
            if player.has_method("take_damage"):
                player.call("take_damage", damage, "enemy_projectile", global_position)
                queue_free()
                return


func _draw() -> void:
    draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.5, 0.2, 1.0))
    draw_circle(Vector2.ZERO, 2.0, Color(1.0, 0.9, 0.6, 1.0))


func _first_world_collision(from_pos: Vector2, to_pos: Vector2) -> Dictionary:
    var mv_game := _mv_game()
    var room: Node = mv_game.get("room_manager") if mv_game != null else null
    if room == null or not room.has_method("is_solid_at_world_pos"):
        return {"hit": false}
    var travel := from_pos.distance_to(to_pos)
    var steps := maxi(1, int(ceil(travel / 4.0)))
    var last_safe := from_pos
    for i in range(1, steps + 1):
        var t := float(i) / float(steps)
        var sample := from_pos.lerp(to_pos, t)
        if _overlaps_world_at(sample, room):
            return {"hit": true, "point": _refine_world_collision(last_safe, sample, room)}
        last_safe = sample
    return {"hit": false}


func _overlaps_world_at(center: Vector2, room: Node) -> bool:
    for point in _world_probe_points(center):
        if bool(room.call("is_solid_at_world_pos", point)):
            return true
    return false


func _mv_game() -> Node:
    var tree := get_tree()
    if tree == null or tree.root == null:
        return null
    return tree.root.get_node_or_null("MvGame")


func _world_probe_points(center: Vector2) -> Array:
    return [
        center,
        center + Vector2(HIT_RADIUS, 0.0),
        center + Vector2(-HIT_RADIUS, 0.0),
        center + Vector2(0.0, HIT_RADIUS),
        center + Vector2(0.0, -HIT_RADIUS),
    ]


func _refine_world_collision(safe_pos: Vector2, blocked_pos: Vector2, room: Node) -> Vector2:
    var lo := safe_pos
    var hi := blocked_pos
    for _i in range(6):
        var mid := lo.lerp(hi, 0.5)
        if _overlaps_world_at(mid, room):
            hi = mid
        else:
            lo = mid
    return hi


func _spawn_impact_fx(hit_pos: Vector2, normal: Vector2 = Vector2.ZERO) -> void:
    var parent := get_parent()
    if parent == null:
        return
    var fx := _MvBulletImpactFx.new()
    parent.add_child(fx)
    fx.setup(hit_pos, normal, 4)


func _impact_normal_toward(target: Node) -> Vector2:
    if target is Node2D:
        return (global_position - (target as Node2D).global_position).normalized()
    return -direction
