extends RefCounted

const TOOL_PAINT: int = 0
const TOOL_ERASE: int = 1
const TOOL_FILL: int = 2
const TOOL_PICK: int = 3

const LAYER_GROUND: int = 0
const LAYER_STRUCTURE: int = 1
const LAYER_SKY: int = 2

static func layer_name(idx: int) -> String:
	if idx == LAYER_GROUND: return "Ground"
	if idx == LAYER_STRUCTURE: return "Structure"
	if idx == LAYER_SKY: return "Sky"
	return "?"

static func layer_color(idx: int) -> Color:
	if idx == LAYER_GROUND: return Color(0.45, 0.75, 0.4, 1.0)
	if idx == LAYER_STRUCTURE: return Color(0.85, 0.6, 0.35, 1.0)
	if idx == LAYER_SKY: return Color(0.5, 0.7, 1.0, 1.0)
	return Color(0.6, 0.6, 0.7, 1.0)

static func layer_alpha(idx: int) -> float:
	if idx == LAYER_GROUND: return 1.0
	if idx == LAYER_STRUCTURE: return 0.75
	if idx == LAYER_SKY: return 0.5
	return 0.6
