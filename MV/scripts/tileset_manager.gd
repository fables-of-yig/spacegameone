class_name MvTilesetManager
extends RefCounted

# Minimal port of the C# TilesetManager. Builds a multi-source TileSet from
# the pack's tileset_NN_atlas.png files — one source per tileset index with
# explicit source IDs pinned to the tileset index. Every atlas cell gets a
# base tile + 3 alt tiles (H / V / HV flip) so TileMapLayer.SetCell can
# resolve flipped cells by alt id.
#
# Deferred from the full C# version (not load-bearing for physics smoke
# test): lo/hi variant splitting, priority masks, per-tileset animations.

const TILE_SIZE: int = 16

var _pack: MvPackRef
var _multi_cache: Dictionary = {}  # variant_key -> TileSet


func _init(pack: MvPackRef) -> void:
	_pack = pack


func get_tile_set(_tileset_index: int = 0) -> TileSet:
	return _get_or_build("")


func _get_or_build(suffix: String) -> TileSet:
	if _multi_cache.has(suffix):
		return _multi_cache[suffix]
	var built := _build_multi_source_tile_set(suffix)
	if built != null:
		_multi_cache[suffix] = built
	return built


func _build_multi_source_tile_set(suffix: String) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	var indices := _list_available_tilesets()
	if indices.is_empty():
		return ts

	for idx in indices:
		var src := _build_atlas_source(idx, suffix)
		if src == null:
			continue
		# Pin source ID = tileset index so RoomRenderer.set_cell hits the
		# right source via the per-cell tileset id from the packed value.
		ts.add_source(src, idx)
	print("[MvTilesetManager] built multi-source TileSet (suffix='%s') with %d source(s)" % [
		suffix, ts.get_source_count()
	])
	return ts


func _list_available_tilesets() -> Array:
	var indices: Array = []
	var seen: Dictionary = {}
	for dir_path in [_pack.tileset_dir(), _pack.tileset_user_dir()]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if not dir.current_is_dir() \
					and fn.begins_with("tileset_") \
					and fn.ends_with("_atlas.png"):
				var n := fn.substr(8, 2)
				if n.is_valid_int():
					var idx := int(n)
					if not seen.has(idx):
						seen[idx] = true
						indices.append(idx)
			fn = dir.get_next()
		dir.list_dir_end()
	indices.sort()
	return indices


func _build_atlas_source(tileset_index: int, suffix: String) -> TileSetAtlasSource:
	var fn := "tileset_%02d_atlas%s.png" % [tileset_index, suffix]
	var path := _pack.resolve_read("Tilesets/" + fn)

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("MvTilesetManager: failed to open %s" % path)
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()

	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		push_error("MvTilesetManager: failed to parse PNG %s" % path)
		return null
	var texture := ImageTexture.create_from_image(image)

	@warning_ignore("integer_division")
	var grid_cols := image.get_width() / TILE_SIZE
	@warning_ignore("integer_division")
	var grid_rows := image.get_height() / TILE_SIZE
	var total_slots := grid_cols * grid_rows

	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	for i in total_slots:
		var col := i % grid_cols
		@warning_ignore("integer_division")
		var row := i / grid_cols
		var atlas_coords := Vector2i(col, row)
		source.create_tile(atlas_coords)

		var alt1 := source.create_alternative_tile(atlas_coords)
		source.get_tile_data(atlas_coords, alt1).flip_h = true

		var alt2 := source.create_alternative_tile(atlas_coords)
		source.get_tile_data(atlas_coords, alt2).flip_v = true

		var alt3 := source.create_alternative_tile(atlas_coords)
		var td3 := source.get_tile_data(atlas_coords, alt3)
		td3.flip_h = true
		td3.flip_v = true

	return source


## Convert a flat metatile index to atlas grid coordinates for the given
## tileset source. Returns Vector2i(-1, -1) if the source isn't loaded.
func metatile_to_atlas_coords(tileset_id: int, metatile_idx: int) -> Vector2i:
	var ts := get_tile_set(tileset_id)
	if ts == null:
		return Vector2i(-1, -1)
	var src_count := ts.get_source_count()
	for i in src_count:
		var sid := ts.get_source_id(i)
		if sid != tileset_id:
			continue
		var src := ts.get_source(sid)
		if src is TileSetAtlasSource and src.texture != null:
			var tile_size: int = src.texture_region_size.x
			if tile_size < 1:
				tile_size = TILE_SIZE
			@warning_ignore("integer_division")
			var cols := maxi(1, src.texture.get_width() / tile_size)
			@warning_ignore("integer_division")
			return Vector2i(metatile_idx % cols, metatile_idx / cols)
	return Vector2i(-1, -1)
