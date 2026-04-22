class_name MvRoomRenderer
extends Node

# Static helper for populating TileMapLayers from packed-tile layer data.
# The runtime RoomManager and the editor (when it comes back) build tilemaps
# the same way — one source of truth for Layer1/Layer2 rendering.
#
# Atlas column count is auto-detected from the map's current TileSet/atlas
# source so callers never pass it. Packs with any atlas grid width work the
# same.
#
# Instance side: when added to the scene tree, drives per-cell frame
# animation. RoomManager creates one instance per room and feeds it
# the animation dicts via load_animations(). Only animated cells are
# touched each frame — the sparse _animated_cells list avoids iterating
# every cell in the room.


# --- Per-cell animation tracking -------------------------------------------
# Each entry: {
#   node: TileMapLayer,
#   col: int, row: int,
#   frames: Array[int],        # metatile indices to cycle through
#   fps: float,
#   loop: bool,
#   ping_pong: bool,
#   phase_offset: float,       # seconds added to the timer at start
#   timer: float,              # accumulated time (seconds)
#   frame_idx: int,            # current index into frames[]
#   direction: int,            # +1 forward, -1 reverse (ping-pong)
#   source_id: int,            # TileSet source id for set_cell
#   atlas_cols: int,           # columns in this source's atlas
#   stopped: bool,             # true once a non-loop anim finishes
# }
var _animated_cells: Array = []


# --- Static tile-building API (unchanged) ----------------------------------

static func build_layer(map: TileMapLayer, layer_data: Array, width_blocks: int, height_blocks: int) -> void:
	map.clear()
	for row in height_blocks:
		if row >= layer_data.size():
			continue
		var line: Array = layer_data[row]
		for col in width_blocks:
			if col >= line.size():
				continue
			_set_cell_from_value(map, col, row, int(line[col]))


static func update_cell(map: TileMapLayer, col: int, row: int, packed_value: int) -> void:
	_set_cell_from_value(map, col, row, packed_value)


static func _set_cell_from_value(map: TileMapLayer, col: int, row: int, packed_value: int) -> void:
	if packed_value == 0:
		map.set_cell(Vector2i(col, row), -1)
		return
	var u := MvTileValue.unpack_full(packed_value)
	var source_id: int = u["tileset"]
	var atlas_cols := _get_atlas_cols_for_source(map, source_id)
	var metatile_idx: int = u["idx"]
	var atlas_coords := Vector2i(metatile_idx % atlas_cols, metatile_idx / atlas_cols)
	# Alternative tile ID: 0=none, 1=H, 2=V, 3=H+V
	var alt_id: int = (1 if u["hflip"] else 0) | (2 if u["vflip"] else 0)
	map.set_cell(Vector2i(col, row), source_id, atlas_coords, alt_id)


static func _get_atlas_cols_for_source(map: TileMapLayer, source_id: int) -> int:
	if map == null or map.tile_set == null:
		return 1
	var ts := map.tile_set
	var src_count := ts.get_source_count()
	for i in src_count:
		var sid := ts.get_source_id(i)
		if sid != source_id:
			continue
		var src := ts.get_source(sid)
		if src is TileSetAtlasSource and src.texture != null:
			var tile_size: int = src.texture_region_size.x
			if tile_size < 1:
				tile_size = 16
			return maxi(1, src.texture.get_width() / tile_size)
	# Fallback: try source 0 if the requested source isn't present.
	if src_count > 0:
		var fb := ts.get_source(ts.get_source_id(0))
		if fb is TileSetAtlasSource and fb.texture != null:
			var tile_size: int = fb.texture_region_size.x
			if tile_size < 1:
				tile_size = 16
			return maxi(1, fb.texture.get_width() / tile_size)
	return 1


# --- Instance animation API -----------------------------------------------

## Called by RoomManager after all tile layers are built. `pairs` is an array
## of dicts: { node: TileMapLayer, animations: Dictionary }. The animations
## dict uses "col,row" keys with values:
##   { frames: [int,...], fps: float, loop: bool, ping_pong: bool, phase_offset: float }
func load_animations(pairs: Array) -> void:
	_animated_cells.clear()
	for pair in pairs:
		var node: TileMapLayer = pair["node"]
		var anims: Dictionary = pair["animations"]
		if node == null or anims.is_empty():
			continue
		for key in anims.keys():
			var parts: PackedStringArray = str(key).split(",")
			if parts.size() < 2:
				continue
			var col := int(parts[0])
			var row := int(parts[1])
			var cfg: Variant = anims[key]
			if typeof(cfg) != TYPE_DICTIONARY:
				continue
			var frames_v: Variant = cfg.get("frames", [])
			if typeof(frames_v) != TYPE_ARRAY or (frames_v as Array).size() < 2:
				continue
			var frames: Array = []
			for f in frames_v:
				frames.append(int(f))
			var fps_val := float(cfg.get("fps", 8.0))
			if fps_val <= 0.0:
				fps_val = 8.0
			var phase := float(cfg.get("phase_offset", 0.0))

			# Determine source_id from the cell's current tile. If the cell
			# is already painted we read its source; otherwise default to 0.
			var cell_data := node.get_cell_source_id(Vector2i(col, row))
			var source_id: int = cell_data if cell_data >= 0 else 0
			var atlas_cols := _get_atlas_cols_for_source(node, source_id)

			_animated_cells.append({
				"node": node,
				"col": col,
				"row": row,
				"frames": frames,
				"fps": fps_val,
				"loop": bool(cfg.get("loop", true)),
				"ping_pong": bool(cfg.get("ping_pong", false)),
				"phase_offset": phase,
				"timer": phase,
				"frame_idx": 0,
				"direction": 1,
				"source_id": source_id,
				"atlas_cols": atlas_cols,
				"stopped": false,
			})
	if not _animated_cells.is_empty():
		# Apply frame 0 immediately so animated cells show the first frame
		# without waiting for the next _process tick.
		for entry in _animated_cells:
			_apply_frame(entry)


func _process(delta: float) -> void:
	if _animated_cells.is_empty():
		return
	for entry in _animated_cells:
		if entry["stopped"]:
			continue
		entry["timer"] += delta
		var spf: float = 1.0 / entry["fps"]
		var frames: Array = entry["frames"]
		var frame_count: int = frames.size()
		var old_idx: int = entry["frame_idx"]

		# Calculate how many whole frames have elapsed.
		var elapsed_frames := int(entry["timer"] / spf)
		if elapsed_frames <= old_idx:
			continue

		var new_idx: int = old_idx
		if entry["ping_pong"]:
			# Ping-pong: bounce between 0 and frame_count-1. The cycle
			# length is 2*(n-1) for n frames.
			var cycle: int = maxi(1, (frame_count - 1) * 2)
			var pos: int = elapsed_frames % cycle
			if pos < frame_count:
				new_idx = pos
			else:
				new_idx = cycle - pos
			new_idx = clampi(new_idx, 0, frame_count - 1)
		else:
			if entry["loop"]:
				new_idx = elapsed_frames % frame_count
			else:
				new_idx = mini(elapsed_frames, frame_count - 1)
				if new_idx >= frame_count - 1:
					entry["stopped"] = true

		if new_idx != old_idx:
			entry["frame_idx"] = new_idx
			_apply_frame(entry)


## Write the current frame's metatile to the TileMapLayer cell.
func _apply_frame(entry: Dictionary) -> void:
	var frames: Array = entry["frames"]
	var metatile_idx: int = frames[entry["frame_idx"]]
	var ac: int = entry["atlas_cols"]
	var atlas_coords := Vector2i(metatile_idx % ac, metatile_idx / ac)
	var node: TileMapLayer = entry["node"]
	# Preserve the cell's existing alternative-tile (flip) flags.
	var cell := Vector2i(entry["col"], entry["row"])
	var alt_id: int = node.get_cell_alternative_tile(cell)
	if alt_id < 0:
		alt_id = 0
	node.set_cell(cell, entry["source_id"], atlas_coords, alt_id)
