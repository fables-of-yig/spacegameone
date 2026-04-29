class_name MvGrappleBeam
extends Node2D


# Grapple projectile. Flies from the player's shoulder along the aim vector
# and steps through the world tile grid each physics tick. If its tip lands
# inside a BT_GRAPPLE_BLOCK cell, it latches and notifies the owning Player,
# which enters swing state. Any other solid cell (or reaching MAX_RANGE)
# cancels the shot.
#
# Spawned in code — no .tscn backing. Renders the rope as a Line2D child so
# the player can see where it's going during flight and while anchored.

const BLOCK_SIZE: int = 16
const DEFAULT_SPEED: float = 420.0
const DEFAULT_MAX_RANGE: float = 200.0

var _owner: Node2D = null   # MvPlayer — untyped to avoid cycle
var _origin: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _travelled: float = 0.0
var _latched: bool = false
var _line: Line2D = null

# Resolved from the grapple_beam ability registry when fire() is called, so
# the physics loop can read them without hitting the param lookup every tick.
var _speed: float = DEFAULT_SPEED
var _max_range: float = DEFAULT_MAX_RANGE


func fire(node_owner: Node2D, origin: Vector2, aim_dir: Vector2) -> void:
	_owner = node_owner
	_origin = origin
	_dir = aim_dir.normalized() if aim_dir.length_squared() > 0.0001 else Vector2.RIGHT
	position = origin
	_speed = MvAbilityParams.param_float("grapple_beam", "speed", DEFAULT_SPEED)
	_max_range = MvAbilityParams.param_float("grapple_beam", "max_length", DEFAULT_MAX_RANGE)


func _ready() -> void:
	_line = Line2D.new()
	_line.width = 1.5
	_line.default_color = Color(0.7, 1.0, 0.8, 0.95)
	_line.z_index = 5
	add_child(_line)
	_update_line()


func _physics_process(delta: float) -> void:
	if MvGame.simulation_paused:
		return
	if _latched:
		_update_line()
		return

	var step := _speed * delta
	_travelled += step
	position += _dir * step

	if _travelled > _max_range:
		despawn()
		return

	# Sample the tile at the tip. BT_GRAPPLE_BLOCK -> latch. Other solids
	# -> cancel. Everything else -> keep flying.
	var room = MvGame.room_manager
	if room != null:
		var info: Dictionary = room.current_room() if room.has_method("current_room") else {}
		if not info.is_empty() and info["collision"].size() > 0:
			var col := int(position.x / BLOCK_SIZE)
			var row := int(position.y / BLOCK_SIZE)
			if row >= 0 and row < info["collision"].size() \
					and col >= 0 and col < info["collision"][row].size():
				var block: int = info["collision"][row][col]
				if block == MvRoomManager.BT_GRAPPLE_BLOCK:
					# Snap to the center of the grapple block so the swing
					# pivot is stable.
					var pivot := Vector2(
						col * BLOCK_SIZE + BLOCK_SIZE / 2.0,
						row * BLOCK_SIZE + BLOCK_SIZE / 2.0)
					position = pivot
					_latched = true
					if _owner != null and _owner.has_method("begin_grapple_swing"):
						_owner.call("begin_grapple_swing", pivot, self)
					_update_line()
					return
				if _is_hard_stop(block):
					despawn()
					return

	_update_line()


# Called by Player every frame while swinging. Keeps the rope attached to
# the pivot visually — the projectile itself stays fixed at the pivot, but
# the far end of the line tracks the player's shoulder.
func refresh_line() -> void:
	_update_line()


func despawn() -> void:
	queue_free()


func _update_line() -> void:
	if _line == null or _owner == null:
		return
	# Line is in this node's local space, so the "from" end is the
	# projectile position (origin 0,0 locally) and the "to" end is the
	# player shoulder converted into local space.
	if not _owner.has_method("get_shoulder_world"):
		return
	var shoulder: Vector2 = _owner.call("get_shoulder_world")
	_line.clear_points()
	_line.add_point(Vector2.ZERO)
	_line.add_point(to_local(shoulder))


static func _is_hard_stop(block: int) -> bool:
	return block == MvRoomManager.BT_SOLID \
		or block == MvRoomManager.BT_SHOOT_SOLID \
		or block == MvRoomManager.BT_BOMB_SOLID \
		or block == MvRoomManager.BT_CRUMBLE \
		or block == MvRoomManager.BT_SPIKE \
		or block == MvRoomManager.BT_DOOR
