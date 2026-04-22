extends CanvasLayer

const TOGGLE_KEY: Key = KEY_F8
const CLEAR_KEY: Key = KEY_F7
const PAUSE_KEY: Key = KEY_F6
const STEP_KEY: Key = KEY_F5

var _panel: PanelContainer = null
var _header: Label = null
var _active_view: RichTextLabel = null
var _breakpoints_view: RichTextLabel = null
var _history_view: RichTextLabel = null
var _max_history_lines: int = 24


func _ready() -> void:
	layer = 220
	_build_ui()
	visible = false
	if not MvTriggerEngine.debug_entry_added.is_connected(_refresh):
		MvTriggerEngine.debug_entry_added.connect(_refresh)
	if not MvTriggerEngine.debug_state_changed.is_connected(_refresh):
		MvTriggerEngine.debug_state_changed.connect(_refresh)
	_refresh()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ke: InputEventKey = event
		if ke.keycode == TOGGLE_KEY:
			visible = not visible
			if visible:
				_refresh()
			get_viewport().set_input_as_handled()
		elif visible and ke.keycode == PAUSE_KEY:
			if MvTriggerEngine.has_method("is_paused") and bool(MvTriggerEngine.is_paused()):
				if MvTriggerEngine.has_method("resume_sequences"):
					MvTriggerEngine.resume_sequences()
			elif MvTriggerEngine.has_method("request_pause"):
				MvTriggerEngine.request_pause()
			get_viewport().set_input_as_handled()
		elif visible and ke.keycode == STEP_KEY:
			if MvTriggerEngine.has_method("request_step"):
				MvTriggerEngine.request_step(1)
			get_viewport().set_input_as_handled()
		elif visible and ke.keycode == CLEAR_KEY:
			MvTriggerEngine.clear_debug_history()
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = 12.0
	_panel.offset_top = 12.0
	_panel.offset_right = 520.0
	_panel.offset_bottom = 430.0
	add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	_panel.add_child(root)

	_header = Label.new()
	_header.text = "Trigger Debugger"
	root.add_child(_header)

	var hint := Label.new()
	hint.text = "F8 toggle  |  F7 clear  |  F6 pause/resume  |  F5 step"
	hint.add_theme_font_size_override("font_size", 11)
	root.add_child(hint)

	var active_label := Label.new()
	active_label.text = "Active Sequences"
	root.add_child(active_label)

	_active_view = RichTextLabel.new()
	_active_view.fit_content = true
	_active_view.scroll_active = true
	_active_view.custom_minimum_size = Vector2(0, 110)
	root.add_child(_active_view)

	var breakpoints_label := Label.new()
	breakpoints_label.text = "Breakpoints"
	root.add_child(breakpoints_label)

	_breakpoints_view = RichTextLabel.new()
	_breakpoints_view.fit_content = true
	_breakpoints_view.scroll_active = true
	_breakpoints_view.custom_minimum_size = Vector2(0, 60)
	root.add_child(_breakpoints_view)

	var history_label := Label.new()
	history_label.text = "Recent History"
	root.add_child(history_label)

	_history_view = RichTextLabel.new()
	_history_view.scroll_active = true
	_history_view.custom_minimum_size = Vector2(0, 240)
	root.add_child(_history_view)


func _refresh(_arg: Variant = null) -> void:
	if _header == null:
		return
	var active: Array = MvTriggerEngine.get_active_sequences()
	var paused: bool = MvTriggerEngine.has_method("is_paused") and bool(MvTriggerEngine.is_paused())
	var step_budget: int = MvTriggerEngine.get_step_budget() if MvTriggerEngine.has_method("get_step_budget") else 0
	var breakpoints: Array = MvTriggerEngine.get_breakpoints() if MvTriggerEngine.has_method("get_breakpoints") else []
	var history: Array = MvTriggerEngine.get_debug_history()
	_header.text = "Trigger Debugger  |  paused %s  |  steps %d  |  active %d  |  breakpoints %d  |  history %d" % [
		"yes" if paused else "no",
		step_budget,
		active.size(),
		breakpoints.size(),
		history.size(),
	]
	_refresh_active(active)
	_refresh_breakpoints(breakpoints)
	_refresh_history(history)


func _refresh_active(active: Array) -> void:
	if _active_view == null:
		return
	if active.is_empty():
		_active_view.text = "none"
		return
	var lines: PackedStringArray = []
	for seq_v in active:
		if typeof(seq_v) != TYPE_DICTIONARY:
			continue
		var seq: Dictionary = seq_v
		lines.append("#%s  %s  step %s  wait=%s  locals=%s" % [
			str(seq.get("sequence_id", "")),
			str(seq.get("rule_id", "")),
			str(seq.get("step", "")),
			str(seq.get("wait", "")),
			_format_small_dict(seq.get("locals", {})),
		])
	_active_view.text = "\n".join(lines)


func _refresh_breakpoints(entries: Array) -> void:
	if _breakpoints_view == null:
		return
	if entries.is_empty():
		_breakpoints_view.text = "none"
		return
	var lines: PackedStringArray = []
	for entry_v in entries:
		lines.append(str(entry_v))
	_breakpoints_view.text = "\n".join(lines)


func _refresh_history(history: Array) -> void:
	if _history_view == null:
		return
	if history.is_empty():
		_history_view.text = "no trigger activity yet"
		return
	var start: int = maxi(0, history.size() - _max_history_lines)
	var lines: PackedStringArray = []
	for i in range(start, history.size()):
		var entry_v: Variant = history[i]
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		lines.append(_format_entry(entry_v))
	_history_view.text = "\n".join(lines)
	_history_view.scroll_to_line(maxi(0, lines.size() - 1))


func _format_entry(entry_v: Variant) -> String:
	var entry: Dictionary = entry_v
	var kind: String = str(entry.get("kind", ""))
	var prefix := "[%s]" % kind
	match kind:
		"event":
			return "%s %s %s" % [prefix, str(entry.get("event", "")), _format_small_dict(entry.get("payload", {}))]
		"rule_match", "rule_blocked":
			return "%s %s on %s" % [prefix, str(entry.get("rule_id", "")), str(entry.get("event", ""))]
		"sequence_start", "sequence_finished":
			return "%s #%s %s locals=%s" % [prefix, str(entry.get("sequence_id", "")), str(entry.get("rule_id", "")), _format_small_dict(entry.get("locals", {}))]
		"action":
			return "%s #%s %s step=%s locals=%s" % [prefix, str(entry.get("sequence_id", "")), str(entry.get("action", "")), str(entry.get("step", "")), _format_small_dict(entry.get("locals", {}))]
		"wait_start", "wait_end", "wait_timeout":
			var line := "%s #%s %s %s %s" % [
				prefix,
				str(entry.get("sequence_id", "")),
				str(entry.get("wait", "")),
				str(entry.get("event", entry.get("entity", ""))),
				str(entry.get("anim", "")),
			]
			return line.strip_edges()
		"breakpoint_hit":
			return "%s #%s %s step=%s" % [
				prefix,
				str(entry.get("sequence_id", "")),
				str(entry.get("rule_id", "")),
				str(entry.get("step", "")),
			]
		"paused", "resumed", "breakpoint_set", "breakpoint_cleared":
			return "%s %s %s" % [prefix, str(entry.get("rule_id", "")), str(entry.get("reason", ""))]
		"step_granted":
			return "%s count=%s budget=%s" % [prefix, str(entry.get("count", "")), str(entry.get("budget", ""))]
		"step_consumed":
			return "%s #%s %s step=%s remaining=%s" % [
				prefix,
				str(entry.get("sequence_id", "")),
				str(entry.get("rule_id", "")),
				str(entry.get("step", "")),
				str(entry.get("remaining", "")),
			]
		_:
			return "%s %s" % [prefix, _format_small_dict(entry)]


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
