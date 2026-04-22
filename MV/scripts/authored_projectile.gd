class_name MvAuthoredProjectile
extends Area2D

const MAX_TRAIL_POINTS: int = 8

var _velocity: Vector2 = Vector2.ZERO
var _gravity: float = 0.0
var _damage: int = 0
var _pierces: bool = false
var _homing: bool = false
var _homing_strength: float = 0.0
var _rotate_to_velocity: bool = false
var _remaining_ticks: float = 0.0
var _trail_color: Color = Color(0.6, 0.8, 1.0, 1.0)
var _trail_points: Array = []
var _explosive: bool = false
var _explode_on_hit: bool = true
var _explode_on_timeout: bool = false
var _break_blocks: bool = true
var _bomb_jump: bool = false
var _blast_radius: float = 0.0
var _explosion_damage: int = 0
var _bomb_jump_speed: float = 280.0
var _exploded: bool = false
var _frame_width: int = 8
var _frame_height: int = 8
var _frame_index: int = 0
var _frame_count: int = 1
var _frame_tick: int = 10
var _anim_timer: float = 0.0
var _anim_frame: int = 0
var _sheet_path: String = ""
var _already_hit: Dictionary = {}

var _shape: CollisionShape2D = null
var _sprite: Sprite2D = null
var _base_texture: Texture2D = null
var _base_image: Image = null


func configure(projectile_def: Dictionary, origin: Vector2, aim_dir: Vector2, damage_scale: float = 1.0) -> void:
	position = origin
	if aim_dir.length_squared() < 0.0001:
		aim_dir = Vector2.RIGHT

	_damage = maxi(0, int(round(float(projectile_def.get("damage", 0)) * damage_scale)))
	_gravity = float(projectile_def.get("gravity", 0.0))
	_pierces = bool(projectile_def.get("pierces", false))
	_homing = bool(projectile_def.get("homing", false))
	_homing_strength = maxf(0.0, float(projectile_def.get("homing_strength", 0.0)))
	_rotate_to_velocity = bool(projectile_def.get("rotate_to_velocity", false))
	_remaining_ticks = maxf(1.0, float(int(projectile_def.get("lifetime_ticks", 1))))
	_explosive = bool(projectile_def.get("explosive", false))
	_explode_on_hit = bool(projectile_def.get("explode_on_hit", true))
	_explode_on_timeout = bool(projectile_def.get("explode_on_timeout", false))
	_break_blocks = bool(projectile_def.get("break_blocks", true))
	_bomb_jump = bool(projectile_def.get("bomb_jump", false))
	_blast_radius = maxf(0.0, float(int(projectile_def.get("blast_radius", 0))))
	_explosion_damage = maxi(0, int(projectile_def.get("explosion_damage", 0)))
	_bomb_jump_speed = maxf(0.0, float(int(projectile_def.get("bomb_jump_speed", 280))))
	_frame_width = maxi(1, int(projectile_def.get("frame_width", 8)))
	_frame_height = maxi(1, int(projectile_def.get("frame_height", 8)))
	_frame_index = maxi(0, int(projectile_def.get("frame_index", 0)))
	_frame_count = maxi(1, int(projectile_def.get("frame_count", 1)))
	_frame_tick = maxi(1, int(projectile_def.get("frame_tick", 10)))
	_sheet_path = str(projectile_def.get("sprite_sheet", "")).strip_edges()

	var trail := str(projectile_def.get("trail_color", "")).strip_edges()
	if not trail.is_empty() and Color.html_is_valid(trail):
		_trail_color = Color.html(trail)

	var speed := float(projectile_def.get("speed", 0.0))
	_velocity = aim_dir.normalized() * speed
	if _rotate_to_velocity and _velocity.length_squared() > 0.0001:
		rotation = _velocity.angle()

	_build_nodes(projectile_def)
	_apply_sprite_frame()


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if MvGame.simulation_paused:
		return

	_tick_homing(delta)
	_velocity.y += _gravity * delta
	position += _velocity * delta
	_remaining_ticks -= delta * 60.0

	_trail_points.append(global_position)
	if _trail_points.size() > MAX_TRAIL_POINTS:
		_trail_points.remove_at(0)
	queue_redraw()

	if _rotate_to_velocity and _velocity.length_squared() > 0.0001:
		rotation = _velocity.angle()

	_anim_timer += delta * 60.0
	if _anim_timer >= float(_frame_tick):
		_anim_timer -= float(_frame_tick)
		_anim_frame = (_anim_frame + 1) % _frame_count
		_apply_sprite_frame()

	if _remaining_ticks <= 0.0:
		if _explosive and _explode_on_timeout:
			_explode()
		else:
			queue_free()


func _draw() -> void:
	if _trail_points.size() >= 2:
		for i in range(1, _trail_points.size()):
			var a: Vector2 = to_local(_trail_points[i - 1])
			var b: Vector2 = to_local(_trail_points[i])
			var alpha := float(i) / float(_trail_points.size())
			draw_line(a, b, Color(_trail_color, alpha * 0.65), 1.5)
	if _base_texture == null:
		draw_rect(Rect2(Vector2(-4, -2), Vector2(8, 4)), Color(_trail_color, 0.9))


func _build_nodes(projectile_def: Dictionary) -> void:
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(
		maxf(1.0, float(int(projectile_def.get("hitbox_w", 8)))),
		maxf(1.0, float(int(projectile_def.get("hitbox_h", 8))))
	)
	_shape.shape = rect
	add_child(_shape)

	_sprite = Sprite2D.new()
	_sprite.centered = true
	add_child(_sprite)
	_load_sprite_texture()


func _load_sprite_texture() -> void:
	if _sheet_path.is_empty() or MvPackLoader.current_pack == null:
		return
	var pack_id := MvPackLoader.current_pack.pack_id
	var tex_path := MvPackLoader.resolve_read_cascade(pack_id, "Projectiles", _sheet_path)
	var tex := load(tex_path)
	if tex is Texture2D:
		_base_texture = tex
		_base_image = _base_texture.get_image()
		_apply_sprite_frame()


func _apply_sprite_frame() -> void:
	if _sprite == null or _base_texture == null:
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = _base_texture
	atlas.region = Rect2(
		float((_frame_index + _anim_frame) * _frame_width),
		0.0,
		float(_frame_width),
		float(_frame_height)
	)
	_sprite.texture = atlas
	_sprite.offset = _sprite_alignment_offset()


func _sprite_alignment_offset() -> Vector2:
	if _base_image == null:
		return Vector2.ZERO
	var frame_x := (_frame_index + _anim_frame) * _frame_width
	var min_x := _frame_width
	var min_y := _frame_height
	var max_x := -1
	var max_y := -1
	for y in range(_frame_height):
		for x in range(_frame_width):
			var px := frame_x + x
			if px < 0 or px >= _base_image.get_width() or y < 0 or y >= _base_image.get_height():
				continue
			if _base_image.get_pixel(px, y).a <= 0.0:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Vector2.ZERO
	var frame_center := Vector2(float(_frame_width) * 0.5, float(_frame_height) * 0.5)
	var opaque_center := Vector2(
		float(min_x + max_x + 1) * 0.5,
		float(min_y + max_y + 1) * 0.5
	)
	return frame_center - opaque_center


func _tick_homing(delta: float) -> void:
	if not _homing or _homing_strength <= 0.0:
		return
	var target := _nearest_enemy()
	if target == null:
		return
	var desired := ((target as Node2D).global_position - global_position).normalized()
	if desired.length_squared() < 0.0001:
		return
	var current := _velocity.normalized() if _velocity.length_squared() > 0.0001 else desired
	var steer := current.lerp(desired, clampf(_homing_strength * delta, 0.0, 1.0)).normalized()
	_velocity = steer * _velocity.length()


func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for enemy in get_tree().get_nodes_in_group("mv_enemy"):
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		var dist := (enemy as Node2D).global_position.distance_squared_to(global_position)
		if dist < best_dist:
			best_dist = dist
			best = enemy
	return best


func _on_area_entered(area: Area2D) -> void:
	var parent := area.get_parent()
	if parent == null or not parent.is_in_group("mv_enemy"):
		return
	if _explosive and _explode_on_hit:
		_explode()
		return
	_apply_damage(parent)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("mv_player"):
		return
	if body.is_in_group("mv_enemy"):
		if _explosive and _explode_on_hit:
			_explode()
			return
		_apply_damage(body)
		return
	if _explosive and _explode_on_hit:
		_explode()
		return
	var room: Node = MvGame.room_manager
	if _break_blocks and room != null and room.has_method("break_block_at_world_pos"):
		room.call("break_block_at_world_pos", global_position)
	queue_free()


func _apply_damage(target: Node) -> void:
	var instance_id := target.get_instance_id()
	if _already_hit.has(instance_id):
		return
	_already_hit[instance_id] = true
	if target.has_method("take_damage"):
		target.call("take_damage", _damage)
	if not _pierces:
		queue_free()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	var radius := _blast_radius
	if radius <= 0.0:
		queue_free()
		return
	var damage := _explosion_damage if _explosion_damage > 0 else _damage
	MvTriggerEngine.fire_event("projectile_explode", {
		"position": global_position,
		"radius": radius,
		"damage": damage,
	})
	var room: Node = MvGame.room_manager
	if _break_blocks and room != null and room.has_method("break_block_at_world_pos"):
		room.call("break_block_at_world_pos", global_position)
	for enemy in get_tree().get_nodes_in_group("mv_enemy"):
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		var enemy_node := enemy as Node2D
		if enemy_node.global_position.distance_to(global_position) > radius:
			continue
		if enemy.has_method("take_damage"):
			enemy.call("take_damage", damage, global_position)
	if _bomb_jump:
		for player in get_tree().get_nodes_in_group("mv_player"):
			if not is_instance_valid(player) or not player is Node2D:
				continue
			var player_node := player as Node2D
			if player_node.global_position.distance_to(global_position) > radius:
				continue
			if player.has_method("apply_bomb_jump"):
				player.call("apply_bomb_jump", _bomb_jump_speed)
	queue_free()
