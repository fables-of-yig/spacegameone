extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const EntTypes = preload("res://Space/scripts/editor/ent/ent_types.gd")

# Left sidebar for the entity editor. Scrollable list of entities in the
# pack; each row shows a category-colored dot, the entity id + name, and
# per-row ✎ (rename) / × (delete) icon buttons. Clicking the row body
# selects that entity; clicking the icons dispatches through the editor.

var editor: Node = null

const ROW_H: float = 36.0
const HEADER_H: float = 38.0
const PAD: float = 10.0
const ICON_SIZE: float = 22.0

var _scroll: float = 0.0
var _viewport_h: float = 0.0
var _content_h: float = 0.0
var _rows: Array = []  # [{id, row_rect, rename_rect, delete_rect}]


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    set_process(true)
    clip_contents = true


func _process(_delta):
    queue_redraw()


func _gui_input(event):
    if editor == null:
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _scroll = min(_scroll + 40.0, max(0.0, _content_h - _viewport_h))
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            _scroll = max(_scroll - 40.0, 0.0)
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            for row in _rows:
                if (row["rename_rect"] as Rect2).has_point(mb.position):
                    editor.request_rename_entity(str(row["id"]))
                    accept_event()
                    return
                if (row["delete_rect"] as Rect2).has_point(mb.position):
                    editor.delete_entity(str(row["id"]))
                    accept_event()
                    return
                if (row["row_rect"] as Rect2).has_point(mb.position):
                    editor.select_entity(str(row["id"]))
                    accept_event()
                    return


func _draw():
    UIPanels.draw_panel(self, Rect2(Vector2.ZERO, size),
        Color.WHITE, UIPanels.PanelVariant.ALT)

    if editor == null:
        return
    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    var header_label := "ENTITIES"
    draw_string(font, Vector2(PAD + 4, 24),
        header_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        UIPanels.TEXT_PANEL)

    var entities: Array = editor.get_entities()
    var count := entities.size()
    draw_string(font, Vector2(size.x - PAD - 40, 24),
        "%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        UIPanels.TEXT_PANEL_DIM)

    var list_y0: float = HEADER_H
    _viewport_h = size.y - list_y0 - PAD
    _content_h = float(count) * ROW_H
    if _scroll > max(0.0, _content_h - _viewport_h):
        _scroll = max(0.0, _content_h - _viewport_h)

    _rows.clear()
    for i in count:
        var e_v: Variant = entities[i]
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        var e: Dictionary = e_v
        var id := str(e.get("id", ""))
        var name_str := str(e.get("name", ""))
        var cat := str(e.get("category", "other"))
        var sprite_set := str(e.get("sprite_set", ""))
        var placement_folder := str(e.get("placement_folder", ""))

        var row_top: float = list_y0 + float(i) * ROW_H - _scroll
        var row_rect := Rect2(PAD, row_top, size.x - PAD * 2.0, ROW_H - 4.0)

        # Icon hit-rects regardless of visibility so draw/input stay in sync.
        var ix: float = row_rect.position.x + row_rect.size.x - ICON_SIZE - 4.0
        var iy: float = row_rect.position.y + (row_rect.size.y - ICON_SIZE) * 0.5
        var delete_rect := Rect2(ix, iy, ICON_SIZE, ICON_SIZE)
        ix -= ICON_SIZE + 4.0
        var rename_rect := Rect2(ix, iy, ICON_SIZE, ICON_SIZE)

        _rows.append({
            "id": id,
            "row_rect": row_rect,
            "rename_rect": rename_rect,
            "delete_rect": delete_rect,
        })

        if row_rect.position.y + row_rect.size.y < list_y0:
            continue
        if row_rect.position.y > size.y:
            continue

        var is_selected: bool = id == editor.selected_entity_id
        var row_hover := row_rect.has_point(mouse_pos) \
            and not rename_rect.has_point(mouse_pos) \
            and not delete_rect.has_point(mouse_pos)

        var bg: Color
        if is_selected:
            bg = Color(0.3, 0.5, 0.8, 0.95)
        elif row_hover:
            bg = Color(0.2, 0.3, 0.45, 0.85)
        else:
            bg = Color(0.1, 0.15, 0.22, 0.85)
        draw_rect(row_rect, bg)

        var dot_col := EntTypes.category_color(cat)
        var dot_pos := Vector2(row_rect.position.x + 10.0,
            row_rect.position.y + row_rect.size.y * 0.5)
        draw_circle(dot_pos, 5.0, dot_col)

        var text_col: Color
        if is_selected:
            text_col = Color(1, 1, 1, 1)
        else:
            text_col = Color(0.78, 0.85, 0.95, 1)
        draw_string(font, Vector2(row_rect.position.x + 22.0,
            row_rect.position.y + 14),
            id, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_col)
        var secondary := ""
        if placement_folder != "":
            secondary = placement_folder
            if name_str != "" and name_str != id:
                secondary += " - " + name_str
        elif name_str != "" and name_str != id:
            secondary = name_str
        elif sprite_set != "":
            secondary = sprite_set

        if secondary != "":
            draw_string(font, Vector2(row_rect.position.x + 22.0,
                row_rect.position.y + 28),
                secondary, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
                Color(0.55, 0.68, 0.82, 1))

        _draw_row_icon(font, rename_rect, "✎",
            rename_rect.has_point(mouse_pos),
            Color(0.45, 0.85, 1, 1), Color(0.25, 0.45, 0.6, 1))
        _draw_row_icon(font, delete_rect, "×",
            delete_rect.has_point(mouse_pos),
            Color(1, 0.45, 0.45, 1), Color(0.55, 0.25, 0.25, 1))

        if rename_rect.has_point(mouse_pos):
            EditorTooltip.show_text("Rename entity \"%s\". This changes its id; rooms that placed this entity will be re-pointed to the new id automatically." % id)
        elif delete_rect.has_point(mouse_pos):
            EditorTooltip.show_text("Delete entity \"%s\". Any room placements of this entity become broken references. There is no undo." % id)
        elif row_hover:
            EditorTooltip.show_text("Entity \"%s\" (category: %s). Click to edit its fields, sprite set, and behavior on the right." % [id, cat])

    if count == 0:
        draw_string(font, Vector2(PAD + 6, list_y0 + 24),
            "No entities yet.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
            Color(0.55, 0.65, 0.8, 1))
        draw_string(font, Vector2(PAD + 6, list_y0 + 42),
            "Use + ADD ENTITY above.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
            Color(0.45, 0.55, 0.7, 1))


func _draw_row_icon(font: Font, rect: Rect2, glyph: String,
        hover: bool, active_col: Color, rest_col: Color) -> void:
    var bg_col: Color
    if hover:
        bg_col = Color(0.3, 0.4, 0.55, 0.95)
    else:
        bg_col = Color(0.14, 0.18, 0.25, 0.7)
    draw_rect(rect, bg_col)
    draw_rect(rect, Color(0.3, 0.45, 0.6, 0.9), false, 1.0)
    var text_col := active_col if hover else rest_col
    draw_string(font, rect.position + Vector2(7, 16),
        glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, text_col)
