extends Control

# Modal for editing a single room's flag-gated variant rules. Backed by
# the region's Regions/<region_id>/room_variants.json file — the modal
# loads the whole file, edits this room's entry, and saves the merged
# file back so other rooms' rules in the same region aren't disturbed.
#
# Fired by env_topbar's VARIANTS button. The environment editor passes
# the canonical room id, the sibling room ids (for the "use" picker),
# and the loaded variants_root. On OK the modal emits `submitted` with
# the updated variants_root dict; on Cancel it emits `cancelled`.

signal submitted(variants_root: Dictionary)
signal cancelled

const TYPES: Array = ["bool", "int", "float", "string", "null"]
const SCOPES: Array = ["planet", "global"]

var _pack_id: String = ""
var _region_id: String = ""
var _canonical_room_id: String = ""
var _sibling_room_ids: Array = []      # bare room ids in this region, minus canonical
var _variants_root: Dictionary = {}    # full room_variants.json contents
var _rows: Array = []                  # [{row: HBoxContainer, scope: OptionButton, ...}, ...]
var _rows_box: VBoxContainer = null
var _title_label: Label = null
var _hint_label: Label = null
var _add_btn: Button = null
var _ok_btn: Button = null
var _cancel_btn: Button = null
var _scroll: ScrollContainer = null


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	_build_ui()


func _build_ui() -> void:
	# Dim background panel that fills the screen and intercepts clicks
	# outside the central box.
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_bg_input)
	add_child(bg)

	# Centered panel host.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 540)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-360, -270)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_title_label)

	_hint_label = Label.new()
	_hint_label.text = "When a flag matches, this room loads the alternate's data instead of its own — but doors, the map, and save snapshots keep using this canonical id. Rules are evaluated top-to-bottom; the first match wins. Alternates can't themselves have variants (no chains)."
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_font_size_override("font_size", 10)
	_hint_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	_hint_label.custom_minimum_size = Vector2(680, 0)
	vbox.add_child(_hint_label)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(680, 360)
	vbox.add_child(_scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 4)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows_box)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	vbox.add_child(footer)

	_add_btn = Button.new()
	_add_btn.text = "+ Add variant"
	_add_btn.tooltip_text = "Add a new flag-gated variant rule."
	_add_btn.pressed.connect(_on_add_pressed)
	footer.add_child(_add_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	footer.add_child(_cancel_btn)

	_ok_btn = Button.new()
	_ok_btn.text = "OK"
	_ok_btn.pressed.connect(_on_ok_pressed)
	footer.add_child(_ok_btn)


# Called by environment_editor.request_edit_room_variants. Stashes the
# context, populates rows from the room's existing rule list (or empty
# if none), shows the modal.
func open_for_room(pack_id: String, region_id: String, canonical_room_id: String,
		sibling_room_ids: Array, variants_root: Dictionary) -> void:
	_pack_id = pack_id
	_region_id = region_id
	_canonical_room_id = canonical_room_id
	_sibling_room_ids = []
	for sid_v in sibling_room_ids:
		var sid := str(sid_v)
		if not sid.is_empty() and sid != canonical_room_id:
			_sibling_room_ids.append(sid)
	_sibling_room_ids.sort()
	_variants_root = variants_root.duplicate(true) if not variants_root.is_empty() else {
		"version": "1.0",
		"region_id": region_id,
		"variants": {},
	}
	if typeof(_variants_root.get("variants", null)) != TYPE_DICTIONARY:
		_variants_root["variants"] = {}

	_title_label.text = "Room Variants — %s" % canonical_room_id

	_clear_rows()
	var existing_v: Variant = (_variants_root["variants"] as Dictionary).get(canonical_room_id, [])
	if typeof(existing_v) == TYPE_ARRAY:
		for rule_v in existing_v:
			if typeof(rule_v) == TYPE_DICTIONARY:
				_append_row(rule_v)
	visible = true


func _on_bg_input(event: InputEvent) -> void:
	# Click outside the central panel cancels.
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_on_cancel_pressed()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()


func _on_add_pressed() -> void:
	_append_row({})


func _append_row(rule: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_rows_box.add_child(row)

	var scope_pick := OptionButton.new()
	for scope_v in SCOPES:
		scope_pick.add_item(str(scope_v))
	scope_pick.tooltip_text = "Flag namespace. 'planet' flags wipe between visits; 'global' flags survive save/load."
	var when_v: Variant = rule.get("when", {})
	var when_dict: Dictionary = when_v if typeof(when_v) == TYPE_DICTIONARY else {}
	var scope_str := str(when_dict.get("scope", "planet")).strip_edges().to_lower()
	var scope_idx := maxi(0, SCOPES.find(scope_str))
	scope_pick.select(scope_idx)
	scope_pick.custom_minimum_size = Vector2(90, 0)
	row.add_child(scope_pick)

	var flag_edit := LineEdit.new()
	flag_edit.placeholder_text = "flag name"
	flag_edit.tooltip_text = "Flag name as written by triggers (set_flag) or read by trigger conditions (var_eq)."
	flag_edit.text = str(when_dict.get("flag", ""))
	flag_edit.custom_minimum_size = Vector2(160, 0)
	row.add_child(flag_edit)

	var equals_pick := OptionButton.new()
	for type_v in TYPES:
		equals_pick.add_item(str(type_v))
	equals_pick.tooltip_text = "Type of the comparison value. 'null' matches an unset flag."
	equals_pick.custom_minimum_size = Vector2(80, 0)
	row.add_child(equals_pick)

	var equals_edit := LineEdit.new()
	equals_edit.placeholder_text = "value"
	equals_edit.tooltip_text = "Value the flag must equal. Booleans accept true/false; ints/floats parse as numbers."
	equals_edit.custom_minimum_size = Vector2(110, 0)
	row.add_child(equals_edit)

	var equals_raw: Variant = when_dict.get("equals", null) if when_dict.has("equals") else null
	var equals_type_idx: int = _equals_type_index_for(equals_raw, when_dict.has("equals"))
	equals_pick.select(equals_type_idx)
	equals_edit.text = _equals_text_for(equals_raw)
	equals_pick.item_selected.connect(func(idx: int): _on_equals_type_changed(idx, equals_edit))

	var use_pick := OptionButton.new()
	use_pick.tooltip_text = "Alternate room loaded when this rule matches. Must be a sibling room in this region."
	use_pick.custom_minimum_size = Vector2(170, 0)
	for sid_v in _sibling_room_ids:
		use_pick.add_item(str(sid_v))
	var use_room: String = str(rule.get("use", "")).strip_edges()
	var use_idx: int = _sibling_room_ids.find(use_room)
	if use_idx < 0:
		# Author may have an alt that no longer exists; surface it as a
		# disabled-ish entry so the row reads clearly. Append at end.
		if not use_room.is_empty():
			use_pick.add_item("%s  (missing)" % use_room)
			use_idx = use_pick.get_item_count() - 1
		else:
			use_idx = 0 if not _sibling_room_ids.is_empty() else -1
	if use_idx >= 0:
		use_pick.select(use_idx)
	row.add_child(use_pick)

	var del_btn := Button.new()
	del_btn.text = "X"
	del_btn.tooltip_text = "Delete this rule."
	del_btn.pressed.connect(_on_delete_row.bind(row))
	row.add_child(del_btn)

	_rows.append({
		"row": row,
		"scope": scope_pick,
		"flag": flag_edit,
		"equals_type": equals_pick,
		"equals_value": equals_edit,
		"use": use_pick,
	})


func _on_equals_type_changed(idx: int, equals_edit: LineEdit) -> void:
	# Disable the value field when the user picks 'null' (no value to enter).
	if idx >= 0 and idx < TYPES.size() and TYPES[idx] == "null":
		equals_edit.editable = false
		equals_edit.text = ""
		equals_edit.placeholder_text = "(unset)"
	else:
		equals_edit.editable = true
		equals_edit.placeholder_text = "value"


func _equals_type_index_for(value: Variant, has_equals: bool) -> int:
	if not has_equals or value == null:
		return TYPES.find("null")
	match typeof(value):
		TYPE_BOOL:
			return TYPES.find("bool")
		TYPE_INT:
			return TYPES.find("int")
		TYPE_FLOAT:
			return TYPES.find("float")
		_:
			return TYPES.find("string")


func _equals_text_for(value: Variant) -> String:
	if value == null:
		return ""
	if typeof(value) == TYPE_BOOL:
		return "true" if bool(value) else "false"
	return str(value)


func _on_delete_row(row: HBoxContainer) -> void:
	for i in range(_rows.size()):
		if (_rows[i] as Dictionary).get("row") == row:
			_rows.remove_at(i)
			break
	row.queue_free()


func _clear_rows() -> void:
	for entry_v in _rows:
		var entry: Dictionary = entry_v
		var row: HBoxContainer = entry.get("row")
		if row != null:
			row.queue_free()
	_rows.clear()


func _on_cancel_pressed() -> void:
	visible = false
	cancelled.emit()


func _on_ok_pressed() -> void:
	var rules: Array = []
	for entry_v in _rows:
		var entry: Dictionary = entry_v
		var scope_pick: OptionButton = entry.get("scope")
		var flag_edit: LineEdit = entry.get("flag")
		var equals_type: OptionButton = entry.get("equals_type")
		var equals_value: LineEdit = entry.get("equals_value")
		var use_pick: OptionButton = entry.get("use")
		if scope_pick == null or flag_edit == null or equals_type == null \
				or equals_value == null or use_pick == null:
			continue
		var flag_name: String = flag_edit.text.strip_edges()
		if flag_name.is_empty():
			continue  # Skip rules without a flag — author was probably mid-edit.
		var scope_idx: int = scope_pick.get_selected()
		var scope_str: String = SCOPES[scope_idx] if scope_idx >= 0 and scope_idx < SCOPES.size() else "planet"
		var use_idx: int = use_pick.get_selected()
		var use_str: String = use_pick.get_item_text(use_idx) if use_idx >= 0 else ""
		use_str = use_str.replace("  (missing)", "").strip_edges()
		if use_str.is_empty():
			continue
		var equals_kind_idx: int = equals_type.get_selected()
		var equals_kind: String = TYPES[equals_kind_idx] if equals_kind_idx >= 0 and equals_kind_idx < TYPES.size() else "bool"
		var when_dict: Dictionary = {
			"scope": scope_str,
			"flag": flag_name,
			"equals": _parse_equals_value(equals_kind, equals_value.text),
		}
		rules.append({"when": when_dict, "use": use_str})

	if typeof(_variants_root.get("variants", null)) != TYPE_DICTIONARY:
		_variants_root["variants"] = {}
	var variants_dict: Dictionary = _variants_root["variants"]
	if rules.is_empty():
		variants_dict.erase(_canonical_room_id)
	else:
		variants_dict[_canonical_room_id] = rules
	_variants_root["variants"] = variants_dict
	if not _variants_root.has("version"):
		_variants_root["version"] = "1.0"
	if not _variants_root.has("region_id"):
		_variants_root["region_id"] = _region_id

	visible = false
	submitted.emit(_variants_root)


# Coerces the typed value back into a proper Variant for on-disk storage.
# Mistyped values fall back gracefully (bool defaults false, numbers default
# zero) rather than killing the save.
func _parse_equals_value(kind: String, raw: String) -> Variant:
	var text: String = raw.strip_edges()
	match kind:
		"null":
			return null
		"bool":
			return text.to_lower() == "true" or text == "1"
		"int":
			return int(text) if text.is_valid_int() else 0
		"float":
			return float(text) if text.is_valid_float() else 0.0
		_:
			return text
