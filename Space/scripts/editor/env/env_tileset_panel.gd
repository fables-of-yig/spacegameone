extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const EnvIO = preload("res://Space/scripts/editor/env/env_io.gd")
const EnvTypes = preload("res://Space/scripts/editor/env/env_types.gd")
const BLOCK_SIZE: int = 16
const BG_SHADER_PRESETS := [
    {"id": "none", "label": "NO SHADER"},
    {"id": "flicker", "label": "FLICKER"},
    {"id": "wave", "label": "WAVE"},
    {"id": "heat", "label": "HEAT"},
]

# Right-side panel. Display mode switches on the editor's active_mode:
#   • MODE_COLLISION → 4×4 grid of collision-nibble swatches with labels.
#   • MODE_ENTITIES  → entity type picker column.
#   • MODE_DOORS     → direction picker + scrollable target-room list.
#   • MODE_TILE      → tileset dropdown + import button + scrollable
#                      metatile atlas grid. Each dropdown row has inline
#                      rename/append buttons; right-clicking a tileset
#                      name in the dropdown also triggers append.
# Click dispatching lives in `_gui_input` with branches into the matching
# hit-test array.

var editor: Node = null

var _scroll_y: float = 0.0
var _content_h: float = 0.0
var _import_tab_rect: Rect2 = Rect2()
var _tile_rect_for_cell: Dictionary = {}  # atlas idx -> Rect2
var _tile_drag_selecting: bool = false
var _tile_drag_start_idx: int = -1
var _tile_drag_current_idx: int = -1
# Dropdown selector replacing the numeric tab strip. When _dropdown_open
# is true we draw an overlay list of [{idx, rect, rename_rect, append_rect}]
# on top of the metatile grid.
var _dropdown_button_rect: Rect2 = Rect2()
var _dropdown_open: bool = false
var _dropdown_row_rects: Array = []
var _nibble_rects: Array = []  # [{nibble: int, rect: Rect2}, ...]
var _entity_rects: Array = []  # [{type: String, rect: Rect2}, ...]
var _door_dir_rects: Array = []  # [{dir: String, rect: Rect2}, ...]
var _door_target_rects: Array = []  # [{addr: String, rect: Rect2}, ...]
var _door_overworld_toggle_rect: Rect2 = Rect2()
var _door_target_scroll: float = 0.0
var _door_target_viewport: Rect2 = Rect2()
var _door_target_content_h: float = 0.0
var _bg_asset_picker: OptionButton = null
var _bg_import_btn: Button = null
var _bg_import_dialog: FileDialog = null
var _bg_x_edit: LineEdit = null
var _bg_y_edit: LineEdit = null
var _bg_w_edit: LineEdit = null
var _bg_h_edit: LineEdit = null
var _bg_sx_edit: LineEdit = null
var _bg_sy_edit: LineEdit = null
var _bg_frames_edit: LineEdit = null
var _bg_fps_edit: LineEdit = null
var _bg_shader_picker: OptionButton = null
var _bg_tint_btn: ColorPickerButton = null
var _bg_shader_strength_edit: LineEdit = null
var _bg_shader_speed_edit: LineEdit = null
var _bg_apply_btn: Button = null
var _bg_delete_btn: Button = null
var _bg_forward_btn: Button = null
var _bg_backward_btn: Button = null
var _bg_merge_btn: Button = null
var _bg_last_asset_list: Array = []
var _bg_last_selected_id: String = ""
var _fx_x_edit: LineEdit = null
var _fx_y_edit: LineEdit = null
var _fx_w_edit: LineEdit = null
var _fx_h_edit: LineEdit = null
var _fx_shader_picker: OptionButton = null
var _fx_tint_btn: ColorPickerButton = null
var _fx_strength_edit: LineEdit = null
var _fx_speed_edit: LineEdit = null
var _fx_apply_btn: Button = null
var _fx_delete_btn: Button = null
var _fx_forward_btn: Button = null
var _fx_backward_btn: Button = null
var _zone_kind_picker: OptionButton = null
var _zone_name_edit: LineEdit = null
var _zone_id_edit: LineEdit = null
var _zone_direction_picker: OptionButton = null
var _zone_target_edit: LineEdit = null
var _zone_overworld_toggle: CheckBox = null
var _zone_overworld_region_edit: LineEdit = null
var _zone_enabled_toggle: CheckBox = null
var _zone_locked_toggle: CheckBox = null
var _zone_required_item_edit: LineEdit = null
var _zone_required_item_count_edit: LineEdit = null
var _zone_required_var_name_edit: LineEdit = null
var _zone_required_var_value_edit: LineEdit = null
var _zone_required_tag_edit: LineEdit = null
var _zone_blocked_event_edit: LineEdit = null
var _zone_success_event_edit: LineEdit = null
var _zone_arrive_event_edit: LineEdit = null
var _zone_prompt_edit: LineEdit = null
var _zone_event_edit: LineEdit = null
var _zone_once_toggle: CheckBox = null
var _last_zone_sync_id: String = ""
var _last_zone_sync_kind: String = ""


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    _build_bg_controls()
    _build_fx_controls()
    set_process(true)


func _build_bg_controls() -> void:
    _bg_asset_picker = OptionButton.new()
    _bg_asset_picker.item_selected.connect(Callable(self, "_on_bg_asset_selected"))
    add_child(_bg_asset_picker)

    _bg_import_btn = Button.new()
    _bg_import_btn.text = "IMPORT PNG"
    _bg_import_btn.pressed.connect(Callable(self, "_on_bg_import_pressed"))
    add_child(_bg_import_btn)

    _bg_import_dialog = FileDialog.new()
    _bg_import_dialog.use_native_dialog = true
    _bg_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
    _bg_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
    _bg_import_dialog.filters = PackedStringArray(["*.png ; PNG images"])
    _bg_import_dialog.title = "Choose background PNGs"
    _bg_import_dialog.files_selected.connect(Callable(self, "_on_bg_import_files_selected"))
    add_child(_bg_import_dialog)

    _bg_x_edit = _make_bg_line_edit("0")
    _bg_y_edit = _make_bg_line_edit("0")
    _bg_w_edit = _make_bg_line_edit("8")
    _bg_h_edit = _make_bg_line_edit("8")
    _bg_sx_edit = _make_bg_line_edit("1.00")
    _bg_sy_edit = _make_bg_line_edit("1.00")
    _bg_frames_edit = _make_bg_line_edit("1")
    _bg_fps_edit = _make_bg_line_edit("0.0")
    _bg_apply_btn = Button.new()
    _bg_apply_btn.text = "APPLY"
    _bg_apply_btn.pressed.connect(Callable(self, "_on_bg_apply_pressed"))
    add_child(_bg_apply_btn)

    _bg_delete_btn = Button.new()
    _bg_delete_btn.text = "DELETE"
    _bg_delete_btn.pressed.connect(Callable(self, "_on_bg_delete_pressed"))
    add_child(_bg_delete_btn)

    _bg_forward_btn = Button.new()
    _bg_forward_btn.text = "BRING FWD"
    _bg_forward_btn.pressed.connect(Callable(self, "_on_bg_forward_pressed"))
    add_child(_bg_forward_btn)

    _bg_backward_btn = Button.new()
    _bg_backward_btn.text = "SEND BACK"
    _bg_backward_btn.pressed.connect(Callable(self, "_on_bg_backward_pressed"))
    add_child(_bg_backward_btn)

    _bg_merge_btn = Button.new()
    _bg_merge_btn.text = "MERGE TO PNG"
    _bg_merge_btn.pressed.connect(Callable(self, "_on_bg_merge_pressed"))
    add_child(_bg_merge_btn)

    _set_bg_controls_visible(false)


func _build_fx_controls() -> void:
    _zone_kind_picker = OptionButton.new()
    for kind in ["shader", "door", "interact", "trigger"]:
        _zone_kind_picker.add_item(kind.to_upper())
        _zone_kind_picker.set_item_metadata(_zone_kind_picker.get_item_count() - 1, kind)
    _zone_kind_picker.item_selected.connect(Callable(self, "_on_zone_kind_selected"))
    add_child(_zone_kind_picker)

    _zone_name_edit = _make_bg_line_edit("Zone Name")
    _zone_name_edit.text_submitted.connect(Callable(self, "_on_zone_name_submitted"))
    _zone_name_edit.focus_exited.connect(Callable(self, "_on_zone_name_focus_exited"))
    _zone_id_edit = _make_bg_line_edit("zone_id")
    _zone_id_edit.text_submitted.connect(Callable(self, "_on_zone_id_submitted"))
    _zone_id_edit.focus_exited.connect(Callable(self, "_on_zone_id_focus_exited"))
    _fx_x_edit = _make_bg_line_edit("0")
    _fx_y_edit = _make_bg_line_edit("0")
    _fx_w_edit = _make_bg_line_edit("4")
    _fx_h_edit = _make_bg_line_edit("4")
    _fx_strength_edit = _make_bg_line_edit("0.60")
    _fx_speed_edit = _make_bg_line_edit("1.00")
    _zone_target_edit = _make_bg_line_edit("target_door_id")
    _zone_target_edit.text_submitted.connect(Callable(self, "_on_zone_target_submitted"))
    _zone_target_edit.focus_exited.connect(Callable(self, "_on_zone_target_focus_exited"))
    _zone_prompt_edit = _make_bg_line_edit("Interact")
    _zone_event_edit = _make_bg_line_edit("zone_enter")

    _fx_shader_picker = OptionButton.new()
    for preset_v in BG_SHADER_PRESETS:
        var preset: Dictionary = preset_v
        if str(preset.get("id", "")) == "none":
            continue
        _fx_shader_picker.add_item(str(preset.get("label", "")))
        _fx_shader_picker.set_item_metadata(_fx_shader_picker.get_item_count() - 1, str(preset.get("id", "")))
    add_child(_fx_shader_picker)

    _fx_tint_btn = ColorPickerButton.new()
    _fx_tint_btn.color = Color.WHITE
    add_child(_fx_tint_btn)

    _zone_direction_picker = OptionButton.new()
    for dir in ["up", "down", "left", "right"]:
        _zone_direction_picker.add_item(dir.to_upper())
        _zone_direction_picker.set_item_metadata(_zone_direction_picker.get_item_count() - 1, dir)
    _zone_direction_picker.item_selected.connect(Callable(self, "_on_zone_direction_selected"))
    add_child(_zone_direction_picker)

    _zone_overworld_toggle = CheckBox.new()
    _zone_overworld_toggle.text = "OVERWORLD"
    _zone_overworld_toggle.toggled.connect(Callable(self, "_on_zone_overworld_toggled"))
    add_child(_zone_overworld_toggle)

    _zone_overworld_region_edit = _make_bg_line_edit("overworld_region_id")
    _zone_enabled_toggle = CheckBox.new()
    _zone_enabled_toggle.text = "ENABLED"
    _zone_enabled_toggle.toggled.connect(Callable(self, "_on_zone_state_toggle_changed"))
    add_child(_zone_enabled_toggle)
    _zone_locked_toggle = CheckBox.new()
    _zone_locked_toggle.text = "LOCKED"
    _zone_locked_toggle.toggled.connect(Callable(self, "_on_zone_state_toggle_changed"))
    add_child(_zone_locked_toggle)
    _zone_required_item_edit = _make_bg_line_edit("required_item_id")
    _zone_required_item_count_edit = _make_bg_line_edit("1")
    _zone_required_var_name_edit = _make_bg_line_edit("required_var_name")
    _zone_required_var_value_edit = _make_bg_line_edit("1")
    _zone_required_tag_edit = _make_bg_line_edit("required_global_tag")
    _zone_blocked_event_edit = _make_bg_line_edit("blocked_event_name")
    _zone_success_event_edit = _make_bg_line_edit("success_event_name")
    _zone_arrive_event_edit = _make_bg_line_edit("arrive_event_name")

    _zone_once_toggle = CheckBox.new()
    _zone_once_toggle.text = "ONCE"
    _zone_once_toggle.toggled.connect(Callable(self, "_on_zone_state_toggle_changed"))
    add_child(_zone_once_toggle)

    _fx_apply_btn = Button.new()
    _fx_apply_btn.text = "APPLY"
    _fx_apply_btn.pressed.connect(Callable(self, "_on_fx_apply_pressed"))
    add_child(_fx_apply_btn)

    _fx_delete_btn = Button.new()
    _fx_delete_btn.text = "DELETE"
    _fx_delete_btn.pressed.connect(Callable(self, "_on_fx_delete_pressed"))
    add_child(_fx_delete_btn)

    _fx_forward_btn = Button.new()
    _fx_forward_btn.text = "BRING FWD"
    _fx_forward_btn.pressed.connect(Callable(self, "_on_fx_forward_pressed"))
    add_child(_fx_forward_btn)

    _fx_backward_btn = Button.new()
    _fx_backward_btn.text = "SEND BACK"
    _fx_backward_btn.pressed.connect(Callable(self, "_on_fx_backward_pressed"))
    add_child(_fx_backward_btn)

    _set_fx_controls_visible(false)


func _make_bg_line_edit(placeholder: String) -> LineEdit:
    var le := LineEdit.new()
    le.placeholder_text = placeholder
    le.alignment = HORIZONTAL_ALIGNMENT_CENTER
    add_child(le)
    return le


func _is_bg_mode() -> bool:
    return editor != null and editor.active_mode == EnvTypes.MODE_BG_IMAGES


func _is_fx_mode() -> bool:
    return editor != null and editor.active_mode == EnvTypes.MODE_ZONES


func _set_bg_controls_visible(visible_now: bool) -> void:
    for ctrl in [
        _bg_asset_picker,
        _bg_import_btn,
        _bg_x_edit,
        _bg_y_edit,
        _bg_w_edit,
        _bg_h_edit,
        _bg_sx_edit,
        _bg_sy_edit,
        _bg_frames_edit,
        _bg_fps_edit,
        _bg_apply_btn,
        _bg_delete_btn,
        _bg_forward_btn,
        _bg_backward_btn,
        _bg_merge_btn,
    ]:
        if ctrl != null:
            ctrl.visible = visible_now


func _set_fx_controls_visible(visible_now: bool) -> void:
    for ctrl in [
        _zone_kind_picker,
        _zone_name_edit,
        _zone_id_edit,
        _fx_x_edit,
        _fx_y_edit,
        _fx_w_edit,
        _fx_h_edit,
        _fx_shader_picker,
        _fx_tint_btn,
        _fx_strength_edit,
        _fx_speed_edit,
        _zone_direction_picker,
        _zone_target_edit,
        _zone_overworld_toggle,
        _zone_overworld_region_edit,
        _zone_enabled_toggle,
        _zone_locked_toggle,
        _zone_required_item_edit,
        _zone_required_item_count_edit,
        _zone_required_var_name_edit,
        _zone_required_var_value_edit,
        _zone_required_tag_edit,
        _zone_blocked_event_edit,
        _zone_success_event_edit,
        _zone_arrive_event_edit,
        _zone_prompt_edit,
        _zone_event_edit,
        _zone_once_toggle,
        _fx_apply_btn,
        _fx_delete_btn,
        _fx_forward_btn,
        _fx_backward_btn,
    ]:
        if ctrl != null:
            ctrl.visible = visible_now


func _layout_bg_controls() -> void:
    if not _is_bg_mode():
        _set_bg_controls_visible(false)
        return
    _set_bg_controls_visible(true)
    var pad := 16.0
    var full_w := size.x - pad * 2.0
    var col_gap := 12.0
    var half_w := (full_w - col_gap) * 0.5
    var import_w := 132.0
    var picker_w := full_w - import_w - col_gap
    var y := 86.0
    _bg_asset_picker.position = Vector2(pad, y)
    _bg_asset_picker.size = Vector2(picker_w, 30.0)
    _bg_import_btn.position = Vector2(pad + picker_w + col_gap, y)
    _bg_import_btn.size = Vector2(import_w, 30.0)
    y += 50.0
    _bg_x_edit.position = Vector2(pad, y)
    _bg_x_edit.size = Vector2(half_w, 30.0)
    _bg_y_edit.position = Vector2(pad + half_w + col_gap, y)
    _bg_y_edit.size = Vector2(half_w, 30.0)
    y += 46.0
    _bg_w_edit.position = Vector2(pad, y)
    _bg_w_edit.size = Vector2(half_w, 30.0)
    _bg_h_edit.position = Vector2(pad + half_w + col_gap, y)
    _bg_h_edit.size = Vector2(half_w, 30.0)
    y += 46.0
    _bg_sx_edit.position = Vector2(pad, y)
    _bg_sx_edit.size = Vector2(half_w, 30.0)
    _bg_sy_edit.position = Vector2(pad + half_w + col_gap, y)
    _bg_sy_edit.size = Vector2(half_w, 30.0)
    y += 46.0
    _bg_frames_edit.position = Vector2(pad, y)
    _bg_frames_edit.size = Vector2(half_w, 30.0)
    _bg_fps_edit.position = Vector2(pad + half_w + col_gap, y)
    _bg_fps_edit.size = Vector2(half_w, 30.0)
    y += 50.0
    _bg_apply_btn.position = Vector2(pad, y)
    _bg_apply_btn.size = Vector2(half_w, 30.0)
    _bg_delete_btn.position = Vector2(pad + half_w + col_gap, y)
    _bg_delete_btn.size = Vector2(half_w, 30.0)
    y += 42.0
    _bg_backward_btn.position = Vector2(pad, y)
    _bg_backward_btn.size = Vector2(half_w, 30.0)
    _bg_forward_btn.position = Vector2(pad + half_w + col_gap, y)
    _bg_forward_btn.size = Vector2(half_w, 30.0)
    y += 42.0
    _bg_merge_btn.position = Vector2(pad, y)
    _bg_merge_btn.size = Vector2(full_w, 30.0)


func _layout_fx_controls() -> void:
    if not _is_fx_mode():
        _set_fx_controls_visible(false)
        return
    _set_fx_controls_visible(true)
    var pad := 16.0
    var full_w := size.x - pad * 2.0
    var col_gap := 12.0
    var half_w := (full_w - col_gap) * 0.5
    var show_door_identity_only := editor != null \
        and editor.has_method("get_selected_zone_kind") \
        and str(editor.get_selected_zone_kind()) == "door"
    var y := 86.0
    _zone_kind_picker.position = Vector2(pad, y)
    _zone_kind_picker.size = Vector2(half_w, 30.0)
    _zone_name_edit.position = Vector2(pad + half_w + col_gap, y)
    _zone_name_edit.size = Vector2(half_w, 30.0)
    if show_door_identity_only:
        _zone_id_edit.visible = false
        y += 50.0
    else:
        y += 50.0
        _zone_id_edit.visible = true
        _zone_id_edit.position = Vector2(pad, y)
        _zone_id_edit.size = Vector2(full_w, 30.0)
        y += 46.0
    _fx_shader_picker.position = Vector2(pad, y)
    _fx_shader_picker.size = Vector2(half_w, 30.0)
    _fx_tint_btn.position = Vector2(pad + half_w + col_gap, y)
    _fx_tint_btn.size = Vector2(half_w, 30.0)
    y += 46.0
    _fx_x_edit.position = Vector2(pad, y)
    _fx_x_edit.size = Vector2(half_w, 30.0)
    _fx_y_edit.position = Vector2(pad + half_w + col_gap, y)
    _fx_y_edit.size = Vector2(half_w, 30.0)
    y += 46.0
    _fx_w_edit.position = Vector2(pad, y)
    _fx_w_edit.size = Vector2(half_w, 30.0)
    _fx_h_edit.position = Vector2(pad + half_w + col_gap, y)
    _fx_h_edit.size = Vector2(half_w, 30.0)
    y += 46.0
    _fx_strength_edit.position = Vector2(pad, y)
    _fx_strength_edit.size = Vector2(half_w, 30.0)
    _fx_speed_edit.position = Vector2(pad + half_w + col_gap, y)
    _fx_speed_edit.size = Vector2(half_w, 30.0)
    y += 46.0
    _zone_direction_picker.position = Vector2(pad, y)
    _zone_direction_picker.size = Vector2(half_w, 30.0)
    _zone_overworld_toggle.position = Vector2(pad + half_w + col_gap, y)
    _zone_overworld_toggle.size = Vector2(half_w, 30.0)
    y += 46.0
    _zone_target_edit.position = Vector2(pad, y)
    _zone_target_edit.size = Vector2(full_w, 30.0)
    y += 46.0
    _zone_overworld_region_edit.position = Vector2(pad, y)
    _zone_overworld_region_edit.size = Vector2(full_w, 30.0)
    y += 46.0
    _zone_enabled_toggle.position = Vector2(pad, y)
    _zone_enabled_toggle.size = Vector2(half_w, 30.0)
    _zone_locked_toggle.position = Vector2(pad + half_w + col_gap, y)
    _zone_locked_toggle.size = Vector2(half_w, 30.0)
    y += 46.0
    _zone_required_item_edit.position = Vector2(pad, y)
    _zone_required_item_edit.size = Vector2(half_w, 30.0)
    _zone_required_item_count_edit.position = Vector2(pad + half_w + col_gap, y)
    _zone_required_item_count_edit.size = Vector2(half_w, 30.0)
    y += 46.0
    _zone_required_var_name_edit.position = Vector2(pad, y)
    _zone_required_var_name_edit.size = Vector2(half_w, 30.0)
    _zone_required_var_value_edit.position = Vector2(pad + half_w + col_gap, y)
    _zone_required_var_value_edit.size = Vector2(half_w, 30.0)
    y += 46.0
    _zone_required_tag_edit.position = Vector2(pad, y)
    _zone_required_tag_edit.size = Vector2(full_w, 30.0)
    y += 46.0
    _zone_blocked_event_edit.position = Vector2(pad, y)
    _zone_blocked_event_edit.size = Vector2(full_w, 30.0)
    y += 46.0
    _zone_success_event_edit.position = Vector2(pad, y)
    _zone_success_event_edit.size = Vector2(full_w, 30.0)
    y += 46.0
    _zone_arrive_event_edit.position = Vector2(pad, y)
    _zone_arrive_event_edit.size = Vector2(full_w, 30.0)
    y += 46.0
    _zone_prompt_edit.position = Vector2(pad, y)
    _zone_prompt_edit.size = Vector2(half_w, 30.0)
    _zone_event_edit.position = Vector2(pad + half_w + col_gap, y)
    _zone_event_edit.size = Vector2(half_w, 30.0)
    y += 46.0
    _zone_once_toggle.position = Vector2(pad, y)
    _zone_once_toggle.size = Vector2(full_w, 30.0)
    y += 50.0
    _fx_apply_btn.position = Vector2(pad, y)
    _fx_apply_btn.size = Vector2(half_w, 30.0)
    _fx_delete_btn.position = Vector2(pad + half_w + col_gap, y)
    _fx_delete_btn.size = Vector2(half_w, 30.0)
    y += 42.0
    _fx_backward_btn.position = Vector2(pad, y)
    _fx_backward_btn.size = Vector2(half_w, 30.0)
    _fx_forward_btn.position = Vector2(pad + half_w + col_gap, y)
    _fx_forward_btn.size = Vector2(half_w, 30.0)


func _set_line_edit_if_idle(le: LineEdit, value: String) -> void:
    if le == null:
        return
    if le.has_focus():
        return
    if le.text != value:
        le.text = value


func _refresh_bg_asset_picker() -> void:
    if _bg_asset_picker == null or editor == null:
        return
    var assets: Array = editor.get_available_backdrop_images() if editor.has_method("get_available_backdrop_images") else []
    var selected_path: String = editor.get_selected_background_asset() if editor.has_method("get_selected_background_asset") else ""
    if assets == _bg_last_asset_list and _bg_asset_picker.get_item_count() > 0:
        var current_idx := _bg_asset_picker.selected
        if current_idx >= 0 and current_idx < _bg_asset_picker.get_item_count() \
                and str(_bg_asset_picker.get_item_metadata(current_idx)) == selected_path:
            return
    _bg_last_asset_list = assets.duplicate()
    _bg_asset_picker.clear()
    _bg_asset_picker.add_item("(pick imported image)")
    _bg_asset_picker.set_item_disabled(0, true)
    var picked_idx := 0
    for i in assets.size():
        var rel_path := str(assets[i])
        _bg_asset_picker.add_item(rel_path.get_file())
        _bg_asset_picker.set_item_metadata(i + 1, rel_path)
        if rel_path == selected_path:
            picked_idx = i + 1
    _bg_asset_picker.select(picked_idx)


func _set_shader_picker(picker: OptionButton, shader_id: String) -> void:
    if picker == null:
        return
    var wanted := shader_id.strip_edges().to_lower()
    for i in range(picker.get_item_count()):
        if str(picker.get_item_metadata(i)) == wanted:
            picker.select(i)
            return
    if picker.get_item_count() > 0:
        picker.select(0)


func _selected_shader_id(picker: OptionButton, fallback: String) -> String:
    if picker == null or picker.selected < 0:
        return fallback
    return str(picker.get_item_metadata(picker.selected))


func _set_option_picker(picker: OptionButton, wanted_id: String) -> void:
    if picker == null:
        return
    var wanted := wanted_id.strip_edges().to_lower()
    for i in range(picker.get_item_count()):
        if str(picker.get_item_metadata(i)) == wanted:
            picker.select(i)
            return
    if picker.get_item_count() > 0:
        picker.select(0)


func _set_checkbox_if_needed(box: CheckBox, wanted: bool) -> void:
    if box == null:
        return
    if box.button_pressed == wanted:
        return
    if box.has_method("set_pressed_no_signal"):
        box.set_pressed_no_signal(wanted)
    else:
        box.button_pressed = wanted


func _sync_bg_controls_from_editor() -> void:
    if not _is_bg_mode() or editor == null:
        return
    _refresh_bg_asset_picker()
    var selected: Dictionary = editor.get_selected_background_image() if editor.has_method("get_selected_background_image") else {}
    var selected_id := str(selected.get("id", ""))
    _bg_last_selected_id = selected_id
    _set_line_edit_if_idle(_bg_x_edit, "%.2f" % float(selected.get("x_blocks", 0.0)))
    _set_line_edit_if_idle(_bg_y_edit, "%.2f" % float(selected.get("y_blocks", 0.0)))
    _set_line_edit_if_idle(_bg_w_edit, "%.2f" % float(selected.get("width_blocks", 0.0)))
    _set_line_edit_if_idle(_bg_h_edit, "%.2f" % float(selected.get("height_blocks", 0.0)))
    _set_line_edit_if_idle(_bg_sx_edit, "%.2f" % float(selected.get("scroll_speed_x", 1.0)))
    _set_line_edit_if_idle(_bg_sy_edit, "%.2f" % float(selected.get("scroll_speed_y", 1.0)))
    _set_line_edit_if_idle(_bg_frames_edit, str(int(selected.get("anim_frames", 1))))
    _set_line_edit_if_idle(_bg_fps_edit, "%.2f" % float(selected.get("anim_fps", 0.0)))
    var has_selected: bool = not selected.is_empty()
    if _bg_apply_btn != null:
        _bg_apply_btn.disabled = not has_selected
    if _bg_delete_btn != null:
        _bg_delete_btn.disabled = not has_selected
    if _bg_forward_btn != null:
        _bg_forward_btn.disabled = not has_selected
    if _bg_backward_btn != null:
        _bg_backward_btn.disabled = not has_selected
    if _bg_merge_btn != null:
        var bg_images: Array = editor.get_room_background_images() if editor.has_method("get_room_background_images") else []
        _bg_merge_btn.disabled = bg_images.is_empty()


func _sync_fx_controls_from_editor() -> void:
    if not _is_fx_mode() or editor == null:
        return
    var selected: Dictionary = editor.get_selected_zone() if editor.has_method("get_selected_zone") else {}
    var kind := str(selected.get("kind", editor.get_selected_zone_kind() if editor.has_method("get_selected_zone_kind") else "shader"))
    var selected_id := str(selected.get("id", "")).strip_edges()
    var selection_changed := selected_id != _last_zone_sync_id or kind != _last_zone_sync_kind
    _set_option_picker(_zone_kind_picker, kind)
    var identity_text := str(selected.get("id", selected.get("name", ""))) if kind == "door" else str(selected.get("name", ""))
    _set_line_edit_if_idle(_zone_name_edit, identity_text)
    _set_line_edit_if_idle(_zone_id_edit, str(selected.get("id", "")))
    _set_line_edit_if_idle(_fx_x_edit, "%.2f" % float(selected.get("x_blocks", 0.0)))
    _set_line_edit_if_idle(_fx_y_edit, "%.2f" % float(selected.get("y_blocks", 0.0)))
    _set_line_edit_if_idle(_fx_w_edit, "%.2f" % float(selected.get("width_blocks", 0.0)))
    _set_line_edit_if_idle(_fx_h_edit, "%.2f" % float(selected.get("height_blocks", 0.0)))
    _set_line_edit_if_idle(_fx_strength_edit, "%.2f" % float(selected.get("shader_strength", 0.6)))
    _set_line_edit_if_idle(_fx_speed_edit, "%.2f" % float(selected.get("shader_speed", 1.0)))
    _set_shader_picker(_fx_shader_picker, str(selected.get("shader_preset", "flicker")))
    _set_option_picker(_zone_direction_picker, str(selected.get("direction", "right")))
    _set_line_edit_if_idle(_zone_target_edit, str(selected.get("target_door_id", selected.get("target_room", ""))))
    _set_line_edit_if_idle(_zone_overworld_region_edit, str(selected.get("overworld_region_id", "")))
    _set_line_edit_if_idle(_zone_required_item_edit, str(selected.get("required_item_id", "")))
    _set_line_edit_if_idle(_zone_required_item_count_edit, str(selected.get("required_item_count", 1)))
    _set_line_edit_if_idle(_zone_required_var_name_edit, str(selected.get("required_var_name", "")))
    _set_line_edit_if_idle(_zone_required_var_value_edit, str(selected.get("required_var_value", 1)))
    _set_line_edit_if_idle(_zone_required_tag_edit, str(selected.get("required_global_tag", "")))
    _set_line_edit_if_idle(_zone_blocked_event_edit, str(selected.get("blocked_event_name", "")))
    _set_line_edit_if_idle(_zone_success_event_edit, str(selected.get("success_event_name", "")))
    _set_line_edit_if_idle(_zone_arrive_event_edit, str(selected.get("arrive_event_name", "")))
    _set_line_edit_if_idle(_zone_prompt_edit, str(selected.get("prompt_text", "Interact")))
    _set_line_edit_if_idle(_zone_event_edit, str(selected.get("event_name", "zone_enter")))
    if _fx_tint_btn != null:
        var wanted_tint: Color = Color.from_string(str(selected.get("shader_tint", "ffffff")), Color.WHITE)
        if _fx_tint_btn.color != wanted_tint:
            _fx_tint_btn.color = wanted_tint
    if selection_changed and _zone_overworld_toggle != null:
        _set_checkbox_if_needed(_zone_overworld_toggle, bool(selected.get("send_to_overworld", false)))
    if selection_changed and _zone_enabled_toggle != null:
        _set_checkbox_if_needed(_zone_enabled_toggle, bool(selected.get("enabled", true)))
    if selection_changed and _zone_locked_toggle != null:
        _set_checkbox_if_needed(_zone_locked_toggle, bool(selected.get("locked", false)))
    if selection_changed and _zone_once_toggle != null:
        _set_checkbox_if_needed(_zone_once_toggle, bool(selected.get("once", false)))
    var has_selected: bool = not selected.is_empty()
    var show_shader := kind == "shader"
    var show_door := kind == "door"
    var show_interact := kind == "interact"
    var show_trigger := kind == "trigger" or show_interact
    if _fx_shader_picker != null:
        _fx_shader_picker.visible = show_shader
    if _fx_tint_btn != null:
        _fx_tint_btn.visible = show_shader
    if _fx_strength_edit != null:
        _fx_strength_edit.visible = show_shader
    if _fx_speed_edit != null:
        _fx_speed_edit.visible = show_shader
    if _zone_direction_picker != null:
        _zone_direction_picker.visible = show_door
    if _zone_id_edit != null:
        _zone_id_edit.visible = has_selected and not show_door
    if _zone_target_edit != null:
        _zone_target_edit.visible = show_door
    if _zone_overworld_toggle != null:
        _zone_overworld_toggle.visible = show_door
    if _zone_overworld_region_edit != null:
        _zone_overworld_region_edit.visible = show_door
    if _zone_enabled_toggle != null:
        _zone_enabled_toggle.visible = show_door
    if _zone_locked_toggle != null:
        _zone_locked_toggle.visible = show_door
    if _zone_required_item_edit != null:
        _zone_required_item_edit.visible = show_door
    if _zone_required_item_count_edit != null:
        _zone_required_item_count_edit.visible = show_door
    if _zone_required_var_name_edit != null:
        _zone_required_var_name_edit.visible = show_door
    if _zone_required_var_value_edit != null:
        _zone_required_var_value_edit.visible = show_door
    if _zone_required_tag_edit != null:
        _zone_required_tag_edit.visible = show_door
    if _zone_blocked_event_edit != null:
        _zone_blocked_event_edit.visible = show_door
    if _zone_success_event_edit != null:
        _zone_success_event_edit.visible = show_door
    if _zone_arrive_event_edit != null:
        _zone_arrive_event_edit.visible = show_door
    if _zone_prompt_edit != null:
        _zone_prompt_edit.visible = show_interact
    if _zone_event_edit != null:
        _zone_event_edit.visible = show_trigger
    if _zone_once_toggle != null:
        _zone_once_toggle.visible = show_trigger
    if _fx_apply_btn != null:
        _fx_apply_btn.disabled = not has_selected
    if _fx_delete_btn != null:
        _fx_delete_btn.disabled = not has_selected
    if _fx_forward_btn != null:
        _fx_forward_btn.disabled = not has_selected
    if _fx_backward_btn != null:
        _fx_backward_btn.disabled = not has_selected
    _last_zone_sync_id = selected_id
    _last_zone_sync_kind = kind


func _process(_delta):
    _layout_bg_controls()
    _layout_fx_controls()
    _sync_bg_controls_from_editor()
    _sync_fx_controls_from_editor()
    queue_redraw()


func close_dropdown_if_open() -> bool:
    if _dropdown_open:
        _dropdown_open = false
        return true
    return false


func _gui_input(event):
    if editor == null:
        return

    var is_collision: bool = editor.active_mode == EnvTypes.MODE_COLLISION
    var is_entities: bool = editor.active_mode == EnvTypes.MODE_ENTITIES
    var is_zones: bool = editor.active_mode == EnvTypes.MODE_ZONES or editor.active_mode == EnvTypes.MODE_DOORS or editor.active_mode == EnvTypes.MODE_SHADERS
    var is_bg_images: bool = editor.active_mode == EnvTypes.MODE_BG_IMAGES

    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            if is_zones and _door_target_viewport.has_point(mb.position):
                _door_target_scroll = maxf(_door_target_scroll - 24.0, 0.0)
            else:
                _scroll_y = maxf(_scroll_y - 32.0, 0.0)
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            if is_zones and _door_target_viewport.has_point(mb.position):
                var max_t := maxf(_door_target_content_h - _door_target_viewport.size.y, 0.0)
                _door_target_scroll = minf(_door_target_scroll + 24.0, max_t)
            else:
                var max_scroll := maxf(_content_h - size.y + 48.0, 0.0)
                _scroll_y = minf(_scroll_y + 32.0, max_scroll)
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
            # Right-click a dropdown row → append PNGs to that tileset
            # (fast path, skips hitting the append button).
            if not is_collision and not is_entities and not is_zones and not is_bg_images and _dropdown_open:
                for entry in _dropdown_row_rects:
                    if (entry["rect"] as Rect2).has_point(mb.position):
                        editor.request_append_to_tileset(int(entry["idx"]))
                        _dropdown_open = false
                        accept_event()
                        return
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            if is_bg_images:
                return
            if is_zones:
                if _door_overworld_toggle_rect.has_point(mb.position):
                    editor.set_selected_door_send_to_overworld(
                        not bool(editor.selected_door_send_to_overworld))
                    accept_event()
                    return
                for entry in _door_dir_rects:
                    if (entry["rect"] as Rect2).has_point(mb.position):
                        editor.set_selected_door_direction(str(entry["dir"]))
                        accept_event()
                        return
                if _door_target_viewport.has_point(mb.position):
                    if bool(editor.selected_door_send_to_overworld):
                        accept_event()
                        return
                    for entry in _door_target_rects:
                        if (entry["rect"] as Rect2).has_point(mb.position):
                            editor.set_selected_door_target_room(str(entry["addr"]))
                            accept_event()
                            return
                return
            if is_collision:
                for entry in _nibble_rects:
                    if (entry["rect"] as Rect2).has_point(mb.position):
                        editor.set_selected_collision_nibble(int(entry["nibble"]))
                        accept_event()
                        return
                return
            if is_entities:
                for entry in _entity_rects:
                    if (entry["rect"] as Rect2).has_point(mb.position):
                        editor.set_selected_entity_type(str(entry["type"]))
                        accept_event()
                        return
                return
            # Tile mode. Dropdown takes priority when open so its rows
            # can shadow whatever metatile cells sit underneath.
            if _dropdown_open:
                for entry in _dropdown_row_rects:
                    var rename_r: Rect2 = entry["rename_rect"]
                    if rename_r.has_point(mb.position):
                        _dropdown_open = false
                        editor.request_rename_tileset(int(entry["idx"]))
                        accept_event()
                        return
                    var append_r: Rect2 = entry["append_rect"]
                    if append_r.has_point(mb.position):
                        _dropdown_open = false
                        editor.request_append_to_tileset(int(entry["idx"]))
                        accept_event()
                        return
                    var delete_r: Rect2 = entry["delete_rect"]
                    if delete_r.has_point(mb.position):
                        _dropdown_open = false
                        editor.request_delete_tileset(int(entry["idx"]))
                        accept_event()
                        return
                    var row_r: Rect2 = entry["rect"]
                    if row_r.has_point(mb.position):
                        editor.set_selected_tileset(int(entry["idx"]))
                        _dropdown_open = false
                        accept_event()
                        return
                # Click on the dropdown button while open → toggle closed.
                if _dropdown_button_rect.has_point(mb.position):
                    _dropdown_open = false
                    accept_event()
                    return
                # Click anywhere else → close without selecting.
                _dropdown_open = false
                accept_event()
                return
            if _dropdown_button_rect.has_point(mb.position):
                _dropdown_open = true
                accept_event()
                return
            if _import_tab_rect.has_point(mb.position):
                editor.request_import_tileset()
                accept_event()
                return
            for idx in _tile_rect_for_cell.keys():
                var r: Rect2 = _tile_rect_for_cell[idx]
                if r.has_point(mb.position):
                    _tile_drag_selecting = true
                    _tile_drag_start_idx = int(idx)
                    _tile_drag_current_idx = int(idx)
                    accept_event()
                    return
        if not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _tile_drag_selecting:
            _tile_drag_selecting = false
            _commit_drag_selection()
            accept_event()
            return
    elif event is InputEventMouseMotion and _tile_drag_selecting:
        var mm := event as InputEventMouseMotion
        for idx in _tile_rect_for_cell.keys():
            var r: Rect2 = _tile_rect_for_cell[idx]
            if r.has_point(mm.position):
                _tile_drag_current_idx = int(idx)
                break
        accept_event()
        return


func _draw():
    UIPanels.draw_panel(self, Rect2(Vector2.ZERO, size), Color.WHITE, UIPanels.PanelVariant.DARK)

    var font := ThemeDB.fallback_font
    if editor == null:
        draw_string(font, Vector2(16, 32), "(no editor)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.55, 0.65, 1))
        return

    if editor.active_mode == EnvTypes.MODE_COLLISION:
        _draw_collision_palette(font)
    elif editor.active_mode == EnvTypes.MODE_ENTITIES:
        _draw_entity_palette(font)
    elif editor.active_mode == EnvTypes.MODE_BG_IMAGES:
        _draw_bg_image_palette(font)
    elif editor.active_mode == EnvTypes.MODE_ZONES \
            or editor.active_mode == EnvTypes.MODE_DOORS \
            or editor.active_mode == EnvTypes.MODE_SHADERS:
        _draw_shader_palette(font)
    else:
        _draw_tile_palette(font)
        # Dropdown overlay is drawn AFTER the picker grid so it sits on
        # top of any metatile cells that would otherwise occlude it.
        if _dropdown_open:
            _draw_tileset_dropdown(font)


func _draw_tile_palette(font: Font) -> void:
    _nibble_rects.clear()
    _entity_rects.clear()
    _door_dir_rects.clear()
    _door_target_rects.clear()
    _door_overworld_toggle_rect = Rect2()
    _dropdown_row_rects.clear()

    var title_y: float = 32.0
    draw_string(font, Vector2(16, title_y), "TILESET",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIPanels.TEXT_PANEL)

    var indices: Array = editor.get_tileset_indices()
    var row_y: float = title_y + 12.0
    var row_h: float = 26.0
    var btn_gap: float = 6.0
    var import_btn_w: float = 30.0
    var dropdown_x: float = 16.0
    var dropdown_w: float = size.x - 32.0 - import_btn_w - btn_gap
    _dropdown_button_rect = Rect2(dropdown_x, row_y, dropdown_w, row_h)
    var mouse_pos := get_local_mouse_position()
    var dd_hover := _dropdown_button_rect.has_point(mouse_pos)
    var dd_tint: Color
    if _dropdown_open:
        dd_tint = Color(0.45, 0.88, 1.0, 1.0)
    elif dd_hover:
        dd_tint = Color(0.5, 0.65, 0.9, 1.0)
    else:
        dd_tint = Color(0.32, 0.42, 0.58, 1.0)
    UIPanels.draw_button_bg(self, _dropdown_button_rect, dd_hover, dd_tint)

    var current_idx: int = int(editor.selected_tileset_id)
    var current_label: String = "(no tilesets)"
    if not indices.is_empty():
        var name_str := str(editor.get_tileset_name(current_idx))
        current_label = "%s  (%02d)" % [name_str, current_idx]
    draw_string(font, Vector2(dropdown_x + 10, row_y + 17), current_label,
        HORIZONTAL_ALIGNMENT_LEFT, dropdown_w - 28, 12, Color(1, 1, 1, 1))
    # Caret on the right edge.
    var caret_x: float = dropdown_x + dropdown_w - 14.0
    var caret_y: float = row_y + row_h * 0.5
    var caret_pts := PackedVector2Array([
        Vector2(caret_x - 4, caret_y - 2),
        Vector2(caret_x + 4, caret_y - 2),
        Vector2(caret_x, caret_y + 3),
    ])
    draw_colored_polygon(caret_pts, Color(1, 1, 1, 0.92))
    if dd_hover:
        EditorTooltip.show_text("Active tileset. Click to open the dropdown — select another tileset, rename it, or append more tiles to it. The numeric ID in parentheses is the disambiguator when multiple tilesets share a name.")

    _import_tab_rect = Rect2(dropdown_x + dropdown_w + btn_gap, row_y, import_btn_w, row_h)
    var import_hover := _import_tab_rect.has_point(mouse_pos)
    var import_tint: Color
    if import_hover:
        import_tint = Color(0.55, 0.95, 0.65, 1.0)
    else:
        import_tint = Color(0.3, 0.6, 0.4, 1.0)
    UIPanels.draw_button_bg(self, _import_tab_rect, import_hover, import_tint)
    draw_string(font, _import_tab_rect.position + Vector2(11, 18), "+",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 1))
    if import_hover:
        EditorTooltip.show_text("Create a new tileset from one or more PNGs. Shift/Ctrl-click in the file picker to select a batch — they'll all get stitched into one atlas. Each source's width and height must be multiples of 16. To add MORE tiles to an EXISTING tileset, use the dropdown's \"append\" button.")

    var grid_top: float = row_y + row_h + 14.0

    _tile_rect_for_cell.clear()
    _content_h = 0.0

    var tex: Texture2D = editor.get_tileset_texture(editor.selected_tileset_id)
    if tex == null:
        draw_string(font, Vector2(16, grid_top + 14),
            "(no tileset texture for id %d)" % editor.selected_tileset_id,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.55, 0.55, 1))
        return

    var atlas_w := tex.get_width()
    var atlas_h := tex.get_height()
    if atlas_w <= 0 or atlas_h <= 0:
        return
    # Storage is always 16-px cells; the grid_cols/grid_rows here are the
    # 16-px sub-tile dimensions (which also match MvTileValue's linearized
    # idx layout). A "logical tile" is an N×N sub-tile chunk where
    # N = tile_size / BLOCK_SIZE.
    @warning_ignore("integer_division")
    var grid_cols := atlas_w / BLOCK_SIZE
    @warning_ignore("integer_division")
    var grid_rows := atlas_h / BLOCK_SIZE
    if grid_cols <= 0 or grid_rows <= 0:
        return
    var tile_px: int = int(editor.get_tileset_tile_size(editor.selected_tileset_id))
    if tile_px < BLOCK_SIZE:
        tile_px = BLOCK_SIZE
    @warning_ignore("integer_division")
    var n_subs: int = tile_px / BLOCK_SIZE
    if n_subs <= 0:
        n_subs = 1
    @warning_ignore("integer_division")
    var logical_cols := grid_cols / n_subs
    @warning_ignore("integer_division")
    var logical_rows := grid_rows / n_subs
    if logical_cols <= 0 or logical_rows <= 0:
        return

    var panel_inner_x: float = 16.0
    var panel_inner_w: float = size.x - 32.0
    var atlas_scale: float = panel_inner_w / float(atlas_w)
    var logical_cell_px: float = float(tile_px) * atlas_scale
    var atlas_draw_h: float = float(atlas_h) * atlas_scale
    _content_h = atlas_draw_h + 60.0

    var max_scroll := maxf(_content_h - (size.y - grid_top - 20.0), 0.0)
    _scroll_y = clampf(_scroll_y, 0.0, max_scroll)

    var panel_rect := Rect2(Vector2(0, grid_top - 2), Vector2(size.x, size.y - grid_top - 4))
    draw_rect(panel_rect, Color(0.04, 0.05, 0.08, 0.85))

    var viewport_h: float = size.y - grid_top
    if viewport_h > 0.0 and atlas_draw_h > 0.0:
        var visible_src_y: float = _scroll_y / atlas_scale
        var visible_src_h: float = minf(float(atlas_h) - visible_src_y, viewport_h / atlas_scale)
        if visible_src_h > 0.0:
            var atlas_dst := Rect2(
                Vector2(panel_inner_x, grid_top),
                Vector2(panel_inner_w, visible_src_h * atlas_scale)
            )
            var atlas_src := Rect2(
                Vector2(0.0, visible_src_y),
                Vector2(float(atlas_w), visible_src_h)
            )
            draw_texture_rect_region(tex, atlas_dst, atlas_src, Color(1, 1, 1, 1))

    var total_logical: int = logical_cols * logical_rows
    for logical_idx in total_logical:
        var l_col := logical_idx % logical_cols
        @warning_ignore("integer_division")
        var l_row := logical_idx / logical_cols
        var px := panel_inner_x + float(l_col * tile_px) * atlas_scale
        var py := grid_top + float(l_row * tile_px) * atlas_scale - _scroll_y
        var dst := Rect2(Vector2(px, py), Vector2(logical_cell_px, logical_cell_px))
        if dst.end.y < grid_top or dst.position.y > size.y:
            continue
        # Key = top-left 16-px sub-tile idx of this logical tile. That's
        # what the editor stores in selected_metatile_idx, so both click
        # dispatch and the selection highlight can match on it directly.
        var top_left_sub_idx: int = (l_row * n_subs) * grid_cols + (l_col * n_subs)
        _tile_rect_for_cell[top_left_sub_idx] = dst

        var mouse_pos2 := get_local_mouse_position()
        var sel_rect := _current_selection_rect(logical_cols, n_subs, grid_cols)
        var selected_start := sel_rect.position
        var selected_size := sel_rect.size
        if l_col >= selected_start.x and l_col < selected_start.x + selected_size.x and l_row >= selected_start.y and l_row < selected_start.y + selected_size.y:
            draw_rect(dst, Color(1, 0.9, 0.3, 1), false, 2.0)
            draw_rect(dst.grow(2), Color(1, 0.95, 0.55, 0.55), false, 1.0)
        elif dst.has_point(mouse_pos2):
            draw_rect(dst, Color(0.5, 0.75, 1.0, 0.85), false, 1.5)
            if n_subs == 1:
                EditorTooltip.show_text("Tile #%d from tileset %d. Click to select it, or drag across multiple tiles to build a larger paint brush." % [top_left_sub_idx, int(editor.selected_tileset_id)])
            else:
                EditorTooltip.show_text("Logical tile at atlas (%d,%d) from tileset %d — %d×%d px, paints as a %d×%d metatile. Drag across multiple logical tiles to build a larger brush." % [int(l_col), int(l_row), int(editor.selected_tileset_id), tile_px, tile_px, n_subs, n_subs])

    var footer_size := _current_selection_rect(logical_cols, n_subs, grid_cols).size
    var footer := "brush: %dx%d logical  (%d×%d px each)" % [footer_size.x, footer_size.y, tile_px, tile_px]
    draw_string(font, Vector2(16, size.y - 12),
        footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.65, 0.8, 1))


func _commit_drag_selection() -> void:
    if editor == null or _tile_drag_start_idx < 0:
        return
    var tex: Texture2D = editor.get_tileset_texture(editor.selected_tileset_id)
    if tex == null:
        editor.set_selected_metatile(_tile_drag_start_idx)
        _tile_drag_start_idx = -1
        _tile_drag_current_idx = -1
        return
    var tile_px: int = int(editor.get_tileset_tile_size(editor.selected_tileset_id))
    if tile_px < BLOCK_SIZE:
        tile_px = BLOCK_SIZE
    @warning_ignore("integer_division")
    var n_subs: int = maxi(tile_px / BLOCK_SIZE, 1)
    @warning_ignore("integer_division")
    var grid_cols: int = maxi(tex.get_width() / BLOCK_SIZE, 1)
    @warning_ignore("integer_division")
    var _logical_cols: int = maxi(grid_cols / n_subs, 1)
    var a := _logical_coord_for_idx(_tile_drag_start_idx, n_subs, grid_cols)
    var b := _logical_coord_for_idx(_tile_drag_current_idx if _tile_drag_current_idx >= 0 else _tile_drag_start_idx, n_subs, grid_cols)
    var min_x := mini(a.x, b.x)
    var min_y := mini(a.y, b.y)
    var max_x := maxi(a.x, b.x)
    var max_y := maxi(a.y, b.y)
    var anchor_idx := (min_y * n_subs) * grid_cols + (min_x * n_subs)
    editor.set_selected_metatile_block(anchor_idx, max_x - min_x + 1, max_y - min_y + 1)
    _tile_drag_start_idx = -1
    _tile_drag_current_idx = -1


func _logical_coord_for_idx(idx: int, n_subs: int, grid_cols: int) -> Vector2i:
    var sub_col := idx % grid_cols
    @warning_ignore("integer_division")
    var sub_row := idx / grid_cols
    @warning_ignore("integer_division", "integer_division")
    return Vector2i(sub_col / n_subs, sub_row / n_subs)


func _current_selection_rect(logical_cols: int, n_subs: int, grid_cols: int) -> Rect2i:
    if _tile_drag_selecting and _tile_drag_start_idx >= 0:
        var a := _logical_coord_for_idx(_tile_drag_start_idx, n_subs, grid_cols)
        var b := _logical_coord_for_idx(_tile_drag_current_idx if _tile_drag_current_idx >= 0 else _tile_drag_start_idx, n_subs, grid_cols)
        var min_x := mini(a.x, b.x)
        var min_y := mini(a.y, b.y)
        var max_x := mini(maxi(a.x, b.x), logical_cols - 1)
        var max_y := maxi(a.y, b.y)
        return Rect2i(Vector2i(min_x, min_y), Vector2i(max_x - min_x + 1, max_y - min_y + 1))
    var start_idx := int(editor.selected_metatile_idx)
    var start := _logical_coord_for_idx(start_idx, n_subs, grid_cols)
    var span: Vector2i = editor.get_selected_metatile_span()
    return Rect2i(start, Vector2i(maxi(span.x, 1), maxi(span.y, 1)))


func _draw_collision_palette(font: Font) -> void:
    _tile_rect_for_cell.clear()
    _dropdown_row_rects.clear()
    _nibble_rects.clear()
    _entity_rects.clear()
    _door_dir_rects.clear()
    _door_target_rects.clear()
    _content_h = 0.0
    _scroll_y = 0.0

    var title_y: float = 32.0
    draw_string(font, Vector2(16, title_y), "COLLISION",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIPanels.TEXT_PANEL)
    draw_string(font, Vector2(16, title_y + 16), "click to select nibble",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.78, 0.9, 1))

    var mouse_pos := get_local_mouse_position()
    var grid_top: float = title_y + 36.0
    var cols: int = 2
    var pad: float = 16.0
    var gap: float = 6.0
    var cell_w: float = (size.x - pad * 2.0 - gap * float(cols - 1)) / float(cols)
    var cell_h: float = 38.0

    for nibble in range(16):
        var col_i := nibble % cols
        @warning_ignore("integer_division")
        var row_i := nibble / cols
        var x := pad + float(col_i) * (cell_w + gap)
        var y := grid_top + float(row_i) * (cell_h + gap)
        var rect := Rect2(x, y, cell_w, cell_h)
        _nibble_rects.append({"nibble": nibble, "rect": rect})

        var is_active := int(editor.selected_collision_nibble) == nibble
        var is_hover := rect.has_point(mouse_pos)

        var bt_col := EnvTypes.block_type_color(nibble)
        bt_col.a = 1.0
        UIPanels.draw_button_bg(self, rect, is_hover, bt_col.lerp(Color(1, 1, 1, 1), 0.15) if is_active else bt_col)

        var swatch := Rect2(rect.position + Vector2(8, 6), Vector2(cell_h - 12, cell_h - 12))
        draw_rect(swatch, EnvTypes.block_type_color(nibble))
        draw_rect(swatch, Color(0, 0, 0, 0.75), false, 1.0)
        var hex_lbl := "%X" % nibble
        draw_string(font, swatch.position + Vector2(7, cell_h - 18),
            hex_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.05, 0.05, 0.1, 1))

        var label_col: Color
        if is_active:
            label_col = Color(1, 1, 1, 1)
        else:
            label_col = Color(0.9, 0.92, 1.0, 0.9)
        var lbl := EnvTypes.block_type_label(nibble)
        draw_string(font, rect.position + Vector2(swatch.size.x + 16, cell_h * 0.5 + 5),
            lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, label_col)

        if is_active:
            draw_rect(rect, Color(1, 0.95, 0.35, 1), false, 2.0)

        if is_hover:
            EditorTooltip.show_text("Collision type 0x%X — %s. Click to select, then PAINT this collision nibble onto canvas cells. 0 = empty, 1 = solid block." % [nibble, EnvTypes.block_type_label(nibble)])

    var sel: int = editor.selected_collision_nibble
    var footer := "nibble: 0x%X  %s" % [sel, EnvTypes.block_type_label(sel)]
    draw_string(font, Vector2(16, size.y - 12),
        footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.75, 0.75, 1))


func _draw_entity_palette(font: Font) -> void:
    _tile_rect_for_cell.clear()
    _dropdown_row_rects.clear()
    _nibble_rects.clear()
    _entity_rects.clear()
    _door_dir_rects.clear()
    _door_target_rects.clear()
    _content_h = 0.0
    _scroll_y = 0.0

    var title_y: float = 32.0
    draw_string(font, Vector2(16, title_y), "ENTITIES",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIPanels.TEXT_PANEL)
    draw_string(font, Vector2(16, title_y + 16), "click to select type",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.78, 0.9, 1))

    var mouse_pos := get_local_mouse_position()
    var list_top: float = title_y + 36.0
    var pad: float = 16.0
    var row_h: float = 34.0
    var gap: float = 6.0
    var row_w: float = size.x - pad * 2.0

    var types: Array = []
    for type_v in EnvTypes.ENTITY_TYPES:
        var type_id := str(type_v)
        if type_id == "trigger_volume":
            continue
        types.append(type_id)
    for i in types.size():
        var t := str(types[i])
        var y := list_top + float(i) * (row_h + gap)
        var rect := Rect2(pad, y, row_w, row_h)
        _entity_rects.append({"type": t, "rect": rect})

        var is_active := str(editor.selected_entity_type) == t
        var is_hover := rect.has_point(mouse_pos)

        var base := EnvTypes.entity_color(t)
        base.a = 1.0
        var tint: Color
        if is_active:
            tint = base.lerp(Color(1, 1, 1, 1), 0.2)
        else:
            tint = Color(base.r * 0.55, base.g * 0.55, base.b * 0.55, 1.0)
        UIPanels.draw_button_bg(self, rect, is_hover, tint)

        var swatch_r: float = 10.0
        var swatch_center := rect.position + Vector2(20, row_h * 0.5)
        draw_circle(swatch_center, swatch_r, EnvTypes.entity_color(t))
        draw_arc(swatch_center, swatch_r, 0, TAU, 18, Color(0, 0, 0, 0.75), 1.5)

        var label_col: Color
        if is_active:
            label_col = Color(1, 1, 1, 1)
        else:
            label_col = Color(0.85, 0.9, 1.0, 0.9)
        draw_string(font, rect.position + Vector2(40, row_h * 0.5 + 5),
            EnvTypes.entity_label(t), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, label_col)

        if is_active:
            draw_rect(rect, Color(1, 0.95, 0.35, 1), false, 2.0)

        if is_hover:
            EditorTooltip.show_text("%s Click to select, then click in the canvas to place instances. Room-placed entities now get stable instance IDs so triggers can target them." % EnvTypes.entity_help(t))

    var footer := "type: %s" % EnvTypes.entity_label(str(editor.selected_entity_type))
    draw_string(font, Vector2(16, size.y - 12),
        footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.82, 0.95, 1))


func _draw_door_palette(font: Font) -> void:
    _tile_rect_for_cell.clear()
    _dropdown_row_rects.clear()
    _nibble_rects.clear()
    _entity_rects.clear()
    _door_dir_rects.clear()
    _door_target_rects.clear()
    _door_overworld_toggle_rect = Rect2()
    _content_h = 0.0
    _scroll_y = 0.0

    var mouse_pos := get_local_mouse_position()
    var pad: float = 16.0

    draw_string(font, Vector2(pad, 32), "DOORS",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIPanels.TEXT_PANEL)
    draw_string(font, Vector2(pad, 48), "click a cell to place",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.85, 0.78, 1))

    draw_string(font, Vector2(pad, 74), "DIRECTION",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)
    var dir_row_y: float = 82.0
    var dir_btn_w: float = (size.x - pad * 2.0 - 12.0) * 0.25
    var dir_btn_h: float = 32.0
    var dirs := [
        {"dir": "up", "glyph": "↑"},
        {"dir": "down", "glyph": "↓"},
        {"dir": "left", "glyph": "←"},
        {"dir": "right", "glyph": "→"},
    ]
    for i in dirs.size():
        var def: Dictionary = dirs[i]
        var rect := Rect2(pad + float(i) * (dir_btn_w + 4.0), dir_row_y, dir_btn_w, dir_btn_h)
        _door_dir_rects.append({"dir": def["dir"], "rect": rect})
        var is_active := str(editor.selected_door_direction) == str(def["dir"])
        var is_hover := rect.has_point(mouse_pos)
        var tint: Color
        if is_active:
            tint = Color(0.4, 0.9, 0.55, 1.0)
        else:
            tint = Color(0.25, 0.45, 0.32, 1.0)
        UIPanels.draw_button_bg(self, rect, is_hover, tint)
        var label_col := Color(1, 1, 1, 1) if is_active else Color(0.75, 0.9, 0.82, 1)
        draw_string(font, rect.position + Vector2(dir_btn_w * 0.5 - 5, dir_btn_h * 0.5 + 7),
            str(def["glyph"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, label_col)
        if is_hover:
            EditorTooltip.show_text("Door exit direction: %s. When the player enters this door, they'll be ejected in this direction in the target room." % str(def["dir"]).to_upper())

    var target_title_y: float = dir_row_y + dir_btn_h + 18.0
    draw_string(font, Vector2(pad, target_title_y), "TARGET ROOM",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)
    var send_to_overworld: bool = bool(editor.selected_door_send_to_overworld)
    var toggle_label := "send to overworld"
    var toggle_font_size := 11
    var toggle_box_size: float = 16.0
    var toggle_gap: float = 6.0
    var toggle_label_w: float = font.get_string_size(toggle_label,
        HORIZONTAL_ALIGNMENT_LEFT, -1, toggle_font_size).x
    var toggle_w: float = toggle_box_size + toggle_gap + toggle_label_w
    var toggle_x: float = maxf(pad + 108.0, size.x - pad - toggle_w)
    var toggle_y: float = target_title_y - 12.0
    _door_overworld_toggle_rect = Rect2(toggle_x, toggle_y, toggle_w, 20.0)
    var toggle_box := Rect2(toggle_x, toggle_y + 2.0, toggle_box_size, toggle_box_size)
    var toggle_hover := _door_overworld_toggle_rect.has_point(mouse_pos)
    draw_rect(toggle_box, Color(0.08, 0.12, 0.16, 0.95))
    draw_rect(toggle_box,
        Color(0.42, 0.86, 1.0, 1.0) if send_to_overworld else Color(0.32, 0.42, 0.5, 0.95),
        false, 2.0)
    if send_to_overworld:
        draw_line(toggle_box.position + Vector2(3.0, 9.0),
            toggle_box.position + Vector2(7.0, 13.0), Color(0.85, 1.0, 1.0, 1.0), 2.0)
        draw_line(toggle_box.position + Vector2(7.0, 13.0),
            toggle_box.position + Vector2(13.0, 4.0), Color(0.85, 1.0, 1.0, 1.0), 2.0)
    draw_string(font, Vector2(toggle_x + toggle_box_size + toggle_gap, target_title_y + 1.0),
        toggle_label, HORIZONTAL_ALIGNMENT_LEFT, -1, toggle_font_size,
        Color(0.86, 0.96, 1.0, 1.0) if send_to_overworld else Color(0.72, 0.82, 0.9, 1.0))
    if toggle_hover:
        EditorTooltip.show_text("When enabled, newly placed doors ignore the room target list and return the player to the overworld.")

    var viewport_top: float = target_title_y + 10.0
    var viewport_bot: float = size.y - 24.0
    _door_target_viewport = Rect2(pad, viewport_top, size.x - pad * 2.0, viewport_bot - viewport_top)
    draw_rect(_door_target_viewport,
        Color(0.04, 0.05, 0.08, 0.5) if send_to_overworld else Color(0.04, 0.05, 0.08, 0.85))

    var addrs: Array = editor.get_room_addrs()
    var options: Array = [""]  # "" = no target
    options.append_array(addrs)

    var row_h: float = 26.0
    var row_gap: float = 4.0
    _door_target_content_h = float(options.size()) * (row_h + row_gap)
    var max_scroll := maxf(_door_target_content_h - _door_target_viewport.size.y, 0.0)
    _door_target_scroll = clampf(_door_target_scroll, 0.0, max_scroll)

    var base_y: float = viewport_top + 4.0 - _door_target_scroll
    for i in options.size():
        var addr := str(options[i])
        var rect := Rect2(pad + 4.0, base_y + float(i) * (row_h + row_gap),
            _door_target_viewport.size.x - 8.0, row_h)
        _door_target_rects.append({"addr": addr, "rect": rect})
        if rect.position.y + row_h < viewport_top or rect.position.y > viewport_bot:
            continue

        var is_active := (not send_to_overworld) and str(editor.selected_door_target_room) == addr
        var is_hover := (not send_to_overworld) and rect.has_point(mouse_pos) and _door_target_viewport.has_point(mouse_pos)

        var bg: Color
        if send_to_overworld:
            bg = Color(0.08, 0.1, 0.12, 0.45)
        elif is_active:
            bg = Color(0.25, 0.5, 0.35, 0.9)
        elif is_hover:
            bg = Color(0.15, 0.22, 0.18, 0.9)
        else:
            bg = Color(0.08, 0.12, 0.12, 0.9)
        draw_rect(rect, bg)

        var text_col: Color
        if send_to_overworld:
            text_col = Color(0.46, 0.54, 0.58, 1.0)
        elif is_active:
            text_col = Color(1, 1, 1, 1)
        else:
            text_col = Color(0.75, 0.88, 0.8, 1)
        var label := "— none —" if addr.is_empty() else addr
        draw_string(font, rect.position + Vector2(8, row_h - 7),
            label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, text_col)
        if send_to_overworld and _door_target_viewport.has_point(mouse_pos):
            EditorTooltip.show_text("Disable send to overworld to pick a room destination for doors.")
        elif is_hover:
            if addr.is_empty():
                EditorTooltip.show_text("No target. Doors without a target room do nothing — useful for placeholder placement.")
            else:
                EditorTooltip.show_text("Target room %s. Doors placed after selecting this room will take the player there on contact." % addr)

    var sel := str(editor.selected_door_target_room)
    if send_to_overworld:
        sel = "OVERWORLD"
    var footer := "dir: %s  target: %s" % [str(editor.selected_door_direction), "—" if sel.is_empty() else sel]
    draw_string(font, Vector2(pad, size.y - 10),
        footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.92, 0.82, 1))


# Overlay list that appears below the dropdown button. Each row has an
# inline "rename" and "append" button on the right; clicking the row
# anywhere else selects that tileset. Populates _dropdown_row_rects so
# _gui_input can dispatch clicks back.
func _draw_tileset_dropdown(font: Font) -> void:
    _dropdown_row_rects.clear()
    var indices: Array = editor.get_tileset_indices()
    if indices.is_empty():
        return

    var list_x: float = _dropdown_button_rect.position.x
    var list_w: float = _dropdown_button_rect.size.x
    var list_top: float = _dropdown_button_rect.position.y + _dropdown_button_rect.size.y + 2.0
    var row_h: float = 28.0
    var btn_pad: float = 4.0
    var btn_w: float = 52.0
    var delete_btn_w: float = 26.0
    var list_h: float = float(indices.size()) * row_h + btn_pad * 2.0
    var list_rect := Rect2(list_x, list_top, list_w, list_h)

    # Opaque backdrop so whatever sits underneath (metatile grid) can't
    # bleed through and confuse the hit test.
    draw_rect(list_rect, Color(0.07, 0.09, 0.14, 0.98))
    draw_rect(list_rect, Color(0.5, 0.65, 0.9, 0.9), false, 1.0)

    var mouse_pos := get_local_mouse_position()
    for i in indices.size():
        var idx: int = int(indices[i])
        var row_y: float = list_top + btn_pad + float(i) * row_h
        var row_rect := Rect2(list_x + btn_pad, row_y, list_w - btn_pad * 2.0, row_h - 2.0)
        # Button strip on the right edge: [rename] [append] [X].
        var delete_rect := Rect2(row_rect.position.x + row_rect.size.x - delete_btn_w,
            row_rect.position.y + 3.0, delete_btn_w, row_rect.size.y - 6.0)
        var append_rect := Rect2(delete_rect.position.x - btn_w - 4.0,
            row_rect.position.y + 3.0, btn_w, row_rect.size.y - 6.0)
        var rename_rect := Rect2(append_rect.position.x - btn_w - 4.0,
            row_rect.position.y + 3.0, btn_w, row_rect.size.y - 6.0)

        _dropdown_row_rects.append({
            "idx": idx,
            "rect": row_rect,
            "rename_rect": rename_rect,
            "append_rect": append_rect,
            "delete_rect": delete_rect,
        })

        var is_active: bool = (idx == int(editor.selected_tileset_id))
        var row_hover := row_rect.has_point(mouse_pos) \
                and not rename_rect.has_point(mouse_pos) \
                and not append_rect.has_point(mouse_pos) \
                and not delete_rect.has_point(mouse_pos)
        var row_bg: Color
        if is_active:
            row_bg = Color(0.2, 0.35, 0.55, 0.95)
        elif row_hover:
            row_bg = Color(0.15, 0.22, 0.32, 0.95)
        else:
            row_bg = Color(0.09, 0.12, 0.18, 0.95)
        draw_rect(row_rect, row_bg)

        var name_str: String = str(editor.get_tileset_name(idx))
        var label := "%s  (%02d)" % [name_str, idx]
        var label_col: Color
        if is_active:
            label_col = Color(1, 1, 1, 1)
        else:
            label_col = Color(0.85, 0.92, 1.0, 1)
        var label_w: float = rename_rect.position.x - row_rect.position.x - 12.0
        draw_string(font, row_rect.position + Vector2(10, 18), label,
            HORIZONTAL_ALIGNMENT_LEFT, label_w, 12, label_col)

        var rename_hover := rename_rect.has_point(mouse_pos)
        var rename_tint: Color
        if rename_hover:
            rename_tint = Color(0.55, 0.7, 0.95, 1.0)
        else:
            rename_tint = Color(0.28, 0.38, 0.55, 1.0)
        UIPanels.draw_button_bg(self, rename_rect, rename_hover, rename_tint)
        draw_string(font, rename_rect.position + Vector2(6, 16), "rename",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 1))
        if rename_hover:
            EditorTooltip.show_text("Rename tileset %02d. Only the display label changes — the numeric ID and every tile painted against it stay stable." % idx)

        var append_hover := append_rect.has_point(mouse_pos)
        var append_tint: Color
        if append_hover:
            append_tint = Color(0.55, 0.95, 0.65, 1.0)
        else:
            append_tint = Color(0.3, 0.6, 0.4, 1.0)
        UIPanels.draw_button_bg(self, append_rect, append_hover, append_tint)
        draw_string(font, append_rect.position + Vector2(8, 16), "append",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 1))
        if append_hover:
            EditorTooltip.show_text("Append PNG(s) to tileset %02d. Uses this tileset's existing tile size — the file picker opens to grab more source art. Existing tile indices stay stable so your painted rooms don't shift." % idx)

        var delete_hover := delete_rect.has_point(mouse_pos)
        var delete_tint: Color
        if delete_hover:
            delete_tint = Color(1.0, 0.45, 0.4, 1.0)
        else:
            delete_tint = Color(0.72, 0.18, 0.16, 1.0)
        UIPanels.draw_button_bg(self, delete_rect, delete_hover, delete_tint)
        # Draw a centered X glyph out of two lines so the button reads as
        # a destructive action at a glance.
        var x_center := delete_rect.position + delete_rect.size * 0.5
        var x_arm: float = 5.0
        var x_col := Color(1, 1, 1, 1)
        draw_line(x_center + Vector2(-x_arm, -x_arm),
            x_center + Vector2(x_arm, x_arm), x_col, 2.0)
        draw_line(x_center + Vector2(-x_arm, x_arm),
            x_center + Vector2(x_arm, -x_arm), x_col, 2.0)
        if delete_hover:
            EditorTooltip.show_text("Delete tileset %02d. You'll get a confirmation prompt first. Any rooms that painted cells from this tileset will render those cells as empty until you repaint them — the tile data isn't rewritten." % idx)

func _draw_bg_image_palette(font: Font) -> void:
    _tile_rect_for_cell.clear()
    _dropdown_row_rects.clear()
    _nibble_rects.clear()
    _entity_rects.clear()
    _door_dir_rects.clear()
    _door_target_rects.clear()
    _door_overworld_toggle_rect = Rect2()
    _content_h = 0.0
    _scroll_y = 0.0

    var pad := 16.0
    var full_w := size.x - pad * 2.0
    var mouse_pos := get_local_mouse_position()
    var label_gap := 10.0
    draw_string(font, Vector2(pad, 32), "BG IMAGES",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIPanels.TEXT_PANEL)
    draw_string(font, Vector2(pad, 48),
        "Paint: drag a rect. Pick: select. Erase: delete.",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.82, 0.68, 1))
    draw_string(font, Vector2(pad, _bg_asset_picker.position.y - label_gap), "Asset",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPanels.TEXT_PANEL_DIM)
    draw_string(font, Vector2(_bg_x_edit.position.x, _bg_x_edit.position.y - label_gap), "X blocks",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    draw_string(font, Vector2(_bg_y_edit.position.x, _bg_y_edit.position.y - label_gap), "Y blocks",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    draw_string(font, Vector2(_bg_w_edit.position.x, _bg_w_edit.position.y - label_gap), "W blocks",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    draw_string(font, Vector2(_bg_h_edit.position.x, _bg_h_edit.position.y - label_gap), "H blocks",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    draw_string(font, Vector2(_bg_sx_edit.position.x, _bg_sx_edit.position.y - label_gap), "X speed",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    draw_string(font, Vector2(_bg_sy_edit.position.x, _bg_sy_edit.position.y - label_gap), "Y speed",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    draw_string(font, Vector2(_bg_frames_edit.position.x, _bg_frames_edit.position.y - label_gap), "Frames",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    draw_string(font, Vector2(_bg_fps_edit.position.x, _bg_fps_edit.position.y - label_gap), "FPS",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)

    var selected: Dictionary = editor.get_selected_background_image() if editor.has_method("get_selected_background_image") else {}
    var info_top := _bg_merge_btn.position.y + _bg_merge_btn.size.y + 18.0
    var info_rect := Rect2(pad, info_top, full_w, 102.0)
    draw_rect(info_rect, Color(0.08, 0.1, 0.14, 0.92))
    draw_rect(info_rect, Color(0.52, 0.42, 0.26, 0.95), false, 1.5)
    draw_string(font, info_rect.position + Vector2(12, 20),
        "Selected Placement", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)
    var selected_label := "(none)"
    if not selected.is_empty():
        selected_label = str(selected.get("image", "")).get_file()
        if selected_label.is_empty():
            selected_label = str(selected.get("id", "(unnamed)"))
    draw_string(font, info_rect.position + Vector2(12, 40),
        selected_label, HORIZONTAL_ALIGNMENT_LEFT, info_rect.size.x - 24.0, 11, Color(0.96, 0.94, 0.88, 1.0))
    draw_string(font, info_rect.position + Vector2(12, 60),
        "Animations use horizontal strip frames inside one PNG. Merge bakes frame 0.",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.76, 0.8, 0.9, 1.0))
    draw_string(font, info_rect.position + Vector2(12, 74),
        "Layer order uses Send Back / Bring Fwd. Merge replaces the stack with one room-sized PNG.",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.72, 0.76, 0.84, 1.0))
    draw_string(font, info_rect.position + Vector2(12, 88),
        "Use ZONES mode for shader, door, interact, and trigger overlays on top of the room.",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.72, 0.8, 0.86, 1.0))

    if info_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Use PAINT to drag out a stretched image rect. Use PICK to select an existing placement, then edit its size, scroll, and strip-animation here.")
    elif Rect2(_bg_merge_btn.position, _bg_merge_btn.size).has_point(mouse_pos):
        EditorTooltip.show_text("Bake the current BG image stack into one room-sized PNG and replace the stack with that merged result.")


func _draw_shader_palette(font: Font) -> void:
    _tile_rect_for_cell.clear()
    _dropdown_row_rects.clear()
    _nibble_rects.clear()
    _entity_rects.clear()
    _door_dir_rects.clear()
    _door_target_rects.clear()
    _door_overworld_toggle_rect = Rect2()
    _content_h = 0.0
    _scroll_y = 0.0

    var pad := 16.0
    var full_w := size.x - pad * 2.0
    var mouse_pos := get_local_mouse_position()
    var label_gap := 10.0
    draw_string(font, Vector2(pad, 32), "ZONES",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIPanels.TEXT_PANEL)
    draw_string(font, Vector2(pad, 48),
        "Paint: drag a rect. Pick: select. Erase: delete.",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.82, 0.88, 0.98, 1.0))
    draw_string(font, Vector2(_zone_kind_picker.position.x, _zone_kind_picker.position.y - label_gap), "Type",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    draw_string(font, Vector2(_zone_name_edit.position.x, _zone_name_edit.position.y - label_gap), "Name",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _zone_id_edit.visible:
        draw_string(font, Vector2(_zone_id_edit.position.x, _zone_id_edit.position.y - label_gap), "ID",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _fx_shader_picker.visible:
        draw_string(font, Vector2(_fx_shader_picker.position.x, _fx_shader_picker.position.y - label_gap), "Effect",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _fx_tint_btn.visible:
        draw_string(font, Vector2(_fx_tint_btn.position.x, _fx_tint_btn.position.y - label_gap), "Tint",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    draw_string(font, Vector2(_fx_x_edit.position.x, _fx_x_edit.position.y - label_gap), "X blocks",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    draw_string(font, Vector2(_fx_y_edit.position.x, _fx_y_edit.position.y - label_gap), "Y blocks",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    draw_string(font, Vector2(_fx_w_edit.position.x, _fx_w_edit.position.y - label_gap), "W blocks",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    draw_string(font, Vector2(_fx_h_edit.position.x, _fx_h_edit.position.y - label_gap), "H blocks",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _fx_strength_edit.visible:
        draw_string(font, Vector2(_fx_strength_edit.position.x, _fx_strength_edit.position.y - label_gap), "Strength",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _fx_speed_edit.visible:
        draw_string(font, Vector2(_fx_speed_edit.position.x, _fx_speed_edit.position.y - label_gap), "Speed",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _zone_direction_picker.visible:
        draw_string(font, Vector2(_zone_direction_picker.position.x, _zone_direction_picker.position.y - label_gap), "Direction",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _zone_target_edit.visible:
        draw_string(font, Vector2(_zone_target_edit.position.x, _zone_target_edit.position.y - label_gap), "Target door ID",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _zone_overworld_region_edit.visible:
        draw_string(font, Vector2(_zone_overworld_region_edit.position.x, _zone_overworld_region_edit.position.y - label_gap), "Overworld region",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _zone_required_item_edit.visible:
        draw_string(font, Vector2(_zone_required_item_edit.position.x, _zone_required_item_edit.position.y - label_gap), "Required item",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _zone_required_item_count_edit.visible:
        draw_string(font, Vector2(_zone_required_item_count_edit.position.x, _zone_required_item_count_edit.position.y - label_gap), "Item count",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _zone_required_var_name_edit.visible:
        draw_string(font, Vector2(_zone_required_var_name_edit.position.x, _zone_required_var_name_edit.position.y - label_gap), "Required var",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _zone_required_var_value_edit.visible:
        draw_string(font, Vector2(_zone_required_var_value_edit.position.x, _zone_required_var_value_edit.position.y - label_gap), "Var value",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _zone_required_tag_edit.visible:
        draw_string(font, Vector2(_zone_required_tag_edit.position.x, _zone_required_tag_edit.position.y - label_gap), "Required global tag",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _zone_blocked_event_edit.visible:
        draw_string(font, Vector2(_zone_blocked_event_edit.position.x, _zone_blocked_event_edit.position.y - label_gap), "Blocked event",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _zone_success_event_edit.visible:
        draw_string(font, Vector2(_zone_success_event_edit.position.x, _zone_success_event_edit.position.y - label_gap), "Success event",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _zone_arrive_event_edit.visible:
        draw_string(font, Vector2(_zone_arrive_event_edit.position.x, _zone_arrive_event_edit.position.y - label_gap), "Arrive event",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _zone_prompt_edit.visible:
        draw_string(font, Vector2(_zone_prompt_edit.position.x, _zone_prompt_edit.position.y - label_gap), "Prompt",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)
    if _zone_event_edit.visible:
        draw_string(font, Vector2(_zone_event_edit.position.x, _zone_event_edit.position.y - label_gap), "Event",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)

    var selected: Dictionary = editor.get_selected_zone() if editor.has_method("get_selected_zone") else {}
    var info_top := _fx_backward_btn.position.y + _fx_backward_btn.size.y + 18.0
    var info_rect := Rect2(pad, info_top, full_w, 100.0)
    draw_rect(info_rect, Color(0.08, 0.1, 0.14, 0.92))
    draw_rect(info_rect, Color(0.34, 0.46, 0.78, 0.95), false, 1.5)
    draw_string(font, info_rect.position + Vector2(12, 20),
        "Selected Zone", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPanels.TEXT_PANEL)
    var selected_label := "(none)"
    if not selected.is_empty():
        selected_label = "%s (%s)" % [str(selected.get("name", selected.get("id", "(unnamed)"))), str(selected.get("kind", ""))]
    draw_string(font, info_rect.position + Vector2(12, 40),
        selected_label, HORIZONTAL_ALIGNMENT_LEFT, info_rect.size.x - 24.0, 11, Color(0.96, 0.94, 0.88, 1.0))
    draw_string(font, info_rect.position + Vector2(12, 60),
        "Zones are now the unified rect tool for doors, shaders, prompts, and triggers.",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.76, 0.8, 0.9, 1.0))
    draw_string(font, info_rect.position + Vector2(12, 74),
        "Door zones link by door ID, then export runtime room/spawn data automatically.",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.72, 0.76, 0.84, 1.0))
    draw_string(font, info_rect.position + Vector2(12, 88),
        "Interact zones store prompt + event data; prompt UI wiring can consume it separately.",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.72, 0.8, 0.86, 1.0))

    if info_rect.has_point(mouse_pos):
        EditorTooltip.show_text("Use PAINT to draw zones, then edit the selected zone's kind, ID, rect, and kind-specific behavior here. Door links should point at another door ID.")


func _on_zone_kind_selected(idx: int) -> void:
    if editor == null or _zone_kind_picker == null or idx < 0:
        return
    _apply_zone_identity_fields()
    if editor.has_method("set_selected_zone_kind"):
        editor.set_selected_zone_kind(str(_zone_kind_picker.get_item_metadata(idx)))


func _on_zone_direction_selected(idx: int) -> void:
    if editor == null or _zone_direction_picker == null or idx < 0:
        return
    _apply_zone_identity_fields()
    if editor.has_method("set_selected_door_direction"):
        editor.set_selected_door_direction(str(_zone_direction_picker.get_item_metadata(idx)))


func _on_zone_overworld_toggled(pressed: bool) -> void:
    _apply_zone_identity_fields()
    if editor != null and editor.has_method("set_selected_door_send_to_overworld"):
        editor.set_selected_door_send_to_overworld(pressed)


func _on_zone_target_submitted(text: String) -> void:
    _apply_zone_identity_fields()
    if editor != null and editor.has_method("set_selected_door_target_room"):
        editor.set_selected_door_target_room(text.strip_edges())


func _on_zone_target_focus_exited() -> void:
    if _zone_target_edit == null:
        return
    _on_zone_target_submitted(_zone_target_edit.text)


func _on_zone_state_toggle_changed(_pressed: bool) -> void:
    if editor == null or not _is_fx_mode():
        return
    _on_fx_apply_pressed()


func _apply_zone_identity_fields() -> void:
    if editor == null or not editor.has_method("get_selected_zone") or not editor.has_method("update_selected_zone"):
        return
    var selected: Dictionary = editor.get_selected_zone()
    if selected.is_empty():
        return
    var kind := str(selected.get("kind", "")).strip_edges().to_lower()
    var identity_text := _zone_name_edit.text.strip_edges() if _zone_name_edit != null else str(selected.get("name", ""))
    var zone_id := identity_text if kind == "door" else (_zone_id_edit.text.strip_edges() if _zone_id_edit != null else str(selected.get("id", "")))
    editor.update_selected_zone({
        "name": identity_text,
        "id": zone_id,
    })


func _on_zone_name_submitted(_text: String) -> void:
    _apply_zone_identity_fields()


func _on_zone_name_focus_exited() -> void:
    _apply_zone_identity_fields()


func _on_zone_id_submitted(_text: String) -> void:
    _apply_zone_identity_fields()


func _on_zone_id_focus_exited() -> void:
    _apply_zone_identity_fields()


func _on_bg_asset_selected(idx: int) -> void:
    if _bg_asset_picker == null or editor == null or idx <= 0:
        return
    editor.set_selected_background_asset(str(_bg_asset_picker.get_item_metadata(idx)))


func _on_bg_import_pressed() -> void:
    if _bg_import_dialog != null:
        _bg_import_dialog.popup_centered_ratio(0.72)


func _on_bg_import_files_selected(paths: PackedStringArray) -> void:
    if editor == null or paths.is_empty():
        return
    var imported := EnvIO.import_backdrops(str(editor.pack_id), paths)
    if not imported.is_empty():
        editor.set_selected_background_asset(str(imported[0]))
    _bg_last_asset_list.clear()
    _refresh_bg_asset_picker()


func _parse_bg_float(le: LineEdit, fallback: float) -> float:
    if le == null:
        return fallback
    var text := le.text.strip_edges()
    if text.is_empty() or not text.is_valid_float():
        return fallback
    return float(text)


func _parse_bg_int(le: LineEdit, fallback: int) -> int:
    if le == null:
        return fallback
    var text := le.text.strip_edges()
    if text.is_empty() or not text.is_valid_int():
        return fallback
    return int(text)


func _on_bg_apply_pressed() -> void:
    if editor == null:
        return
    var selected: Dictionary = editor.get_selected_background_image() if editor.has_method("get_selected_background_image") else {}
    if selected.is_empty():
        return
    editor.update_selected_background_image({
        "image": editor.get_selected_background_asset(),
        "x_blocks": _parse_bg_float(_bg_x_edit, float(selected.get("x_blocks", 0.0))),
        "y_blocks": _parse_bg_float(_bg_y_edit, float(selected.get("y_blocks", 0.0))),
        "width_blocks": _parse_bg_float(_bg_w_edit, float(selected.get("width_blocks", 0.0))),
        "height_blocks": _parse_bg_float(_bg_h_edit, float(selected.get("height_blocks", 0.0))),
        "scroll_speed_x": _parse_bg_float(_bg_sx_edit, float(selected.get("scroll_speed_x", 1.0))),
        "scroll_speed_y": _parse_bg_float(_bg_sy_edit, float(selected.get("scroll_speed_y", 1.0))),
        "anim_frames": _parse_bg_int(_bg_frames_edit, int(selected.get("anim_frames", 1))),
        "anim_fps": _parse_bg_float(_bg_fps_edit, float(selected.get("anim_fps", 0.0))),
    })


func _on_bg_delete_pressed() -> void:
    if editor != null:
        editor.delete_selected_background_image()


func _on_bg_forward_pressed() -> void:
    if editor != null:
        editor.reorder_selected_background_image(1)


func _on_bg_backward_pressed() -> void:
    if editor != null:
        editor.reorder_selected_background_image(-1)


func _on_bg_merge_pressed() -> void:
    if editor != null and editor.has_method("merge_background_images_to_baked"):
        editor.merge_background_images_to_baked()


func _on_fx_apply_pressed() -> void:
    if editor == null:
        return
    var selected: Dictionary = editor.get_selected_zone() if editor.has_method("get_selected_zone") else {}
    if selected.is_empty():
        return
    var kind := _selected_shader_id(_zone_kind_picker, str(selected.get("kind", "shader")))
    var identity_text := _zone_name_edit.text.strip_edges() if _zone_name_edit != null else str(selected.get("name", ""))
    var zone_id := identity_text if kind == "door" else (_zone_id_edit.text.strip_edges() if _zone_id_edit != null else str(selected.get("id", "")))
    editor.update_selected_zone({
        "kind": kind,
        "name": identity_text,
        "id": zone_id,
        "x_blocks": _parse_bg_float(_fx_x_edit, float(selected.get("x_blocks", 0.0))),
        "y_blocks": _parse_bg_float(_fx_y_edit, float(selected.get("y_blocks", 0.0))),
        "width_blocks": _parse_bg_float(_fx_w_edit, float(selected.get("width_blocks", 0.0))),
        "height_blocks": _parse_bg_float(_fx_h_edit, float(selected.get("height_blocks", 0.0))),
        "shader_preset": _selected_shader_id(_fx_shader_picker, "flicker"),
        "shader_tint": _fx_tint_btn.color.to_html(true) if _fx_tint_btn != null else "ffffff",
        "shader_strength": _parse_bg_float(_fx_strength_edit, float(selected.get("shader_strength", 0.6))),
        "shader_speed": _parse_bg_float(_fx_speed_edit, float(selected.get("shader_speed", 1.0))),
        "direction": _selected_shader_id(_zone_direction_picker, str(selected.get("direction", "right"))),
        "target_door_id": _zone_target_edit.text.strip_edges() if _zone_target_edit != null else str(selected.get("target_door_id", selected.get("target_room", ""))),
        "target_room": "",
        "send_to_overworld": _zone_overworld_toggle.button_pressed if _zone_overworld_toggle != null else bool(selected.get("send_to_overworld", false)),
        "overworld_region_id": _zone_overworld_region_edit.text.strip_edges() if _zone_overworld_region_edit != null else str(selected.get("overworld_region_id", "")),
        "enabled": _zone_enabled_toggle.button_pressed if _zone_enabled_toggle != null else bool(selected.get("enabled", true)),
        "locked": _zone_locked_toggle.button_pressed if _zone_locked_toggle != null else bool(selected.get("locked", false)),
        "required_item_id": _zone_required_item_edit.text.strip_edges() if _zone_required_item_edit != null else str(selected.get("required_item_id", "")),
        "required_item_count": int(_zone_required_item_count_edit.text) if _zone_required_item_count_edit != null and not _zone_required_item_count_edit.text.strip_edges().is_empty() else int(selected.get("required_item_count", 1)),
        "required_var_name": _zone_required_var_name_edit.text.strip_edges() if _zone_required_var_name_edit != null else str(selected.get("required_var_name", "")),
        "required_var_value": _zone_required_var_value_edit.text.strip_edges() if _zone_required_var_value_edit != null and not _zone_required_var_value_edit.text.strip_edges().is_empty() else selected.get("required_var_value", 1),
        "required_global_tag": _zone_required_tag_edit.text.strip_edges() if _zone_required_tag_edit != null else str(selected.get("required_global_tag", "")),
        "blocked_event_name": _zone_blocked_event_edit.text.strip_edges() if _zone_blocked_event_edit != null else str(selected.get("blocked_event_name", "")),
        "success_event_name": _zone_success_event_edit.text.strip_edges() if _zone_success_event_edit != null else str(selected.get("success_event_name", "")),
        "arrive_event_name": _zone_arrive_event_edit.text.strip_edges() if _zone_arrive_event_edit != null else str(selected.get("arrive_event_name", "")),
        "prompt_text": _zone_prompt_edit.text.strip_edges() if _zone_prompt_edit != null else str(selected.get("prompt_text", "Interact")),
        "event_name": _zone_event_edit.text.strip_edges() if _zone_event_edit != null else str(selected.get("event_name", "zone_enter")),
        "once": _zone_once_toggle.button_pressed if _zone_once_toggle != null else bool(selected.get("once", false)),
        "interaction_mode": "interact" if kind == "interact" else "enter",
    })


func _on_fx_delete_pressed() -> void:
    if editor != null:
        editor.delete_selected_zone()


func _on_fx_forward_pressed() -> void:
    if editor != null:
        editor.reorder_selected_zone(1)


func _on_fx_backward_pressed() -> void:
    if editor != null:
        editor.reorder_selected_zone(-1)
