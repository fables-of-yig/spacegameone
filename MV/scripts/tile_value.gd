class_name MvTileValue

# Packed metatile value encoding for Layer1/Layer2 cells.
#   bits 0-9   = metatile index (0..1023)
#   bit 10     = horizontal flip
#   bit 11     = vertical flip
#   bits 12-19 = tileset id (0..255) — multi-tileset rooms
#   bit 20     = present flag — set on every painted cell so packed value
#                is guaranteed non-zero (0 is the "empty cell" sentinel).

const INDEX_MASK:    int = 0x3FF
const HFLIP_BIT:     int = 0x400
const VFLIP_BIT:     int = 0x800
const TILESET_SHIFT: int = 12
const TILESET_MASK:  int = 0xFF << 12
const PRESENT_BIT:   int = 0x100000


static func pack(metatile_idx: int, hflip: bool, vflip: bool, tileset_id: int = 0) -> int:
	var val: int = metatile_idx & INDEX_MASK
	if hflip:
		val |= HFLIP_BIT
	if vflip:
		val |= VFLIP_BIT
	val |= (tileset_id & 0xFF) << TILESET_SHIFT
	val |= PRESENT_BIT
	return val


static func unpack_full(packed: int) -> Dictionary:
	return {
		"idx":     packed & INDEX_MASK,
		"hflip":   (packed & HFLIP_BIT) != 0,
		"vflip":   (packed & VFLIP_BIT) != 0,
		"tileset": (packed & TILESET_MASK) >> TILESET_SHIFT,
	}


static func get_tileset_id(packed: int) -> int:
	return (packed & TILESET_MASK) >> TILESET_SHIFT


static func set_tileset_id(packed: int, tileset_id: int) -> int:
	return (packed & ~TILESET_MASK) | ((tileset_id & 0xFF) << TILESET_SHIFT)
