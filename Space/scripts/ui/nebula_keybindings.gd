extends Control

# Nebula-skinned Keybindings rebinder. Category tabs come from the REAL action
# catalog (InputSetup.control_sections — Space / Planetary / MV / Menus), and the
# capture/persist flow reuses InputSetup + SettingsManager exactly like the legacy
# settings_menu.gd did. Rebinds write through SettingsManager.set_input_binding_slot
# so overrides land in user://settings.json and InputMap immediately.
#
# Input is OWNED by NebulaPause, which forwards capture key presses to feed_capture
# while is_capturing() is true and pops this overlay on Back. This overlay never
# calls set_input_as_handled itself.

const NT := preload("res://MV/scripts/console/nebula_theme.gd")

signal closed

var _active_section: String = ""
var _veil: ColorRect = null
var _list: VBoxContainer = null
var _tab_rail: HBoxContainer = null
var _capture_overlay: PanelContainer = null
var _capture_label: Label = null

var _capture_action: String = ""
var _capture_device_group: String = ""
var _capture_slot_index: int = -1
var _capture_arm_time_ms: int = 0


func _ready() -> void:
    visible = false
    set_anchors_preset(PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_STOP
    var sections := InputSetup.control_sections()
    if not sections.is_empty():
        _active_section = str((sections[0] as Dictionary).get("id", ""))
    _build_ui()


func open_menu() -> void:
    theme = NT.theme()
    set_anchors_preset(PRESET_FULL_RECT)
    visible = true
    _cancel_capture()
    _rebuild_list()


func close_menu() -> void:
    _cancel_capture()
    visible = false
    closed.emit()


func is_open() -> bool:
    return visible


func is_capturing() -> bool:
    return not _capture_action.is_empty() and _capture_slot_index >= 0


# --- UI ------------------------------------------------------------------------

func _build_ui() -> void:
    theme = NT.theme()

    _veil = ColorRect.new()
    _veil.color = Color(4.0 / 255.0, 7.0 / 255.0, 12.0 / 255.0, 0.7)
    _veil.set_anchors_preset(PRESET_FULL_RECT)
    _veil.mouse_filter = MOUSE_FILTER_STOP
    add_child(_veil)

    var center := CenterContainer.new()
    center.set_anchors_preset(PRESET_FULL_RECT)
    add_child(center)

    var frame := PanelContainer.new()
    frame.custom_minimum_size = Vector2(680, 560)
    center.add_child(frame)

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 24)
    margin.add_theme_constant_override("margin_right", 24)
    margin.add_theme_constant_override("margin_top", 20)
    margin.add_theme_constant_override("margin_bottom", 18)
    frame.add_child(margin)

    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 14)
    margin.add_child(root)

    # Header.
    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 12)
    header.add_child(NT.title_label("KEYBINDINGS"))
    var spacer := Control.new()
    spacer.size_flags_horizontal = SIZE_EXPAND_FILL
    header.add_child(spacer)
    var close_btn := Button.new()
    close_btn.text = "✕"
    close_btn.custom_minimum_size = Vector2(40, 0)
    close_btn.pressed.connect(close_menu)
    header.add_child(close_btn)
    root.add_child(header)

    # Category tabs.
    _tab_rail = HBoxContainer.new()
    _tab_rail.add_theme_constant_override("separation", 6)
    root.add_child(_tab_rail)
    _build_tabs()

    # Scrolling action list.
    var well := PanelContainer.new()
    well.add_theme_stylebox_override("panel", NT.well_box())
    well.size_flags_vertical = SIZE_EXPAND_FILL
    root.add_child(well)
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_horizontal = SIZE_EXPAND_FILL
    scroll.size_flags_vertical = SIZE_EXPAND_FILL
    well.add_child(scroll)
    _list = VBoxContainer.new()
    _list.add_theme_constant_override("separation", 4)
    _list.size_flags_horizontal = SIZE_EXPAND_FILL
    scroll.add_child(_list)

    # Footer.
    var footer := HBoxContainer.new()
    footer.add_theme_constant_override("separation", 10)
    var reset := NebulaUi.button("↺ Reset to defaults", "ghost")
    reset.pressed.connect(_on_reset_all)
    footer.add_child(reset)
    var fspacer := Control.new()
    fspacer.size_flags_horizontal = SIZE_EXPAND_FILL
    footer.add_child(fspacer)
    var done := NebulaUi.button("Done", "primary")
    done.pressed.connect(close_menu)
    footer.add_child(done)
    root.add_child(footer)

    # Capture overlay (hidden until a chip is clicked).
    _capture_overlay = PanelContainer.new()
    _capture_overlay.add_theme_stylebox_override("panel", NT.card_box(true))
    _capture_overlay.visible = false
    _capture_overlay.set_anchors_preset(PRESET_CENTER)
    _capture_overlay.custom_minimum_size = Vector2(420, 120)
    add_child(_capture_overlay)
    _capture_label = Label.new()
    _capture_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _capture_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _capture_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _capture_label.add_theme_color_override("font_color", NT.C_TITLE)
    _capture_overlay.add_child(_capture_label)


func _build_tabs() -> void:
    for child in _tab_rail.get_children():
        child.queue_free()
    for section_v in InputSetup.control_sections():
        var section: Dictionary = section_v
        var sid := str(section.get("id", ""))
        var b := Button.new()
        b.text = str(section.get("label", sid)).to_upper()
        if sid != _active_section:
            b.self_modulate = NT.C_BORDER
        b.pressed.connect(func() -> void:
            if sid == _active_section:
                return
            _active_section = sid
            _build_tabs()
            _rebuild_list())
        _tab_rail.add_child(b)


func _rebuild_list() -> void:
    for child in _list.get_children():
        child.queue_free()
    var section := _find_section(_active_section)
    if section.is_empty():
        return
    var desc := str(section.get("description", ""))
    if not desc.is_empty():
        var d := Label.new()
        d.text = desc
        d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        d.add_theme_color_override("font_color", NT.C_DIM)
        d.add_theme_font_size_override("font_size", NT.size("hint"))
        _list.add_child(d)
    for action_v in (section.get("actions", []) as Array):
        _list.add_child(_build_action_row(str(action_v)))


func _find_section(sid: String) -> Dictionary:
    for section_v in InputSetup.control_sections():
        var section: Dictionary = section_v
        if str(section.get("id", "")) == sid:
            return section
    return {}


func _build_action_row(action: String) -> Control:
    var card := PanelContainer.new()
    card.add_theme_stylebox_override("panel", NT.card_box(false))
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    card.add_child(row)

    var name_lbl := Label.new()
    name_lbl.text = InputSetup.action_label(action)
    name_lbl.tooltip_text = action
    name_lbl.custom_minimum_size = Vector2(220, 0)
    name_lbl.size_flags_vertical = SIZE_SHRINK_CENTER
    name_lbl.add_theme_color_override("font_color", NT.C_BODY)
    row.add_child(name_lbl)

    var split := InputSetup.action_bindings_by_device(action)
    var kbm: Array = split.get(InputSetup.DEVICE_KBM, [])
    var pad: Array = split.get(InputSetup.DEVICE_CONTROLLER, [])
    row.add_child(_chip(action, InputSetup.DEVICE_KBM, 0, kbm))
    row.add_child(_chip(action, InputSetup.DEVICE_KBM, 1, kbm))
    row.add_child(_chip(action, InputSetup.DEVICE_CONTROLLER, 0, pad))
    row.add_child(_chip(action, InputSetup.DEVICE_CONTROLLER, 1, pad))

    var reset := Button.new()
    reset.text = "↺"
    reset.tooltip_text = "Reset this action to defaults."
    reset.custom_minimum_size = Vector2(40, 0)
    reset.self_modulate = NT.C_BORDER
    reset.pressed.connect(func() -> void:
        SettingsManager.reset_input_action(action)
        _rebuild_list())
    row.add_child(reset)
    return card


func _chip(action: String, device_group: String, slot_index: int, bindings: Array) -> Control:
    var b := Button.new()
    b.custom_minimum_size = Vector2(120, 0)
    b.size_flags_horizontal = SIZE_EXPAND_FILL
    if slot_index < bindings.size():
        b.text = InputSetup.format_binding_spec(bindings[slot_index])
    else:
        b.text = "—"
        b.self_modulate = NT.C_BORDER
    b.tooltip_text = "Click to rebind. Right-click to clear."
    b.pressed.connect(_begin_capture.bind(action, device_group, slot_index))
    b.gui_input.connect(func(e: InputEvent) -> void:
        if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
            SettingsManager.clear_input_binding_slot(action, device_group, slot_index)
            _rebuild_list())
    return b


# --- Capture (driven by NebulaPause via feed_capture) --------------------------

func _begin_capture(action: String, device_group: String, slot_index: int) -> void:
    _capture_action = action
    _capture_device_group = device_group
    _capture_slot_index = slot_index
    _capture_arm_time_ms = Time.get_ticks_msec() + 160
    _capture_label.text = "Press a key…\n%s  (%s)\n\nEsc cancels." % [
        InputSetup.action_label(action),
        "controller" if device_group == InputSetup.DEVICE_CONTROLLER else "keyboard / mouse",
    ]
    _capture_overlay.visible = true


func feed_capture(event: InputEvent) -> void:
    if not is_capturing():
        return
    if Time.get_ticks_msec() < _capture_arm_time_ms:
        return
    var wants_controller := _capture_device_group == InputSetup.DEVICE_CONTROLLER
    if event is InputEventKey:
        if wants_controller:
            return
        var key_event: InputEventKey = event
        if not key_event.pressed or key_event.echo:
            return
        if key_event.keycode == KEY_ESCAPE:
            _cancel_capture()
            return
        _finish_capture(InputSetup.make_event_spec(key_event))
        return
    if event is InputEventMouseButton:
        if wants_controller:
            return
        var mouse_event: InputEventMouseButton = event
        if not mouse_event.pressed:
            return
        if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            return
        _finish_capture(InputSetup.make_event_spec(mouse_event))
        return
    if event is InputEventJoypadButton:
        if not wants_controller:
            return
        var joy_button: InputEventJoypadButton = event
        if not joy_button.pressed:
            return
        _finish_capture(InputSetup.make_event_spec(joy_button))
        return
    if event is InputEventJoypadMotion:
        if not wants_controller:
            return
        var joy_axis: InputEventJoypadMotion = event
        if absf(joy_axis.axis_value) < 0.6:
            return
        _finish_capture(InputSetup.make_event_spec(joy_axis))


func _finish_capture(spec: Dictionary) -> void:
    if spec.is_empty():
        _cancel_capture()
        return
    SettingsManager.set_input_binding_slot(_capture_action, _capture_device_group, _capture_slot_index, spec)
    _cancel_capture()
    _rebuild_list()


func _cancel_capture() -> void:
    _capture_action = ""
    _capture_device_group = ""
    _capture_slot_index = -1
    if _capture_overlay != null:
        _capture_overlay.visible = false


func _on_reset_all() -> void:
    _cancel_capture()
    SettingsManager.reset_input_settings()
    _rebuild_list()
