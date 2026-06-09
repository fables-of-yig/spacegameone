extends Control

# Nebula-skinned player-facing pack MAIN MENU (title screen) — New Game / Load
# Game / Settings / Exit to Desktop, with a 5-slot save picker, overwrite confirm,
# exit confirm, and a save/load toast. Built from the Claude Design "Main Menu"
# handoff. Shown by main_menu.gd's _start_play_pack_menu (replacing the dormant
# per-pack authored "main_menu" screen, mirroring how NebulaPause supersedes the
# authored pause screen). Settings reuses the same NebulaPause settings surface.
#
# It owns no game logic: New Game / Load route back out via signals to main_menu,
# which fires the SAME real entry paths the dev hub already uses (play_pack /
# _load_slot). Slot metadata is read from GameManager.get_save_info (real fields
# only — ship/hull name, system, credits, playtime, last-saved; no fabricated
# commander/level/difficulty/completion).

const NT := preload("res://MV/scripts/console/nebula_theme.gd")

signal new_game_requested(slot: int)
signal load_game_requested(slot: int)
signal settings_requested
signal exit_requested
signal back_requested

var _pack_id: String = ""
var _picker_mode: String = ""   # "" (title) | "new" | "load"
var _confirm_kind: String = ""  # "" | "overwrite" | "exit"
var _confirm_slot: int = -1

var _title: Control = null
var _picker: Control = null
var _slot_list: VBoxContainer = null
var _picker_title: Label = null
var _picker_hint: Label = null
var _picker_footer: Label = null
var _confirm: Control = null
var _confirm_title: Label = null
var _confirm_body: Label = null
var _confirm_accept: Button = null
var _toast: PanelContainer = null
var _toast_label: Label = null


func _ready() -> void:
    set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_IGNORE  # let the parent's starfield show; only our controls capture
    visible = false
    _build_ui()


func open(pack_id: String) -> void:
    _pack_id = pack_id
    theme = NT.theme()
    set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    _picker_mode = ""
    _confirm_kind = ""
    visible = true
    _apply_views()


func close() -> void:
    visible = false


func is_open() -> bool:
    return visible


func _input(event: InputEvent) -> void:
    if not visible:
        return
    # Settings is the NebulaPause autoload on a higher layer; while it's open it
    # owns Esc (pop settings/keybindings), so don't also pop our own view.
    if NebulaPause != null and NebulaPause.is_open():
        return
    if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
        handle_back()
        get_viewport().set_input_as_handled()


func handle_back() -> void:
    if _confirm_kind != "":
        _hide_confirm()
        return
    if _picker_mode != "":
        _picker_mode = ""
        _apply_views()
        return
    back_requested.emit()


# --- Views ---------------------------------------------------------------------

func _apply_views() -> void:
    if _title != null:
        _title.visible = _picker_mode == ""
    if _picker != null:
        _picker.visible = _picker_mode != ""
        if _picker_mode != "":
            _rebuild_picker()


func _open_picker(mode: String) -> void:
    _picker_mode = mode
    _apply_views()


# --- UI ------------------------------------------------------------------------

func _build_ui() -> void:
    theme = NT.theme()

    # Title view — centered menu column over the parent's live starfield (no veil).
    _title = Control.new()
    _title.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    _title.mouse_filter = MOUSE_FILTER_IGNORE
    add_child(_title)

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    center.mouse_filter = MOUSE_FILTER_IGNORE
    _title.add_child(center)

    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 12)
    col.custom_minimum_size = Vector2(392, 0)
    center.add_child(col)

    col.add_child(_menu_row("New Game", "Begin or overwrite a campaign", _on_new_game, "primary"))
    col.add_child(_menu_row("Load Game", "Resume a saved campaign", _on_load_game, "steel"))
    col.add_child(_menu_row("Settings", "Graphics · Audio · Controls", func(): settings_requested.emit(), "steel"))
    col.add_child(_menu_row("Exit to Desktop", "Quit to your desktop", _on_exit, "danger"))

    _build_picker()
    _build_confirm()
    _build_toast()
    _apply_views()


func _menu_row(label_text: String, sub_text: String, on_click: Callable, variant: String) -> Control:
    var card := PanelContainer.new()
    var box := NT.card_box(variant == "primary")
    if variant == "danger":
        box.border_color = NT.C_ERROR
        box.border_width_left = 3
    card.add_theme_stylebox_override("panel", box)
    card.mouse_filter = MOUSE_FILTER_STOP
    card.mouse_default_cursor_shape = CURSOR_POINTING_HAND
    card.gui_input.connect(func(e: InputEvent):
        if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
            on_click.call())
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    card.add_child(row)
    var txt := VBoxContainer.new()
    txt.add_theme_constant_override("separation", 0)
    txt.size_flags_horizontal = SIZE_EXPAND_FILL
    var name_lbl := Label.new()
    name_lbl.text = label_text.to_upper()
    name_lbl.add_theme_font_size_override("font_size", NT.size("button"))
    var name_col := NT.C_TITLE if variant == "primary" else NT.C_BODY
    if variant == "danger":
        name_col = NT.C_ERROR
    name_lbl.add_theme_color_override("font_color", name_col)
    if NT.font() != null:
        name_lbl.add_theme_font_override("font", NT.font())
    txt.add_child(name_lbl)
    if not sub_text.is_empty():
        var sub := Label.new()
        sub.text = sub_text
        sub.add_theme_color_override("font_color", NT.C_DIM)
        sub.add_theme_font_size_override("font_size", NT.size("hint"))
        txt.add_child(sub)
    row.add_child(txt)
    var chev := Label.new()
    chev.text = "›"
    chev.add_theme_color_override("font_color", NT.C_DIM)
    chev.size_flags_vertical = SIZE_SHRINK_CENTER
    row.add_child(chev)
    return card


func _build_picker() -> void:
    _picker = Control.new()
    _picker.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    _picker.mouse_filter = MOUSE_FILTER_STOP
    add_child(_picker)

    var scrim := ColorRect.new()
    scrim.color = Color(4.0 / 255.0, 7.0 / 255.0, 12.0 / 255.0, 0.5)
    scrim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    scrim.mouse_filter = MOUSE_FILTER_STOP
    scrim.gui_input.connect(func(e: InputEvent):
        if e is InputEventMouseButton and e.pressed:
            _picker_mode = ""
            _apply_views())
    _picker.add_child(scrim)

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    _picker.add_child(center)

    var frame := PanelContainer.new()
    frame.custom_minimum_size = Vector2(640, 0)
    center.add_child(frame)
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 24)
    margin.add_theme_constant_override("margin_right", 24)
    margin.add_theme_constant_override("margin_top", 20)
    margin.add_theme_constant_override("margin_bottom", 18)
    frame.add_child(margin)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 14)
    margin.add_child(col)

    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 10)
    var head_col := VBoxContainer.new()
    head_col.add_theme_constant_override("separation", 0)
    head_col.size_flags_horizontal = SIZE_EXPAND_FILL
    _picker_title = NT.title_label("NEW GAME")
    head_col.add_child(_picker_title)
    _picker_hint = Label.new()
    _picker_hint.add_theme_color_override("font_color", NT.C_DIM)
    _picker_hint.add_theme_font_size_override("font_size", NT.size("hint"))
    head_col.add_child(_picker_hint)
    header.add_child(head_col)
    var close_btn := Button.new()
    close_btn.text = "✕"
    close_btn.custom_minimum_size = Vector2(40, 0)
    close_btn.pressed.connect(func():
        _picker_mode = ""
        _apply_views())
    header.add_child(close_btn)
    col.add_child(header)

    _slot_list = VBoxContainer.new()
    _slot_list.add_theme_constant_override("separation", 8)
    col.add_child(_slot_list)

    var footer := HBoxContainer.new()
    footer.add_theme_constant_override("separation", 10)
    _picker_footer = Label.new()
    _picker_footer.size_flags_horizontal = SIZE_EXPAND_FILL
    _picker_footer.add_theme_color_override("font_color", NT.C_DIM)
    _picker_footer.add_theme_font_size_override("font_size", NT.size("hint"))
    footer.add_child(_picker_footer)
    var back := NebulaUi.button("Back", "ghost")
    back.pressed.connect(func():
        _picker_mode = ""
        _apply_views())
    footer.add_child(back)
    col.add_child(footer)


func _rebuild_picker() -> void:
    var is_new := _picker_mode == "new"
    _picker_title.text = "NEW GAME" if is_new else "LOAD GAME"
    _picker_hint.text = "Choose a slot" if is_new else "Select a save"
    _picker_footer.text = "Selecting an occupied slot will ask before overwriting." if is_new else "Empty slots cannot be loaded."
    for child in _slot_list.get_children():
        child.queue_free()
    for slot in range(1, GameManager.MAX_SAVE_SLOTS + 1):
        _slot_list.add_child(_slot_row(slot, GameManager.get_save_info(slot), is_new))


func _slot_row(slot: int, info: Dictionary, is_new: bool) -> Control:
    var occupied := not info.is_empty()
    var loadable := occupied or is_new
    var card := PanelContainer.new()
    card.add_theme_stylebox_override("panel", NT.card_box(false))
    card.custom_minimum_size = Vector2(0, 78)
    if not loadable:
        card.modulate = Color(1, 1, 1, 0.45)
    else:
        card.mouse_filter = MOUSE_FILTER_STOP
        card.mouse_default_cursor_shape = CURSOR_POINTING_HAND
        card.gui_input.connect(func(e: InputEvent):
            if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
                _on_slot_picked(slot, occupied, is_new))

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 14)
    card.add_child(row)

    # Slot-number badge.
    var badge := PanelContainer.new()
    var bbox := NT.well_box()
    bbox.border_color = NT.C_ACCENT
    badge.add_theme_stylebox_override("panel", bbox)
    badge.custom_minimum_size = Vector2(54, 54)
    badge.size_flags_vertical = SIZE_SHRINK_CENTER
    var bnum := Label.new()
    bnum.text = str(slot)
    bnum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    bnum.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    bnum.add_theme_color_override("font_color", NT.C_ACCENT)
    bnum.add_theme_font_size_override("font_size", NT.size("title"))
    badge.add_child(bnum)
    row.add_child(badge)

    var info_col := VBoxContainer.new()
    info_col.add_theme_constant_override("separation", 1)
    info_col.size_flags_horizontal = SIZE_EXPAND_FILL
    info_col.size_flags_vertical = SIZE_SHRINK_CENTER
    if occupied:
        var headline := Label.new()
        headline.text = str(info.get("hull_name", "Unknown Ship"))
        headline.add_theme_color_override("font_color", NT.C_TITLE)
        headline.add_theme_font_size_override("font_size", NT.size("section"))
        info_col.add_child(headline)
        var loc := Label.new()
        loc.text = str(info.get("system_name", "—"))
        loc.add_theme_color_override("font_color", NT.C_BODY)
        loc.add_theme_font_size_override("font_size", NT.size("hint"))
        info_col.add_child(loc)
        var meta := Label.new()
        meta.text = "◇ %s cr   ◷ %s" % [_fmt_credits(int(info.get("credits", 0))), _fmt_playtime(float(info.get("total_game_hours", 0.0)))]
        meta.add_theme_color_override("font_color", NT.C_DIM)
        meta.add_theme_font_size_override("font_size", NT.size("hint"))
        info_col.add_child(meta)
    else:
        var empty := Label.new()
        empty.text = "EMPTY SLOT"
        empty.add_theme_color_override("font_color", NT.C_DIM)
        empty.add_theme_font_size_override("font_size", NT.size("section"))
        info_col.add_child(empty)
        var hint := Label.new()
        hint.text = "Begin a new campaign here" if is_new else "No saved data"
        hint.add_theme_color_override("font_color", NT.C_DIM)
        hint.add_theme_font_size_override("font_size", NT.size("hint"))
        info_col.add_child(hint)
    row.add_child(info_col)

    var right := Label.new()
    right.size_flags_vertical = SIZE_SHRINK_CENTER
    right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    right.add_theme_font_size_override("font_size", NT.size("hint"))
    if occupied:
        right.text = _fmt_saved(int(info.get("save_time", 0)))
        right.add_theme_color_override("font_color", NT.C_DIM)
    elif is_new:
        right.text = "+ START"
        right.add_theme_color_override("font_color", NT.C_ACCENT)
    else:
        right.text = "— — —"
        right.add_theme_color_override("font_color", NT.C_DIM)
    row.add_child(right)
    return card


func _on_slot_picked(slot: int, occupied: bool, is_new: bool) -> void:
    if is_new:
        if occupied:
            _show_confirm("overwrite", slot)
        else:
            _start_new(slot)
    else:
        if occupied:
            load_game_requested.emit(slot)


func _start_new(slot: int) -> void:
    _show_toast("✓  New campaign — Slot %d" % slot, NT.C_SUCCESS)
    new_game_requested.emit(slot)


# --- Title-row actions ---------------------------------------------------------

func _on_new_game() -> void:
    _open_picker("new")


func _on_load_game() -> void:
    _open_picker("load")


func _on_exit() -> void:
    _show_confirm("exit", -1)


# --- Confirm modal -------------------------------------------------------------

func _build_confirm() -> void:
    _confirm = Control.new()
    _confirm.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    _confirm.theme = NT.theme()
    _confirm.visible = false
    _confirm.mouse_filter = MOUSE_FILTER_STOP
    add_child(_confirm)

    var scrim := ColorRect.new()
    scrim.color = Color(4.0 / 255.0, 7.0 / 255.0, 12.0 / 255.0, 0.7)
    scrim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    scrim.mouse_filter = MOUSE_FILTER_STOP
    scrim.gui_input.connect(func(e: InputEvent):
        if e is InputEventMouseButton and e.pressed:
            _hide_confirm())
    _confirm.add_child(scrim)

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    _confirm.add_child(center)
    var frame := PanelContainer.new()
    frame.custom_minimum_size = Vector2(440, 0)
    center.add_child(frame)
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 24)
    margin.add_theme_constant_override("margin_right", 24)
    margin.add_theme_constant_override("margin_top", 22)
    margin.add_theme_constant_override("margin_bottom", 20)
    frame.add_child(margin)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 14)
    margin.add_child(col)

    _confirm_title = Label.new()
    _confirm_title.add_theme_color_override("font_color", NT.C_ERROR)
    _confirm_title.add_theme_font_size_override("font_size", NT.size("title"))
    if NT.font() != null:
        _confirm_title.add_theme_font_override("font", NT.font())
    col.add_child(_confirm_title)
    _confirm_body = Label.new()
    _confirm_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _confirm_body.add_theme_color_override("font_color", NT.C_BODY)
    col.add_child(_confirm_body)

    var btns := HBoxContainer.new()
    btns.add_theme_constant_override("separation", 10)
    var spacer := Control.new()
    spacer.size_flags_horizontal = SIZE_EXPAND_FILL
    btns.add_child(spacer)
    var cancel := NebulaUi.button("Cancel", "ghost")
    cancel.pressed.connect(_hide_confirm)
    btns.add_child(cancel)
    _confirm_accept = Button.new()
    _confirm_accept.self_modulate = NT.C_ERROR
    _confirm_accept.pressed.connect(_on_confirm_accept)
    btns.add_child(_confirm_accept)
    col.add_child(btns)


func _show_confirm(kind: String, slot: int) -> void:
    _confirm_kind = kind
    _confirm_slot = slot
    if kind == "overwrite":
        var info := GameManager.get_save_info(slot)
        _confirm_title.text = "OVERWRITE SAVE?"
        _confirm_body.text = "Slot %d holds %s in %s. Starting a new campaign here will erase it." % [
            slot, str(info.get("hull_name", "a save")), str(info.get("system_name", "—"))]
        _confirm_accept.text = "Overwrite"
    else:
        _confirm_title.text = "EXIT TO DESKTOP"
        _confirm_body.text = "Quit and return to your desktop? Any unsaved progress will be lost."
        _confirm_accept.text = "Quit"
    _confirm.theme = NT.theme()
    _confirm.visible = true


func _hide_confirm() -> void:
    _confirm_kind = ""
    _confirm_slot = -1
    if _confirm != null:
        _confirm.visible = false


func _on_confirm_accept() -> void:
    var kind := _confirm_kind
    var slot := _confirm_slot
    _hide_confirm()
    if kind == "overwrite":
        _start_new(slot)
    elif kind == "exit":
        exit_requested.emit()


# --- Toast ---------------------------------------------------------------------

func _build_toast() -> void:
    _toast = PanelContainer.new()
    var box := NT.card_box(false)
    box.border_color = NT.C_SUCCESS
    _toast.add_theme_stylebox_override("panel", box)
    _toast.visible = false
    _toast.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM)
    _toast.offset_top = -40
    _toast.offset_bottom = -40
    _toast.grow_horizontal = GROW_DIRECTION_BOTH
    _toast.grow_vertical = GROW_DIRECTION_BEGIN
    _toast_label = Label.new()
    _toast_label.add_theme_color_override("font_color", NT.C_SUCCESS)
    _toast.add_child(_toast_label)
    add_child(_toast)


func _show_toast(text: String, color: Color) -> void:
    if _toast == null:
        return
    var box := NT.card_box(false)
    box.border_color = color
    _toast.add_theme_stylebox_override("panel", box)
    _toast_label.text = text
    _toast_label.add_theme_color_override("font_color", color)
    _toast.visible = true
    var timer := get_tree().create_timer(2.6, true)
    timer.timeout.connect(func():
        if _toast != null:
            _toast.visible = false)


# --- Formatting helpers --------------------------------------------------------

func _fmt_credits(n: int) -> String:
    var s := str(n)
    var out := ""
    var c := 0
    for i in range(s.length() - 1, -1, -1):
        out = s[i] + out
        c += 1
        if c % 3 == 0 and i > 0:
            out = "," + out
    return out


func _fmt_playtime(hours: float) -> String:
    var total_min := int(round(hours * 60.0))
    return "%dh %02dm" % [total_min / 60, total_min % 60]


func _fmt_saved(unix: int) -> String:
    if unix <= 0:
        return ""
    var d := Time.get_datetime_dict_from_unix_time(unix)
    return "%04d-%02d-%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]
