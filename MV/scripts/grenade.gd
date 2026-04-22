class_name MvGrenade
extends RigidBody2D

# Thrown explosive. Arcs under gravity, bounces off world geometry,
# detonates on fuse expiry or enemy contact. On detonate: AoE damage
# to mv_enemy inside BLAST_RADIUS, bomb-jump push to mv_player if it's
# in radius, fires "bomb_explode" trigger event, self-destroys.
#
# Set throw_dir, throw_speed, throw_up, damage before add_child. The
# player's _fire_grenade_launcher uses these to toss in aim direction.

const FUSE_SEC: float = 1.1
const BLAST_RADIUS: float = 44.0
const BASE_DAMAGE: int = 20
const BOMB_JUMP_SPEED: float = 280.0

@export var damage: int = BASE_DAMAGE

var throw_dir: Vector2 = Vector2.RIGHT
var throw_speed: float = 220.0
var throw_up: float = 180.0

var _fuse: float = 0.0
var _exploded: bool = false


func _ready() -> void:
    add_to_group("mv_grenade")
    gravity_scale = 1.0
    linear_damp = 0.4
    angular_damp = 2.0
    contact_monitor = true
    max_contacts_reported = 4

    var mat := PhysicsMaterial.new()
    mat.bounce = 0.35
    mat.friction = 0.7
    physics_material_override = mat

    var shape := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = 3.5
    shape.shape = circle
    add_child(shape)

    body_entered.connect(_on_body_entered)

    linear_velocity = Vector2(throw_dir.x * throw_speed, -throw_up)


func _physics_process(delta: float) -> void:
    if _exploded:
        return
    if MvGame.simulation_paused:
        return
    _fuse += delta
    if _fuse >= FUSE_SEC:
        _detonate()


func _on_body_entered(body: Node) -> void:
    if _exploded:
        return
    if body.is_in_group("mv_enemy"):
        _detonate()


func _detonate() -> void:
    if _exploded:
        return
    _exploded = true
    freeze = true

    MvTriggerEngine.fire_event("bomb_explode", {
        "position": global_position,
        "radius": BLAST_RADIUS,
        "damage": damage,
    })

    for enemy in get_tree().get_nodes_in_group("mv_enemy"):
        if not is_instance_valid(enemy):
            continue
        var ep: Vector2 = (enemy as Node2D).global_position
        if ep.distance_to(global_position) <= BLAST_RADIUS:
            if enemy.has_method("take_damage"):
                enemy.take_damage(damage, global_position)

    for player in get_tree().get_nodes_in_group("mv_player"):
        if not is_instance_valid(player):
            continue
        var pp: Vector2 = (player as Node2D).global_position
        if pp.distance_to(global_position) <= BLAST_RADIUS:
            if player.has_method("apply_bomb_jump"):
                player.apply_bomb_jump(BOMB_JUMP_SPEED)

    queue_free()


func _draw() -> void:
    var t := _fuse / FUSE_SEC
    var body_col := Color(0.25, 0.25, 0.28, 1.0).lerp(Color(1.0, 0.3, 0.15, 1.0), t)
    draw_circle(Vector2.ZERO, 3.5, body_col)
    draw_circle(Vector2.ZERO, 1.6, Color(0.9, 0.85, 0.4, 1.0))


func _process(_delta: float) -> void:
    if not _exploded:
        queue_redraw()
