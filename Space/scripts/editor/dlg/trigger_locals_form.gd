class_name TriggerLocalsForm
extends VBoxContainer

signal changed

const TYPES: Array = ["int", "float", "bool", "string"]

var _rows_box: VBoxContainer = null
var _rows: Array = []
var _suppress_emit: bool = false


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	_rows_box = VBoxContainer.new()
	add_child(_rows_box)

	var footer := HBoxContainer.new()
	add_child(footer)
	var lbl := Label.new()
	lbl.text = "Locals:"
	lbl.tooltip_text = "Per-trigger local variables for scratch state inside this rule."
	footer.add_child(lbl)
	var hint := Label.new()
	hint.text = "Persistent locals keep their value between separate trigger firings."
	hint.tooltip_text = "Persistent locals survive across separate executions of the same rule. Non-persistent locals reset every time the rule fires."
	hint.add_theme_font_size_override("font_size", 10)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)
	var add_btn := Button.new()
	add_btn.text = "+ Add"
	add_btn.tooltip_text = "Add a new local variable row."
	add_btn.pressed.connect(_on_add_pressed)
	footer.add_child(add_btn)


func open(entries: Array) -> void:
	_suppress_emit = true
	_clear_rows()
	for entry_v in entries:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		_append_row(entry_v)
	_suppress_emit = false


func get_value() -> Array:
	var out: Array = []
	for row_v in _rows:
		var row: Dictionary = row_v
		var name_edit: LineEdit = row.get("name") as LineEdit
		var type_option: OptionButton = row.get("type") as OptionButton
		var default_edit: LineEdit = row.get("default") as LineEdit
		if name_edit == null or type_option == null or default_edit == null:
			continue
		var entry_name: String = name_edit.text.strip_edges()
		if entry_name.is_empty():
			continue
		var type_name: String = TYPES[type_option.get_selected()] if type_option.get_selected() >= 0 and type_option.get_selected() < TYPES.size() else "int"
		out.append({
			"name": entry_name,
			"type": type_name,
			"default": default_edit.text.strip_edges(),
			"persistent": (row.get("persistent") as CheckBox).button_pressed if row.get("persistent") is CheckBox else false,
		})
	return out


func has_error() -> bool:
	var seen: Dictionary = {}
	for row_v in _rows:
		var row: Dictionary = row_v
		var name_edit: LineEdit = row.get("name") as LineEdit
		if name_edit == null:
			continue
		var entry_name: String = name_edit.text.strip_edges()
		if entry_name.is_empty():
			continue
		if seen.has(entry_name):
			return true
		seen[entry_name] = true
	return false


func error_text() -> String:
	var seen: Dictionary = {}
	for row_v in _rows:
		var row: Dictionary = row_v
		var name_edit: LineEdit = row.get("name") as LineEdit
		if name_edit == null:
			continue
		var entry_name: String = name_edit.text.strip_edges()
		if entry_name.is_empty():
			continue
		if seen.has(entry_name):
			return "Duplicate local variable '%s'." % entry_name
		seen[entry_name] = true
	return ""


func _on_add_pressed() -> void:
	_append_row({})
	_emit_changed()


func _append_row(rng_seed: Dictionary) -> void:
	var row_box := HBoxContainer.new()
	_rows_box.add_child(row_box)

	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "name"
	name_edit.custom_minimum_size = Vector2(120, 0)
	name_edit.tooltip_text = "Local variable name. Use short stable ids like intro_step or boss_seen."
	name_edit.text = str(rng_seed.get("name", ""))
	name_edit.text_changed.connect(func(_t): _emit_changed())
	row_box.add_child(name_edit)

	var type_option := OptionButton.new()
	for type_name in TYPES:
		type_option.add_item(type_name)
	var selected := maxi(0, TYPES.find(str(rng_seed.get("type", "int")).to_lower()))
	type_option.select(selected)
	type_option.tooltip_text = "Storage type for this local variable."
	type_option.item_selected.connect(func(_idx): _emit_changed())
	row_box.add_child(type_option)

	var default_edit := LineEdit.new()
	default_edit.placeholder_text = "default"
	default_edit.custom_minimum_size = Vector2(120, 0)
	default_edit.tooltip_text = "Default value used when the local is first created."
	default_edit.text = str(rng_seed.get("default", ""))
	default_edit.text_changed.connect(func(_t): _emit_changed())
	row_box.add_child(default_edit)

	var persistent_check := CheckBox.new()
	persistent_check.text = "Persist"
	persistent_check.tooltip_text = "Keep this local's value between separate firings of the same rule."
	persistent_check.button_pressed = bool(rng_seed.get("persistent", false))
	persistent_check.toggled.connect(func(_on): _emit_changed())
	row_box.add_child(persistent_check)

	var del_btn := Button.new()
	del_btn.text = "X"
	del_btn.tooltip_text = "Delete this local variable row."
	del_btn.pressed.connect(_on_delete_row.bind(row_box))
	row_box.add_child(del_btn)

	_rows.append({
		"row": row_box,
		"name": name_edit,
		"type": type_option,
		"default": default_edit,
		"persistent": persistent_check,
	})


func _on_delete_row(row_box: HBoxContainer) -> void:
	for i in range(_rows.size()):
		if (_rows[i] as Dictionary).get("row") == row_box:
			_rows.remove_at(i)
			break
	row_box.queue_free()
	_emit_changed()


func _clear_rows() -> void:
	for row_v in _rows:
		var row_box: HBoxContainer = (row_v as Dictionary).get("row") as HBoxContainer
		if row_box != null:
			row_box.queue_free()
	_rows.clear()


func _emit_changed() -> void:
	if not _suppress_emit:
		changed.emit()
