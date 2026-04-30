extends Node2D

const BLOCK_SIZE: int = 16
const TURN_SPEED: float = 0.5
const MAX_SPEED: float = 180.0
const ACCEL: float = 200.0
const FRICTION: float = 120.0
const BOOST_IMPULSE: float = 90.0
const BOOST_SPEED_CAP_MULT: float = 1.45

var world_pos: Vector2 = Vector2(256, 256)
var angle: float = 0.0
var speed: float = 0.0
var grid_cells_x: int = 32
var grid_cells_y: int = 32
var controls_enabled: bool = true


func _process(delta: float) -> void:
	var turn_input: float = 0.0
	if controls_enabled and Input.is_action_pressed("move_right"):
		turn_input += 1.0
	if controls_enabled and Input.is_action_pressed("move_left"):
		turn_input -= 1.0
	angle += turn_input * TURN_SPEED * delta

	var thrust: float = 0.0
	if controls_enabled and (Input.is_action_pressed("aim_up") or Input.is_action_pressed("move_up")):
		thrust = 1.0
	if controls_enabled and (Input.is_action_pressed("crouch") or Input.is_action_pressed("move_down")):
		thrust = -0.5

	if thrust != 0.0:
		speed = move_toward(speed, MAX_SPEED * thrust, ACCEL * delta)
	else:
		speed = move_toward(speed, 0.0, FRICTION * delta)

	if controls_enabled and Input.is_action_just_pressed("boost"):
		speed = minf(maxf(speed, 0.0) + BOOST_IMPULSE, MAX_SPEED * BOOST_SPEED_CAP_MULT)

	world_pos.x += sin(angle) * speed * delta
	world_pos.y += cos(angle) * speed * delta

	var max_x: float = float(grid_cells_x * BLOCK_SIZE)
	var max_y: float = float(grid_cells_y * BLOCK_SIZE)
	world_pos.x = wrapf(world_pos.x, 0.0, max_x)
	world_pos.y = wrapf(world_pos.y, 0.0, max_y)

	rotation = -angle


func grid_col() -> int:
	@warning_ignore("integer_division")
	return clampi(int(world_pos.x) / BLOCK_SIZE, 0, grid_cells_x - 1)


func grid_row() -> int:
	@warning_ignore("integer_division")
	return clampi(int(world_pos.y) / BLOCK_SIZE, 0, grid_cells_y - 1)


func speed_ratio() -> float:
	return clampf(absf(speed) / maxf(MAX_SPEED, 1.0), 0.0, 1.0)
