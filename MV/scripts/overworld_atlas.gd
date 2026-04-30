extends RefCounted

const EnvIO = preload("res://Space/scripts/editor/env/env_io.gd")
const OverworldLayout = preload("res://MV/scripts/overworld_layout.gd")
const BLOCK_SIZE: int = 16


# Animated ground tile tracking. Each entry:
# {col, row, tileset_name, frames: [{atlas_x, atlas_y}], fps, loop, ping_pong, phase_offset, _elapsed, _cur_frame}
static var _animated_ground_cells: Array = []
static var _ground_image: Image = null
static var _ground_texture: ImageTexture = null
static var _ground_tex_cache: Dictionary = {}


static func bake_ground_atlas(pack_id: String, realm_data: Dictionary) -> ImageTexture:
	var authored_grid := OverworldLayout.authored_grid_size(realm_data)
	var expanded_grid := OverworldLayout.expanded_grid_size(realm_data)
	var offset := OverworldLayout.content_offset(realm_data)
	var grid_w: int = expanded_grid.x
	var grid_h: int = expanded_grid.y
	var img_w: int = grid_w * BLOCK_SIZE
	var img_h: int = grid_h * BLOCK_SIZE
	var img := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.06, 0.08, 0.12, 1.0))

	var layers_v: Variant = realm_data.get("realm_tile_layers", [])
	if typeof(layers_v) != TYPE_ARRAY:
		return ImageTexture.create_from_image(img)
	var layers: Array = layers_v
	if layers.is_empty():
		return ImageTexture.create_from_image(img)
	var ground_v: Variant = layers[0]
	if typeof(ground_v) != TYPE_DICTIONARY:
		return ImageTexture.create_from_image(img)
	var tiles: Array = (ground_v as Dictionary).get("tiles", [])

	var tex_cache: Dictionary = {}

	for entry_v in tiles:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var col: int = int(entry.get("col", 0))
		var row: int = int(entry.get("row", 0))
		if col < 0 or col >= authored_grid.x or row < 0 or row >= authored_grid.y:
			continue
		var tileset_name: String = str(entry.get("tileset", ""))
		var atlas_x: int = int(entry.get("atlas_x", 0))
		var atlas_y: int = int(entry.get("atlas_y", 0))

		var src_img: Image = _get_tileset_image(pack_id, tileset_name, tex_cache)
		if src_img == null:
			continue

		var src_x: int = atlas_x * BLOCK_SIZE
		var src_y: int = atlas_y * BLOCK_SIZE
		if src_x + BLOCK_SIZE > src_img.get_width() or src_y + BLOCK_SIZE > src_img.get_height():
			continue
		var src_rect := Rect2i(src_x, src_y, BLOCK_SIZE, BLOCK_SIZE)
		var dst := Vector2i((col + offset.x) * BLOCK_SIZE, (row + offset.y) * BLOCK_SIZE)
		img.blit_rect(src_img, src_rect, dst)

	# Scan ground layer for animation entries.
	_animated_ground_cells.clear()
	_ground_image = img
	_ground_tex_cache = tex_cache.duplicate()
	var anims_v: Variant = (ground_v as Dictionary).get("animations", {})
	if typeof(anims_v) == TYPE_DICTIONARY:
		var anims: Dictionary = anims_v
		for key in anims.keys():
			var parts: PackedStringArray = str(key).split(",")
			if parts.size() < 2:
				continue
			var acol := int(parts[0])
			var arow := int(parts[1])
			var anim_v: Variant = anims[key]
			if typeof(anim_v) != TYPE_DICTIONARY:
				continue
			var anim: Dictionary = anim_v
			# Find the tileset for this cell from the tiles array.
			var ts_name: String = ""
			for t_v in tiles:
				if typeof(t_v) != TYPE_DICTIONARY:
					continue
				var t: Dictionary = t_v
				if int(t.get("col", -1)) == acol and int(t.get("row", -1)) == arow:
					ts_name = str(t.get("tileset", ""))
					break
			if ts_name.is_empty():
				continue
			# Build frame list as atlas coords.
			var frames_v: Variant = anim.get("frames", [])
			if typeof(frames_v) != TYPE_ARRAY or (frames_v as Array).size() < 2:
				continue
			var src_img: Image = _get_tileset_image(pack_id, ts_name, tex_cache)
			if src_img == null:
				continue
			@warning_ignore("integer_division")
			var ts_cols: int = src_img.get_width() / BLOCK_SIZE
			if ts_cols <= 0:
				continue
			var frame_coords: Array = []
			for fidx in (frames_v as Array):
				var mi := int(fidx)
				@warning_ignore("integer_division")
				frame_coords.append({
					"atlas_x": mi % ts_cols,
					"atlas_y": mi / ts_cols,
				})
			_animated_ground_cells.append({
				"col": acol + offset.x,
				"row": arow + offset.y,
				"tileset_name": ts_name,
				"frame_coords": frame_coords,
				"fps": float(anim.get("fps", 8.0)),
				"loop": bool(anim.get("loop", true)),
				"ping_pong": bool(anim.get("ping_pong", false)),
				"phase_offset": int(anim.get("phase_offset", 0)),
				"_elapsed": 0.0,
				"_cur_frame": 0,
			})

	var result := ImageTexture.create_from_image(img)
	_ground_texture = result
	return result


# Called each frame from OverworldMain._process to advance animated ground tiles.
static func update_animations(delta: float, pack_id: String) -> void:
	if _animated_ground_cells.is_empty() or _ground_image == null or _ground_texture == null:
		return
	var changed := false
	for cell in _animated_ground_cells:
		var frames: Array = cell["frame_coords"]
		if frames.size() < 2:
			continue
		cell["_elapsed"] = float(cell["_elapsed"]) + delta
		var fps: float = float(cell["fps"])
		if fps <= 0.0:
			continue
		var frame_dur := 1.0 / fps
		if float(cell["_elapsed"]) < frame_dur:
			continue
		cell["_elapsed"] = float(cell["_elapsed"]) - frame_dur
		var old_frame: int = int(cell["_cur_frame"])
		var new_frame: int = old_frame + 1
		if new_frame >= frames.size():
			if bool(cell["loop"]):
				new_frame = 0
			else:
				new_frame = frames.size() - 1
		if new_frame == old_frame:
			continue
		cell["_cur_frame"] = new_frame
		# Re-blit this cell's pixels in the ground image.
		var fc: Dictionary = frames[new_frame]
		var src_img: Image = _get_tileset_image(pack_id, str(cell["tileset_name"]), _ground_tex_cache)
		if src_img == null:
			continue
		var src_x: int = int(fc["atlas_x"]) * BLOCK_SIZE
		var src_y: int = int(fc["atlas_y"]) * BLOCK_SIZE
		if src_x + BLOCK_SIZE > src_img.get_width() or src_y + BLOCK_SIZE > src_img.get_height():
			continue
		var dst := Vector2i(int(cell["col"]) * BLOCK_SIZE, int(cell["row"]) * BLOCK_SIZE)
		_ground_image.blit_rect(src_img, Rect2i(src_x, src_y, BLOCK_SIZE, BLOCK_SIZE), dst)
		changed = true
	if changed:
		_ground_texture.update(_ground_image)


static func _get_tileset_image(pack_id: String, tileset_name: String, cache: Dictionary) -> Image:
	if cache.has(tileset_name):
		return cache[tileset_name]
	var indices := EnvIO.list_tileset_indices(pack_id)
	for idx in indices:
		var i := int(idx)
		var name_str := str(EnvIO.load_tileset_name(pack_id, i))
		if name_str == tileset_name:
			var tex := EnvIO.load_tileset_texture(pack_id, i)
			if tex != null:
				var result := tex.get_image()
				cache[tileset_name] = result
				return result
	if tileset_name.is_valid_int():
		var tex := EnvIO.load_tileset_texture(pack_id, int(tileset_name))
		if tex != null:
			var result := tex.get_image()
			cache[tileset_name] = result
			return result
	cache[tileset_name] = null
	return null
