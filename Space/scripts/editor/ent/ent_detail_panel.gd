extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const EntTypes = preload("res://Space/scripts/editor/ent/ent_types.gd")

# Right pane for the entity editor. Shows the fields of the currently
# selected entity as clickable rows — clicking a row opens the shared
# text modal to edit that field. The category row instead cycles through
# the predefined category list.
#
# Pass 2a intentionally ships as text-field-only. Pass 2b will add a
# sprite-set browser + PNG preview next to this panel, and Pass 2c will
# drop in per-animation metadata editing.

var editor: Node = null

const FIELD_H: float = 44.0
const FIELD_PAD_X: float = 18.0
const FIELD_PAD_Y: float = 18.0
const HEADER_H: float = 52.0

var _field_rects: Array = []  # [{field, rect, kind}] where kind is "text" or "category"
var _scroll_y: float = 0.0


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    set_process(true)


func _process(_delta):
    queue_redraw()


func _gui_input(event):
    if editor == null:
        return
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _scroll_y = maxf(_scroll_y - 40.0, 0.0)
            accept_event()
            return
        if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _scroll_y += 40.0
            accept_event()
            return
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        for row in _field_rects:
            if (row["rect"] as Rect2).has_point(event.position):
                var field := str(row["field"])
                var kind := str(row["kind"])
                if kind == "category":
                    editor.cycle_category()
                elif kind == "behavior":
                    editor.request_pick_behavior()
                else:
                    var title := "Edit %s" % field
                    var prompt := _prompt_for(field)
                    editor.request_edit_field(field, title, prompt)
                accept_event()
                return


func _draw():
    UIPanels.draw_panel(self, Rect2(Vector2.ZERO, size),
        Color.WHITE, UIPanels.PanelVariant.MAIN)

    if editor == null:
        return
    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    _field_rects.clear()

    var e: Dictionary = editor.get_selected_entity()
    if e.is_empty():
        draw_string(font, Vector2(FIELD_PAD_X + 6, 40),
            "No entity selected.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
            UIPanels.TEXT_PANEL)
        draw_string(font, Vector2(FIELD_PAD_X + 6, 62),
            "Select one on the left, or click + ADD ENTITY.",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL_DIM)
        return

    var header := "ENTITY  %s" % str(e.get("id", ""))
    draw_string(font, Vector2(FIELD_PAD_X + 4, 34),
        header, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIPanels.TEXT_PANEL)

    var y: float = HEADER_H + 8.0 - _scroll_y
    y = _draw_field(font, mouse_pos, e, "id", "ID", "text", y)
    y = _draw_field(font, mouse_pos, e, "name", "Name", "text", y)
    y = _draw_field(font, mouse_pos, e, "category", "Category", "category", y)
    y = _draw_field(font, mouse_pos, e, "description", "Description", "text", y)
    y = _draw_field(font, mouse_pos, e, "scene", "Scene (.tscn)", "text", y)
    y = _draw_field(font, mouse_pos, e, "sprite_set", "Sprite set folder", "text", y)
    y = _draw_field(font, mouse_pos, e, "behavior", "Behavior", "behavior", y)
    y = _draw_field(font, mouse_pos, e, "movement_mode", "Movement mode", "text", y)
    y = _draw_field(font, mouse_pos, e, "hp", "HP", "text", y)
    y = _draw_field(font, mouse_pos, e, "attack_damage", "Melee damage", "text", y)
    y = _draw_field(font, mouse_pos, e, "contact_damage", "Touch damage", "text", y)
    y = _draw_field(font, mouse_pos, e, "contact_cooldown", "Touch cooldown", "text", y)
    y = _draw_field(font, mouse_pos, e, "move_speed", "Move speed", "text", y)
    y = _draw_field(font, mouse_pos, e, "projectile_damage", "Projectile damage", "text", y)
    y = _draw_field(font, mouse_pos, e, "projectile_speed", "Projectile speed", "text", y)

    var hint_y: float = y + 12.0
    if hint_y >= -16.0 and hint_y <= size.y + 16.0:
        draw_string(font, Vector2(FIELD_PAD_X + 4, hint_y),
            "Click a field to edit. Category cycles; Behavior opens picker. AI leaves can use authored stat defaults.",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)


func _draw_field(font: Font, mouse_pos: Vector2, e: Dictionary,
        field: String, label: String, kind: String, y: float) -> float:
    var rect := Rect2(FIELD_PAD_X, y, size.x - FIELD_PAD_X * 2.0, FIELD_H)
    if rect.position.y + rect.size.y < 0.0 or rect.position.y > size.y:
        _field_rects.append({
            "field": field,
            "rect": rect,
            "kind": kind,
        })
        return y + FIELD_H + 6.0
    var hover := rect.has_point(mouse_pos)
    var bg: Color
    if hover:
        bg = Color(0.22, 0.32, 0.48, 0.9)
    else:
        bg = Color(0.12, 0.17, 0.24, 0.85)
    draw_rect(rect, bg)
    draw_rect(rect, Color(0.3, 0.45, 0.65, 0.9), false, 1.0)

    draw_string(font, rect.position + Vector2(12, 16),
        label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
        Color(0.6, 0.72, 0.88, 1))

    var value := str(e.get(field, ""))
    var value_col := Color(0.95, 0.97, 1.0, 1) if hover else Color(0.82, 0.9, 1.0, 1)
    if value == "":
        value = "(empty)"
        value_col = Color(0.5, 0.6, 0.78, 1)

    if kind == "category":
        var swatch := Rect2(rect.position.x + 12, rect.position.y + 24, 12, 12)
        draw_rect(swatch, EntTypes.category_color(str(e.get("category", "other"))))
        draw_string(font, rect.position + Vector2(32, 36),
            value, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, value_col)
        draw_string(font, Vector2(rect.position.x + rect.size.x - 58,
            rect.position.y + 36),
            "click", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
            Color(0.55, 0.7, 0.88, 1))
    elif kind == "behavior":
        var raw_beh: String = str(e.get("behavior", "")).strip_edges()
        var unknown: bool = (editor != null
            and not raw_beh.is_empty()
            and not editor.is_known_behavior(raw_beh))
        var beh_col := value_col
        if unknown:
            beh_col = Color(1.0, 0.55, 0.35, 1)
        draw_string(font, rect.position + Vector2(12, 36),
            value, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, beh_col)
        if unknown:
            draw_string(font, rect.position + Vector2(12 + float(value.length()) * 7.0 + 8, 36),
                "(unknown id)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
                Color(1.0, 0.55, 0.35, 1))
        draw_string(font, Vector2(rect.position.x + rect.size.x - 58,
            rect.position.y + 36),
            "▾ pick", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
            Color(0.55, 0.7, 0.88, 1))
    else:
        # Truncate extremely long values so they don't bleed past the edge.
        var max_chars: int = int((rect.size.x - 24.0) / 6.0)
        if value.length() > max_chars and max_chars > 3:
            value = value.substr(0, max_chars - 3) + "..."
        draw_string(font, rect.position + Vector2(12, 36),
            value, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, value_col)

    _field_rects.append({
        "field": field,
        "rect": rect,
        "kind": kind,
    })

    if hover:
        EditorTooltip.show_text(_tooltip_for(field, kind))

    return y + FIELD_H + 6.0


func _prompt_for(field: String) -> String:
    if field == "id":
        return "Unique id (snake_case)."
    if field == "name":
        return "Human-readable label for this entity."
    if field == "description":
        return "Short one-line description. Optional."
    if field == "scene":
        return "Path to gameplay scene, e.g. res://Space/scenes/enemies/crawler.tscn"
    if field == "sprite_set":
        return "Sprite-set folder under the pack's Sprites/, e.g. Sprites/crawler"
    if field == "behavior":
        return "Behavior id from this pack's behaviors.json. Click to pick."
    if field == "movement_mode":
        return "ground, hover, or fly. Hover/fly suppress gravity and use flight-aware AI leaves."
    if field == "hp":
        return "Maximum HP for this entity. Runtime enemy and boss nodes read this directly."
    if field == "attack_damage":
        return "Default damage used by authored melee AI actions when the behavior leaf does not override damage."
    if field == "contact_damage":
        return "Damage dealt by simply touching the player's authored hurtbox. Set to 0 to disable passive touch damage."
    if field == "contact_cooldown":
        return "Seconds between passive touch-damage hits while the player remains overlapping this enemy."
    if field == "move_speed":
        return "Default horizontal movement speed used by walk/pursue/flee/patrol leaves when their speed param is omitted."
    if field == "projectile_damage":
        return "Default damage used by shoot_action when the leaf does not override damage."
    if field == "projectile_speed":
        return "Default projectile speed used by shoot_action when the leaf does not override speed."
    return ""


func _tooltip_for(field: String, _kind: String) -> String:
    if field == "id":
        return "Unique id for this entity (snake_case). Rooms reference entities by id; renaming here updates all room placements automatically."
    if field == "name":
        return "Human-readable label shown in pickers and the editor sidebar. Free text — does not affect runtime behavior."
    if field == "category":
        return "Category bucket for this entity (enemy, item, npc, decor, other). Click to cycle through the predefined list. Drives the colored dot in the list and category filtering."
    if field == "description":
        return "Optional one-line note about this entity. Purely for your own reference."
    if field == "scene":
        return "Absolute res:// path to the gameplay scene that gets instantiated when this entity is placed. e.g. res://Space/scenes/enemies/crawler.tscn"
    if field == "sprite_set":
        return "Folder under this pack's Sprites/ that holds the entity's animation PNGs. The sprite browser on the right shows what's inside."
    if field == "behavior":
        return "Behavior id from this pack's behaviors.json. Click to open a picker. Leave empty for entities that do not have AI."
    if field == "movement_mode":
        return "ground applies normal gravity. hover/fly suppress gravity so Beehave flight leaves can steer in both axes."
    if field == "hp":
        return "Entity HP. This is the runtime max/current spawn HP for generic enemies and bosses."
    if field == "attack_damage":
        return "Default authored melee damage. attack_action reads this when the leaf's damage param is omitted."
    if field == "contact_damage":
        return "Passive body-contact damage against the player's authored hurtbox. Uses the enemy collision box as the touch area."
    if field == "contact_cooldown":
        return "Cooldown for passive body-contact damage, in seconds."
    if field == "move_speed":
        return "Fallback speed for walk, walk_left, walk_right, pursue, flee, and patrol_point leaves when their params omit speed."
    if field == "projectile_damage":
        return "Fallback damage for shoot_action when its params omit damage."
    if field == "projectile_speed":
        return "Fallback projectile speed for shoot_action when its params omit speed."
    return "Click to edit this field. Opens a text input modal."
