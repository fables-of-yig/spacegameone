extends Control

const DEFAULT_KINDS: Array = [
    "all",
    "event",
    "rule_match",
    "rule_blocked",
    "sequence_start",
    "action",
    "wait_start",
    "wait_end",
    "wait_timeout",
    "breakpoint_hit",
    "step_granted",
    "step_consumed",
    "paused",
    "resumed",
    "sequence_finished",
]

signal closed

var _panel: PanelContainer = null
var _status_label: Label = null
var _rule_filter_edit: LineEdit = null
var _event_filter_edit: LineEdit = null
var _kind_option: OptionButton = null
var _breakpoint_rule_edit: LineEdit = null
var _active_view: RichTextLabel = null
var _breakpoints_view: RichTextLabel = null
var _history_view: RichTextLabel = null


func _ready() -> void:
    visible = false
    mouse_filter = MOUSE_FILTER_STOP
    set_anchors_preset(PRESET_FULL_RECT)
    _build_ui()
    _connect_engine()
    _refresh()


func open_window(selected_rule_id: String = "") -> void:
    visible = true
    if _breakpoint_rule_edit != null and not selected_rule_id.strip_edges().is_empty():
        _breakpoint_rule_edit.text = selected_rule_id.strip_edges()
    _refresh()


func close_window() -> void:
    visible = false
    closed.emit()


func _build_ui() -> void:
    var scrim := ColorRect.new()
    scrim.color = Color(0.02, 0.04, 0.07, 0.82)
    scrim.set_anchors_preset(PRESET_FULL_RECT)
    add_child(scrim)

    _panel = PanelContainer.new()
    _panel.anchor_left = 0.08
    _panel.anchor_top = 0.06
    _panel.anchor_right = 0.92
    _panel.anchor_bottom = 0.92
    add_child(_panel)

    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 8)
    _panel.add_child(root)

    var top_row := HBoxContainer.new()
    root.add_child(top_row)

    var title := Label.new()
    title.text = "TRIGGER DEBUGGER"
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top_row.add_child(title)

    var refresh_btn := Button.new()
    refresh_btn.text = "Refresh"
    refresh_btn.pressed.connect(_refresh)
    top_row.add_child(refresh_btn)

    var clear_btn := Button.new()
    clear_btn.text = "Clear"
    clear_btn.pressed.connect(_on_clear_pressed)
    top_row.add_child(clear_btn)

    var pause_btn := Button.new()
    pause_btn.text = "Pause"
    pause_btn.pressed.connect(_on_pause_pressed)
    top_row.add_child(pause_btn)

    var step_btn := Button.new()
    step_btn.text = "Step"
    step_btn.pressed.connect(_on_step_pressed)
    top_row.add_child(step_btn)

    var step5_btn := Button.new()
    step5_btn.text = "Step x5"
    step5_btn.pressed.connect(_on_step_five_pressed)
    top_row.add_child(step5_btn)

    var resume_btn := Button.new()
    resume_btn.text = "Resume"
    resume_btn.pressed.connect(_on_resume_pressed)
    top_row.add_child(resume_btn)

    var close_btn := Button.new()
    close_btn.text = "Close"
    close_btn.pressed.connect(close_window)
    top_row.add_child(close_btn)

    _status_label = Label.new()
    _status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status_label.add_theme_font_size_override("font_size", 11)
    root.add_child(_status_label)

    var filter_row := HBoxContainer.new()
    root.add_child(filter_row)

    _rule_filter_edit = LineEdit.new()
    _rule_filter_edit.placeholder_text = "Filter by rule id"
    _rule_filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _rule_filter_edit.text_changed.connect(_refresh)
    filter_row.add_child(_rule_filter_edit)

    _event_filter_edit = LineEdit.new()
    _event_filter_edit.placeholder_text = "Filter by event"
    _event_filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _event_filter_edit.text_changed.connect(_refresh)
    filter_row.add_child(_event_filter_edit)

    _kind_option = OptionButton.new()
    for kind in DEFAULT_KINDS:
        _kind_option.add_item(str(kind))
    _kind_option.item_selected.connect(_refresh)
    filter_row.add_child(_kind_option)

    var bp_row := HBoxContainer.new()
    root.add_child(bp_row)

    _breakpoint_rule_edit = LineEdit.new()
    _breakpoint_rule_edit.placeholder_text = "Rule id for breakpoint"
    _breakpoint_rule_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bp_row.add_child(_breakpoint_rule_edit)

    var toggle_bp_btn := Button.new()
    toggle_bp_btn.text = "Toggle Breakpoint"
    toggle_bp_btn.pressed.connect(_on_toggle_breakpoint_pressed)
    bp_row.add_child(toggle_bp_btn)

    var clear_bp_btn := Button.new()
    clear_bp_btn.text = "Clear Breakpoints"
    clear_bp_btn.pressed.connect(_on_clear_breakpoints_pressed)
    bp_row.add_child(clear_bp_btn)

    var split := HSplitContainer.new()
    split.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(split)

    var left := VBoxContainer.new()
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.add_child(left)

    var active_label := Label.new()
    active_label.text = "Active Sequences"
    left.add_child(active_label)

    _active_view = RichTextLabel.new()
    _active_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _active_view.custom_minimum_size = Vector2(0, 220)
    _active_view.scroll_active = true
    left.add_child(_active_view)

    var right := VBoxContainer.new()
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.add_child(right)

    var bp_label := Label.new()
    bp_label.text = "Breakpoints"
    right.add_child(bp_label)

    _breakpoints_view = RichTextLabel.new()
    _breakpoints_view.custom_minimum_size = Vector2(0, 120)
    _breakpoints_view.scroll_active = true
    right.add_child(_breakpoints_view)

    var history_label := Label.new()
    history_label.text = "History"
    right.add_child(history_label)

    _history_view = RichTextLabel.new()
    _history_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _history_view.custom_minimum_size = Vector2(0, 320)
    _history_view.scroll_active = true
    right.add_child(_history_view)


func _connect_engine() -> void:
    if MvTriggerEngine == null:
        return
    if MvTriggerEngine.has_signal("debug_entry_added") and not MvTriggerEngine.debug_entry_added.is_connected(_refresh):
        MvTriggerEngine.debug_entry_added.connect(_refresh)
    if MvTriggerEngine.has_signal("debug_state_changed") and not MvTriggerEngine.debug_state_changed.is_connected(_refresh):
        MvTriggerEngine.debug_state_changed.connect(_refresh)


func _on_clear_pressed() -> void:
    if MvTriggerEngine != null and MvTriggerEngine.has_method("clear_debug_history"):
        MvTriggerEngine.clear_debug_history()
    _refresh()


func _on_pause_pressed() -> void:
    if MvTriggerEngine != null and MvTriggerEngine.has_method("request_pause"):
        MvTriggerEngine.request_pause()
    _refresh()


func _on_resume_pressed() -> void:
    if MvTriggerEngine != null and MvTriggerEngine.has_method("resume_sequences"):
        MvTriggerEngine.resume_sequences()
    _refresh()


func _on_step_pressed() -> void:
    if MvTriggerEngine != null and MvTriggerEngine.has_method("request_step"):
        MvTriggerEngine.request_step(1)
    _refresh()


func _on_step_five_pressed() -> void:
    if MvTriggerEngine != null and MvTriggerEngine.has_method("request_step"):
        MvTriggerEngine.request_step(5)
    _refresh()


func _on_toggle_breakpoint_pressed() -> void:
    var rule_id: String = _breakpoint_rule_edit.text.strip_edges()
    if rule_id.is_empty() or MvTriggerEngine == null:
        return
    if MvTriggerEngine.has_method("toggle_breakpoint"):
        MvTriggerEngine.toggle_breakpoint(rule_id)
    _refresh()


func _on_clear_breakpoints_pressed() -> void:
    if MvTriggerEngine != null and MvTriggerEngine.has_method("clear_breakpoints"):
        MvTriggerEngine.clear_breakpoints()
    _refresh()


func _refresh(_arg: Variant = null) -> void:
    if _status_label == null:
        return
    if MvTriggerEngine == null or not MvTriggerEngine.has_method("get_debug_history"):
        _status_label.text = "MvTriggerEngine is unavailable in the current editor context."
        _active_view.text = "unavailable"
        _breakpoints_view.text = "unavailable"
        _history_view.text = "unavailable"
        return
    var paused: bool = MvTriggerEngine.has_method("is_paused") and bool(MvTriggerEngine.is_paused())
    var step_budget: int = MvTriggerEngine.get_step_budget() if MvTriggerEngine.has_method("get_step_budget") else 0
    var active: Array = MvTriggerEngine.get_active_sequences() if MvTriggerEngine.has_method("get_active_sequences") else []
    var breakpoints: Array = MvTriggerEngine.get_breakpoints() if MvTriggerEngine.has_method("get_breakpoints") else []
    var history: Array = MvTriggerEngine.get_debug_history()
    _status_label.text = "Paused: %s | Step Budget: %d | Active: %d | Breakpoints: %d | History: %d" % [
        "yes" if paused else "no",
        step_budget,
        active.size(),
        breakpoints.size(),
        history.size(),
    ]
    _active_view.text = _format_active(active)
    _breakpoints_view.text = _format_breakpoints(breakpoints)
    _history_view.text = _format_history(history)
    if _history_view.get_line_count() > 0:
        _history_view.scroll_to_line(maxi(0, _history_view.get_line_count() - 1))


func _format_active(active: Array) -> String:
    if active.is_empty():
        return "No active trigger sequences."
    var lines: PackedStringArray = []
    for seq_v in active:
        if typeof(seq_v) != TYPE_DICTIONARY:
            continue
        var seq: Dictionary = seq_v
        lines.append("#%s  %s  step=%s  wait=%s  locals=%s" % [
            str(seq.get("sequence_id", "")),
            str(seq.get("rule_id", "")),
            str(seq.get("step", "")),
            str(seq.get("wait", "")),
            _format_small_dict(seq.get("locals", {})),
        ])
    return "\n".join(lines)


func _format_breakpoints(entries: Array) -> String:
    if entries.is_empty():
        return "No breakpoints set."
    var lines: PackedStringArray = []
    for entry_v in entries:
        lines.append(str(entry_v))
    return "\n".join(lines)


func _format_history(history: Array) -> String:
    if history.is_empty():
        return "No trigger activity yet."
    var lines: PackedStringArray = []
    var wanted_rule: String = _rule_filter_edit.text.strip_edges().to_lower() if _rule_filter_edit != null else ""
    var wanted_event: String = _event_filter_edit.text.strip_edges().to_lower() if _event_filter_edit != null else ""
    var wanted_kind: String = "all"
    if _kind_option != null and _kind_option.get_selected() >= 0 and _kind_option.get_selected() < _kind_option.item_count:
        wanted_kind = _kind_option.get_item_text(_kind_option.get_selected())
    for entry_v in history:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        if not _history_matches(entry, wanted_rule, wanted_event, wanted_kind):
            continue
        lines.append(_format_entry(entry))
    if lines.is_empty():
        return "No history entries match the current filters."
    return "\n".join(lines)


func _history_matches(entry: Dictionary, wanted_rule: String, wanted_event: String, wanted_kind: String) -> bool:
    if wanted_kind != "all" and str(entry.get("kind", "")) != wanted_kind:
        return false
    if not wanted_rule.is_empty():
        var rule_id: String = str(entry.get("rule_id", "")).to_lower()
        if wanted_rule not in rule_id:
            return false
    if not wanted_event.is_empty():
        var event_name: String = str(entry.get("event", "")).to_lower()
        if wanted_event not in event_name:
            return false
    return true


func _format_entry(entry: Dictionary) -> String:
    var seconds: float = float(entry.get("time_ms", 0)) / 1000.0
    var parts: PackedStringArray = []
    parts.append("[%0.3f]" % seconds)
    parts.append("[%s]" % str(entry.get("kind", "")))
    var rule_id: String = str(entry.get("rule_id", ""))
    if not rule_id.is_empty():
        parts.append(rule_id)
    var event_name: String = str(entry.get("event", ""))
    if not event_name.is_empty():
        parts.append("event=%s" % event_name)
    var action_name: String = str(entry.get("action", ""))
    if not action_name.is_empty():
        parts.append("action=%s" % action_name)
    var wait_name: String = str(entry.get("wait", ""))
    if not wait_name.is_empty():
        parts.append("wait=%s" % wait_name)
    if entry.has("step"):
        parts.append("step=%s" % str(entry.get("step", "")))
    if entry.has("remaining"):
        parts.append("remaining=%s" % str(entry.get("remaining", "")))
    var entity_ref: String = str(entry.get("entity", ""))
    if not entity_ref.is_empty():
        parts.append("entity=%s" % entity_ref)
    var locals_v: Variant = entry.get("locals", {})
    if typeof(locals_v) == TYPE_DICTIONARY and not (locals_v as Dictionary).is_empty():
        parts.append("locals=%s" % _format_small_dict(locals_v))
    return " ".join(parts)


func _format_small_dict(value: Variant) -> String:
    if typeof(value) != TYPE_DICTIONARY:
        return "{}"
    var d: Dictionary = value
    if d.is_empty():
        return "{}"
    var parts: PackedStringArray = []
    for key_v in d.keys():
        parts.append("%s=%s" % [str(key_v), str(d[key_v])])
    return "{%s}" % ", ".join(parts)
