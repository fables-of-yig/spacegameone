class_name MvProjectile
extends Area2D

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


func _ready() -> void:
    add_to_group("mv_projectile")
    monitoring = true
    monitorable = true
    if _shape == null:
        _shape = CollisionShape2D.new()
        var circle := CircleShape2D.new()
        circle.radius = 4.0
        _shape.shape = circle
        add_child(_shape)
    body_entered.connect(_on_body_entered)
    area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
    if MvGame.simulation_paused:
        return
    _age += delta
    if _age >= lifetime:
        queue_free()
        return
    global_position += direction * speed * delta


func _on_body_entered(body: Node) -> void:
    if body == null:
        return
    if body.is_in_group("mv_player") and body.has_method("take_damage"):
        body.take_damage(damage, "enemy_projectile", global_position)
        queue_free()


func _on_area_entered(area: Area2D) -> void:
    if area == null or not area.is_in_group("mv_player_hurt"):
        return
    var player: Node = area.get_meta("player", null)
    if player == null:
        player = area.get_parent()
    if player != null and player.has_method("take_damage"):
        player.take_damage(damage, "enemy_projectile", global_position)
        queue_free()


func _draw() -> void:
    draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.5, 0.2, 1.0))
    draw_circle(Vector2.ZERO, 2.0, Color(1.0, 0.9, 0.6, 1.0))
