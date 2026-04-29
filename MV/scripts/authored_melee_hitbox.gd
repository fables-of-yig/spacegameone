class_name MvAuthoredMeleeHitbox
extends Area2D

var _damage: int = 0
var _lifetime: float = 1.0 / 60.0
var _already_hit: Dictionary = {}
var _rect_size: Vector2 = Vector2(16, 16)
var _shape: CollisionShape2D = null
var _initial_overlap_scan_pending: bool = true


func configure(world_pos: Vector2, rect_size: Vector2, damage: int, lifetime_sec: float = 1.0 / 60.0) -> void:
	global_position = world_pos
	_rect_size = Vector2(maxf(1.0, rect_size.x), maxf(1.0, rect_size.y))
	_damage = maxi(0, damage)
	_lifetime = maxf(1.0 / 120.0, lifetime_sec)
	_build_shape()
	queue_redraw()


func _ready() -> void:
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if MvGame.simulation_paused:
		return
	if _initial_overlap_scan_pending:
		_initial_overlap_scan_pending = false
		_apply_initial_overlaps()
		_apply_geometry_hits()
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()


func _draw() -> void:
	pass


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


func _apply_initial_overlaps() -> void:
	for area in get_overlapping_areas():
		_on_area_entered(area)
		if is_queued_for_deletion():
			return
	for body in get_overlapping_bodies():
		if body is Node2D:
			_on_body_entered(body)
			if is_queued_for_deletion():
				return


func _apply_geometry_hits() -> void:
	var world_rect := Rect2(global_position - _rect_size * 0.5, _rect_size)
	for enemy in get_tree().get_nodes_in_group("mv_enemy"):
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("hurtbox_intersects_rect"):
			if bool(enemy.call("hurtbox_intersects_rect", world_rect)):
				_apply_damage(enemy)
		elif enemy is Node2D and world_rect.has_point((enemy as Node2D).global_position):
			_apply_damage(enemy)
