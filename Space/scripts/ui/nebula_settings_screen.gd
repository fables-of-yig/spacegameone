extends Control

# Nebula-skinned Settings screen — Graphics / Audio / Gameplay / Controls. Data-
# driven: rows are generated from SettingsCatalog and read/write through
# SettingsManager (the single persistence + apply layer). Replaces the vanilla
# settings_menu.gd as the one settings surface (pause menu + main menu both route
# here via NebulaPause.open_settings).
#
# Honesty: any catalog setting with wired==false renders a dim "PREVIEW — not yet
# wired" tag; the value still persists so it's ready to wire later, but nothing
# pretends it changes the game.
#
# This screen does NOT own its Escape input — NebulaPause routes Back to it (and
# owns the keybindings sub-overlay) so the pause→settings→keybindings stack pops
# deterministically across both engines.

const NT := preload("res://MV/scripts/console/nebula_theme.gd")
const Catalog := preload("res://Space/scripts/shared/settings/settings_catalog.gd")

signal closed
signal edit_keybindings_requested

var _host_context: String = "pause_menu"
var _active_tab: String = "graphics"

var _veil: ColorRect = null
var _frame: PanelContainer = null
var _tab_rail: VBoxContainer = null
var _content_scroll: ScrollContainer = null
var _content: VBoxContainer = null
var _tab_buttons: Dictionary = {}      # tab_id -> PanelContainer (rail row)


func _ready() -> void:
    visible = false
    set_anchors_preset(PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_STOP
    _build_ui()


func open_menu(host_context: String = "pause_menu") -> void:
    _host_context = host_context
    theme = NT.theme()
    set_anchors_preset(PRESET_FULL_RECT)
    visible = true
    _rebuild_tab_content()


func close_menu() -> void:
    visible = false
    closed.emit()


func is_open() -> bool:
    return visible


# --- UI construction -----------------------------------------------------------

func _build_ui() -> void:
    theme = NT.theme()

    _veil = ColorRect.new()
    _veil.color = Color(4.0 / 255.0, 7.0 / 255.0, 12.0 / 255.0, 0.62)
    _veil.set_anchors_preset(PRESET_FULL_RECT)
    _veil.mouse_filter = MOUSE_FILTER_STOP
    add_child(_veil)

    var center := CenterContainer.new()
    center.set_anchors_preset(PRESET_FULL_RECT)
    add_child(center)

    _frame = PanelContainer.new()
    _frame.custom_minimum_size = Vector2(940, 660)
    center.add_child(_frame)

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 26)
    margin.add_theme_constant_override("margin_right", 26)
    margin.add_theme_constant_override("margin_top", 22)
    margin.add_theme_constant_override("margin_bottom", 20)
    _frame.add_child(margin)

    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 16)
    margin.add_child(root)

    root.add_child(_build_header())

    var body := HBoxContainer.new()
    body.add_theme_constant_override("separation", 18)
    body.size_flags_vertical = SIZE_EXPAND_FILL
    root.add_child(body)

    _tab_rail = VBoxContainer.new()
    _tab_rail.add_theme_constant_override("separation", 6)
    _tab_rail.custom_minimum_size = Vector2(184, 0)
    body.add_child(_tab_rail)
    _build_tab_rail()

    var well := PanelContainer.new()
    well.add_theme_stylebox_override("panel", NT.well_box())
    well.size_flags_horizontal = SIZE_EXPAND_FILL
    well.size_flags_vertical = SIZE_EXPAND_FILL
    body.add_child(well)

    _content_scroll = ScrollContainer.new()
    _content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _content_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
    _content_scroll.size_flags_vertical = SIZE_EXPAND_FILL
    well.add_child(_content_scroll)

    _content = VBoxContainer.new()
    _content.add_theme_constant_override("separation", 18)
    _content.size_flags_horizontal = SIZE_EXPAND_FILL
    _content_scroll.add_child(_content)

    root.add_child(_build_footer())


func _build_header() -> Control:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)

    var title := NT.title_label("SETTINGS")
    row.add_child(title)

    var tag := Label.new()
    tag.text = "PAUSED"
    tag.add_theme_color_override("font_color", NT.C_ACCENT)
    tag.add_theme_font_size_override("font_size", NT.size("hint"))
    tag.size_flags_vertical = SIZE_SHRINK_CENTER
    row.add_child(tag)

    var spacer := Control.new()
    spacer.size_flags_horizontal = SIZE_EXPAND_FILL
    row.add_child(spacer)

    var close_btn := Button.new()
    close_btn.text = "✕"
    close_btn.custom_minimum_size = Vector2(40, 0)
    close_btn.pressed.connect(close_menu)
    row.add_child(close_btn)
    return row


func _build_footer() -> Control:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)

    var restore := NebulaUi.button("↺ Restore Defaults", "ghost")
    restore.pressed.connect(_on_restore_defaults)
    row.add_child(restore)

    var spacer := Control.new()
    spacer.size_flags_horizontal = SIZE_EXPAND_FILL
    row.add_child(spacer)

    var back := NebulaUi.button("Back", "ghost")
    back.pressed.connect(close_menu)
    row.add_child(back)

    var apply := NebulaUi.button("Apply", "primary")
    apply.pressed.connect(close_menu)
    row.add_child(apply)
    return row


func _build_tab_rail() -> void:
    _tab_buttons.clear()
    for child in _tab_rail.get_children():
        child.queue_free()
    for tab_v in Catalog.tabs():
        var tab: Dictionary = tab_v
        var tab_id := str(tab.get("id", ""))
        var pc := PanelContainer.new()
        pc.add_theme_stylebox_override("panel", NT.card_box(tab_id == _active_tab))
        pc.mouse_filter = MOUSE_FILTER_STOP
        pc.mouse_default_cursor_shape = CURSOR_POINTING_HAND
        pc.gui_input.connect(_on_tab_clicked.bind(tab_id))
        var lbl := Label.new()
        lbl.text = str(tab.get("label", tab_id)).to_upper()
        lbl.add_theme_color_override("font_color", NT.C_TITLE if tab_id == _active_tab else NT.C_BODY)
        lbl.add_theme_font_size_override("font_size", NT.size("section"))
        if NT.font() != null:
            lbl.add_theme_font_override("font", NT.font())
        pc.add_child(lbl)
        _tab_rail.add_child(pc)
        _tab_buttons[tab_id] = pc


func _on_tab_clicked(event: InputEvent, tab_id: String) -> void:
    if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
        if tab_id == _active_tab:
            return
        _active_tab = tab_id
        _build_tab_rail()
        _rebuild_tab_content()


# --- Content (rows from catalog) -----------------------------------------------

func _rebuild_tab_content() -> void:
    for child in _content.get_children():
        child.queue_free()
    var tab := _find_tab(_active_tab)
    if tab.is_empty():
        return
    for group_v in (tab.get("groups", []) as Array):
        var group: Dictionary = group_v
        _content.add_child(NebulaUi.section_header(str(group.get("label", ""))))
        for setting_v in (group.get("settings", []) as Array):
            _content.add_child(_build_setting_row(setting_v as Dictionary))


func _find_tab(tab_id: String) -> Dictionary:
    for tab_v in Catalog.tabs():
        var tab: Dictionary = tab_v
        if str(tab.get("id", "")) == tab_id:
            return tab
    return {}


func _build_setting_row(setting: Dictionary) -> Control:
    var kind := str(setting.get("kind", ""))
    if kind == "keybinds_cta":
        return _build_keybinds_cta(setting)

    var control := _build_control(setting, kind)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)

    var label_col := VBoxContainer.new()
    label_col.add_theme_constant_override("separation", 0)
    label_col.custom_minimum_size = Vector2(300, 0)
    label_col.size_flags_vertical = SIZE_SHRINK_CENTER
    var lbl := Label.new()
    lbl.text = str(setting.get("label", ""))
    lbl.add_theme_color_override("font_color", NT.C_BODY)
    label_col.add_child(lbl)
    var sub := str(setting.get("hint", ""))
    if not bool(setting.get("wired", false)):
        sub = "PREVIEW — not yet wired" + ("  ·  " + sub if not sub.is_empty() else "")
    if not sub.is_empty():
        var hint := Label.new()
        hint.text = sub
        hint.add_theme_color_override("font_color", NT.C_DIM)
        hint.add_theme_font_size_override("font_size", NT.size("hint"))
        label_col.add_child(hint)
    row.add_child(label_col)

    control.size_flags_horizontal = SIZE_EXPAND_FILL
    control.size_flags_vertical = SIZE_SHRINK_CENTER
    if not bool(setting.get("wired", false)):
        control.modulate = Color(1, 1, 1, 0.7)
    row.add_child(control)
    return row


func _build_control(setting: Dictionary, kind: String) -> Control:
    match kind:
        "segmented":
            return _build_segmented(setting)
        "select":
            return _build_select(setting)
        "toggle":
            return _build_toggle(setting)
        "slider":
            return _build_slider(setting)
    var fallback := Label.new()
    fallback.text = "(unsupported: %s)" % kind
    fallback.add_theme_color_override("font_color", NT.C_ERROR)
    return fallback


func _options_for(setting: Dictionary) -> Array:
    if str(setting.get("source", "")) == "resolution":
        var out: Array = []
        for entry_v in SettingsManager.resolution_options():
            var entry: Dictionary = entry_v
            var sz: Vector2i = entry.get("size", Vector2i(1920, 1080))
            out.append({"label": str(entry.get("label", "")), "value": "%dx%d" % [sz.x, sz.y]})
        return out
    return setting.get("options", []) as Array


func _build_segmented(setting: Dictionary) -> Control:
    var section := str(setting.get("section", ""))
    var key := str(setting.get("key", ""))
    var current := str(get_value(setting))
    var hb := HBoxContainer.new()
    hb.add_theme_constant_override("separation", 6)
    hb.size_flags_horizontal = SIZE_EXPAND_FILL
    for opt_v in _options_for(setting):
        var opt: Dictionary = opt_v
        var val := str(opt.get("value", ""))
        var b := Button.new()
        b.text = str(opt.get("label", val))
        b.toggle_mode = false
        b.size_flags_horizontal = SIZE_EXPAND_FILL
        if val != current:
            b.self_modulate = NT.C_BORDER
        b.pressed.connect(func() -> void:
            SettingsManager.set_setting(section, key, val)
            _rebuild_tab_content())
        hb.add_child(b)
    return hb


func _build_select(setting: Dictionary) -> Control:
    var section := str(setting.get("section", ""))
    var key := str(setting.get("key", ""))
    var current := str(get_value(setting))
    var ob := OptionButton.new()
    var sel := -1
    var i := 0
    for opt_v in _options_for(setting):
        var opt: Dictionary = opt_v
        var val := str(opt.get("value", ""))
        ob.add_item(str(opt.get("label", val)))
        ob.set_item_metadata(i, val)
        if val == current:
            sel = i
        i += 1
    if sel >= 0:
        ob.select(sel)
    ob.item_selected.connect(func(idx: int) -> void:
        SettingsManager.set_setting(section, key, str(ob.get_item_metadata(idx))))
    return ob


func _build_toggle(setting: Dictionary) -> Control:
    var section := str(setting.get("section", ""))
    var key := str(setting.get("key", ""))
    var cb := CheckButton.new()
    cb.button_pressed = bool(get_value(setting))
    cb.size_flags_horizontal = SIZE_SHRINK_END
    cb.toggled.connect(func(on: bool) -> void:
        SettingsManager.set_setting(section, key, on))
    return cb


func _build_slider(setting: Dictionary) -> Control:
    var section := str(setting.get("section", ""))
    var key := str(setting.get("key", ""))
    var unit := str(setting.get("unit", ""))
    var hb := HBoxContainer.new()
    hb.add_theme_constant_override("separation", 10)
    var slider := HSlider.new()
    slider.min_value = float(setting.get("min", 0))
    slider.max_value = float(setting.get("max", 100))
    slider.step = float(setting.get("step", 1))
    slider.value = float(get_value(setting))
    slider.size_flags_horizontal = SIZE_EXPAND_FILL
    slider.size_flags_vertical = SIZE_SHRINK_CENTER
    var readout := Label.new()
    readout.custom_minimum_size = Vector2(60, 0)
    readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    readout.add_theme_color_override("font_color", NT.C_TITLE)
    readout.text = "%d%s" % [int(round(slider.value)), unit]
    slider.value_changed.connect(func(v: float) -> void:
        readout.text = "%d%s" % [int(round(v)), unit]
        SettingsManager.set_setting(section, key, v))
    hb.add_child(slider)
    hb.add_child(readout)
    return hb


func _build_keybinds_cta(setting: Dictionary) -> Control:
    var card := PanelContainer.new()
    card.add_theme_stylebox_override("panel", NT.card_box(true))
    card.mouse_filter = MOUSE_FILTER_STOP
    card.mouse_default_cursor_shape = CURSOR_POINTING_HAND
    card.gui_input.connect(func(e: InputEvent) -> void:
        if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
            edit_keybindings_requested.emit())
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 4)
    card.add_child(col)
    var t := Label.new()
    t.text = "⌨  " + str(setting.get("label", "Edit Keybindings"))
    t.add_theme_color_override("font_color", NT.C_TITLE)
    t.add_theme_font_size_override("font_size", NT.size("section"))
    col.add_child(t)
    var hint := str(setting.get("hint", ""))
    if not hint.is_empty():
        var h := Label.new()
        h.text = hint
        h.add_theme_color_override("font_color", NT.C_DIM)
        h.add_theme_font_size_override("font_size", NT.size("hint"))
        col.add_child(h)
    return card


func get_value(setting: Dictionary) -> Variant:
    return SettingsManager.get_setting(
        str(setting.get("section", "")), str(setting.get("key", "")), setting.get("default", null))


func _on_restore_defaults() -> void:
    SettingsManager.reset_all_settings()
    _rebuild_tab_content()
