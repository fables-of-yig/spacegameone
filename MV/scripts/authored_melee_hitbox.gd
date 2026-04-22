class_name MvAuthoredMeleeHitbox
extends Area2D

var _damage: int = 0
var _lifetime: float = 1.0 / 60.0
var _already_hit: Dictionary = {}
var _rect_size: Vector2 = Vector2(16, 16)
var _shape: CollisionShape2D = null


func configure(world_pos: Vector2, rect_size: Vector2, damage: int, lifetime_sec: float = 1.0 / 60.0) -> void:
	global_position = world_pos
	_rect_size = Vector2(maxf(1.0, rect_size.x), maxf(1.0, rect_size.y))
	_damage = maxi(0, damage)
	_lifetime = maxf(1.0 / 120.0, lifetime_sec)
	_build_shape()
	queue_redraw()


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if MvGame.simulation_paused:
		return
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()


func _draw() -> void:
	draw_rect(Rect2(-_rect_size * 0.5, _rect_size), Color(1.0, 0.35, 0.2, 0.18))


func _build_shape() -> void:
	if _shape != null:
		return
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _rect_size
	_shape.shape = rect
	add_child(_shape)


func _on_area_entered(area: Area2D) -> void:
	var parent := area.get_parent()
	if parent == null or not parent.is_in_group("mv_enemy"):
		return
	_apply_damage(parent)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("mv_enemy"):
		return
	_apply_damage(body)


func _apply_damage(target: Node) -> void:
	var instance_id := target.get_instance_id()
	if _already_hit.has(instance_id):
		return
	_already_hit[instance_id] = true
	if target.has_method("take_damage"):
		target.call("take_damage", _damage)
