extends RefCounted


const DEFAULT_SPRITE_CELL_SIZE: float = 50.0


static func get_shape(data: Dictionary) -> Array:
    var hs: int = int(data.get("hex_size", 1))
    return data.get("hex_shape", HexUtil.default_shape(hs))


static func get_sprite_cell_size(data: Dictionary) -> float:
    return maxf(float(data.get("sprite_cell_size", DEFAULT_SPRITE_CELL_SIZE)), 1.0)


static func get_sprite_scale(data: Dictionary, hex_cell_size: float) -> float:
    return hex_cell_size / get_sprite_cell_size(data) * maxf(float(data.get("sprite_scale", 1.0)), 0.01)


static func get_sprite_rotation_rad(data: Dictionary) -> float:
    return deg_to_rad(float(data.get("sprite_rotation_deg", 0.0)))


static func get_sprite_offset(data: Dictionary, hex_cell_size: float) -> Vector2:
    var raw: Variant = data.get("sprite_offset", [0.0, 0.0])
    var offset := Vector2.ZERO
    if raw is Array and raw.size() >= 2:
        offset = Vector2(float(raw[0]), float(raw[1]))
    elif raw is Dictionary:
        offset = Vector2(float(raw.get("x", 0.0)), float(raw.get("y", 0.0)))
    return offset * (hex_cell_size / get_sprite_cell_size(data))


static func get_shape_center(data: Dictionary, hex_cell_size: float) -> Vector2:
    var shape := get_shape(data)
    if shape.is_empty():
        return Vector2.ZERO
    var first: Variant = shape[0]
    var p0 := HexUtil.hex_to_pixel(Vector2i(int(first[0]), int(first[1])), hex_cell_size)
    var pmin := p0
    var pmax := p0
    for cell_v in shape:
        var cell: Array = cell_v
        var p := HexUtil.hex_to_pixel(Vector2i(int(cell[0]), int(cell[1])), hex_cell_size)
        pmin.x = minf(pmin.x, p.x)
        pmin.y = minf(pmin.y, p.y)
        pmax.x = maxf(pmax.x, p.x)
        pmax.y = maxf(pmax.y, p.y)
    return (pmin + pmax) * 0.5


static func get_canonical_sprite_center(data: Dictionary, hex_cell_size: float) -> Vector2:
    return get_shape_center(data, hex_cell_size) + get_sprite_offset(data, hex_cell_size)
