class_name DlgConditionsListForm
extends VBoxContainer

signal changed

var _rows_box: VBoxContainer = null
var _add_btn: Button = null
var _rows: Array = []  # [{row, form}]
var _suppress_emit: bool = false


func _ready() -> void:
    _build_ui()


func _build_ui() -> void:
    _rows_box = VBoxContainer.new()
    add_child(_rows_box)

    var footer := HBoxContainer.new()
    add_child(footer)
    var lbl := Label.new()
    lbl.text = "Only run if:"
    lbl.tooltip_text = "These checks decide whether the rule may run after its event fires."
    footer.add_child(lbl)
    _add_btn = Button.new()
    _add_btn.text = "+ Add"
    _add_btn.tooltip_text = "Append another check."
    _add_btn.pressed.connect(_on_add_pressed)
    footer.add_child(_add_btn)


func open(conditions: Array) -> void:
    _suppress_emit = true
    _clear_rows()
    for cond_v in conditions:
        if typeof(cond_v) != TYPE_DICTIONARY:
            continue
        _append_row(cond_v)
    _suppress_emit = false


func get_value() -> Array:
    var out: Array = []
    for row_v in _rows:
        var row: Dictionary = row_v
        var form: DlgConditionForm = row.get("form")
        if form == null:
            continue
        var value: Dictionary = form.get_value()
        if not value.is_empty():
            out.append(value)
    return out


func has_error() -> bool:
    for row_v in _rows:
        var row: Dictionary = row_v
        var form: DlgConditionForm = row.get("form")
        if form != null and form.has_error():
            return true
    return false


func error_text() -> String:
    for row_v in _rows:
        var row: Dictionary = row_v
        var form: DlgConditionForm = row.get("form")
        if form != null and form.has_error():
            return form.error_text()
    return ""


func _on_add_pressed() -> void:
    _append_row({})
    _emit_changed()


func _append_row(seed_data: Dictionary) -> void:
    var row := VBoxContainer.new()
    row.add_theme_constant_override("separation", 4)
    _rows_box.add_child(row)

    var header := HBoxContainer.new()
    row.add_child(header)

    var title := Label.new()
    title.text = "Check"
    title.tooltip_text = "One requirement in this rule."
    title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
    header.add_child(title)

    var del_btn := Button.new()
    del_btn.text = "X"
    del_btn.tooltip_text = "Delete this condition clause."
    del_btn.pressed.connect(_on_delete_row.bind(row))
    header.add_child(del_btn)

    var form := DlgConditionForm.new()
    form.changed.connect(_emit_changed)
    row.add_child(form)
    form.open(seed_data)

    var sep := HSeparator.new()
    row.add_child(sep)

    _rows.append({"row": row, "form": form})


func _on_delete_row(row_box: VBoxContainer) -> void:
    for i in range(_rows.size()):
        if (_rows[i] as Dictionary).get("row") == row_box:
            _rows.remove_at(i)
            break
    row_box.queue_free()
    _emit_changed()


func _clear_rows() -> void:
    for row_v in _rows:
        var row: VBoxContainer = (row_v as Dictionary).get("row")
        if row != null:
            row.queue_free()
    _rows.clear()


func _emit_changed() -> void:
    if not _suppress_emit:
        changed.emit()
