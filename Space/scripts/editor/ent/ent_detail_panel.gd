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
    y = _draw_section(font, y, "Identity")
    y = _draw_field(font, mouse_pos, e, "id", "Internal name", "text", y)
    y = _draw_field(font, mouse_pos, e, "name", "Display name", "text", y)
    y = _draw_field(font, mouse_pos, e, "category", "Kind of entity", "category", y)
    y = _draw_field(font, mouse_pos, e, "description", "Author note", "text", y)

    y = _draw_section(font, y, "Appearance")
    y = _draw_field(font, mouse_pos, e, "scene", "Gameplay scene", "text", y)
    y = _draw_field(font, mouse_pos, e, "sprite_set", "Animation art", "text", y)

    y = _draw_section(font, y, "AI")
    y = _draw_field(font, mouse_pos, e, "behavior", "Behavior tree", "behavior", y)
    y = _draw_field(font, mouse_pos, e, "movement_mode", "How it moves", "text", y)
    y = _draw_field(font, mouse_pos, e, "move_speed", "Move speed", "text", y)

    y = _draw_section(font, y, "Combat")
    y = _draw_field(font, mouse_pos, e, "hp", "Health", "text", y)
    y = _draw_field(font, mouse_pos, e, "attack_damage", "Melee damage", "text", y)
    y = _draw_field(font, mouse_pos, e, "contact_damage", "Touch damage", "text", y)
    y = _draw_field(font, mouse_pos, e, "contact_cooldown", "Touch hit delay", "text", y)
    y = _draw_field(font, mouse_pos, e, "projectile_damage", "Projectile damage", "text", y)
    y = _draw_field(font, mouse_pos, e, "projectile_speed", "Projectile speed", "text", y)
    y = _draw_field(font, mouse_pos, e, "melee_range", "Melee reach", "text", y)
    y = _draw_field(font, mouse_pos, e, "melee_attack_trigger_frame", "Melee hit frame", "text", y)
    y = _draw_field(font, mouse_pos, e, "projectile_range", "Projectile range", "text", y)
    y = _draw_field(font, mouse_pos, e, "projectile_attack_trigger_frame", "Projectile fire frame", "text", y)

    y = _draw_section(font, y, "Loot")
    y = _draw_field(font, mouse_pos, e, "item_drops", "Drops", "text", y)

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


func _draw_section(font: Font, y: float, label: String) -> float:
    if y >= -18.0 and y <= size.y + 18.0:
        draw_string(font, Vector2(FIELD_PAD_X + 4, y + 16),
            label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
            Color(0.48, 0.72, 0.96, 1))
        draw_line(Vector2(FIELD_PAD_X, y + 22),
            Vector2(size.x - FIELD_PAD_X, y + 22),
            Color(0.28, 0.42, 0.62, 0.8), 1.0)
    return y + 30.0


func _prompt_for(field: String) -> String:
    if field == "id":
        return "Stable internal name. Use snake_case, like mayor_guard."
    if field == "name":
        return "Name shown in editor pickers and notes."
    if field == "description":
        return "Short author note. Optional."
    if field == "scene":
        return "Path to the gameplay scene, e.g. res://Space/scenes/enemies/crawler.tscn"
    if field == "sprite_set":
        return "Animation art folder under this pack's Sprites folder, e.g. Sprites/crawler"
    if field == "behavior":
        return "Behavior tree this actor uses. Click to pick one."
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
    if field == "melee_range":
        return "Default melee attack range in pixels for attack_action when the leaf does not override range."
    if field == "melee_attack_trigger_frame":
        return "Animation frame index that actually lands the melee hit. Use -1 to land on the final frame."
    if field == "projectile_range":
        return "Default max distance in pixels for shoot_action when aiming at the player and the leaf does not override range."
    if field == "projectile_attack_trigger_frame":
        return "Animation frame index that actually fires the projectile. Use -1 to fire on the final frame."
    if field == "item_drops":
        return "Advanced drop list. Example: [{\"id\":\"health_pickup\",\"count\":1,\"chance\":0.35}]. Use item ids from the Shop Editor's Item Registry."
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
    if field == "melee_range":
        return "Fallback melee distance used by attack_action when its params omit range."
    if field == "melee_attack_trigger_frame":
        return "Which frame of the attack animation actually applies melee damage. -1 means the last frame."
    if field == "projectile_range":
        return "Fallback attack distance used by shoot_action when aiming at the player and its params omit range."
    if field == "projectile_attack_trigger_frame":
        return "Which frame of the attack animation actually spawns the projectile. -1 means the last frame."
    if field == "item_drops":
        return "Enemy loot table. JSON array entries support id/item_id, count, chance 0..1, and optional pickup_entity. Spawned pickups use these item ids."
    return "Click to edit this field. Opens a text input modal."
