extends Control

const UIPanels := preload("res://Space/scripts/ui/ui_panels.gd")
const PedIO := preload("res://Space/scripts/editor/ped/ped_io.gd")
const EcaSchema := preload("res://Space/scripts/editor/dlg/eca_schema.gd")
const EditorUndoLib = preload("res://Space/scripts/editor/editor_undo.gd")
const DlgConditionsListFormLib := preload("res://Space/scripts/editor/dlg/conditions_list_form.gd")
const DlgActionsFormLib := preload("res://Space/scripts/editor/dlg/actions_form.gd")
const TriggerLocalsFormLib := preload("res://Space/scripts/editor/dlg/trigger_locals_form.gd")
const TriggerDebuggerWindowLib := preload("res://Space/scripts/editor/dlg/trigger_debugger_window.gd")
const TriggerRoot := preload("res://Space/scripts/shared/trigger_root.gd")

signal status_changed(text: String)
signal closed
signal camera_preview_changed(preview_items: Array)
signal camera_preview_cleared

var _pack_id: String = ""
var _root: Dictionary = TriggerRoot.default_root()
var _selected: int = -1
var _dirty: bool = false
var _suppress: bool = false
var _save_callback: Callable = Callable()
var _current_library_idx: int = -1
var _current_folder_idx: int = -1

var _tutorial_btn: Button = null
var _tutorial_overlay: Control = null
var _undo: RefCounted = null

var _library_option: OptionButton = null
var _library_name_edit: LineEdit = null
var _folder_option: OptionButton = null
var _folder_name_edit: LineEdit = null
var _list: ItemList = null
var _detail: VBoxContainer = null
var _id_edit: LineEdit = null
var _event_edit: OptionButton = null
var _event_custom_edit: LineEdit = null
var _enabled_check: CheckBox = null
var _once_check: CheckBox = null
var _breakpoint_check: CheckBox = null
var _workflow_label: Label = null
var _summary_label: Label = null
var _locals_form: TriggerLocalsForm = null
var _cond_form: DlgConditionsListForm = null
var _action_form: DlgActionsForm = null
var _debug_view: RichTextLabel = null
var _debugger_window: Control = null
var _scope_transfer_dialog: ConfirmationDialog = null
var _scope_transfer_option: OptionButton = null
var _scope_transfer_mode: String = "move"
var _scope_tree: Tree = null
var _current_folder_path: Array = []
var _main_split: HSplitContainer = null

const MODAL_MARGIN_X: float = 18.0
const MODAL_MARGIN_TOP: float = 44.0
const MODAL_MARGIN_BOTTOM: float = 18.0
const PANEL_INSET: float = 14.0


func request_close() -> void:
    visible = false
    closed.emit()


func open(pack_id: String) -> void:
    _pack_id = pack_id
    _save_callback = Callable()
    _set_root_value(PedIO.load_triggers(pack_id))


func open_editor(pack_id: String) -> void:
    open(pack_id)
    visible = true
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)


func open_with_rules(pack_id: String, rules: Array, save_callback: Callable = Callable()) -> void:
    open_with_root(pack_id, rules, save_callback)


func open_with_root(pack_id: String, root_value: Variant, save_callback: Callable = Callable()) -> void:
    _pack_id = pack_id
    _save_callback = save_callback
    _set_root_value(root_value)


func get_root_value() -> Dictionary:
    _flush_detail()
    return _root.duplicate(true)


func get_rules_value() -> Array:
    return TriggerRoot.flatten_rules(get_root_value())


func save() -> bool:
    if not _flush_detail():
        return false
    var payload: Dictionary = _root.duplicate(true)
    if _save_callback.is_valid():
        _save_callback.call(payload)
        _dirty = false
        status_changed.emit("Triggers saved")
        return true
    if PedIO.save_triggers(_pack_id, payload):
        _dirty = false
        status_changed.emit("Triggers saved")
        return true
    status_changed.emit("Trigger save failed validation; save aborted")
    return false


func is_dirty() -> bool:
    return _dirty


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_STOP
    set_process(true)
    _undo = EditorUndoLib.new(_capture_state, _apply_state)
    _build_ui()
    if MvTriggerEngine != null and MvTriggerEngine.has_signal("debug_state_changed") and not MvTriggerEngine.debug_state_changed.is_connected(_on_runtime_debug_changed):
        MvTriggerEngine.debug_state_changed.connect(_on_runtime_debug_changed)


func _process(_delta: float) -> void:
    if visible:
        queue_redraw()


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _layout_ui()


func _capture_state() -> Dictionary:
    return {
        "root": _root.duplicate(true),
        "selected": _selected,
        "library_idx": _current_library_idx,
        "folder_idx": _current_folder_idx,
        "folder_path": _current_folder_path.duplicate(),
        "dirty": _dirty,
    }


func _apply_state(snap: Dictionary) -> void:
    _root = TriggerRoot.normalize_root(snap.get("root", TriggerRoot.default_root()))
    _selected = int(snap.get("selected", -1))
    _current_library_idx = int(snap.get("library_idx", -1))
    _current_folder_idx = int(snap.get("folder_idx", -1))
    _current_folder_path = _safe_array(snap.get("folder_path", []))
    _dirty = bool(snap.get("dirty", false))
    _rebuild_all()


func _build_ui() -> void:
    var split := HSplitContainer.new()
    split.split_offset = 320
    split.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(split)
    _main_split = split

    var left := VBoxContainer.new()
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.add_child(left)

    var btn_row := HBoxContainer.new()
    left.add_child(btn_row)

    var back_btn := Button.new()
    back_btn.text = "Back"
    back_btn.tooltip_text = "Close the trigger editor and return to the previous editor view. Unsaved trigger changes remain in memory until you discard them or leave the editor."
    back_btn.pressed.connect(request_close)
    btn_row.add_child(back_btn)

    var save_btn := Button.new()
    save_btn.text = "Save"
    save_btn.tooltip_text = "Validate the current trigger root and save it back to the pack or room-local callback target."
    save_btn.pressed.connect(save)
    btn_row.add_child(save_btn)

    var add_rule_btn := Button.new()
    add_rule_btn.text = "+ New Rule"
    add_rule_btn.tooltip_text = "Add a new: When this happens, if these checks pass, do these actions."
    add_rule_btn.pressed.connect(_on_add_rule)
    btn_row.add_child(add_rule_btn)

    var dup_rule_btn := Button.new()
    dup_rule_btn.text = "Duplicate"
    dup_rule_btn.tooltip_text = "Duplicate the selected rule into the current scope and give it a fresh id."
    dup_rule_btn.pressed.connect(_on_duplicate_rule)
    btn_row.add_child(dup_rule_btn)

    var del_rule_btn := Button.new()
    del_rule_btn.text = "Delete Rule"
    del_rule_btn.tooltip_text = "Delete the currently selected rule from this scope."
    del_rule_btn.pressed.connect(_on_delete_rule)
    btn_row.add_child(del_rule_btn)

    var debugger_btn := Button.new()
    debugger_btn.text = "Debugger"
    debugger_btn.tooltip_text = "Open the live trigger debugger window with history, breakpoints, and active sequence inspection."
    debugger_btn.pressed.connect(_on_open_debugger)
    btn_row.add_child(debugger_btn)

    var tooltip_toggle := CheckButton.new()
    tooltip_toggle.text = "Tooltips"
    tooltip_toggle.tooltip_text = "Toggle trigger-editor tooltips."
    tooltip_toggle.button_pressed = EditorTooltip.enabled
    tooltip_toggle.toggled.connect(func(on: bool): EditorTooltip.set_enabled(on))
    tooltip_toggle.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
    tooltip_toggle.add_theme_font_size_override("font_size", 11)
    btn_row.add_child(tooltip_toggle)

    _tutorial_btn = Button.new()
    _tutorial_btn.text = "TUTORIAL"
    _tutorial_btn.tooltip_text = "Open the trigger editor tutorial and authoring quick-reference."
    _tutorial_btn.pressed.connect(_on_tutorial_pressed)
    btn_row.add_child(_tutorial_btn)

    _tutorial_overlay = Control.new()
    _tutorial_overlay.set_script(preload("res://Space/scripts/editor/editor_tutorial.gd"))
    _tutorial_overlay.visible = false
    _tutorial_overlay.set_anchors_preset(PRESET_FULL_RECT)
    add_child(_tutorial_overlay)

    _debugger_window = TriggerDebuggerWindowLib.new()
    add_child(_debugger_window)

    left.add_child(_build_scope_row("Library", true))
    left.add_child(_build_scope_row("Folder", false))

    var scope_tree_label := Label.new()
    scope_tree_label.text = "Trigger folders"
    left.add_child(scope_tree_label)

    _scope_tree = Tree.new()
    _scope_tree.custom_minimum_size = Vector2(0, 170)
    _scope_tree.tooltip_text = "Folders for organizing trigger rules. Select a folder to edit the rules stored inside it."
    _scope_tree.item_selected.connect(_on_scope_tree_selected)
    left.add_child(_scope_tree)

    var list_label := Label.new()
    list_label.text = "Rules here"
    left.add_child(list_label)

    _list = ItemList.new()
    _list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _list.tooltip_text = "Rules in the selected folder. Select one to edit its event, checks, and actions."
    _list.item_selected.connect(_on_select)
    left.add_child(_list)

    var list_tools := HBoxContainer.new()
    left.add_child(list_tools)

    var up_btn := Button.new()
    up_btn.text = "Up"
    up_btn.tooltip_text = "Move the selected rule earlier in execution order within this scope."
    up_btn.pressed.connect(_on_move_rule_up)
    list_tools.add_child(up_btn)

    var down_btn := Button.new()
    down_btn.text = "Down"
    down_btn.tooltip_text = "Move the selected rule later in execution order within this scope."
    down_btn.pressed.connect(_on_move_rule_down)
    list_tools.add_child(down_btn)

    var move_btn := Button.new()
    move_btn.text = "Move..."
    move_btn.tooltip_text = "Move the selected rule into another library or folder scope."
    move_btn.pressed.connect(_on_move_rule_to_scope)
    list_tools.add_child(move_btn)

    var copy_btn := Button.new()
    copy_btn.text = "Copy..."
    copy_btn.tooltip_text = "Copy the selected rule into another library or folder scope."
    copy_btn.pressed.connect(_on_copy_rule_to_scope)
    list_tools.add_child(copy_btn)

    var right := ScrollContainer.new()
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.add_child(right)

    _detail = VBoxContainer.new()
    _detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _detail.add_theme_constant_override("separation", 8)
    right.add_child(_detail)

    _workflow_label = Label.new()
    _workflow_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _workflow_label.add_theme_font_size_override("font_size", 10)
    _workflow_label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.9))
    _detail.add_child(_workflow_label)
    _refresh_workflow_help()

    _add_label("Rule name")
    _id_edit = LineEdit.new()
    _id_edit.placeholder_text = "intro_bootstrap"
    _id_edit.tooltip_text = "Stable name for this rule. Use something descriptive because breakpoints and debug history reference it."
    _id_edit.text_changed.connect(_on_rule_field_changed)
    _detail.add_child(_id_edit)

    _add_label("When should this rule start?")
    _event_edit = OptionButton.new()
    for ev in EcaSchema.event_type_names():
        _event_edit.add_item(EcaSchema.event_label(str(ev)))
    _event_edit.tooltip_text = "Choose what has to happen before this rule is considered."
    _event_edit.item_selected.connect(_on_event_field_changed)
    _detail.add_child(_event_edit)

    _event_custom_edit = LineEdit.new()
    _event_custom_edit.placeholder_text = "Advanced: custom event name"
    _event_custom_edit.tooltip_text = "Advanced custom event name. Leave blank to use the selected built-in event."
    _event_custom_edit.text_changed.connect(_on_event_field_changed)
    _detail.add_child(_event_custom_edit)

    var state_row := HBoxContainer.new()
    _detail.add_child(state_row)
    _enabled_check = CheckBox.new()
    _enabled_check.text = "Enabled"
    _enabled_check.button_pressed = true
    _enabled_check.tooltip_text = "Disable a rule without deleting it."
    _enabled_check.toggled.connect(_on_rule_field_changed)
    state_row.add_child(_enabled_check)
    _once_check = CheckBox.new()
    _once_check.text = "Run Once"
    _once_check.tooltip_text = "Automatically disable this rule after its first successful match."
    _once_check.toggled.connect(_on_rule_field_changed)
    state_row.add_child(_once_check)
    _breakpoint_check = CheckBox.new()
    _breakpoint_check.text = "Breakpoint"
    _breakpoint_check.tooltip_text = "Pause trigger execution when this rule matches so you can inspect state in the debugger."
    _breakpoint_check.toggled.connect(_on_breakpoint_toggled)
    state_row.add_child(_breakpoint_check)

    _summary_label = Label.new()
    _summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _summary_label.add_theme_font_size_override("font_size", 10)
    _summary_label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.9))
    _summary_label.tooltip_text = "Readable summary of what starts this rule and what it does."
    _detail.add_child(_summary_label)

    _add_label("Temporary memory")
    var locals_hint := Label.new()
    locals_hint.text = "Optional values this rule can remember while it is running. They reset each time the rule starts."
    locals_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    locals_hint.add_theme_font_size_override("font_size", 10)
    locals_hint.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
    _detail.add_child(locals_hint)
    _locals_form = TriggerLocalsFormLib.new()
    _locals_form.changed.connect(_on_rule_field_changed)
    _detail.add_child(_locals_form)

    _add_label("Only run if")
    var cond_hint := Label.new()
    cond_hint.text = "Add checks here when the event should only matter in certain cases."
    cond_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    cond_hint.add_theme_font_size_override("font_size", 10)
    cond_hint.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
    _detail.add_child(cond_hint)
    _cond_form = DlgConditionsListFormLib.new()
    _cond_form.changed.connect(_on_rule_field_changed)
    _detail.add_child(_cond_form)

    _add_label("Do these actions")
    var act_hint := Label.new()
    act_hint.text = "Actions run from top to bottom. Wait actions pause this rule before continuing."
    act_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    act_hint.add_theme_font_size_override("font_size", 10)
    act_hint.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
    _detail.add_child(act_hint)
    _action_form = DlgActionsFormLib.new()
    _action_form.changed.connect(_on_rule_field_changed)
    _detail.add_child(_action_form)

    _add_label("Runtime Debug")
    var debug_row := HBoxContainer.new()
    _detail.add_child(debug_row)
    var refresh_btn := Button.new()
    refresh_btn.text = "Refresh Debug"
    refresh_btn.tooltip_text = "Refresh the inline runtime debug summary from the live trigger engine."
    refresh_btn.pressed.connect(_refresh_debug_view)
    debug_row.add_child(refresh_btn)
    var clear_btn := Button.new()
    clear_btn.text = "Clear Debug"
    clear_btn.tooltip_text = "Clear inline trigger debug history."
    clear_btn.pressed.connect(_clear_debug_view)
    debug_row.add_child(clear_btn)
    _debug_view = RichTextLabel.new()
    _debug_view.custom_minimum_size = Vector2(0, 180)
    _debug_view.scroll_active = true
    _debug_view.tooltip_text = "Recent runtime trigger history and pause state for quick inline inspection."
    _detail.add_child(_debug_view)
    _refresh_debug_view()

    _scope_transfer_dialog = ConfirmationDialog.new()
    _scope_transfer_dialog.title = "Move Trigger Rule"
    _scope_transfer_dialog.confirmed.connect(_on_scope_transfer_confirmed)
    add_child(_scope_transfer_dialog)

    var transfer_box := VBoxContainer.new()
    _scope_transfer_dialog.add_child(transfer_box)

    var transfer_label := Label.new()
    transfer_label.text = "Target scope"
    transfer_box.add_child(transfer_label)

    _scope_transfer_option = OptionButton.new()
    _scope_transfer_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _scope_transfer_option.tooltip_text = "Choose the library or folder scope that should receive the selected rule."
    transfer_box.add_child(_scope_transfer_option)

    _layout_ui()


func _layout_ui() -> void:
    if _main_split == null:
        return
    _main_split.anchor_left = 0.0
    _main_split.anchor_top = 0.0
    _main_split.anchor_right = 1.0
    _main_split.anchor_bottom = 1.0
    _main_split.offset_left = MODAL_MARGIN_X + PANEL_INSET
    _main_split.offset_top = MODAL_MARGIN_TOP + PANEL_INSET
    _main_split.offset_right = -(MODAL_MARGIN_X + PANEL_INSET)
    _main_split.offset_bottom = -(MODAL_MARGIN_BOTTOM + PANEL_INSET)
    if _tutorial_overlay != null:
        _tutorial_overlay.anchor_left = 0.0
        _tutorial_overlay.anchor_top = 0.0
        _tutorial_overlay.anchor_right = 1.0
        _tutorial_overlay.anchor_bottom = 1.0
        _tutorial_overlay.offset_left = 0.0
        _tutorial_overlay.offset_top = 0.0
        _tutorial_overlay.offset_right = 0.0
        _tutorial_overlay.offset_bottom = 0.0


func _draw() -> void:
    if not visible:
        return
    UIPanels.draw_dim(self, Rect2(Vector2.ZERO, size), 0.72)
    var panel_rect := Rect2(
        Vector2(MODAL_MARGIN_X, MODAL_MARGIN_TOP),
        Vector2(
            maxf(0.0, size.x - MODAL_MARGIN_X * 2.0),
            maxf(0.0, size.y - MODAL_MARGIN_TOP - MODAL_MARGIN_BOTTOM)
        )
    )
    UIPanels.draw_panel(self, panel_rect, Color.WHITE, UIPanels.PanelVariant.DARK)


func _build_scope_row(label_text: String, is_library: bool) -> Control:
    var box := VBoxContainer.new()
    var label := Label.new()
    label.text = label_text
    box.add_child(label)

    var row := HBoxContainer.new()
    box.add_child(row)

    var option := OptionButton.new()
    option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    option.tooltip_text = "Select the active %s scope." % label_text.to_lower()
    row.add_child(option)

    var add_btn := Button.new()
    add_btn.text = "+"
    add_btn.tooltip_text = "Create a new %s under the current scope." % label_text.to_lower()
    row.add_child(add_btn)

    var del_btn := Button.new()
    del_btn.text = "X"
    del_btn.tooltip_text = "Delete the selected %s." % label_text.to_lower()
    row.add_child(del_btn)

    var up_btn := Button.new()
    up_btn.text = "^"
    up_btn.tooltip_text = "Move the selected %s earlier in the list." % label_text.to_lower()
    row.add_child(up_btn)

    var down_btn := Button.new()
    down_btn.text = "v"
    down_btn.tooltip_text = "Move the selected %s later in the list." % label_text.to_lower()
    row.add_child(down_btn)

    var name_edit := LineEdit.new()
    name_edit.placeholder_text = "%s name" % label_text.to_lower()
    name_edit.tooltip_text = "Rename the selected %s. Names are for authoring organization; ids remain separate." % label_text.to_lower()
    box.add_child(name_edit)

    if is_library:
        _library_option = option
        _library_name_edit = name_edit
        _library_option.item_selected.connect(_on_library_selected)
        _library_name_edit.text_changed.connect(_on_library_name_changed)
        add_btn.pressed.connect(_on_add_library)
        del_btn.pressed.connect(_on_delete_library)
        up_btn.pressed.connect(_on_move_library_up)
        down_btn.pressed.connect(_on_move_library_down)
    else:
        _folder_option = option
        _folder_name_edit = name_edit
        _folder_option.item_selected.connect(_on_folder_selected)
        _folder_name_edit.text_changed.connect(_on_folder_name_changed)
        add_btn.pressed.connect(_on_add_folder)
        del_btn.pressed.connect(_on_delete_folder)
        up_btn.pressed.connect(_on_move_folder_up)
        down_btn.pressed.connect(_on_move_folder_down)
    return box


func _add_label(text: String) -> void:
    var lbl := Label.new()
    lbl.text = text
    lbl.add_theme_font_size_override("font_size", 11)
    _detail.add_child(lbl)


func _set_root_value(value: Variant) -> void:
    _root = TriggerRoot.normalize_root(value)
    _selected = -1
    _current_library_idx = -1
    _current_folder_idx = -1
    _current_folder_path = []
    _dirty = false
    if _undo != null:
        _undo.clear()
    _rebuild_all()


func _rebuild_all() -> void:
    _populate_library_selector()
    _populate_folder_selector()
    _populate_scope_tree()
    _rebuild_list()
    _refresh_debug_view()


func _library_array() -> Array:
    return _root.get("libraries", [])


func _current_library() -> Dictionary:
    var libs := _library_array()
    if _current_library_idx < 0 or _current_library_idx >= libs.size():
        return {}
    var lib_v: Variant = libs[_current_library_idx]
    return lib_v if typeof(lib_v) == TYPE_DICTIONARY else {}


func _current_folder() -> Dictionary:
    var lib := _current_library()
    if lib.is_empty():
        return {}
    if _current_folder_path.is_empty():
        return {}
    return _folder_at_path(_safe_array(lib.get("folders", [])), _current_folder_path)


func _current_rules_array() -> Array:
    if _current_library_idx < 0:
        return _root.get("triggers", [])
    if _current_folder_path.is_empty():
        return _current_library().get("triggers", [])
    return _current_folder().get("triggers", [])


func _folder_at_path(folders: Array, path: Array) -> Dictionary:
    var current_folders: Array = folders
    var current: Dictionary = {}
    for idx_v in path:
        var idx: int = int(idx_v)
        if idx < 0 or idx >= current_folders.size():
            return {}
        var folder_v: Variant = current_folders[idx]
        if typeof(folder_v) != TYPE_DICTIONARY:
            return {}
        current = folder_v
        current_folders = _safe_array(current.get("folders", []))
    return current


func _folder_children_array(path: Array) -> Array:
    if _current_library_idx < 0:
        return []
    var libs := _library_array()
    if _current_library_idx >= libs.size():
        return []
    var lib: Dictionary = libs[_current_library_idx]
    if path.is_empty():
        return _safe_array(lib.get("folders", []))
    var folder := _folder_at_path(_safe_array(lib.get("folders", [])), path)
    if folder.is_empty():
        return []
    return _safe_array(folder.get("folders", []))


func _populate_library_selector() -> void:
    if _library_option == null:
        return
    _library_option.clear()
    _library_option.add_item("Root Rules")
    var libs := _library_array()
    for lib_v in libs:
        var lib: Dictionary = lib_v if typeof(lib_v) == TYPE_DICTIONARY else {}
        _library_option.add_item(str(lib.get("name", "Library")))
    if _current_library_idx >= libs.size():
        _current_library_idx = -1
        _current_folder_path = []
    var select_idx := _current_library_idx + 1
    _library_option.select(maxi(0, select_idx))
    if _library_name_edit != null:
        _library_name_edit.editable = _current_library_idx >= 0
        _library_name_edit.text = "" if _current_library_idx < 0 else str(_current_library().get("name", ""))


func _populate_folder_selector() -> void:
    if _folder_option == null:
        return
    _folder_option.clear()
    _folder_option.add_item("Use trigger folders")
    _folder_option.select(0)
    _folder_option.disabled = true
    if _folder_name_edit != null:
        _folder_name_edit.editable = _current_library_idx >= 0 and not _current_folder_path.is_empty()
        _folder_name_edit.text = "" if _current_folder_path.is_empty() else str(_current_folder().get("name", ""))


func _rebuild_list() -> void:
    if _list == null:
        return
    _list.clear()
    var rules := _current_rules_array()
    for rule_v in rules:
        var rule: Dictionary = rule_v if typeof(rule_v) == TYPE_DICTIONARY else {}
        var label := "%s - %s" % [
            str(rule.get("id", "?")),
            EcaSchema.event_label(str(rule.get("event", ""))),
        ]
        if _rule_has_breakpoint(rule):
            label = "[BP] " + label
        if bool(rule.get("once", false)):
            label += " [once]"
        if not bool(rule.get("enabled", true)):
            label += " [off]"
        _list.add_item(label)
    if _selected >= rules.size():
        _selected = -1
    if _selected >= 0 and _selected < rules.size():
        _list.select(_selected)
        _show_detail(_selected)
    else:
        _clear_detail()


func _populate_scope_tree() -> void:
    if _scope_tree == null:
        return
    _suppress = true
    _scope_tree.clear()
    var root_item := _scope_tree.create_item()
    root_item.set_text(0, "Trigger Folders")
    root_item.set_selectable(0, false)

    var root_rules := _scope_tree.create_item(root_item)
    root_rules.set_text(0, "Rules not in a folder")
    root_rules.set_metadata(0, {"library_idx": -1, "folder_path": []})

    var libs := _library_array()
    for lib_idx in range(libs.size()):
        var lib_v: Variant = libs[lib_idx]
        if typeof(lib_v) != TYPE_DICTIONARY:
            continue
        var lib: Dictionary = lib_v
        var lib_item := _scope_tree.create_item(root_item)
        lib_item.set_text(0, str(lib.get("name", "Library")))
        lib_item.set_metadata(0, {"library_idx": lib_idx, "folder_path": []})
        _populate_scope_tree_folders(lib_item, _safe_array(lib.get("folders", [])), [lib_idx], [])
    _select_scope_tree_item(root_item)
    _suppress = false


func _populate_scope_tree_folders(parent_item: TreeItem, folders: Array, prefix: Array, parent_path: Array) -> void:
    for folder_idx in range(folders.size()):
        var folder_v: Variant = folders[folder_idx]
        if typeof(folder_v) != TYPE_DICTIONARY:
            continue
        var folder: Dictionary = folder_v
        var path: Array = parent_path.duplicate()
        path.append(folder_idx)
        var item := _scope_tree.create_item(parent_item)
        item.set_text(0, str(folder.get("name", "Folder")))
        item.set_metadata(0, {"library_idx": prefix[0], "folder_path": path})
        _populate_scope_tree_folders(item, _safe_array(folder.get("folders", [])), prefix, path)


func _select_scope_tree_item(root_item: TreeItem) -> void:
    if _scope_tree == null:
        return
    var wanted_library_idx: int = _current_library_idx
    var wanted_path: Array = _current_folder_path.duplicate()
    var stack: Array = [root_item]
    while not stack.is_empty():
        var item: TreeItem = stack.pop_back()
        var meta_v: Variant = item.get_metadata(0)
        if typeof(meta_v) == TYPE_DICTIONARY:
            var meta: Dictionary = meta_v
            if int(meta.get("library_idx", -99)) == wanted_library_idx and _paths_equal(_safe_array(meta.get("folder_path", [])), wanted_path):
                item.select(0)
                return
        var child: TreeItem = item.get_first_child()
        while child != null:
            stack.append(child)
            child = child.get_next()
    var fallback := root_item.get_first_child()
    if fallback != null:
        fallback.select(0)


func _selected_rule() -> Dictionary:
    var rules := _current_rules_array()
    if _selected < 0 or _selected >= rules.size():
        return {}
    var rule_v: Variant = rules[_selected]
    return rule_v if typeof(rule_v) == TYPE_DICTIONARY else {}


func _show_detail(idx: int) -> void:
    var rules := _current_rules_array()
    if idx < 0 or idx >= rules.size():
        return
    _suppress = true
    var rule: Dictionary = rules[idx]
    _id_edit.text = str(rule.get("id", ""))
    _set_event_option(str(rule.get("event", "")))
    _enabled_check.button_pressed = bool(rule.get("enabled", true))
    _once_check.button_pressed = bool(rule.get("once", false))
    if _breakpoint_check != null:
        _breakpoint_check.button_pressed = _rule_has_breakpoint(rule)
    _locals_form.open(_safe_array(rule.get("locals", [])))
    _cond_form.open(_safe_array(rule.get("conditions", [])))
    _action_form.open(_safe_array(rule.get("actions", [])))
    _refresh_workflow_help(rule)
    _refresh_summary(rule)
    _update_camera_preview(rule)
    _suppress = false


func _clear_detail() -> void:
    _suppress = true
    if _id_edit != null:
        _id_edit.text = ""
    if _event_edit != null and _event_edit.item_count > 0:
        _event_edit.select(0)
    if _event_custom_edit != null:
        _event_custom_edit.text = ""
    if _enabled_check != null:
        _enabled_check.button_pressed = true
    if _once_check != null:
        _once_check.button_pressed = false
    if _breakpoint_check != null:
        _breakpoint_check.button_pressed = false
    if _locals_form != null:
        _locals_form.open([])
    if _cond_form != null:
        _cond_form.open([])
    if _action_form != null:
        _action_form.open([])
    if _summary_label != null:
        _summary_label.text = ""
    _refresh_workflow_help()
    _update_event_control_tooltips()
    camera_preview_cleared.emit()
    _suppress = false


func _set_event_option(event_name: String) -> void:
    if _event_custom_edit != null:
        _event_custom_edit.text = ""
    var idx := EcaSchema.event_type_names().find(event_name)
    if idx < 0:
        idx = EcaSchema.event_type_names().find("pickup")
        _event_custom_edit.text = event_name
    _event_edit.select(maxi(0, idx))
    _update_event_control_tooltips()


func _on_event_field_changed(_arg: Variant = null) -> void:
    _update_event_control_tooltips()
    _on_rule_field_changed()


func _update_event_control_tooltips() -> void:
    if _event_edit == null:
        return
    var event_name: String = _selected_event_name()
    var help_text: String = EcaSchema.event_help(event_name)
    if help_text.is_empty():
        help_text = "Choose what has to happen before this rule is considered."
    _event_edit.tooltip_text = help_text
    if _event_custom_edit != null:
        var custom_hint := "Advanced custom event name. Leave blank to use the selected built-in event."
        if not event_name.is_empty():
            custom_hint += " Current event: %s." % EcaSchema.event_label(event_name)
        if not help_text.is_empty():
            custom_hint += " " + help_text
        _event_custom_edit.tooltip_text = custom_hint
    _refresh_workflow_help()


func _flush_detail() -> bool:
    var rules := _current_rules_array()
    if _selected < 0 or _selected >= rules.size():
        return true
    if _locals_form != null and _locals_form.has_error():
        status_changed.emit("Trigger locals are invalid: %s" % _locals_form.error_text())
        return false
    if _cond_form != null and _cond_form.has_error():
        status_changed.emit("Trigger conditions are invalid: %s" % _cond_form.error_text())
        return false
    if _action_form != null and _action_form.has_error():
        status_changed.emit("Trigger actions are invalid: %s" % _action_form.error_text())
        return false
    var rule: Dictionary = rules[_selected]
    rule["id"] = _id_edit.text.strip_edges()
    rule["event"] = _selected_event_name()
    rule["enabled"] = _enabled_check.button_pressed
    rule["once"] = _once_check.button_pressed
    rule["locals"] = _locals_form.get_value()
    rule["conditions"] = _cond_form.get_value()
    rule["actions"] = _action_form.get_value()
    _refresh_workflow_help(rule)
    _refresh_summary(rule)
    return true


func _on_add_library() -> void:
    if _undo != null:
        _undo.begin()
    var libs := _library_array()
    var new_lib := {
        "id": _unique_scope_id(libs, "library"),
        "name": "New Library",
        "triggers": [],
        "folders": [],
    }
    libs.append(new_lib)
    _root["libraries"] = libs
    _current_library_idx = libs.size() - 1
    _current_folder_idx = -1
    _selected = -1
    _mark_dirty()
    _rebuild_all()
    if _undo != null:
        _undo.commit("add trigger library")


func _on_delete_library() -> void:
    if _current_library_idx < 0:
        return
    if _undo != null:
        _undo.begin()
    var libs := _library_array()
    libs.remove_at(_current_library_idx)
    _root["libraries"] = libs
    _current_library_idx = -1
    _current_folder_idx = -1
    _selected = -1
    _mark_dirty()
    _rebuild_all()
    if _undo != null:
        _undo.commit("delete trigger library")


func _on_move_library_up() -> void:
    _move_library_by(-1)


func _on_move_library_down() -> void:
    _move_library_by(1)


func _on_add_folder() -> void:
    if _current_library_idx < 0:
        return
    if _undo != null:
        _undo.begin()
    var sibling_folders: Array = _folder_children_array(_current_folder_path)
    var new_idx: int = sibling_folders.size()
    var new_folder := {
        "id": _unique_scope_id(sibling_folders, "folder"),
        "name": "New Folder",
        "triggers": [],
        "folders": [],
    }
    _append_folder_to_current_scope(new_folder)
    _current_folder_path.append(new_idx)
    _current_folder_idx = int(_current_folder_path[_current_folder_path.size() - 1])
    _selected = -1
    _mark_dirty()
    _rebuild_all()
    if _undo != null:
        _undo.commit("add trigger folder")


func _on_delete_folder() -> void:
    if _current_library_idx < 0 or _current_folder_path.is_empty():
        return
    if _undo != null:
        _undo.begin()
    _remove_current_folder()
    _current_folder_idx = -1
    _current_folder_path = []
    _selected = -1
    _mark_dirty()
    _rebuild_all()
    if _undo != null:
        _undo.commit("delete trigger folder")


func _on_move_folder_up() -> void:
    _move_folder_by(-1)


func _on_move_folder_down() -> void:
    _move_folder_by(1)


func _on_add_rule() -> void:
    if _undo != null:
        _undo.begin()
    var rules := _current_rules_array()
    var new_rule := {
        "id": "new_rule_%d" % rules.size(),
        "event": "pickup",
        "enabled": true,
        "once": false,
        "locals": [],
        "conditions": [],
        "actions": [{"type": "log", "message": "triggered"}],
    }
    rules.append(new_rule)
    _selected = rules.size() - 1
    _mark_dirty()
    _rebuild_list()
    if _undo != null:
        _undo.commit("add trigger rule")


func _on_delete_rule() -> void:
    var rules := _current_rules_array()
    if _selected < 0 or _selected >= rules.size():
        return
    if _undo != null:
        _undo.begin()
    rules.remove_at(_selected)
    _selected = mini(_selected, rules.size() - 1)
    _mark_dirty()
    _rebuild_list()
    if _undo != null:
        _undo.commit("delete trigger rule")


func _on_duplicate_rule() -> void:
    var rules := _current_rules_array()
    if _selected < 0 or _selected >= rules.size():
        return
    if _undo != null:
        _undo.begin()
    var dup_rule: Dictionary = (rules[_selected] as Dictionary).duplicate(true)
    dup_rule["id"] = _make_unique_rule_id(str(dup_rule.get("id", "new_rule")))
    rules.insert(_selected + 1, dup_rule)
    _selected += 1
    _mark_dirty()
    _rebuild_list()
    if _undo != null:
        _undo.commit("duplicate trigger rule")


func _on_move_rule_up() -> void:
    _move_rule_by(-1)


func _on_move_rule_down() -> void:
    _move_rule_by(1)


func _on_move_rule_to_scope() -> void:
    _open_scope_transfer_dialog("move")


func _on_copy_rule_to_scope() -> void:
    _open_scope_transfer_dialog("copy")


func _on_select(idx: int) -> void:
    if not _flush_detail():
        if _selected >= 0 and _selected < _current_rules_array().size():
            _list.select(_selected)
        return
    _selected = idx
    _show_detail(idx)


func _on_library_selected(idx: int) -> void:
    if not _flush_detail():
        _populate_library_selector()
        return
    _current_library_idx = idx - 1
    _current_folder_idx = -1
    _current_folder_path = []
    _selected = -1
    _rebuild_all()


func _on_folder_selected(idx: int) -> void:
    if not _flush_detail():
        _populate_folder_selector()
        return
    if idx <= 0:
        _current_folder_path = []
        _current_folder_idx = -1
    _selected = -1
    _rebuild_all()


func _on_scope_tree_selected() -> void:
    if _scope_tree == null:
        return
    if _suppress:
        return
    if not _flush_detail():
        _suppress = true
        _populate_scope_tree()
        _suppress = false
        return
    var item: TreeItem = _scope_tree.get_selected()
    if item == null:
        return
    var meta_v: Variant = item.get_metadata(0)
    if typeof(meta_v) != TYPE_DICTIONARY:
        return
    var meta: Dictionary = meta_v
    _current_library_idx = int(meta.get("library_idx", -1))
    _current_folder_path = _safe_array(meta.get("folder_path", []))
    _current_folder_idx = -1 if _current_folder_path.is_empty() else int(_current_folder_path[_current_folder_path.size() - 1])
    _selected = -1
    _rebuild_all()


func _on_library_name_changed(text: String) -> void:
    if _suppress or _current_library_idx < 0:
        return
    var libs := _library_array()
    var lib: Dictionary = libs[_current_library_idx]
    lib["name"] = text.strip_edges()
    libs[_current_library_idx] = lib
    _root["libraries"] = libs
    _mark_dirty()
    _populate_library_selector()


func _on_folder_name_changed(text: String) -> void:
    if _suppress or _current_library_idx < 0 or _current_folder_path.is_empty():
        return
    _rename_current_folder(text.strip_edges())
    _mark_dirty()
    _rebuild_all()


func _on_rule_field_changed(_arg: Variant = null) -> void:
    if _suppress:
        return
    _mark_dirty()
    var rules := _current_rules_array()
    if _selected < 0 or _selected >= rules.size():
        return
    var draft: Dictionary = rules[_selected].duplicate(true)
    draft["id"] = _id_edit.text.strip_edges()
    draft["event"] = _selected_event_name()
    draft["enabled"] = _enabled_check.button_pressed
    draft["once"] = _once_check.button_pressed
    if _locals_form != null:
        draft["locals"] = _locals_form.get_value()
    if _cond_form != null:
        draft["conditions"] = _cond_form.get_value()
    if _action_form != null:
        draft["actions"] = _action_form.get_value()
    _refresh_summary(draft)
    _update_camera_preview(draft)


func _on_breakpoint_toggled(enabled: bool) -> void:
    if _suppress:
        return
    var rule_id: String = _id_edit.text.strip_edges() if _id_edit != null else ""
    if rule_id.is_empty():
        if _breakpoint_check != null:
            _suppress = true
            _breakpoint_check.button_pressed = false
            _suppress = false
        status_changed.emit("Save or name the rule before toggling a breakpoint.")
        return
    if MvTriggerEngine != null and MvTriggerEngine.has_method("set_breakpoint"):
        MvTriggerEngine.set_breakpoint(rule_id, enabled)
    _rebuild_list()


func _on_open_debugger() -> void:
    if _debugger_window != null and _debugger_window.has_method("open_window"):
        _debugger_window.call("open_window", _id_edit.text.strip_edges() if _id_edit != null else "")


func _on_runtime_debug_changed() -> void:
    _refresh_debug_view()
    if _selected >= 0:
        _rebuild_list()


func _update_camera_preview(rule: Dictionary) -> void:
    var preview: Array = []
    var actions: Array = _safe_array(rule.get("actions", []))
    for action_v in actions:
        if typeof(action_v) != TYPE_DICTIONARY:
            continue
        var action: Dictionary = action_v
        if str(action.get("type", "")) != "camera_focus":
            continue
        preview.append({
            "mode": str(action.get("mode", "")).strip_edges().to_lower(),
            "target": str(action.get("target", "")).strip_edges(),
            "x": float(action.get("x", 0.0)),
            "y": float(action.get("y", 0.0)),
            "duration": float(action.get("duration", 0.0)),
        })
    if preview.is_empty():
        camera_preview_cleared.emit()
    else:
        camera_preview_changed.emit(preview)


func _mark_dirty() -> void:
    if _suppress:
        return
    _dirty = true


func _input(event: InputEvent) -> void:
    if not visible:
        return
    if _tutorial_overlay != null and _tutorial_overlay.visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if _has_text_focus():
            return
        if _undo != null and _undo.handle_key(event):
            get_viewport().set_input_as_handled()
            return
        if event.keycode == KEY_ESCAPE:
            request_close()
            get_viewport().set_input_as_handled()


func _has_text_focus() -> bool:
    var focused := get_viewport().gui_get_focus_owner()
    return focused is LineEdit or focused is TextEdit


func _on_tutorial_pressed() -> void:
    if _tutorial_overlay == null:
        return
    var EditorTutorial := preload("res://Space/scripts/editor/editor_tutorial.gd")
    var tut: Dictionary = EditorTutorial.get_tutorial("trigger")
    _tutorial_overlay.show_tutorial(str(tut["title"]), tut["steps"])


func _refresh_workflow_help(rule: Dictionary = {}) -> void:
    if _workflow_label == null:
        return
    var event_name: String = str(rule.get("event", "")).strip_edges()
    if event_name.is_empty():
        event_name = _selected_event_name()
    var message := "Build this like a sentence: When something happens, only if these checks pass, do these actions."
    match event_name:
        "interact":
            message = "Interact rules run when the player uses an interactable. Simplest NPC dialogue does not need a trigger at all: set the entity's `dialogue_id`. Use an `interact` trigger when you need extra checks or side effects before or after dialogue. The payload includes `entity_id`, `entity_type`, tags, and authored entity properties."
        "zone_enter", "zone_exit":
            message = "Zone rules come from named trigger-volume entities in a room. Give the zone a zone_id, then use %s here for cutscenes, ambushes, camera moves, spawns, or room logic tied to crossing that area." % EcaSchema.event_label(event_name)
        "dialogue_choice":
            message = "Dialogue-choice rules let conversations branch into game logic. When a player picks a response, the payload includes `dialogue_id`, `line_index`, `choice_index`, and `choice_text`."
        "ui_button":
            message = "UI-button rules fire from authored UI screens and menus. Use them when a button should do more than its built-in UI action, or when you want menus to drive story/campaign logic."
        "game_started":
            message = "Game-start rules are the clean entry point for boot-time setup, opening cinematics, or starting the first dialogue after the room is fully loaded."
        "":
            message = "Common recipes: talk to an NPC -> start a conversation, enter a zone -> run a cutscene, choose dialogue -> set a flag, press a UI button -> start another event."
        _:
            var help_text: String = EcaSchema.event_help(event_name)
            if not help_text.is_empty():
                message = "%s: %s" % [EcaSchema.event_label(event_name), help_text]
    _workflow_label.text = message


func _safe_array(value: Variant) -> Array:
    if typeof(value) == TYPE_ARRAY:
        return value
    return []


func _selected_event_name() -> String:
    var custom_name: String = _event_custom_edit.text.strip_edges() if _event_custom_edit != null else ""
    if not custom_name.is_empty():
        return custom_name
    var event_names: Array = EcaSchema.event_type_names()
    var idx: int = _event_edit.get_selected() if _event_edit != null else -1
    if idx >= 0 and idx < event_names.size():
        return str(event_names[idx])
    return "pickup"


func _refresh_summary(rule: Dictionary) -> void:
    if _summary_label == null:
        return
    var rule_id := str(rule.get("id", "")).strip_edges()
    var event_name := str(rule.get("event", "pickup"))
    var scope_name := "root"
    if _current_library_idx >= 0:
        scope_name = str(_current_library().get("name", "library"))
        if _current_folder_idx >= 0:
            scope_name += " / " + str(_current_folder().get("name", "folder"))
    var locals_count := _safe_array(rule.get("locals", [])).size()
    var conditions := _safe_array(rule.get("conditions", []))
    var actions := _safe_array(rule.get("actions", []))
    var state_bits: Array = []
    state_bits.append("enabled" if bool(rule.get("enabled", true)) else "disabled")
    if bool(rule.get("once", false)):
        state_bits.append("once")
    var condition_preview := _preview_conditions(conditions)
    var action_preview := _preview_actions(actions)
    _summary_label.text = "In %s, %s starts on: %s. It has %d temporary value%s, %d check%s, and %d action%s. %s%s State: %s." % [
        scope_name,
        rule_id if not rule_id.is_empty() else "(unnamed)",
        EcaSchema.event_label(event_name),
        locals_count,
        "" if locals_count == 1 else "s",
        conditions.size(),
        "" if conditions.size() == 1 else "s",
        actions.size(),
        "" if actions.size() == 1 else "s",
        condition_preview,
        action_preview,
        ", ".join(state_bits),
    ]


func _preview_conditions(conditions: Array) -> String:
    if conditions.is_empty():
        return "No checks are required. "
    var lines: Array = []
    for i in range(mini(conditions.size(), 2)):
        var cond_v: Variant = conditions[i]
        if typeof(cond_v) == TYPE_DICTIONARY:
            lines.append(EcaSchema.condition_summary(cond_v))
    if conditions.size() > 2:
        lines.append("and %d more" % (conditions.size() - 2))
    return "Checks: %s. " % "; ".join(lines)


func _preview_actions(actions: Array) -> String:
    if actions.is_empty():
        return "No actions yet. "
    var lines: Array = []
    for i in range(mini(actions.size(), 2)):
        var action_v: Variant = actions[i]
        if typeof(action_v) == TYPE_DICTIONARY:
            lines.append(EcaSchema.action_summary(action_v))
    if actions.size() > 2:
        lines.append("and %d more" % (actions.size() - 2))
    return "Actions: %s. " % "; ".join(lines)


func _refresh_debug_view() -> void:
    if _debug_view == null:
        return
    if MvTriggerEngine == null or not MvTriggerEngine.has_method("get_debug_history"):
        _debug_view.text = "Trigger debugger unavailable."
        return
    var paused: bool = MvTriggerEngine.has_method("is_paused") and bool(MvTriggerEngine.is_paused())
    var active_count: int = 0
    if MvTriggerEngine.has_method("get_active_sequences"):
        var active_v: Variant = MvTriggerEngine.get_active_sequences()
        if typeof(active_v) == TYPE_ARRAY:
            active_count = (active_v as Array).size()
    var breakpoints_count: int = 0
    if MvTriggerEngine.has_method("get_breakpoints"):
        var breakpoints_v: Variant = MvTriggerEngine.get_breakpoints()
        if typeof(breakpoints_v) == TYPE_ARRAY:
            breakpoints_count = (breakpoints_v as Array).size()
    var history: Array = MvTriggerEngine.get_debug_history()
    if history.is_empty():
        _debug_view.text = "Paused: %s | Active: %d | Breakpoints: %d\nNo runtime trigger history yet." % [
            "yes" if paused else "no",
            active_count,
            breakpoints_count,
        ]
        return
    var start: int = maxi(0, history.size() - 32)
    var lines: PackedStringArray = []
    lines.append("Paused: %s | Active: %d | Breakpoints: %d" % [
        "yes" if paused else "no",
        active_count,
        breakpoints_count,
    ])
    for i in range(start, history.size()):
        var entry_v: Variant = history[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        var line := "[%s] %s %s %s" % [
            str(entry.get("kind", "")),
            str(entry.get("event", entry.get("rule_id", entry.get("action", "")))),
            str(entry.get("wait", "")),
            str(entry.get("locals", "")),
        ]
        lines.append(line.strip_edges())
    _debug_view.text = "\n".join(lines)
    _debug_view.scroll_to_line(maxi(0, lines.size() - 1))


func _clear_debug_view() -> void:
    if MvTriggerEngine != null and MvTriggerEngine.has_method("clear_debug_history"):
        MvTriggerEngine.clear_debug_history()
    _refresh_debug_view()


func _open_scope_transfer_dialog(mode: String) -> void:
    var rules := _current_rules_array()
    if _selected < 0 or _selected >= rules.size() or _scope_transfer_dialog == null or _scope_transfer_option == null:
        return
    _scope_transfer_mode = mode
    _scope_transfer_dialog.title = "Move Trigger Rule" if mode == "move" else "Copy Trigger Rule"
    _scope_transfer_option.clear()
    for scope in _all_scopes():
        _scope_transfer_option.add_item(str(scope.get("label", "Scope")))
    _scope_transfer_option.select(maxi(0, _find_scope_index(_current_library_idx, _current_folder_path)))
    _scope_transfer_dialog.popup_centered(Vector2(420, 120))


func _on_scope_transfer_confirmed() -> void:
    var rules := _current_rules_array()
    if _selected < 0 or _selected >= rules.size():
        return
    if not _flush_detail():
        return
    var scope_idx: int = _scope_transfer_option.get_selected() if _scope_transfer_option != null else -1
    var scopes: Array = _all_scopes()
    if scope_idx < 0 or scope_idx >= scopes.size():
        return
    var target: Dictionary = scopes[scope_idx]
    var target_library_idx: int = int(target.get("library_idx", -1))
    var target_folder_path: Array = _safe_array(target.get("folder_path", []))
    var source_rules := _current_rules_array()
    var source_library_idx: int = _current_library_idx
    var source_folder_path: Array = _current_folder_path.duplicate()
    var rule: Dictionary = (source_rules[_selected] as Dictionary).duplicate(true)
    if _scope_transfer_mode == "copy":
        rule["id"] = _make_unique_rule_id(str(rule.get("id", "copied_rule")))
    elif source_library_idx == target_library_idx and _paths_equal(source_folder_path, target_folder_path):
        return
    if _undo != null:
        _undo.begin()
    if _scope_transfer_mode == "move":
        source_rules.remove_at(_selected)
    var target_rules: Array = _rules_for_scope(target_library_idx, target_folder_path)
    target_rules.append(rule)
    _current_library_idx = target_library_idx
    _current_folder_path = target_folder_path.duplicate()
    _current_folder_idx = -1 if _current_folder_path.is_empty() else int(_current_folder_path[_current_folder_path.size() - 1])
    _selected = target_rules.size() - 1
    _mark_dirty()
    _rebuild_all()
    if _undo != null:
        _undo.commit("%s trigger rule" % _scope_transfer_mode)


func _move_rule_by(delta: int) -> void:
    var rules := _current_rules_array()
    if _selected < 0 or _selected >= rules.size():
        return
    var target_idx: int = clampi(_selected + delta, 0, rules.size() - 1)
    if target_idx == _selected:
        return
    if _undo != null:
        _undo.begin()
    var rule_v: Variant = rules[_selected]
    rules.remove_at(_selected)
    rules.insert(target_idx, rule_v)
    _selected = target_idx
    _mark_dirty()
    _rebuild_list()
    if _undo != null:
        _undo.commit("reorder trigger rule")


func _move_library_by(delta: int) -> void:
    var libs := _library_array()
    if _current_library_idx < 0 or _current_library_idx >= libs.size():
        return
    var target_idx: int = clampi(_current_library_idx + delta, 0, libs.size() - 1)
    if target_idx == _current_library_idx:
        return
    if _undo != null:
        _undo.begin()
    var lib_v: Variant = libs[_current_library_idx]
    libs.remove_at(_current_library_idx)
    libs.insert(target_idx, lib_v)
    _root["libraries"] = libs
    _current_library_idx = target_idx
    _mark_dirty()
    _rebuild_all()
    if _undo != null:
        _undo.commit("reorder trigger library")


func _move_folder_by(delta: int) -> void:
    if _current_library_idx < 0 or _current_folder_path.is_empty():
        return
    var siblings: Array = _folder_children_array(_current_folder_path.slice(0, _current_folder_path.size() - 1))
    var current_idx: int = int(_current_folder_path[_current_folder_path.size() - 1])
    if current_idx < 0 or current_idx >= siblings.size():
        return
    var target_idx: int = clampi(current_idx + delta, 0, siblings.size() - 1)
    if target_idx == current_idx:
        return
    if _undo != null:
        _undo.begin()
    _reorder_current_folder(target_idx)
    _current_folder_idx = target_idx
    _current_folder_path[_current_folder_path.size() - 1] = target_idx
    _mark_dirty()
    _rebuild_all()
    if _undo != null:
        _undo.commit("reorder trigger folder")


func _append_folder_to_current_scope(new_folder: Dictionary) -> void:
    var libs := _library_array()
    var lib: Dictionary = libs[_current_library_idx]
    lib["folders"] = _append_folder_recursive(_safe_array(lib.get("folders", [])), _current_folder_path, new_folder, 0)
    libs[_current_library_idx] = lib
    _root["libraries"] = libs


func _remove_current_folder() -> void:
    var libs := _library_array()
    var lib: Dictionary = libs[_current_library_idx]
    lib["folders"] = _remove_folder_recursive(_safe_array(lib.get("folders", [])), _current_folder_path, 0)
    libs[_current_library_idx] = lib
    _root["libraries"] = libs


func _reorder_current_folder(target_idx: int) -> void:
    var libs := _library_array()
    var lib: Dictionary = libs[_current_library_idx]
    lib["folders"] = _reorder_folder_recursive(_safe_array(lib.get("folders", [])), _current_folder_path, target_idx, 0)
    libs[_current_library_idx] = lib
    _root["libraries"] = libs


func _rename_current_folder(new_name: String) -> void:
    var libs := _library_array()
    var lib: Dictionary = libs[_current_library_idx]
    lib["folders"] = _rename_folder_recursive(_safe_array(lib.get("folders", [])), _current_folder_path, new_name, 0)
    libs[_current_library_idx] = lib
    _root["libraries"] = libs


func _append_folder_recursive(folders: Array, path: Array, new_folder: Dictionary, depth: int) -> Array:
    if depth >= path.size():
        folders.append(new_folder)
        return folders
    var idx: int = int(path[depth])
    if idx < 0 or idx >= folders.size():
        return folders
    var folder: Dictionary = folders[idx]
    folder["folders"] = _append_folder_recursive(_safe_array(folder.get("folders", [])), path, new_folder, depth + 1)
    folders[idx] = folder
    return folders


func _remove_folder_recursive(folders: Array, path: Array, depth: int) -> Array:
    if depth >= path.size():
        return folders
    var idx: int = int(path[depth])
    if idx < 0 or idx >= folders.size():
        return folders
    if depth == path.size() - 1:
        folders.remove_at(idx)
        return folders
    var folder: Dictionary = folders[idx]
    folder["folders"] = _remove_folder_recursive(_safe_array(folder.get("folders", [])), path, depth + 1)
    folders[idx] = folder
    return folders


func _reorder_folder_recursive(folders: Array, path: Array, target_idx: int, depth: int) -> Array:
    if depth >= path.size():
        return folders
    var idx: int = int(path[depth])
    if idx < 0 or idx >= folders.size():
        return folders
    if depth == path.size() - 1:
        var folder_v: Variant = folders[idx]
        folders.remove_at(idx)
        folders.insert(target_idx, folder_v)
        return folders
    var folder: Dictionary = folders[idx]
    folder["folders"] = _reorder_folder_recursive(_safe_array(folder.get("folders", [])), path, target_idx, depth + 1)
    folders[idx] = folder
    return folders


func _rename_folder_recursive(folders: Array, path: Array, new_name: String, depth: int) -> Array:
    if depth >= path.size():
        return folders
    var idx: int = int(path[depth])
    if idx < 0 or idx >= folders.size():
        return folders
    var folder: Dictionary = folders[idx]
    if depth == path.size() - 1:
        folder["name"] = new_name
        folders[idx] = folder
        return folders
    folder["folders"] = _rename_folder_recursive(_safe_array(folder.get("folders", [])), path, new_name, depth + 1)
    folders[idx] = folder
    return folders


func _rules_for_scope(library_idx: int, folder_path: Array) -> Array:
    if library_idx < 0:
        return _root.get("triggers", [])
    var libs := _library_array()
    if library_idx >= libs.size():
        return []
    var lib: Dictionary = libs[library_idx]
    if folder_path.is_empty():
        return lib.get("triggers", [])
    var folder: Dictionary = _folder_at_path(_safe_array(lib.get("folders", [])), folder_path)
    if folder.is_empty():
        return []
    return folder.get("triggers", [])


func _all_scopes() -> Array:
    var scopes: Array = []
    scopes.append({
        "label": "Root Rules",
        "library_idx": -1,
        "folder_path": [],
    })
    var libs := _library_array()
    for lib_idx in range(libs.size()):
        var lib_v: Variant = libs[lib_idx]
        if typeof(lib_v) != TYPE_DICTIONARY:
            continue
        var lib: Dictionary = lib_v
        scopes.append({
            "label": str(lib.get("name", "Library")),
            "library_idx": lib_idx,
            "folder_path": [],
        })
        _append_scopes_recursive(scopes, lib_idx, str(lib.get("name", "Library")), _safe_array(lib.get("folders", [])), [])
    return scopes


func _append_scopes_recursive(scopes: Array, lib_idx: int, prefix: String, folders: Array, parent_path: Array) -> void:
    for folder_idx in range(folders.size()):
        var folder_v: Variant = folders[folder_idx]
        if typeof(folder_v) != TYPE_DICTIONARY:
            continue
        var folder: Dictionary = folder_v
        var path: Array = parent_path.duplicate()
        path.append(folder_idx)
        var label: String = "%s / %s" % [prefix, str(folder.get("name", "Folder"))]
        scopes.append({
            "label": label,
            "library_idx": lib_idx,
            "folder_path": path,
        })
        _append_scopes_recursive(scopes, lib_idx, label, _safe_array(folder.get("folders", [])), path)


func _find_scope_index(library_idx: int, folder_path: Array) -> int:
    var scopes: Array = _all_scopes()
    for idx in range(scopes.size()):
        var scope: Dictionary = scopes[idx]
        if int(scope.get("library_idx", -2)) == library_idx and _paths_equal(_safe_array(scope.get("folder_path", [])), folder_path):
            return idx
    return 0


func _paths_equal(a: Array, b: Array) -> bool:
    if a.size() != b.size():
        return false
    for i in range(a.size()):
        if int(a[i]) != int(b[i]):
            return false
    return true


func _rule_has_breakpoint(rule: Dictionary) -> bool:
    if MvTriggerEngine == null or not MvTriggerEngine.has_method("has_breakpoint"):
        return false
    return bool(MvTriggerEngine.has_breakpoint(str(rule.get("id", ""))))


func _make_unique_rule_id(base_id: String) -> String:
    var trimmed: String = base_id.strip_edges()
    if trimmed.is_empty():
        trimmed = "rule"
    var candidate: String = trimmed
    var idx: int = 2
    var existing_ids: Dictionary = {}
    for rule_v in TriggerRoot.flatten_rules(_root):
        if typeof(rule_v) != TYPE_DICTIONARY:
            continue
        existing_ids[str((rule_v as Dictionary).get("id", "")).strip_edges()] = true
    while existing_ids.has(candidate):
        candidate = "%s_%d" % [trimmed, idx]
        idx += 1
    return candidate


func _unique_scope_id(entries: Array, prefix: String) -> String:
    var idx: int = 1
    while true:
        var candidate := "%s_%d" % [prefix, idx]
        var exists: bool = false
        for entry_v in entries:
            if typeof(entry_v) != TYPE_DICTIONARY:
                continue
            if str((entry_v as Dictionary).get("id", "")).strip_edges() == candidate:
                exists = true
                break
        if not exists:
            return candidate
        idx += 1
    return ""
