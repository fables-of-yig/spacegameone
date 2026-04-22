extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")

# Top bar: campaign label on the left, room selector + NEW ROOM button in
# the middle, save + close buttons on the right. Clicking the room
# dropdown opens an overlay list of rooms with per-row action icons
# (★ set start, ✎ rename, × delete). Clicking the row body elsewhere
# switches to that room.

var editor: Node = null

# Nominal topbar strip height. The control itself is normally sized to
# (vw, STRIP_H) by environment_editor._layout_children, but grows to the
# full viewport while the room-list dropdown is open so the dropdown can
# overflow past the strip and still receive clicks — see _open_room_list.
const STRIP_H: float = 64.0

var _room_dropdown_rect: Rect2 = Rect2()
var _new_room_rect: Rect2 = Rect2()
var _play_rect: Rect2 = Rect2()
var _validate_rect: Rect2 = Rect2()
var _triggers_rect: Rect2 = Rect2()
var _meta_rect: Rect2 = Rect2()
var _save_rect: Rect2 = Rect2()
var _close_rect: Rect2 = Rect2()
var _tooltips_rect: Rect2 = Rect2()
var _room_list_open: bool = false
var _room_list_rows: Array = []  # [{addr, row_rect, star_rect, rename_rect, delete_rect}]


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    set_process(true)


func _process(_delta):
    queue_redraw()


func _gui_input(event):
    if editor == null:
        return
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if _room_list_open:
            for row in _room_list_rows:
                if (row["star_rect"] as Rect2).has_point(event.position):
                    editor.set_start_room(str(row["addr"]))
                    accept_event()
                    return
                if (row["rename_rect"] as Rect2).has_point(event.position):
                    _close_room_list()
                    editor.request_rename_room(str(row["addr"]))
                    accept_event()
                    return
                if (row["dupe_rect"] as Rect2).has_point(event.position):
                    _close_room_list()
                    editor.request_duplicate_room(str(row["addr"]))
                    accept_event()
                    return
                if (row["delete_rect"] as Rect2).has_point(event.position):
                    editor.delete_room(str(row["addr"]))
                    accept_event()
                    return
                if (row["row_rect"] as Rect2).has_point(event.position):
                    editor.switch_to_room(str(row["addr"]))
                    _close_room_list()
                    accept_event()
                    return
            _close_room_list()
            accept_event()
            return

        if _tooltips_rect.has_point(event.position):
            EditorTooltip.toggle()
            accept_event()
            return
        if _room_dropdown_rect.has_point(event.position):
            _open_room_list()
            accept_event()
            return
        if _new_room_rect.has_point(event.position):
            editor.request_new_room()
            accept_event()
            return
        if _play_rect.has_point(event.position):
            editor.request_playtest()
            accept_event()
            return
        if _validate_rect.has_point(event.position):
            editor.request_validate()
            accept_event()
            return
        if _triggers_rect.has_point(event.position):
            editor.request_edit_room_triggers()
            accept_event()
            return
        if _meta_rect.has_point(event.position):
            editor.request_edit_room_meta()
            accept_event()
            return
        if _save_rect.has_point(event.position):
            editor.save_all()
            accept_event()
            return
        if _close_rect.has_point(event.position):
            editor.request_close()
            accept_event()
            return


func _open_room_list() -> void:
    _room_list_open = true
    var parent := get_parent() as Control
    if parent != null:
        size = parent.size


func _close_room_list() -> void:
    _room_list_open = false
    _room_list_rows.clear()
    var parent := get_parent() as Control
    if parent != null:
        size = Vector2(parent.size.x, STRIP_H)


func _draw():
    # Background only fills the strip even while the control is expanded
    # full-screen (list open). The rest of the control is transparent so
    # the canvas underneath stays visible behind the dropdown.
    UIPanels.draw_panel(self, Rect2(Vector2.ZERO, Vector2(size.x, STRIP_H)),
        Color.WHITE, UIPanels.PanelVariant.MAIN)

    if editor == null:
        return
    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    var pad: float = 18.0
    var label := "CAMPAIGN  %s" % editor.pack_id
    draw_string(font, Vector2(pad, 34),
        label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIPanels.TEXT_PANEL)
    var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x

    _tooltips_rect = Rect2(pad + label_w + 18.0, 16, EditorTooltip.TOGGLE_WIDTH, 32)
    EditorTooltip.draw_toggle(self, _tooltips_rect, mouse_pos)

    var room_label := "ROOM  %s" % editor.current_room_addr
    var room_label_w := font.get_string_size(room_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
    var dropdown_w: float = room_label_w + 60.0
    var new_btn_w: float = 96.0
    var group_w: float = dropdown_w + 8.0 + new_btn_w
    var group_x: float = (size.x - group_w) * 0.5

    _room_dropdown_rect = Rect2(group_x, 16, dropdown_w, 32)
    var dropdown_hover := _room_dropdown_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _room_dropdown_rect, dropdown_hover,
        Color(0.55, 0.75, 1.0, 1))
    draw_string(font, Vector2(_room_dropdown_rect.position.x + 14, 36),
        room_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 1))
    var arrow_x := _room_dropdown_rect.position.x + dropdown_w - 18
    draw_string(font, Vector2(arrow_x, 36),
        "▾", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.95, 1, 1))
    if dropdown_hover:
        EditorTooltip.show_text("The currently-edited room. Click to open the room list — switch rooms, mark the start room (★), rename (✎), or delete (×).")

    _new_room_rect = Rect2(group_x + dropdown_w + 8, 16, new_btn_w, 32)
    var new_hover := _new_room_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _new_room_rect, new_hover,
        Color(0.45, 0.8, 1.0, 1))
    if new_hover:
        EditorTooltip.show_text("Create a new empty room. You'll be asked for an address like A01 — rooms are keyed by address in the pack's room data.")
    var new_label := "+ NEW ROOM"
    var new_w := float(new_label.length()) * 6.0
    draw_string(font, Vector2(_new_room_rect.position.x + (new_btn_w - new_w) * 0.5, 36),
        new_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
        Color(1, 1, 1, 1) if new_hover else Color(0.85, 0.92, 1.0, 1))

    # Pack-level warning: the runtime falls back to the first authored
    # room if start_room is unset, but authors should see the issue in
    # the UI rather than only in a console push_warning.
    var start_addr: String = editor.get_start_room_addr()
    var rooms: Array = editor.get_room_addrs()
    if start_addr.is_empty() or not rooms.has(start_addr):
        var warn_y: float = STRIP_H - 14
        var warn_text: String = "[!] NO START ROOM SET — open the room list (▾) and click a ★ to mark one."
        draw_string(font, Vector2(pad, warn_y),
            warn_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
            Color(1.0, 0.65, 0.3, 1.0))

    var btn_w: float = 110.0
    var btn_h: float = 32.0
    var small_btn_w: float = 84.0
    var trigger_btn_w: float = 96.0
    var gap: float = 8.0

    # Right-side buttons laid out from right edge: CLOSE, SAVE, META, TRIGGERS, VALIDATE, PLAY
    var rx: float = size.x - pad

    _close_rect = Rect2(rx - btn_w, 16, btn_w, btn_h)
    rx -= btn_w + gap

    _save_rect = Rect2(rx - btn_w, 16, btn_w, btn_h)
    rx -= btn_w + gap

    _meta_rect = Rect2(rx - small_btn_w, 16, small_btn_w, btn_h)
    rx -= small_btn_w + gap

    _triggers_rect = Rect2(rx - trigger_btn_w, 16, trigger_btn_w, btn_h)
    rx -= trigger_btn_w + gap

    _validate_rect = Rect2(rx - small_btn_w, 16, small_btn_w, btn_h)
    rx -= small_btn_w + gap

    _play_rect = Rect2(rx - small_btn_w, 16, small_btn_w, btn_h)

    # Draw CLOSE
    var close_hover := _close_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _close_rect, close_hover,
        Color(0.95, 0.45, 0.4, 1))
    if close_hover:
        EditorTooltip.show_text("Return to the region editor. Unsaved changes stay in memory — use SAVE first if you want them on disk.")
    var close_label := "< REGION"
    var close_w := font.get_string_size(close_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
    var close_col: Color = Color(1, 0.95, 0.95, 1) if close_hover else Color(0.8, 0.55, 0.55, 1)
    draw_string(font, Vector2(_close_rect.position.x + (btn_w - close_w) * 0.5,
        _close_rect.position.y + 21),
        close_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, close_col)

    # Draw SAVE
    var save_hover := _save_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _save_rect, save_hover,
        Color(0.4, 0.9, 0.55, 1))
    var save_label := "SAVE*" if editor.dirty else "SAVE"
    if save_hover:
        EditorTooltip.show_text("Save every room, tileset, and metadata change to disk. An asterisk (SAVE*) means there are unsaved changes.")
    var save_w := font.get_string_size(save_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
    var save_col: Color = Color(1, 1, 0.95, 1) if save_hover else Color(0.75, 0.95, 0.75, 1)
    draw_string(font, Vector2(_save_rect.position.x + (btn_w - save_w) * 0.5,
        _save_rect.position.y + 21),
        save_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, save_col)

    # Draw META
    var meta_hover := _meta_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _meta_rect, meta_hover,
        Color(0.55, 0.7, 1.0, 1))
    if meta_hover:
        EditorTooltip.show_text("Edit this room's metadata — width/height in tiles, tileset to use, background color, music, and per-room flags.")
    var meta_label := "META"
    var meta_w := font.get_string_size(meta_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
    var meta_col: Color = Color(1, 1, 1, 1) if meta_hover else Color(0.85, 0.92, 1.0, 1)
    draw_string(font, Vector2(_meta_rect.position.x + (small_btn_w - meta_w) * 0.5,
        _meta_rect.position.y + 21),
        meta_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, meta_col)

    # Draw TRIGGERS
    var triggers_hover := _triggers_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _triggers_rect, triggers_hover,
        Color(0.85, 0.45, 0.95, 1))
    if triggers_hover:
        EditorTooltip.show_text("Author room-local triggers here. These rules live on the current room, not global.json, and are ideal for room events and cinematics.")
    var triggers_label := "TRIGGERS"
    var triggers_w := font.get_string_size(triggers_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
    var triggers_col: Color = Color(1, 1, 1, 1) if triggers_hover else Color(0.97, 0.88, 1.0, 1)
    draw_string(font, Vector2(_triggers_rect.position.x + (trigger_btn_w - triggers_w) * 0.5,
        _triggers_rect.position.y + 21),
        triggers_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, triggers_col)

    # Draw VALIDATE
    var validate_hover := _validate_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _validate_rect, validate_hover,
        Color(0.85, 0.65, 0.3, 1))
    if validate_hover:
        EditorTooltip.show_text("Validate pack content — cross-reference rooms, entities, triggers, dialogues, and abilities for dangling references or missing fields.")
    var val_label := "CHECK"
    var val_w := font.get_string_size(val_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
    var val_col: Color = Color(1, 1, 1, 1) if validate_hover else Color(0.95, 0.85, 0.7, 1)
    draw_string(font, Vector2(_validate_rect.position.x + (small_btn_w - val_w) * 0.5,
        _validate_rect.position.y + 21),
        val_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, val_col)

    # Draw PLAY
    var play_hover := _play_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _play_rect, play_hover,
        Color(0.3, 0.85, 0.45, 1))
    if play_hover:
        EditorTooltip.show_text("Playtest this room (Ctrl+9). Saves, then launches the MV runtime with the player spawned at the player_spawn entity.")
    var play_label := "▶ PLAY"
    var play_w := font.get_string_size(play_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
    var play_col: Color = Color(1, 1, 1, 1) if play_hover else Color(0.85, 1.0, 0.85, 1)
    draw_string(font, Vector2(_play_rect.position.x + (small_btn_w - play_w) * 0.5,
        _play_rect.position.y + 21),
        play_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, play_col)

    if _room_list_open:
        _draw_room_list(font, mouse_pos)
    else:
        _room_list_rows.clear()


func _draw_room_list(font: Font, mouse_pos: Vector2) -> void:
    var rooms: Array = editor.get_room_addrs()
    var list_w: float = 340.0
    var row_h: float = 30.0
    var list_h: float = float(rooms.size()) * row_h + 12.0
    var list_x: float = _room_dropdown_rect.position.x + (_room_dropdown_rect.size.x - list_w) * 0.5
    var list_y: float = _room_dropdown_rect.position.y + _room_dropdown_rect.size.y + 4
    var list_rect := Rect2(list_x, list_y, list_w, list_h)
    draw_rect(list_rect, Color(0.05, 0.07, 0.12, 0.98))
    draw_rect(list_rect, Color(0.4, 0.6, 0.9, 1), false, 2.0)

    var start_addr: String = editor.get_start_room_addr()

    _room_list_rows.clear()
    for i in rooms.size():
        var addr := str(rooms[i])
        var row_rect := Rect2(list_x + 6, list_y + 6 + float(i) * row_h, list_w - 12, row_h - 4)
        var icon_size: float = 22.0
        var ix: float = row_rect.position.x + row_rect.size.x - icon_size - 4.0
        var iy: float = row_rect.position.y + (row_rect.size.y - icon_size) * 0.5
        var delete_rect := Rect2(ix, iy, icon_size, icon_size)
        ix -= icon_size + 4.0
        var dupe_rect := Rect2(ix, iy, icon_size, icon_size)
        ix -= icon_size + 4.0
        var rename_rect := Rect2(ix, iy, icon_size, icon_size)
        ix -= icon_size + 4.0
        var star_rect := Rect2(ix, iy, icon_size, icon_size)

        _room_list_rows.append({
            "addr": addr,
            "row_rect": row_rect,
            "star_rect": star_rect,
            "rename_rect": rename_rect,
            "dupe_rect": dupe_rect,
            "delete_rect": delete_rect,
        })

        var is_active: bool = addr == editor.current_room_addr
        var is_start := addr == start_addr
        var row_hover := row_rect.has_point(mouse_pos) \
            and not star_rect.has_point(mouse_pos) \
            and not rename_rect.has_point(mouse_pos) \
            and not dupe_rect.has_point(mouse_pos) \
            and not delete_rect.has_point(mouse_pos)

        var bg: Color
        if is_active:
            bg = Color(0.25, 0.45, 0.75, 0.9)
        elif row_hover:
            bg = Color(0.2, 0.28, 0.42, 0.9)
        else:
            bg = Color(0.1, 0.14, 0.2, 0.9)
        draw_rect(row_rect, bg)

        var text_col: Color
        if is_active:
            text_col = Color(1, 1, 1, 1)
        else:
            text_col = Color(0.7, 0.8, 0.9, 1)
        var label_prefix := "★ " if is_start else "  "
        draw_string(font, Vector2(row_rect.position.x + 8, row_rect.position.y + 20),
            label_prefix + addr, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_col)

        _draw_row_icon(font, star_rect, "★", is_start,
            star_rect.has_point(mouse_pos),
            Color(1, 0.85, 0.25, 1), Color(0.45, 0.42, 0.25, 1))
        _draw_row_icon(font, rename_rect, "✎", false,
            rename_rect.has_point(mouse_pos),
            Color(0.45, 0.85, 1, 1), Color(0.25, 0.45, 0.6, 1))
        _draw_row_icon(font, dupe_rect, "⊕", false,
            dupe_rect.has_point(mouse_pos),
            Color(0.5, 0.9, 0.6, 1), Color(0.3, 0.5, 0.35, 1))
        _draw_row_icon(font, delete_rect, "×", false,
            delete_rect.has_point(mouse_pos),
            Color(1, 0.45, 0.45, 1), Color(0.55, 0.25, 0.25, 1))
        if star_rect.has_point(mouse_pos):
            EditorTooltip.show_text("Set this room as the start room. The player will spawn here when the pack begins.")
        elif rename_rect.has_point(mouse_pos):
            EditorTooltip.show_text("Rename this room's address. All door links that reference this room get updated automatically.")
        elif dupe_rect.has_point(mouse_pos):
            EditorTooltip.show_text("Duplicate this room — creates a deep copy with a new address. Useful for variations or test layouts.")
        elif delete_rect.has_point(mouse_pos):
            EditorTooltip.show_text("Delete this room permanently. Door links pointing to it will be broken — check the room list afterwards.")
        elif row_hover:
            EditorTooltip.show_text("Click to switch to this room. The current room's unsaved changes stay in memory — use SAVE to persist.")


func _draw_row_icon(font: Font, rect: Rect2, glyph: String, active: bool,
        hover: bool, active_col: Color, rest_col: Color) -> void:
    var bg_col: Color
    if hover:
        bg_col = Color(0.3, 0.4, 0.55, 0.95)
    elif active:
        bg_col = Color(0.25, 0.32, 0.45, 0.8)
    else:
        bg_col = Color(0.14, 0.18, 0.25, 0.7)
    draw_rect(rect, bg_col)
    draw_rect(rect, Color(0.3, 0.45, 0.6, 0.9), false, 1.0)
    var text_col := active_col if (hover or active) else rest_col
    draw_string(font, rect.position + Vector2(7, 16),
        glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, text_col)
