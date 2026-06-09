class_name MvDialogueEditor
extends CanvasLayer

# In-game dialogue editor (Frontier 2 / D1+D2). Opened from the dev console with
# `dialogue` / `dlg`. Lists the pack's dialogues, edits lines (speaker + text +
# branching choices), saves Dialogue/<id>.json, and previews via MvDialogueRunner.
#
# To trigger a dialogue in-game, use the `triggers` editor (event `interact` →
# action `start_dialogue` with this id), or give an interactable a dialogue_id.

const DlgIO := preload("res://Space/scripts/shared/dlg/dlg_io.gd")

var _id := ""               # current dialogue id ("" = list view)
var _data: Dictionary = {}  # working {lines:[...]}
var _new_id_field: LineEdit = null

var _skin_host: Control = null
var _title: Label = null
var _content: VBoxContainer = null
var _status: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 134
	_build_shell()
	visible = false


func open_editor() -> void:
	_id = ""
	if _skin_host != null:
		_skin_host.theme = NebulaTheme.theme()
	PlanetaryInterface.edit_session_active = true
	MvGame.simulation_paused = true
	visible = true
	_set_status("")
	_show()


func close_editor() -> void:
	visible = false
	PlanetaryInterface.edit_session_active = false
	MvGame.simulation_paused = false


func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.color = NebulaTheme.C_PANEL_DARK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.theme = NebulaTheme.theme()
	_skin_host = margin
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	add_child(margin)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root.add_child(header)
	_title = NebulaTheme.title_label("Dialogue")
	header.add_child(_title)
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(hsp)
	var close := NebulaUi.button("✕", "ghost")
	close.pressed.connect(close_editor)
	header.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)


func _show() -> void:
	for c in _content.get_children():
		c.queue_free()
	if _id.is_empty():
		_build_list()
	else:
		_build_edit()


# ── List view ────────────────────────────────────────────────────────────────

func _build_list() -> void:
	_title.text = "DIALOGUE"
	var wp := NebulaUi.work_panel("Conversations")
	var panel: Control = wp["root"]
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.custom_minimum_size = Vector2(820, 0)
	_content.add_child(panel)
	var body: VBoxContainer = wp["body"]
	var ids := DlgIO.list_dialogues(_pack_id())
	if ids.is_empty():
		body.add_child(_hint("No conversations yet. Create one below, then trigger it with the `triggers` editor (event interact → action start_dialogue)."))
	for id_v in ids:
		body.add_child(_dialogue_row(str(id_v)))
	body.add_child(NebulaUi.section_header("New conversation"))
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 8)
	body.add_child(nrow)
	_new_id_field = LineEdit.new()
	_new_id_field.placeholder_text = "id (lowercase, no spaces)"
	_new_id_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(_new_id_field)
	var create := NebulaUi.button("＋ Create", "primary")
	create.pressed.connect(_create_new)
	nrow.add_child(create)


func _dialogue_row(id: String) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", NebulaTheme.card_box())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var lbl := Label.new()
	lbl.text = id
	lbl.add_theme_color_override("font_color", NebulaTheme.C_BODY)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var play := NebulaUi.button("▶ Play", "gold")
	play.pressed.connect(func(): _play(id))
	row.add_child(play)
	var open := NebulaUi.button("Edit", "primary")
	open.pressed.connect(func():
		_id = id
		_data = DlgIO.load_dialogue(_pack_id(), id)
		_show())
	row.add_child(open)
	var del := NebulaUi.button("✕", "ghost")
	del.pressed.connect(func():
		DlgIO.delete_dialogue(_pack_id(), id)
		_show())
	row.add_child(del)
	return card


func _create_new() -> void:
	var id := _new_id_field.text.strip_edges().to_lower().replace(" ", "_") if _new_id_field != null else ""
	if id.is_empty():
		_set_status("enter an id first", true)
		return
	if DlgIO.exists(_pack_id(), id):
		_set_status("'%s' already exists — opening it" % id)
	else:
		DlgIO.save_dialogue(_pack_id(), id, DlgIO.default_dialogue())
	_id = id
	_data = DlgIO.load_dialogue(_pack_id(), id)
	_show()


# ── Edit view ────────────────────────────────────────────────────────────────

func _build_edit() -> void:
	_title.text = "DIALOGUE  ·  %s" % _id
	var lines: Array = _data.get("lines", [])
	_data["lines"] = lines
	for li in lines.size():
		_content.add_child(_line_card(li))
	var add := NebulaUi.button("＋ Add line", "primary")
	add.pressed.connect(func():
		lines.append({"speaker": "", "text": ""})
		_show())
	_content.add_child(add)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	_content.add_child(nav)
	var back := NebulaUi.button("← Conversations", "ghost")
	back.pressed.connect(func():
		_id = ""
		_show())
	nav.add_child(back)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(sp)
	var play := NebulaUi.button("▶ Play", "gold")
	play.pressed.connect(func():
		if _save():
			_play(_id))
	nav.add_child(play)
	var save := NebulaUi.button("Save", "primary")
	save.pressed.connect(func():
		if _save():
			_set_status("saved '%s' (%d lines)" % [_id, lines.size()]))
	nav.add_child(save)


func _line_card(li: int) -> Control:
	var lines: Array = _data["lines"]
	var line: Dictionary = lines[li]
	var wp := NebulaUi.work_panel("Line %d" % li)
	var panel: Control = wp["root"]
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.custom_minimum_size = Vector2(860, 0)
	var body: VBoxContainer = wp["body"]
	# Line controls row: speaker + reorder/remove.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	body.add_child(head)
	var spk := LineEdit.new()
	spk.text = str(line.get("speaker", ""))
	spk.placeholder_text = "speaker"
	spk.custom_minimum_size = Vector2(220, 0)
	spk.text_changed.connect(func(t): line["speaker"] = t)
	head.add_child(spk)
	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(grow)
	var up := NebulaUi.button("▲", "ghost")
	up.pressed.connect(func(): _move_line(li, -1))
	head.add_child(up)
	var down := NebulaUi.button("▼", "ghost")
	down.pressed.connect(func(): _move_line(li, 1))
	head.add_child(down)
	var rm := NebulaUi.button("✕", "ghost")
	rm.pressed.connect(func():
		lines.remove_at(li)
		if lines.is_empty():
			lines.append({"speaker": "", "text": ""})
		_show())
	head.add_child(rm)
	# Text.
	var txt := TextEdit.new()
	txt.text = str(line.get("text", ""))
	txt.placeholder_text = "line text"
	txt.custom_minimum_size = Vector2(0, 56)
	txt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	txt.text_changed.connect(func(): line["text"] = txt.text)
	body.add_child(txt)
	# Choices.
	var choices: Array = line.get("choices", [])
	if not choices.is_empty():
		line["choices"] = choices
		body.add_child(NebulaUi.section_header("Choices (branch to a line)"))
		for ci in choices.size():
			body.add_child(_choice_row(choices, ci, lines.size()))
	var addc := NebulaUi.button("＋ Add choice", "ghost")
	addc.pressed.connect(func():
		var arr: Array = line.get("choices", [])
		arr.append({"text": "Option", "next_line": mini(li + 1, lines.size() - 1)})
		line["choices"] = arr
		_show())
	body.add_child(addc)
	return panel


func _choice_row(choices: Array, ci: int, line_count: int) -> Control:
	var ch: Dictionary = choices[ci]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var t := LineEdit.new()
	t.text = str(ch.get("text", ""))
	t.placeholder_text = "choice text"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.text_changed.connect(func(x): ch["text"] = x)
	row.add_child(t)
	var arrow := Label.new()
	arrow.text = "→ line"
	arrow.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	row.add_child(arrow)
	var nx := SpinBox.new()
	nx.min_value = -1
	nx.max_value = maxi(0, line_count - 1)
	nx.step = 1
	# -1 means "end"; an int is a line index.
	var cur: Variant = ch.get("next_line", -1)
	nx.value = (-1 if str(cur) == "end" else float(cur))
	nx.value_changed.connect(func(v): ch["next_line"] = ("end" if int(v) < 0 else int(v)))
	row.add_child(nx)
	var del := NebulaUi.button("✕", "ghost")
	del.pressed.connect(func():
		choices.remove_at(ci)
		_show())
	row.add_child(del)
	return row


# ── Helpers ──────────────────────────────────────────────────────────────────

func _move_line(li: int, dir: int) -> void:
	var lines: Array = _data["lines"]
	var j := li + dir
	if j < 0 or j >= lines.size():
		return
	var tmp: Variant = lines[li]
	lines[li] = lines[j]
	lines[j] = tmp
	_show()


func _save() -> bool:
	var lines: Array = _data.get("lines", [])
	if lines.is_empty():
		_set_status("a conversation needs at least one line", true)
		return false
	if not DlgIO.save_dialogue(_pack_id(), _id, _data):
		_set_status("save failed for '%s'" % _id, true)
		return false
	return true


func _play(id: String) -> void:
	# Close the editor and play the conversation in-game; it ends back in play.
	close_editor()
	MvDialogueRunner.start(id)


func _pack_id() -> String:
	if MvPackLoader.current_pack != null:
		return str(MvPackLoader.current_pack.pack_id)
	if not str(PlanetaryInterface.pending_pack_id).is_empty():
		return str(PlanetaryInterface.pending_pack_id)
	return "demo"


func _hint(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	return l


func _set_status(msg: String, is_err := false) -> void:
	if _status != null:
		_status.text = msg
		_status.add_theme_color_override("font_color", NebulaTheme.C_ERROR if is_err else NebulaTheme.C_SUCCESS)
