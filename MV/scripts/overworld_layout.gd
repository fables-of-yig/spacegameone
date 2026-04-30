extends RefCounted

const RegIO = preload("res://Space/scripts/editor/reg/reg_io.gd")
const BASELINE_REALM_GRID_X: int = 32
const BASELINE_REALM_GRID_Y: int = 32
const TARGET_TILE_MULTIPLIER: int = 10
const TARGET_MIN_TILE_COUNT: int = BASELINE_REALM_GRID_X * BASELINE_REALM_GRID_Y * TARGET_TILE_MULTIPLIER


static func authored_grid_size(realm_data: Dictionary) -> Vector2i:
	return Vector2i(
		maxi(1, int(realm_data.get("realm_grid_cells_x", RegIO.DEFAULT_REALM_GRID_X))),
		maxi(1, int(realm_data.get("realm_grid_cells_y", RegIO.DEFAULT_REALM_GRID_Y)))
	)


static func expanded_grid_size(realm_data: Dictionary) -> Vector2i:
	var authored := authored_grid_size(realm_data)
	var tile_count: int = authored.x * authored.y
	if tile_count >= TARGET_MIN_TILE_COUNT:
		return authored
	var scale: float = sqrt(float(TARGET_MIN_TILE_COUNT) / float(tile_count))
	return Vector2i(
		maxi(authored.x, int(ceili(float(authored.x) * scale))),
		maxi(authored.y, int(ceili(float(authored.y) * scale)))
	)


static func content_offset(realm_data: Dictionary) -> Vector2i:
	var authored := authored_grid_size(realm_data)
	var expanded := expanded_grid_size(realm_data)
	return Vector2i(
		int((expanded.x - authored.x) / 2),
		int((expanded.y - authored.y) / 2)
	)


static func shifted_cell(col: int, row: int, realm_data: Dictionary) -> Vector2i:
	return Vector2i(col, row) + content_offset(realm_data)


static func shifted_world_pos(col: int, row: int, realm_data: Dictionary, block_size: float) -> Vector2:
	var shifted := shifted_cell(col, row, realm_data)
	return Vector2(
		(float(shifted.x) + 0.5) * block_size,
		(float(shifted.y) + 0.5) * block_size
	)


static func shifted_region_center_world_pos(col: int, row: int, span_w: int, span_h: int,
		realm_data: Dictionary, block_size: float) -> Vector2:
	var shifted := shifted_cell(col, row, realm_data)
	return Vector2(
		(float(shifted.x) + float(maxi(1, span_w)) * 0.5) * block_size,
		(float(shifted.y) + float(maxi(1, span_h)) * 0.5) * block_size
	)
