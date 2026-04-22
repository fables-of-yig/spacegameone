extends RefCounted

# Shared constants for the environment editor. Kept in its own module so
# both the main controller and the child panels can preload this without
# touching each other's scripts (no circular preloads).

const TOOL_PAINT: int = 0
const TOOL_ERASE: int = 1
const TOOL_FILL: int = 2
const TOOL_PICK: int = 3
const TOOL_ANIMATE: int = 4

# Editor sidebar mode. MODE_TILE means the active edit target is one of
# the entries in room.tile_layers (index held in editor.active_tile_layer_idx).
# The other modes edit single authoritative surfaces per room.
const MODE_TILE: int = 0
const MODE_COLLISION: int = 1
const MODE_ENTITIES: int = 2
const MODE_DOORS: int = 3

# Tile layer role. Determines runtime z-order (bg → main → fg). Painted
# tile layers are world-locked; backdrop parallax is authored in room meta.
const ROLE_BG: String = "bg"
const ROLE_MAIN: String = "main"
const ROLE_FG: String = "fg"

static func role_color(role: String) -> Color:
    if role == ROLE_BG: return Color(0.45, 0.6, 0.95, 1.0)
    if role == ROLE_MAIN: return Color(0.4, 0.85, 0.55, 1.0)
    if role == ROLE_FG: return Color(0.95, 0.65, 0.35, 1.0)
    return Color(0.6, 0.6, 0.7, 1.0)

static func role_label(role: String) -> String:
    if role == ROLE_BG: return "BG"
    if role == ROLE_MAIN: return "MAIN"
    if role == ROLE_FG: return "FG"
    return "?"

static func default_scroll_for_role(role: String) -> Vector2:
    return Vector2(1.0, 1.0)

# Known entity type ids. The runtime has more (ship_boarder etc.) but
# these are the core authoring-surface types the editor exposes as a
# dropdown. Unknown types still round-trip through save/load untouched.
const ENTITY_TYPES: Array = [
    "player_spawn",
    "npc",
    "sign",
    "pickup",
    "trigger_volume",
    "patroller",
    "enemy",
]

static func entity_label(type_id: String) -> String:
    if type_id == "player_spawn": return "PLAYER SPAWN"
    if type_id == "npc": return "NPC"
    if type_id == "sign": return "SIGN"
    if type_id == "pickup": return "PICKUP"
    if type_id == "trigger_volume": return "ZONE"
    if type_id == "patroller": return "PATROLLER"
    if type_id == "enemy": return "ENEMY"
    return type_id.to_upper()


static func entity_help(type_id: String) -> String:
    if type_id == "player_spawn":
        return "Player start point for room playtests and authored room entry."
    if type_id == "npc":
        return "Interactable NPC. Use triggers or dialogue_id properties for conversations and cutscenes."
    if type_id == "sign":
        return "Static interactable sign. Good for readable lore or hints."
    if type_id == "pickup":
        return "Touch pickup. Set item_id/count in properties if needed."
    if type_id == "trigger_volume":
        return "Named trigger zone. Fires zone_enter/zone_exit for the player and doubles as a target for move/spawn-to-zone trigger actions."
    if type_id == "patroller":
        return "Basic enemy/patrol actor."
    if type_id == "enemy":
        return "Generic enemy actor."
    return "Room entity."


static func entity_color(type_id: String) -> Color:
    if type_id == "player_spawn": return Color(0.2, 1.0, 0.5, 0.85)
    if type_id == "npc": return Color(0.4, 0.7, 1.0, 0.85)
    if type_id == "sign": return Color(0.9, 0.9, 0.3, 0.85)
    if type_id == "pickup": return Color(1.0, 0.8, 0.2, 0.85)
    if type_id == "trigger_volume": return Color(0.92, 0.4, 1.0, 0.88)
    if type_id == "patroller": return Color(1.0, 0.35, 0.35, 0.85)
    if type_id == "enemy": return Color(0.95, 0.25, 0.4, 0.9)
    return Color(0.8, 0.4, 1.0, 0.85)

# Collision block type nibbles. Mirrors MvRoomManager.BT_* — keep in sync.
const BT_AIR: int = 0x0
const BT_SLOPE: int = 0x1
const BT_AIR_SPECIAL: int = 0x2
const BT_TREADMILL_AIR: int = 0x3
const BT_SHOOT_AIR: int = 0x4
const BT_H_COPY: int = 0x5
const BT_BOMB_AIR: int = 0x6
const BT_GRAPPLE_AIR: int = 0x7
const BT_SOLID: int = 0x8
const BT_DOOR: int = 0x9
const BT_SPIKE: int = 0xA
const BT_CRUMBLE: int = 0xB
const BT_SHOOT_SOLID: int = 0xC
const BT_V_COPY: int = 0xD
const BT_BOMB_SOLID: int = 0xE
const BT_GRAPPLE_BLOCK: int = 0xF

const SLOPE_SHAPE_MASK: int = 0x3F
const SLOPE_HFLIP_BIT: int = 0x40
const SLOPE_VFLIP_BIT: int = 0x80
const CRUMBLE_PERSIST_UNTIL_RELOAD_BIT: int = 0x01

static func block_type_label(bt: int) -> String:
    var n := bt & 0xF
    if n == BT_AIR: return "AIR"
    if n == BT_SLOPE: return "SLOPE"
    if n == BT_AIR_SPECIAL: return "AIR+"
    if n == BT_TREADMILL_AIR: return "TREAD"
    if n == BT_SHOOT_AIR: return "SHOOT AIR"
    if n == BT_H_COPY: return "H COPY"
    if n == BT_BOMB_AIR: return "BOMB AIR"
    if n == BT_GRAPPLE_AIR: return "GRAP AIR"
    if n == BT_SOLID: return "SOLID"
    if n == BT_DOOR: return "DOOR"
    if n == BT_SPIKE: return "SPIKE"
    if n == BT_CRUMBLE: return "CRUMBLE"
    if n == BT_SHOOT_SOLID: return "SHOOT"
    if n == BT_V_COPY: return "V COPY"
    if n == BT_BOMB_SOLID: return "BOMB"
    if n == BT_GRAPPLE_BLOCK: return "GRAPPLE"
    return "?"

static func block_type_color(bt: int) -> Color:
    var n := bt & 0xF
    if n == BT_AIR: return Color(0.2, 0.25, 0.35, 0.35)
    if n == BT_SLOPE: return Color(0.4, 0.5, 0.9, 0.75)
    if n == BT_AIR_SPECIAL: return Color(0.5, 0.6, 0.85, 0.55)
    if n == BT_TREADMILL_AIR: return Color(0.55, 0.8, 0.95, 0.6)
    if n == BT_SHOOT_AIR: return Color(0.9, 0.6, 0.2, 0.6)
    if n == BT_H_COPY: return Color(0.5, 0.5, 0.6, 0.45)
    if n == BT_BOMB_AIR: return Color(0.9, 0.4, 0.2, 0.6)
    if n == BT_GRAPPLE_AIR: return Color(0.2, 0.7, 0.9, 0.65)
    if n == BT_SOLID: return Color(0.9, 0.25, 0.25, 0.8)
    if n == BT_DOOR: return Color(0.3, 0.85, 0.35, 0.8)
    if n == BT_SPIKE: return Color(0.95, 0.1, 0.55, 0.85)
    if n == BT_CRUMBLE: return Color(0.85, 0.55, 0.2, 0.75)
    if n == BT_SHOOT_SOLID: return Color(0.9, 0.4, 0.4, 0.8)
    if n == BT_V_COPY: return Color(0.55, 0.55, 0.65, 0.45)
    if n == BT_BOMB_SOLID: return Color(0.85, 0.35, 0.15, 0.8)
    if n == BT_GRAPPLE_BLOCK: return Color(0.3, 0.8, 0.95, 0.8)
    return Color(0.6, 0.6, 0.7, 0.4)


static func encode_slope_bts(shape_idx: int, hflip: bool, vflip: bool) -> int:
    var out := shape_idx & SLOPE_SHAPE_MASK
    if hflip:
        out |= SLOPE_HFLIP_BIT
    if vflip:
        out |= SLOPE_VFLIP_BIT
    return out


static func decode_slope_bts(bts_value: int, shape_count: int = 0) -> Dictionary:
    var shape_idx := bts_value & SLOPE_SHAPE_MASK
    if shape_count > 0 and (shape_idx == 0 or shape_idx >= shape_count):
        shape_idx = 1 if shape_count > 1 else 0
    return {
        "shape": shape_idx,
        "hflip": (bts_value & SLOPE_HFLIP_BIT) != 0,
        "vflip": (bts_value & SLOPE_VFLIP_BIT) != 0,
    }


static func encode_crumble_bts(reload_only: bool) -> int:
    return CRUMBLE_PERSIST_UNTIL_RELOAD_BIT if reload_only else 0


static func crumble_is_reload_only(bts_value: int) -> bool:
    return (bts_value & CRUMBLE_PERSIST_UNTIL_RELOAD_BIT) != 0
