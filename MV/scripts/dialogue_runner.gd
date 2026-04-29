extends CanvasLayer

# Runtime dialogue UI. Reads a dialogue JSON (lines array with speaker,
# text, choices, conditions, actions) and renders a text box at screen
# bottom with typewriter reveal. Choices appear as buttons; conditions
# gate visibility. Actions fire through MvTriggerEngine.
#
# Usage: MvDialogueRunner.start("shopkeep_greet")
# The runner pauses MvGame.simulation_paused while active.


const UIPanels := preload("res://Space/scripts/ui/ui_panels.gd")
const UIIo := preload("res://Space/scripts/editor/ui/ui_io.gd")
const AuthoredScreenRuntime := preload("res://Space/scripts/ui/authored_screen_runtime.gd")
const HudDataSource := preload("res://Space/scripts/ui/hud_data_source.gd")
const UiHostActions := preload("res://Space/scripts/ui/ui_host_actions.gd")
const CHAR_DELAY: float = 0.03
const BOX_HEIGHT: int = 180
const BOX_MARGIN: int = 16

var _panel: Control = null
var _speaker_label: Label = null
var _text_label: RichTextLabel = null
var _choice_container: VBoxContainer = null

var _lines: Array = []
var _line_index: int = 0
var _current_id: String = ""
var _char_index: int = 0
var _char_timer: float = 0.0
var _full_text: String = ""
var _revealing: bool = false
var _waiting_choice: bool = false
var _active: bool = false
var _pending_choices: Array = []
var _visible_choices: Array = []
var _line_has_choices: bool = false
var _authored_screen: Control = null
var _authored_pack_id: String = ""


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_build_ui()
	visible = false
	_authored_screen = Control.new()
	_authored_screen.set_script(AuthoredScreenRuntime)
	_authored_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	_authored_screen.visible = false
	add_child(_authored_screen)
	_authored_screen.action_requested.connect(_on_authored_action)


func _process(delta: float) -> void:
	if not _active:
		return

	if _revealing:
		_char_timer += delta
		while _char_timer >= CHAR_DELAY and _char_index < _full_text.length():
			_char_index += 1
			_char_timer -= CHAR_DELAY
			_text_label.text = _full_text.substr(0, _char_index)
			_refresh_runtime_ui()
		if _char_index >= _full_text.length():
			_revealing = false
			_finish_line_reveal()

	if _waiting_choice:
		return

	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept"):
		if _revealing:
			_char_index = _full_text.length()
			_text_label.text = _full_text
			_revealing = false
			_refresh_runtime_ui()
			_finish_line_reveal()
		else:
			_advance()


func start(dialogue_id: String) -> void:
	var data := _load_dialogue(dialogue_id)
	var lines_v: Variant = data.get("lines", [])
	if typeof(lines_v) != TYPE_ARRAY or lines_v.is_empty():
		push_warning("MvDialogueRunner: no lines in '%s'" % dialogue_id)
		return
	_lines = lines_v
	_line_index = 0
	_current_id = dialogue_id
	_active = true
	visible = true
	MvGame.simulation_paused = true
	_refresh_authored_screen()
	_show_line()


func stop() -> void:
	_active = false
	_waiting_choice = false
	_line_has_choices = false
	_pending_choices.clear()
	_visible_choices.clear()
	visible = false
	_lines.clear()
	_clear_choices()
	MvGame.simulation_paused = false
	dialogue_finished.emit()


signal dialogue_finished


func is_active() -> bool:
	return _active


# ── Line display ────────────────────────────────────────────────────────

func _show_line() -> void:
	if _line_index >= _lines.size():
		stop()
		return

	var line: Dictionary = _lines[_line_index]

	if line.has("condition"):
		if not MvTriggerEngine.evaluate_condition(line["condition"], {}):
			_line_index += 1
			_show_line()
			return

	if line.has("actions"):
		if not _run_actions(line.get("actions", [])):
			return

	_speaker_label.text = str(line.get("speaker", ""))
	_full_text = str(line.get("text", ""))
	_char_index = 0
	_char_timer = 0.0
	_text_label.text = ""
	_revealing = true
	_waiting_choice = false
	_line_has_choices = line.has("choices")
	_pending_choices = _collect_visible_choices(line.get("choices", []))
	_visible_choices.clear()
	_clear_choices()
	if _line_has_choices:
		_build_reveal_skip_choice()
	_refresh_runtime_ui()

	if _full_text.is_empty():
		_revealing = false
		_finish_line_reveal()


func _advance(next_value: Variant = null) -> void:
	var fallback := _line_index + 1
	var resolved := _resolve_next_line(next_value, fallback)
	if resolved < 0:
		stop()
		return
	_line_index = resolved
	_show_line()


func _resolve_next_line(value: Variant, fallback: int) -> int:
	if value == null:
		return fallback
	match typeof(value):
		TYPE_INT:
			return int(value) if int(value) >= 0 else -1
		TYPE_FLOAT:
			return int(value) if int(value) >= 0 else -1
		TYPE_STRING:
			var text := str(value).strip_edges()
			if text.is_empty():
				return fallback
			var lower := text.to_lower()
			if lower == "end" or lower == "stop" or lower == "close":
				return -1
			if text.is_valid_int():
				var idx := int(text)
				return idx if idx >= 0 else -1
	return fallback


# ── Choices ─────────────────────────────────────────────────────────────

func _build_choices(choices: Array) -> void:
	_clear_choices()
	_choice_container.visible = true
	for entry_v in choices:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var btn := Button.new()
		btn.text = str(entry.get("text", "..."))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_color_override("font_color", UIPanels.text_color("button"))
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size = Vector2(0.0, 40.0)
		btn.pressed.connect(_on_choice_pressed.bind(int(entry.get("choice_index", -1))))
		_choice_container.add_child(btn)


func _build_reveal_skip_choice() -> void:
	_clear_choices()
	_choice_container.visible = true
	var btn := Button.new()
	btn.text = "..."
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.pressed.connect(_on_reveal_skip_pressed)
	_choice_container.add_child(btn)


func _on_choice_pressed(index: int) -> void:
	var line: Dictionary = _lines[_line_index]
	var choices: Array = line.get("choices", [])
	if index < 0 or index >= choices.size():
		return
	var choice: Dictionary = choices[index]

	MvTriggerEngine.fire_event("dialogue_choice", {
		"dialogue_id": _current_id,
		"line_index": _line_index,
		"choice_index": index,
		"choice_text": str(choice.get("text", "")),
	})

	if not _run_actions(choice.get("actions", [])):
		return
	_waiting_choice = false
	_line_has_choices = false
	_pending_choices.clear()
	_visible_choices.clear()
	_clear_choices()
	_advance(choice.get("next_line", null))


func _on_reveal_skip_pressed() -> void:
	if not _revealing:
		return
	_char_index = _full_text.length()
	_text_label.text = _full_text
	_revealing = false
	_refresh_runtime_ui()
	_finish_line_reveal()


func _clear_choices() -> void:
	if _choice_container == null:
		return
	for child in _choice_container.get_children():
		child.queue_free()
	_choice_container.visible = false
	_refresh_runtime_ui()


func _run_actions(actions: Variant) -> bool:
	if typeof(actions) != TYPE_ARRAY:
		return true
	var starting_id := _current_id
	for action in actions:
		if typeof(action) != TYPE_DICTIONARY:
			continue
		if action.get("type", "") == "end_dialogue":
			stop()
			return false
		MvTriggerEngine.execute_action(action, {})
		if not _active:
			return false
		if _current_id != starting_id:
			return false
	return true


# ── IO ──────────────────────────────────────────────────────────────────

func _load_dialogue(dialogue_id: String) -> Dictionary:
	var path := MvPackLoader.resolve_read_cascade(
		_current_pack_id(), "Dialogue", dialogue_id + ".json")
	var raw := MvPackLoader.read_json_dict(path)
	if raw.is_empty():
		push_warning("MvDialogueRunner: dialogue '%s' not found" % dialogue_id)
	return raw


func _current_pack_id() -> String:
	if MvPackLoader.current_pack != null:
		return MvPackLoader.current_pack.pack_id
	return "demo"


func current_ui_state() -> Dictionary:
	var line: Dictionary = {}
	if _line_index >= 0 and _line_index < _lines.size():
		line = _lines[_line_index]
	var visible_text := _full_text.substr(0, _char_index) if _char_index > 0 else ""
	return {
		"speaker": str(line.get("speaker", "")),
		"text": visible_text,
		"full_text": _full_text,
		"choices": _choice_items_for_ui(),
		"dialogue_id": _current_id,
		"line_index": _line_index,
	}


# ── UI construction ─────────────────────────────────────────────────────

func _build_ui() -> void:
	_panel = Control.new()
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.anchor_top = 1.0
	_panel.offset_top = -BOX_HEIGHT - BOX_MARGIN
	_panel.offset_bottom = -BOX_MARGIN
	_panel.offset_left = BOX_MARGIN
	_panel.offset_right = -BOX_MARGIN
	_panel.draw.connect(_draw_panel_bg)

	_speaker_label = Label.new()
	_speaker_label.anchor_right = 1.0
	_speaker_label.offset_left = 10.0
	_speaker_label.offset_top = 4.0
	_speaker_label.offset_right = -10.0
	_speaker_label.offset_bottom = 22.0
	_speaker_label.add_theme_color_override("font_color", UIPanels.text_color("title"))
	_speaker_label.add_theme_font_size_override("font_size", UIPanels.font_size("body_size"))
	_panel.add_child(_speaker_label)

	_text_label = RichTextLabel.new()
	_text_label.anchor_right = 1.0
	_text_label.offset_left = 12.0
	_text_label.offset_top = 28.0
	_text_label.offset_right = -12.0
	_text_label.offset_bottom = 112.0
	_text_label.bbcode_enabled = false
	_text_label.scroll_active = false
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.fit_content = true
	_text_label.add_theme_color_override("default_color", UIPanels.text_color("body"))
	_text_label.add_theme_font_size_override("normal_font_size", UIPanels.font_size("hint_size"))
	_panel.add_child(_text_label)

	_choice_container = VBoxContainer.new()
	_choice_container.anchor_right = 1.0
	_choice_container.anchor_bottom = 1.0
	_choice_container.offset_right = -12
	_choice_container.offset_left = 12
	_choice_container.offset_top = 120
	_choice_container.offset_bottom = -12
	_choice_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_container.add_theme_constant_override("separation", 6)
	_choice_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_choice_container.visible = false
	_panel.add_child(_choice_container)

	add_child(_panel)


func _draw_panel_bg() -> void:
	UIPanels.draw_panel(_panel, Rect2(Vector2.ZERO, _panel.size), Color.WHITE, UIPanels.PanelVariant.ALT)


func _has_authored_screen() -> bool:
	return _authored_screen != null and _authored_screen.visible and _authored_screen.has_method("has_screen") and _authored_screen.has_screen()


func _refresh_authored_screen() -> void:
	if _authored_screen == null:
		return
	var pack_id := _current_pack_id()
	if pack_id.is_empty() or not UIIo.screen_exists(pack_id, "dialogue_box"):
		_authored_pack_id = ""
		_authored_screen.call("clear_screen")
		_panel.visible = true
		return
	if pack_id != _authored_pack_id or not _authored_screen.call("has_screen"):
		_authored_pack_id = pack_id
		var data: Dictionary = UIIo.load_screen(pack_id, "dialogue_box")
		_authored_screen.call("load_screen", "dialogue_box", data, HudDataSource.new(null, null))
	_authored_screen.visible = true
	_panel.visible = false


func _on_authored_action(action_id: String, _action_args: String, _element_id: String) -> void:
	_emit_ui_button_event(action_id, _action_args, _element_id)
	match action_id:
		"close_screen", "end_dialogue":
			stop()
		"choose_dialogue":
			if _revealing:
				_on_reveal_skip_pressed()
				return
			if _action_args.is_valid_int():
				_on_choice_pressed(int(_action_args))
		"open_screen":
			if _action_args in ["boss_intro", "cinematic"]:
				UiHostActions.open_cinematic(_current_pack_id(), "dialogue_runner", _action_args)
			elif not _action_args.is_empty() and _action_args.begins_with("shop:"):
				var shop_id := _action_args.substr(5)
				stop()
				MvShopUI.open_shop(shop_id)
			else:
				push_warning("MvDialogueRunner: open_screen currently supports only 'shop:<id>'")
		"fire_event":
			UiHostActions.fire_authored_event("dialogue_box", "dialogue_runner", _action_args, _element_id, {
				"dialogue_id": _current_id,
				"line_index": _line_index,
			})
		"play_sfx":
			UiHostActions.play_authored_sfx(_action_args)
		_:
			UiHostActions.warn_unhandled_action("dialogue_runner", action_id)


func _emit_ui_button_event(action_id: String, action_args: String, element_id: String) -> void:
	UiHostActions.emit_ui_button_event("dialogue_box", "dialogue_runner", action_id, action_args, element_id, {
		"dialogue_id": _current_id,
		"line_index": _line_index,
	})


func _collect_visible_choices(choices_v: Variant) -> Array:
	var visible: Array = []
	if typeof(choices_v) != TYPE_ARRAY:
		return visible
	var choices: Array = choices_v
	for i in range(choices.size()):
		var choice_v: Variant = choices[i]
		if typeof(choice_v) != TYPE_DICTIONARY:
			continue
		var choice: Dictionary = choice_v
		if choice.has("condition") and not MvTriggerEngine.evaluate_condition(choice["condition"], {}):
			continue
		visible.append({
			"choice_index": i,
			"text": str(choice.get("text", "...")),
		})
	return visible


func _finish_line_reveal() -> void:
	_text_label.text = _full_text
	if not _line_has_choices:
		_refresh_runtime_ui()
		return
	if _pending_choices.is_empty():
		_line_has_choices = false
		_refresh_runtime_ui()
		_advance()
		return
	_waiting_choice = true
	_visible_choices = _pending_choices.duplicate(true)
	_pending_choices.clear()
	_build_choices(_visible_choices)
	_refresh_runtime_ui()


func _choice_items_for_ui() -> Array:
	if _revealing and _line_has_choices:
		return [{
			"label": "...",
			"text": "...",
			"choice_index": -1,
		}]
	if not _waiting_choice:
		return []
	var items: Array = []
	for entry_v in _visible_choices:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var label := str(entry.get("text", "..."))
		items.append({
			"label": label,
			"text": label,
			"choice_index": int(entry.get("choice_index", -1)),
		})
	return items


func _refresh_runtime_ui() -> void:
	if _authored_screen != null and _authored_screen.visible:
		_authored_screen.queue_redraw()
