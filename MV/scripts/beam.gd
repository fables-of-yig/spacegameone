class_name MvBeam
extends Area2D

# Free-aim projectile. Legacy 8-direction SM beam behavior is gone — beams
# fly straight at a fixed speed, despawn after max travel, deal damage to
# Enemies on touch, and punch destructible blocks on tile contact.

const BEAM_SPEED: float          = 240.0  # power beam baseline
const POWER_BEAM_DAMAGE: int     = 3
const CHARGED_BEAM_DAMAGE: int   = 15     # 5x power beam — ROM $90:C37F
const CHARGED_BEAM_SPEED: float  = 300.0  # faster streak so it reads as "hot"
const MAX_TRAVEL: float          = 400.0

var _vel: Vector2 = Vector2.ZERO
var _spawn: Vector2 = Vector2.ZERO
var _anim_timer: float = 0.0
var _anim_frame: int = 0
var _damage: int = POWER_BEAM_DAMAGE
var _charged: bool = false

@onready var _sprite: Sprite2D = $Sprite2D


# Fire along a normalized aim vector. Use BEAM_SPEED for the default muzzle
# velocity; caller can pass anything (charged shots etc.).
func init_aimed(aim_dir: Vector2, speed: float = BEAM_SPEED) -> void:
	if aim_dir.length_squared() < 0.0001:
		aim_dir = Vector2.RIGHT
	_vel = aim_dir.normalized() * speed
	# Orient the sprite along the travel direction so the beam streak
	# visually matches where it's going.
	rotation = _vel.angle()


# Charged shot variant — bigger damage, faster streak, 1.5x sprite scale,
# cyan modulate so the player can see at a glance it's charged. Same
# physics otherwise.
func init_charged(aim_dir: Vector2) -> void:
	_charged = true
	_damage = CHARGED_BEAM_DAMAGE
	init_aimed(aim_dir, CHARGED_BEAM_SPEED)


func _ready() -> void:
	_spawn = position
	if _sprite != null:
		_sprite.frame = 0
		if _charged:
			_sprite.scale = Vector2(1.5, 1.5)
			_sprite.modulate = Color(0.5, 1.0, 1.0, 1.0)

	# Hit detection: overlap events fire when the beam enters an enemy's
	# hurtbox (Area2D in the "mv_enemy_hurt" group) or a solid tile. Body
	# contact catches destructible tile colliders; area contact catches
	# enemies + the player's grapple target if it ever crosses one.
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if MvGame.simulation_paused:
		return

	position += _vel * delta

	if position.distance_to(_spawn) > MAX_TRAVEL:
		queue_free()
		return

	_anim_timer += delta * 60.0
	if _anim_timer >= 4.0:
		_anim_timer -= 4.0
		_anim_frame = (_anim_frame + 1) % 4
		if _sprite != null:
			_sprite.frame = _anim_frame


func _on_area_entered(area: Area2D) -> void:
	var parent := area.get_parent()
	if parent == null:
		return
	if parent.is_in_group("mv_enemy") and parent.has_method("take_damage"):
		parent.call("take_damage", _damage)
		# Charged shots pierce: don't despawn on the first hit so a charged
		# round can cleave a row of enemies. Uncharged shots still despawn
		# on first contact.
		if not _charged:
			queue_free()


func _on_body_entered(body: Node2D) -> void:
	# Tile colliders are StaticBody2Ds with no script — any hit on a
	# non-Player/Enemy body deletes the beam. If the body corresponds to a
	# destructible tile we ask RoomManager to break it.
	if body.is_in_group("mv_player") or body.is_in_group("mv_enemy"):
		return

	var room: Node = MvGame.room_manager
	if room != null and room.has_method("break_block_at_world_pos"):
		room.call("break_block_at_world_pos", position)
	queue_free()
