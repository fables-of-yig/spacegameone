extends Control

const InputSetup := preload("res://Space/scripts/autoload/input_setup.gd")

signal closed

var _dim: ColorRect = null
var _frame: PanelContainer = null
var _title_label: Label = null
var _tabs: TabContainer = null
var _controls_tabs: TabContainer = null
var _section_lists: Dictionary = {}

var _music_slider: HSlider = null
var _music_value: Label = null
var _sfx_slider: HSlider = null
var _sfx_value: Label = null
var _voice_slider: HSlider = null
var _voice_value: Label = null

var _window_mode_option: OptionButton = null
var _resolution_option: OptionButton = null
var _video_note: Label = null

var _capture_overlay: ColorRect = null
var _capture_label: Label = null

var _host_context: String = "main_menu"
var _capture_action: String = ""
var _capture_device_group: String = ""
var _capture_slot_index: int = -1
var _capture_arm_time_ms: int = 0


func _ready() -> void:
    visible = false
    mouse_filter = MOUSE_FILTER_STOP
    process_mode = Node.PROCESS_MODE_ALWAYS
    _sync_host_rect()
    _build_ui()
    _connect_manager_signals()
    _refresh_all()


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _sync_host_rect()
        _layout_frame()


func open_menu(host_context: String = "main_menu") -> void:
    _host_context = host_context
    _sync_host_rect()
    visible = true
    _cancel_capture()
    _refresh_all()
    _layout_frame()
    call_deferred("_refresh_open_layout")


func close_menu() -> void:
    _cancel_capture()
    visible = false
    closed.emit()


func is_open() -> bool:
    return visible


func _input(event: InputEvent) -> void:
    if not visible:
        return
    if _capture_active():
        get_viewport().set_input_as_handled()
        _handle_capture_input(event)
        return
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled()
        close_menu()
        return
    if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
        get_viewport().set_input_as_handled()
        close_menu()
        return


func _build_ui() -> void:
    _dim = ColorRect.new()
    _dim.color = Color(0.02, 0.03, 0.06, 0.84)
    _dim.set_anchors_preset(PRESET_FULL_RECT)
    add_child(_dim)

    _frame = PanelContainer.new()
    _frame.focus_mode = FOCUS_ALL
    _frame.add_theme_stylebox_override("panel", _make_panel_style())
    add_child(_frame)

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 18)
    margin.add_theme_constant_override("margin_right", 18)
    margin.add_theme_constant_override("margin_top", 16)
    margin.add_theme_constant_override("margin_bottom", 14)
    _frame.add_child(margin)

    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 10)
    margin.add_child(root)

    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 12)
    root.add_child(header)

    _title_label = Label.new()
    _title_label.text = "SETTINGS"
    _title_label.add_theme_font_size_override("font_size", 24)
    _title_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.42))
    header.add_child(_title_label)

    var subtitle := Label.new()
    subtitle.text = "Gameplay, audio, and display settings. Changes apply immediately."
    subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    subtitle.add_theme_font_size_override("font_size", 13)
    subtitle.add_theme_color_override("font_color", Color(0.72, 0.78, 0.88))
    header.add_child(subtitle)

    var close_header_btn := Button.new()
    close_header_btn.text = "CLOSE"
    close_header_btn.pressed.connect(close_menu)
    header.add_child(close_header_btn)

    _tabs = TabContainer.new()
    _tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _tabs.add_theme_color_override("font_selected_color", Color(0.98, 0.96, 0.65))
    _tabs.add_theme_color_override("font_unselected_color", Color(0.74, 0.8, 0.9))
    root.add_child(_tabs)

    _build_gameplay_tab()
    _build_audio_tab()
    _build_video_tab()

    var footer := HBoxContainer.new()
    footer.add_theme_constant_override("separation", 10)
    root.add_child(footer)

    var footer_hint := Label.new()
    footer_hint.text = "Use Esc / B to close. Rebinding waits for the next pressed key, mouse button, or pad input."
    footer_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    footer_hint.add_theme_font_size_override("font_size", 12)
    footer_hint.add_theme_color_override("font_color", Color(0.56, 0.64, 0.74))
    footer.add_child(footer_hint)

    var reset_all_btn := Button.new()
    reset_all_btn.text = "RESTORE ALL DEFAULTS"
    reset_all_btn.tooltip_text = "Reset audio, video, and every control bind back to the shipped defaults."
    reset_all_btn.pressed.connect(_on_restore_all_pressed)
    footer.add_child(reset_all_btn)

    _capture_overlay = ColorRect.new()
    _capture_overlay.color = Color(0.01, 0.02, 0.04, 0.92)
    _capture_overlay.visible = false
    _capture_overlay.set_anchors_preset(PRESET_FULL_RECT)
    add_child(_capture_overlay)

    var capture_center := CenterContainer.new()
    capture_center.set_anchors_preset(PRESET_FULL_RECT)
    _capture_overlay.add_child(capture_center)

    var capture_panel := PanelContainer.new()
    capture_panel.custom_minimum_size = Vector2(640, 180)
    capture_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.11, 0.18, 0.98), Color(0.45, 0.7, 1.0, 0.9)))
    capture_center.add_child(capture_panel)

    var capture_margin := MarginContainer.new()
    capture_margin.add_theme_constant_override("margin_left", 22)
    capture_margin.add_theme_constant_override("margin_right", 22)
    capture_margin.add_theme_constant_override("margin_top", 22)
    capture_margin.add_theme_constant_override("margin_bottom", 22)
    capture_panel.add_child(capture_margin)

    _capture_label = Label.new()
    _capture_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _capture_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _capture_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _capture_label.add_theme_font_size_override("font_size", 20)
    _capture_label.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
    capture_margin.add_child(_capture_label)

    _layout_frame()


func _sync_host_rect() -> void:
    if not is_inside_tree():
        return
    var viewport_size := get_viewport_rect().size
    var parent_control := get_parent() as Control
    if parent_control != null:
        set_anchors_preset(PRESET_TOP_LEFT)
        position = Vector2.ZERO
        size = parent_control.size
        if size.x < 1.0 or size.y < 1.0:
            size = viewport_size
        return
    set_anchors_preset(PRESET_TOP_LEFT)
    position = Vector2.ZERO
    size = viewport_size


func _refresh_open_layout() -> void:
    if not visible:
        return
    _sync_host_rect()
    _layout_frame()


func _build_gameplay_tab() -> void:
    var gameplay := VBoxContainer.new()
    gameplay.name = "Gameplay"
    gameplay.add_theme_constant_override("separation", 10)
    _tabs.add_child(gameplay)

    var top_row := HBoxContainer.new()
    top_row.add_theme_constant_override("separation", 8)
    gameplay.add_child(top_row)

    var intro := Label.new()
    intro.text = "Space, planetary, MV, and shared menu controls live here. Each slot can be rebound or cleared independently."
    intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    intro.add_theme_font_size_override("font_size", 13)
    intro.add_theme_color_override("font_color", Color(0.76, 0.82, 0.9))
    top_row.add_child(intro)

    var reset_controls_btn := Button.new()
    reset_controls_btn.text = "RESET CONTROLS"
    reset_controls_btn.tooltip_text = "Restore every gameplay and menu binding back to its default."
    reset_controls_btn.pressed.connect(_on_reset_controls_pressed)
    top_row.add_child(reset_controls_btn)

    _controls_tabs = TabContainer.new()
    _controls_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    gameplay.add_child(_controls_tabs)

    for section_v in InputSetup.control_sections():
        var section: Dictionary = section_v
        var scroll := ScrollContainer.new()
        scroll.name = str(section.get("label", "Controls"))
        scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
        _controls_tabs.add_child(scroll)

        var content := VBoxContainer.new()
        content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        content.add_theme_constant_override("separation", 8)
        scroll.add_child(content)
        _section_lists[str(section.get("id", ""))] = content


func _build_audio_tab() -> void:
    var audio := VBoxContainer.new()
    audio.name = "Audio"
    audio.add_theme_constant_override("separation", 14)
    _tabs.add_child(audio)

    var intro := Label.new()
    intro.text = "Control music, sound effects, and voice separately."
    intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    intro.add_theme_font_size_override("font_size", 13)
    intro.add_theme_color_override("font_color", Color(0.76, 0.82, 0.9))
    audio.add_child(intro)

    _music_slider = _build_audio_row(audio, "Music", "_on_music_volume_changed")
    _music_value = _music_slider.get_meta("value_label")
    _sfx_slider = _build_audio_row(audio, "SFX", "_on_sfx_volume_changed")
    _sfx_value = _sfx_slider.get_meta("value_label")
    _voice_slider = _build_audio_row(audio, "Voice", "_on_voice_volume_changed")
    _voice_value = _voice_slider.get_meta("value_label")

    var reset_audio_btn := Button.new()
    reset_audio_btn.text = "RESET AUDIO"
    reset_audio_btn.pressed.connect(_on_reset_audio_pressed)
    audio.add_child(reset_audio_btn)


func _build_video_tab() -> void:
    var video := VBoxContainer.new()
    video.name = "Video"
    video.add_theme_constant_override("separation", 14)
    _tabs.add_child(video)

    var intro := Label.new()
    intro.text = "Switch between windowed and fullscreen modes, then pick a windowed resolution that fits the player's display."
    intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    intro.add_theme_font_size_override("font_size", 13)
    intro.add_theme_color_override("font_color", Color(0.76, 0.82, 0.9))
    video.add_child(intro)

    _window_mode_option = _build_option_row(video, "Window Mode")
    _window_mode_option.item_selected.connect(_on_window_mode_selected)
    _window_mode_option.add_item("Windowed")
    _window_mode_option.add_item("Borderless Fullscreen")
    _window_mode_option.add_item("Exclusive Fullscreen")

    _resolution_option = _build_option_row(video, "Resolution")
    _resolution_option.item_selected.connect(_on_resolution_selected)

    _video_note = Label.new()
    _video_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _video_note.add_theme_font_size_override("font_size", 12)
    _video_note.add_theme_color_override("font_color", Color(0.62, 0.7, 0.8))
    video.add_child(_video_note)

    var reset_video_btn := Button.new()
    reset_video_btn.text = "RESET VIDEO"
    reset_video_btn.pressed.connect(_on_reset_video_pressed)
    video.add_child(reset_video_btn)


func _build_audio_row(parent: VBoxContainer, label_text: String, callback_name: String) -> HSlider:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    parent.add_child(row)

    var label := Label.new()
    label.text = label_text
    label.custom_minimum_size = Vector2(140, 0)
    label.add_theme_font_size_override("font_size", 15)
    label.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0))
    row.add_child(label)

    var slider := HSlider.new()
    slider.min_value = 0.0
    slider.max_value = 1.0
    slider.step = 0.01
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.value_changed.connect(Callable(self, callback_name))
    row.add_child(slider)

    var value_label := Label.new()
    value_label.custom_minimum_size = Vector2(64, 0)
    value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    value_label.add_theme_font_size_override("font_size", 13)
    value_label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.94))
    row.add_child(value_label)
    slider.set_meta("value_label", value_label)
    return slider


func _build_option_row(parent: VBoxContainer, label_text: String) -> OptionButton:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    parent.add_child(row)

    var label := Label.new()
    label.text = label_text
    label.custom_minimum_size = Vector2(160, 0)
    label.add_theme_font_size_override("font_size", 15)
    label.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0))
    row.add_child(label)

    var option := OptionButton.new()
    option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(option)
    return option


func _connect_manager_signals() -> void:
    if not has_node("/root/SettingsManager"):
        return
    SettingsManager.audio_settings_changed.connect(_refresh_audio_tab)
    SettingsManager.video_settings_changed.connect(_refresh_video_tab)
    SettingsManager.input_settings_changed.connect(_rebuild_controls_tab)


func _layout_frame() -> void:
    if _frame == null:
        return
    var edge_margin := 24.0
    var max_w := maxf(size.x - edge_margin * 2.0, 640.0)
    var max_h := maxf(size.y - edge_margin * 2.0, 420.0)
    var target_w := minf(clampf(size.x * 0.86, 980.0, 1400.0), max_w)
    var target_h := minf(clampf(size.y * 0.84, 560.0, 900.0), max_h)
    _frame.size = Vector2(target_w, target_h)
    _frame.position = Vector2((size.x - target_w) * 0.5, (size.y - target_h) * 0.5)


func _refresh_all() -> void:
    _title_label.text = "SETTINGS  [%s]" % ("MAIN MENU" if _host_context == "main_menu" else "PAUSE")
    _refresh_audio_tab()
    _refresh_video_tab()
    _rebuild_controls_tab()


func _refresh_audio_tab() -> void:
    if not has_node("/root/SettingsManager"):
        return
    var audio := SettingsManager.get_audio_settings()
    _set_slider_without_signal(_music_slider, float(audio.get("music", 0.8)))
    _set_slider_without_signal(_sfx_slider, float(audio.get("sfx", 0.8)))
    _set_slider_without_signal(_voice_slider, float(audio.get("voice", 0.8)))
    _music_value.text = _percent_text(_music_slider.value)
    _sfx_value.text = _percent_text(_sfx_slider.value)
    _voice_value.text = _percent_text(_voice_slider.value)


func _refresh_video_tab() -> void:
    if not has_node("/root/SettingsManager"):
        return
    var mode := SettingsManager.current_window_mode()
    match mode:
        SettingsManager.WINDOW_MODE_WINDOWED:
            _window_mode_option.select(0)
        SettingsManager.WINDOW_MODE_EXCLUSIVE:
            _window_mode_option.select(2)
        _:
            _window_mode_option.select(1)

    _resolution_option.clear()
    var options := SettingsManager.resolution_options()
    var current := SettingsManager.current_resolution()
    var selected := -1
    for i in range(options.size()):
        var entry: Dictionary = options[i]
        var label := str(entry.get("label", ""))
        var res: Vector2i = entry.get("size", Vector2i(1280, 720))
        _resolution_option.add_item(label)
        _resolution_option.set_item_metadata(i, res)
        if res == current:
            selected = i
    if selected >= 0:
        _resolution_option.select(selected)
    elif _resolution_option.get_item_count() > 0:
        _resolution_option.select(0)

    var is_windowed := mode == SettingsManager.WINDOW_MODE_WINDOWED
    _resolution_option.disabled = not is_windowed
    _video_note.text = "Windowed mode uses the selected resolution. Fullscreen modes use the monitor size and ignore the windowed-size picker." if not is_windowed else "Windowed mode is active. The selected resolution is applied immediately."


func _rebuild_controls_tab() -> void:
    for section_v in InputSetup.control_sections():
        var section: Dictionary = section_v
        var section_id := str(section.get("id", ""))
        var list: VBoxContainer = _section_lists.get(section_id)
        if list == null:
            continue
        _clear_container(list)

        var desc := Label.new()
        desc.text = str(section.get("description", ""))
        desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        desc.add_theme_font_size_override("font_size", 12)
        desc.add_theme_color_override("font_color", Color(0.64, 0.72, 0.82))
        list.add_child(desc)

        list.add_child(_build_controls_header())

        for action_v in (section.get("actions", []) as Array):
            var action := str(action_v)
            list.add_child(_build_action_row(action))


func _build_controls_header() -> Control:
    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 8)

    var action_lbl := Label.new()
    action_lbl.text = "Action"
    action_lbl.custom_minimum_size = Vector2(250, 0)
    action_lbl.add_theme_font_size_override("font_size", 13)
    action_lbl.add_theme_color_override("font_color", Color(0.96, 0.95, 0.68))
    header.add_child(action_lbl)

    for title in ["KB/M 1", "KB/M 2", "Pad 1", "Pad 2", "Reset"]:
        var lbl := Label.new()
        lbl.text = title
        lbl.custom_minimum_size = Vector2(135 if title != "Action" else 96, 0)
        lbl.add_theme_font_size_override("font_size", 13)
        lbl.add_theme_color_override("font_color", Color(0.96, 0.95, 0.68))
        header.add_child(lbl)
    return header


func _build_action_row(action: String) -> Control:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)

    var action_lbl := Label.new()
    action_lbl.text = InputSetup.action_label(action)
    action_lbl.tooltip_text = action
    action_lbl.custom_minimum_size = Vector2(250, 0)
    action_lbl.add_theme_font_size_override("font_size", 14)
    action_lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
    row.add_child(action_lbl)

    var split := InputSetup.action_bindings_by_device(action)
    var kbm: Array = split.get(InputSetup.DEVICE_KBM, [])
    var controller: Array = split.get(InputSetup.DEVICE_CONTROLLER, [])

    row.add_child(_build_binding_slot_button(action, InputSetup.DEVICE_KBM, 0, kbm))
    row.add_child(_build_binding_slot_button(action, InputSetup.DEVICE_KBM, 1, kbm))
    row.add_child(_build_binding_slot_button(action, InputSetup.DEVICE_CONTROLLER, 0, controller))
    row.add_child(_build_binding_slot_button(action, InputSetup.DEVICE_CONTROLLER, 1, controller))

    var reset_btn := Button.new()
    reset_btn.text = "RESET"
    reset_btn.custom_minimum_size = Vector2(96, 0)
    reset_btn.tooltip_text = "Restore this action to its default binds."
    reset_btn.pressed.connect(_on_reset_action_pressed.bind(action))
    row.add_child(reset_btn)

    return row


func _build_binding_slot_button(action: String, device_group: String, slot_index: int, bindings: Array) -> Control:
    var btn := MenuButton.new()
    btn.custom_minimum_size = Vector2(135, 0)
    if slot_index < bindings.size():
        btn.text = InputSetup.format_binding_spec(bindings[slot_index])
    else:
        btn.text = "Unbound"
    btn.tooltip_text = "Choose Rebind to capture a new input, or Clear to empty this slot."
    var popup := btn.get_popup()
    popup.add_item("Rebind", 0)
    popup.add_item("Clear", 1)
    popup.id_pressed.connect(_on_binding_popup_selected.bind(action, device_group, slot_index))
    return btn


func _capture_active() -> bool:
    return not _capture_action.is_empty() and _capture_slot_index >= 0


func _handle_capture_input(event: InputEvent) -> void:
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
        return
    SettingsManager.set_input_binding_slot(_capture_action, _capture_device_group, _capture_slot_index, spec)
    _cancel_capture()


func _cancel_capture() -> void:
    _capture_action = ""
    _capture_device_group = ""
    _capture_slot_index = -1
    _capture_overlay.visible = false


func _begin_capture(action: String, device_group: String, slot_index: int) -> void:
    _capture_action = action
    _capture_device_group = device_group
    _capture_slot_index = slot_index
    _capture_arm_time_ms = Time.get_ticks_msec() + 160
    _capture_label.text = "Press the new %s input for:\n%s\n\nEsc cancels capture." % [
        "controller" if device_group == InputSetup.DEVICE_CONTROLLER else "keyboard / mouse",
        InputSetup.action_label(action),
    ]
    _capture_overlay.visible = true


func _on_binding_popup_selected(id: int, action: String, device_group: String, slot_index: int) -> void:
    match id:
        0:
            _begin_capture(action, device_group, slot_index)
        1:
            SettingsManager.clear_input_binding_slot(action, device_group, slot_index)


func _on_reset_action_pressed(action: String) -> void:
    SettingsManager.reset_input_action(action)


func _on_reset_controls_pressed() -> void:
    SettingsManager.reset_input_settings()


func _on_restore_all_pressed() -> void:
    SettingsManager.reset_all_settings()


func _on_reset_audio_pressed() -> void:
    SettingsManager.reset_audio_settings()


func _on_reset_video_pressed() -> void:
    SettingsManager.reset_video_settings()


func _on_music_volume_changed(value: float) -> void:
    if not visible:
        return
    SettingsManager.set_audio_volume("music", value)
    _music_value.text = _percent_text(value)


func _on_sfx_volume_changed(value: float) -> void:
    if not visible:
        return
    SettingsManager.set_audio_volume("sfx", value)
    _sfx_value.text = _percent_text(value)


func _on_voice_volume_changed(value: float) -> void:
    if not visible:
        return
    SettingsManager.set_audio_volume("voice", value)
    _voice_value.text = _percent_text(value)


func _on_window_mode_selected(index: int) -> void:
    match index:
        0:
            SettingsManager.set_window_mode(SettingsManager.WINDOW_MODE_WINDOWED)
        2:
            SettingsManager.set_window_mode(SettingsManager.WINDOW_MODE_EXCLUSIVE)
        _:
            SettingsManager.set_window_mode(SettingsManager.WINDOW_MODE_FULLSCREEN)


func _on_resolution_selected(index: int) -> void:
    if index < 0:
        return
    var res_v: Variant = _resolution_option.get_item_metadata(index)
    if typeof(res_v) == TYPE_VECTOR2I:
        SettingsManager.set_resolution(res_v)


func _set_slider_without_signal(slider: HSlider, value: float) -> void:
    if slider == null:
        return
    slider.set_block_signals(true)
    slider.value = value
    slider.set_block_signals(false)


func _percent_text(value: float) -> String:
    return "%d%%" % int(round(value * 100.0))


func _clear_container(container: Node) -> void:
    for child in container.get_children():
        child.queue_free()


func _make_panel_style(bg: Color = Color(0.05, 0.07, 0.12, 0.98), border: Color = Color(0.31, 0.47, 0.75, 0.9)) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = bg
    style.border_color = border
    style.border_width_left = 2
    style.border_width_top = 2
    style.border_width_right = 2
    style.border_width_bottom = 2
    style.corner_radius_top_left = 8
    style.corner_radius_top_right = 8
    style.corner_radius_bottom_left = 8
    style.corner_radius_bottom_right = 8
    style.shadow_color = Color(0.0, 0.0, 0.0, 0.3)
    style.shadow_size = 8
    return style
