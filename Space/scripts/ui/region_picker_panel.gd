extends Control

# Modal-ish overlay shown after the player presses the Land action near a
# landable POI. Lists the POI's authored regions (planet_data.regions[]),
# lets the player pick one with arrow keys / mouse, and emits region_chosen
# with the selected entry so Space main can call PlanetaryInterface.begin_landing.
#
# Owned by main.gd, mounted on its own CanvasLayer by UICoordinator. The panel
# never calls begin_landing itself — host wiring lives in main.gd so the
# follow-up scene change stays co-located with _on_launch_requested.

signal region_chosen(pack_id: String, poi_id: String, region: Dictionary)
signal cancelled()

const PANEL_MIN_WIDTH: float = 360.0
const PANEL_MAX_WIDTH: float = 520.0

var _pack_id: String = ""
var _poi_id: String = ""
var _poi_name: String = ""
var _regions: Array = []

var _panel: PanelContainer = null
var _title_label: Label = null
var _empty_label: Label = null
var _list: ItemList = null
var _footer_label: Label = null
var _confirm_button: Button = null


func _ready() -> void:
    visible = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    mouse_filter = Control.MOUSE_FILTER_STOP
    set_anchors_preset(PRESET_FULL_RECT)

    var dim := ColorRect.new()
    dim.color = Color(0.0, 0.0, 0.0, 0.55)
    dim.set_anchors_preset(PRESET_FULL_RECT)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(dim)

    var center := CenterContainer.new()
    center.set_anchors_preset(PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(center)

    _panel = PanelContainer.new()
    _panel.custom_minimum_size = Vector2(PANEL_MIN_WIDTH, 0)
    _panel.add_theme_stylebox_override("panel", _make_panel_stylebox())
    center.add_child(_panel)

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 18)
    margin.add_theme_constant_override("margin_right", 18)
    margin.add_theme_constant_override("margin_top", 14)
    margin.add_theme_constant_override("margin_bottom", 14)
    _panel.add_child(margin)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 8)
    margin.add_child(vbox)

    _title_label = Label.new()
    _title_label.text = "Select Landing Region"
    _title_label.add_theme_font_size_override("font_size", 18)
    _title_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
    vbox.add_child(_title_label)

    _empty_label = Label.new()
    _empty_label.text = "No landable regions"
    _empty_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
    _empty_label.visible = false
    vbox.add_child(_empty_label)

    _list = ItemList.new()
    _list.custom_minimum_size = Vector2(0, 180)
    _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _list.allow_reselect = true
    _list.auto_height = false
    _list.item_activated.connect(_on_item_activated)
    _list.item_selected.connect(_on_item_selected)
    vbox.add_child(_list)

    var button_row := HBoxContainer.new()
    button_row.alignment = BoxContainer.ALIGNMENT_END
    button_row.add_theme_constant_override("separation", 8)
    vbox.add_child(button_row)

    var cancel_button := Button.new()
    cancel_button.text = "Cancel"
    cancel_button.focus_mode = Control.FOCUS_NONE
    cancel_button.pressed.connect(_on_cancel_pressed)
    button_row.add_child(cancel_button)

    _confirm_button = Button.new()
    _confirm_button.text = "Land"
    _confirm_button.focus_mode = Control.FOCUS_NONE
    _confirm_button.pressed.connect(_on_confirm_pressed)
    button_row.add_child(_confirm_button)

    _footer_label = Label.new()
    _footer_label.text = "[Enter] Land  ·  [Esc] Cancel"
    _footer_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
    _footer_label.add_theme_font_size_override("font_size", 11)
    vbox.add_child(_footer_label)


func _make_panel_stylebox() -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.06, 0.07, 0.10, 0.96)
    sb.border_color = Color(0.35, 0.55, 0.85, 0.9)
    sb.border_width_left = 2
    sb.border_width_right = 2
    sb.border_width_top = 2
    sb.border_width_bottom = 2
    sb.corner_radius_top_left = 6
    sb.corner_radius_top_right = 6
    sb.corner_radius_bottom_left = 6
    sb.corner_radius_bottom_right = 6
    sb.content_margin_left = 4
    sb.content_margin_right = 4
    sb.content_margin_top = 4
    sb.content_margin_bottom = 4
    return sb


# Called by main.gd when the player presses Land at a landable POI.
# planet_data is the POI.planet_data dict (new shape: pack_id + regions[]).
# poi_id is the resolved identifier used by PlanetaryInterface.begin_landing.
func open(pack_id: String, poi_id: String, poi_name: String, regions: Array) -> void:
    _pack_id = pack_id
    _poi_id = poi_id
    _poi_name = poi_name
    _regions = regions

    if _poi_name.strip_edges().is_empty():
        _title_label.text = "Select Landing Region"
    else:
        _title_label.text = "Land on %s" % _poi_name

    _list.clear()
    var has_entries := false
    for region_v in _regions:
        if typeof(region_v) != TYPE_DICTIONARY:
            continue
        var region: Dictionary = region_v
        var rid := str(region.get("id", "")).strip_edges()
        var rname := str(region.get("name", "")).strip_edges()
        if rname.is_empty():
            rname = rid if not rid.is_empty() else "(unnamed region)"
        var label := rname
        if not rid.is_empty() and rid != rname:
            label = "%s    [%s]" % [rname, rid]
        _list.add_item(label)
        var last := _list.item_count - 1
        _list.set_item_tooltip(last, "Region id: %s" % rid)
        has_entries = true

    _empty_label.visible = not has_entries
    _list.visible = has_entries
    _confirm_button.disabled = not has_entries

    if has_entries:
        _list.select(0)
        _list.ensure_current_is_visible()
        _list.grab_focus()

    visible = true


func close() -> void:
    if not visible:
        return
    visible = false
    _regions = []
    _pack_id = ""
    _poi_id = ""
    _poi_name = ""
    _list.clear()


func is_open() -> bool:
    return visible


func _unhandled_input(event: InputEvent) -> void:
    if not visible:
        return
    if event.is_action_pressed("ui_cancel"):
        accept_event()
        _on_cancel_pressed()
        return
    if event.is_action_pressed("ui_accept"):
        accept_event()
        _on_confirm_pressed()


func _on_item_activated(_index: int) -> void:
    _on_confirm_pressed()


func _on_item_selected(_index: int) -> void:
    # Keep focus on the list so the keyboard hint remains accurate.
    pass


func _on_confirm_pressed() -> void:
    if _regions.is_empty():
        return
    var selected := _list.get_selected_items()
    if selected.is_empty():
        return
    var idx := int(selected[0])
    if idx < 0 or idx >= _regions.size():
        return
    var region_v: Variant = _regions[idx]
    if typeof(region_v) != TYPE_DICTIONARY:
        return
    var region: Dictionary = (region_v as Dictionary).duplicate(true)
    var pack := _pack_id
    var poi := _poi_id
    visible = false
    region_chosen.emit(pack, poi, region)


func _on_cancel_pressed() -> void:
    if not visible:
        return
    visible = false
    cancelled.emit()
