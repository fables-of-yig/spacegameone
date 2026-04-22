extends RefCounted

# Shared constants and label helpers for the in-game theme editor.
# Mirrors the schema enforced by UIPanels.FALLBACK_THEME so the editor
# UI never invents fields the runtime side won't read back.

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const UiContract = preload("res://Space/scripts/ui/ui_contract.gd")

const PANEL_KEYS: Array = ["main", "alt", "dark"]
const BUTTON_KEYS: Array = ["normal", "hover", "pressed"]
const TEXT_ROLES: Array = [
    "title", "body", "dim", "button", "button_hover", "error", "success",
]
const FONT_ROLES: Array = [
    "title_size", "body_size", "hint_size", "button_size",
]

# Human-readable labels used by the field panel and modals.
const PANEL_LABELS: Dictionary = {
    "main": "Main panel",
    "alt":  "Alt panel",
    "dark": "Dark panel",
}
const BUTTON_LABELS: Dictionary = {
    "normal":  "Button (normal)",
    "hover":   "Button (hover)",
    "pressed": "Button (pressed)",
}
const TEXT_LABELS: Dictionary = {
    "title":        "Title text",
    "body":         "Body text",
    "dim":          "Dim / hint text",
    "button":       "Button label",
    "button_hover": "Button label (hover)",
    "error":        "Error text",
    "success":      "Success text",
}
const FONT_LABELS: Dictionary = {
    "title_size":  "Title size",
    "body_size":   "Body size",
    "hint_size":   "Hint size",
    "button_size": "Button size",
}

# Section headers used by the field panel.
const SECTION_PANELS: String  = "PANEL ART"
const SECTION_BUTTONS: String = "BUTTON ART"
const SECTION_TEXT: String    = "TEXT COLORS"
const SECTION_FONTS: String   = "FONT SIZES"
const SECTION_MISC: String    = "MISC"


static func default_theme() -> Dictionary:
    return UIPanels.FALLBACK_THEME.duplicate(true)


static func is_panel_key(k: String) -> bool:
    return PANEL_KEYS.has(k)


static func is_button_key(k: String) -> bool:
    return BUTTON_KEYS.has(k)


static func is_text_role(role: String) -> bool:
    return TEXT_ROLES.has(role)


static func is_font_role(role: String) -> bool:
    return FONT_ROLES.has(role)


static func panel_label(k: String) -> String:
    return str(PANEL_LABELS.get(k, k))


static func button_label(k: String) -> String:
    return str(BUTTON_LABELS.get(k, k))


static func text_label(role: String) -> String:
    return str(TEXT_LABELS.get(role, role))


static func font_label(role: String) -> String:
    return str(FONT_LABELS.get(role, role))


# Pulls a frame entry (frame path + margin) out of a theme dict, with
# fallback to the FALLBACK_THEME if the key is missing or malformed.
static func get_panel_entry(theme_dict: Dictionary, key: String) -> Dictionary:
    var panels_v: Variant = theme_dict.get("panels", {})
    if typeof(panels_v) != TYPE_DICTIONARY:
        panels_v = {}
    var entry_v: Variant = (panels_v as Dictionary).get(key, null)
    if typeof(entry_v) != TYPE_DICTIONARY:
        return _fallback_panel_entry(key)
    return entry_v


static func get_button_entry(theme_dict: Dictionary, key: String) -> Dictionary:
    var buttons_v: Variant = theme_dict.get("buttons", {})
    if typeof(buttons_v) != TYPE_DICTIONARY:
        buttons_v = {}
    var entry_v: Variant = (buttons_v as Dictionary).get(key, null)
    if typeof(entry_v) != TYPE_DICTIONARY:
        return _fallback_button_entry(key)
    return entry_v


# Reads the `text.<role>` hex string out of a theme dict, falling back
# to the hardcoded fallback color if the key is missing.
static func get_text_hex(theme_dict: Dictionary, role: String) -> String:
    var text_v: Variant = theme_dict.get("text", {})
    if typeof(text_v) != TYPE_DICTIONARY:
        text_v = {}
    var v: Variant = (text_v as Dictionary).get(role, null)
    if v == null:
        var fb: Variant = UIPanels.FALLBACK_THEME["text"].get(role, "#ffffff")
        return str(fb)
    return str(v)


static func get_font_size(theme_dict: Dictionary, role: String) -> int:
    var fonts_v: Variant = theme_dict.get("fonts", {})
    if typeof(fonts_v) != TYPE_DICTIONARY:
        fonts_v = {}
    var v: Variant = (fonts_v as Dictionary).get(role, null)
    if v == null:
        return int(UIPanels.FALLBACK_THEME["fonts"].get(role, 12))
    return int(v)


# Mutators used by the editor — all operate on a working theme dict.
# Each makes sure the parent key exists so subsequent reads see the
# write back.
static func set_panel_frame(theme_dict: Dictionary, key: String, frame_path: String) -> void:
    _ensure_subdict(theme_dict, "panels")
    _ensure_subdict(theme_dict["panels"], key)
    (theme_dict["panels"] as Dictionary)[key]["frame"] = frame_path


static func set_panel_margin(theme_dict: Dictionary, key: String, margin: Vector2i) -> void:
    _ensure_subdict(theme_dict, "panels")
    _ensure_subdict(theme_dict["panels"], key)
    (theme_dict["panels"] as Dictionary)[key]["margin"] = [margin.x, margin.y]


static func set_button_frame(theme_dict: Dictionary, key: String, frame_path: String) -> void:
    _ensure_subdict(theme_dict, "buttons")
    _ensure_subdict(theme_dict["buttons"], key)
    (theme_dict["buttons"] as Dictionary)[key]["frame"] = frame_path


static func set_button_margin(theme_dict: Dictionary, key: String, margin: Vector2i) -> void:
    _ensure_subdict(theme_dict, "buttons")
    _ensure_subdict(theme_dict["buttons"], key)
    (theme_dict["buttons"] as Dictionary)[key]["margin"] = [margin.x, margin.y]


static func set_text_hex(theme_dict: Dictionary, role: String, hex: String) -> void:
    _ensure_subdict(theme_dict, "text")
    (theme_dict["text"] as Dictionary)[role] = hex


static func set_font_size(theme_dict: Dictionary, role: String, size: int) -> void:
    _ensure_subdict(theme_dict, "fonts")
    (theme_dict["fonts"] as Dictionary)[role] = size


static func set_modal_dim_alpha(theme_dict: Dictionary, alpha: float) -> void:
    theme_dict["modal_dim_alpha"] = clampf(alpha, 0.0, 1.0)


static func set_frame_stroke(theme_dict: Dictionary, hex: String) -> void:
    theme_dict["frame_stroke"] = hex


static func _ensure_subdict(parent: Dictionary, key: String) -> void:
    if not parent.has(key) or typeof(parent[key]) != TYPE_DICTIONARY:
        parent[key] = {}


static func _fallback_panel_entry(key: String) -> Dictionary:
    var fb: Dictionary = UIPanels.FALLBACK_THEME["panels"].get(key, {})
    return fb.duplicate(true)


static func _fallback_button_entry(key: String) -> Dictionary:
    var fb: Dictionary = UIPanels.FALLBACK_THEME["buttons"].get(key, {})
    return fb.duplicate(true)


# ─── UI Screen Builder element types ────────────────────────────────────

const ELEM_PANEL: String         = "panel"
const ELEM_LABEL: String         = "label"
const ELEM_BUTTON: String        = "button"
const ELEM_PROGRESS_BAR: String  = "progress_bar"
const ELEM_ICON: String          = "icon"
const ELEM_LIST: String          = "list"
const ELEM_GRID: String          = "grid"
const ELEM_SEPARATOR: String     = "separator"
const ELEM_TAB_BAR: String       = "tab_bar"
const ELEM_CONDITIONAL: String   = "conditional"

const ELEMENT_TYPES: Array = UiContract.ELEMENT_TYPES

const ELEMENT_LABELS: Dictionary = {
    "panel": "Panel",
    "label": "Label",
    "button": "Button",
    "progress_bar": "Progress Bar",
    "icon": "Icon",
    "list": "List",
    "grid": "Grid",
    "separator": "Separator",
    "tab_bar": "Tab Bar",
    "conditional": "Conditional",
}

const ELEMENT_COLORS: Dictionary = {
    "panel": Color(0.4, 0.6, 0.9, 0.7),
    "label": Color(0.8, 0.8, 0.4, 0.7),
    "button": Color(0.4, 0.85, 0.55, 0.7),
    "progress_bar": Color(0.9, 0.35, 0.35, 0.7),
    "icon": Color(0.7, 0.5, 0.9, 0.7),
    "list": Color(0.5, 0.75, 0.85, 0.7),
    "grid": Color(0.6, 0.7, 0.5, 0.7),
    "separator": Color(0.6, 0.6, 0.6, 0.5),
    "tab_bar": Color(0.5, 0.55, 0.85, 0.7),
    "conditional": Color(0.85, 0.65, 0.3, 0.7),
}

const ANCHOR_OPTIONS: Array = [
    "top_left", "top_center", "top_right",
    "center_left", "center", "center_right",
    "bottom_left", "bottom_center", "bottom_right",
]

# Named screen IDs that the runtime knows about.
const SCREEN_IDS: Array = [
    "hud",
    "pause",
    "main_menu",
    "inventory",
    "map",
    "shop",
    "dialogue_box",
    "game_over",
    "boss_intro",
]

const SCREEN_LABELS: Dictionary = {
    "hud": "HUD (in-game overlay)",
    "pause": "Pause Menu",
    "main_menu": "Main Menu",
    "inventory": "Inventory / Pause Screen",
    "map": "Map Screen",
    "shop": "Shop Menu",
    "dialogue_box": "Dialogue Box",
    "game_over": "Game Over",
    "boss_intro": "Cinematic Overlay / Letterbox",
}

# UI authoring vocabulary is defined centrally in UiContract so the
# editor surface cannot drift from validation/runtime support.
const BINDING_SOURCES: Array = UiContract.BINDING_SOURCES
const BINDING_RATIOS: Array = UiContract.BINDING_RATIOS
const ACTION_IDS: Array = UiContract.ACTION_IDS


static func default_element(type: String) -> Dictionary:
    return {
        "type": type,
        "id": "%s_%d" % [type, randi() % 10000],
        "rect": {"x": 10, "y": 10, "w": 100, "h": 30},
        "anchor": "top_left",
        "anchor_offset": {"x": 0, "y": 0},
        "properties": _default_properties_for(type),
        "children": [],
    }


static func _default_properties_for(type: String) -> Dictionary:
    match type:
        ELEM_PANEL:
            return {"variant": "main", "padding": 8, "scroll": "none", "tab_id": "", "tab_group": "default"}
        ELEM_LABEL:
            return {
                "text_role": "body", "static_text": "Label",
                "bind_var": "", "format": "{value}",
                "decimal_places": 0,
                "alignment": "left", "wrap": false,
                "tab_id": "", "tab_group": "default",
            }
        ELEM_BUTTON:
            return {
                "label": "Button",
                "action_id": "",
                "action_args": "",
                "enabled_condition": "",
                "sprite_normal": "",
                "sprite_hover": "",
                "sprite_pressed": "",
                "sprite_tint": "#ffffff",
                "show_label": true,
                "tab_id": "",
                "tab_group": "default",
            }
        ELEM_PROGRESS_BAR:
            return {
                "fill_color": "#ff4444", "bg_color": "#441111",
                "bind_current": "player.health", "bind_max": "player.max_health",
                "direction": "left_to_right", "show_label": true,
                "animate_fill": true, "pulse_on_low": true, "pulse_threshold": 0.25,
                "tab_id": "", "tab_group": "default",
            }
        ELEM_ICON:
            return {"sprite_source": "", "bind_sprite": "", "scale": 1.0, "tint": "#ffffff", "tab_id": "", "tab_group": "default"}
        ELEM_LIST:
            return {
                "bind_array": "",
                "item_template": {},
                "spacing": 4,
                "max_visible": 10,
                "item_action_id": "",
                "item_action_arg_key": "",
                "tab_id": "",
                "tab_group": "default",
            }
        ELEM_GRID:
            return {
                "bind_array": "",
                "slot_template": {},
                "columns": 4,
                "slot_size": 32,
                "empty_slot_style": "dim",
                "item_action_id": "",
                "item_action_arg_key": "",
                "tab_id": "",
                "tab_group": "default",
            }
        ELEM_SEPARATOR:
            return {"orientation": "horizontal", "color": "#666666", "thickness": 1, "tab_id": "", "tab_group": "default"}
        ELEM_TAB_BAR:
            return {"tabs": [], "active_tab": 0, "active_style": "main", "inactive_style": "dim", "tab_group": "default"}
        ELEM_CONDITIONAL:
            return {"condition": "", "condition_type": "has_flag", "condition_value": "", "tab_id": "", "tab_group": "default"}
    return {}


static func element_label(type: String) -> String:
    return str(ELEMENT_LABELS.get(type, type))
