extends Control

const LegacyLootEditor = preload("res://Space/scripts/editor/loot_editor.gd")

signal closed

var _legacy: Control = null


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_STOP
    visible = false
    set_anchors_preset(PRESET_FULL_RECT)
    _build_ui()


func open_editor(_pack_id: String = "") -> void:
    visible = true
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)
    if _legacy != null:
        _legacy.refresh()
    grab_focus()


func request_close() -> void:
    visible = false
    closed.emit()


func _input(event: InputEvent) -> void:
    if not visible:
        return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled()
        request_close()


func _build_ui() -> void:
    var root := VBoxContainer.new()
    root.set_anchors_preset(PRESET_FULL_RECT)
    root.offset_left = 18.0
    root.offset_top = 18.0
    root.offset_right = -18.0
    root.offset_bottom = -18.0
    add_child(root)

    var header := HBoxContainer.new()
    root.add_child(header)

    var back_btn := Button.new()
    back_btn.text = "Back"
    back_btn.pressed.connect(request_close)
    header.add_child(back_btn)

    var title := Label.new()
    title.text = "Loot And Shop Stock"
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_theme_font_size_override("font_size", 20)
    header.add_child(title)

    var note := Label.new()
    note.text = "Controls module drops by threat tier and system vendor stock."
    note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    note.add_theme_font_size_override("font_size", 12)
    note.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
    header.add_child(note)

    var panel := PanelContainer.new()
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(panel)

    _legacy = Control.new()
    _legacy.set_script(LegacyLootEditor)
    _legacy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _legacy.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel.add_child(_legacy)
