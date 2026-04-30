extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const RlmTypes = preload("res://Space/scripts/editor/rlm/rlm_types.gd")

var editor: Node = null

const PAD_X: float = 16.0
const ROW_H: float = 30.0
const GAP_SM: float = 4.0
const GAP_LG: float = 14.0

var _tool_rects: Array = []
var _layer_rects: Array = []
var _action_rects: Array = []


func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	set_process(true)


func _process(_delta):
	queue_redraw()


func _gui_input(event):
	if editor == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			for entry in _tool_rects:
				if (entry["rect"] as Rect2).has_point(mb.position):
					editor.active_tool = int(entry["tool"])
					accept_event()
					return
			for entry in _layer_rects:
				if (entry["rect"] as Rect2).has_point(mb.position):
					editor.active_realm_layer = int(entry["layer"])
					accept_event()
					return
			for entry in _action_rects:
				if (entry["rect"] as Rect2).has_point(mb.position):
					var action := str(entry["action"])
					if action == "apply_anim" and editor.has_method("apply_selected_animation_to_hover_cell"):
						editor.apply_selected_animation_to_hover_cell()
					elif action == "clear_anim" and editor.has_method("clear_hover_cell_animation"):
						editor.clear_hover_cell_animation()
					accept_event()
					return


func _draw():
	UIPanels.draw_panel(self, Rect2(Vector2.ZERO, size),
		Color.WHITE, UIPanels.PanelVariant.DARK)

	if editor == null:
		return
	var font := ThemeDB.fallback_font
	var mouse_pos := get_local_mouse_position()
	var btn_w: float = size.x - PAD_X * 2.0
	var y: float = 16.0

	_tool_rects.clear()
	_layer_rects.clear()
	_action_rects.clear()

	_draw_section_label(font, y, "TOOLS")
	y += 18.0
	var tool_defs := [
		{"tool": RlmTypes.TOOL_PAINT, "label": "PAINT", "tint": Color(0.45, 0.85, 0.55),
			"tip": "Paint tool. LMB drag on the realm canvas to place the selected tile on the active layer."},
		{"tool": RlmTypes.TOOL_ERASE, "label": "ERASE", "tint": Color(0.9, 0.5, 0.45),
			"tip": "Erase tool. LMB drag clears tiles on the active layer. RMB always erases regardless of the selected tool."},
		{"tool": RlmTypes.TOOL_FILL, "label": "FILL", "tint": Color(0.6, 0.7, 1.0),
			"tip": "Flood-fill tool. LMB fills all connected cells of the same value on the active layer with the selected tile."},
		{"tool": RlmTypes.TOOL_PICK, "label": "PICK", "tint": Color(0.95, 0.85, 0.4),
			"tip": "Eyedropper. LMB samples the tile under the cursor on the active layer so you can paint with it."},
	]
	for def in tool_defs:
		var rect := Rect2(PAD_X, y, btn_w, ROW_H)
		_tool_rects.append({"tool": def["tool"], "rect": rect})
		var is_active: bool = int(def["tool"]) == editor.active_tool
		var tint: Color = def["tint"]
		if not is_active:
			tint = Color(tint.r * 0.5, tint.g * 0.5, tint.b * 0.5, 1.0)
		var hover := rect.has_point(mouse_pos)
		UIPanels.draw_button_bg(self, rect, hover, tint)
		var label_col := Color(1, 1, 1, 1) if is_active else Color(0.65, 0.72, 0.85, 1)
		draw_string(font, Vector2(rect.position.x + 12, rect.position.y + 20),
			str(def["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, label_col)
		if hover:
			EditorTooltip.show_text(str(def["tip"]))
		y += ROW_H + GAP_SM

	y += GAP_LG

	_draw_section_label(font, y, "LAYER")
	y += 18.0
	for i in 3:
		var rect := Rect2(PAD_X, y, btn_w, ROW_H)
		_layer_rects.append({"layer": i, "rect": rect})
		var is_active: bool = i == editor.active_realm_layer
		var tint: Color = RlmTypes.layer_color(i)
		if not is_active:
			tint = Color(tint.r * 0.45, tint.g * 0.45, tint.b * 0.45, 1.0)
		var hover := rect.has_point(mouse_pos)
		UIPanels.draw_button_bg(self, rect, hover, tint)
		var label_col := Color(1, 1, 1, 1) if is_active else Color(0.65, 0.72, 0.85, 1)
		draw_string(font, Vector2(rect.position.x + 12, rect.position.y + 20),
			RlmTypes.layer_name(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, label_col)
		if hover:
			EditorTooltip.show_text("Switch to the %s layer. Only the active layer is painted/erased; other layers are dimmed for reference." % RlmTypes.layer_name(i))
		y += ROW_H + GAP_SM

	y += GAP_LG
	_draw_section_label(font, y, "ANIMATION")
	y += 18.0
	var action_defs := [
		{"action": "apply_anim", "label": "SET ANIM", "tint": Color(0.5, 0.82, 1.0),
			"tip": "Apply an animation to the last realm cell you hovered. The current tileset selection becomes the frame strip."},
		{"action": "clear_anim", "label": "CLEAR ANIM", "tint": Color(0.86, 0.5, 0.42),
			"tip": "Remove animation data from the last realm cell you hovered without erasing its tile."},
	]
	for def in action_defs:
		var rect := Rect2(PAD_X, y, btn_w, ROW_H)
		_action_rects.append({"action": def["action"], "rect": rect})
		var hover := rect.has_point(mouse_pos)
		UIPanels.draw_button_bg(self, rect, hover, def["tint"])
		draw_string(font, Vector2(rect.position.x + 12, rect.position.y + 20),
			str(def["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 1))
		if hover:
			EditorTooltip.show_text(str(def["tip"]))
		y += ROW_H + GAP_SM

	var hint := "MMB: pan  Wheel: zoom"
	draw_string(font, Vector2(PAD_X, size.y - 28),
		hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.58, 0.7, 1))
	var hint2 := "LMB: tool   RMB: erase"
	draw_string(font, Vector2(PAD_X, size.y - 14),
		hint2, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.58, 0.7, 1))


func _draw_section_label(font: Font, y: float, text: String) -> void:
	draw_string(font, Vector2(PAD_X, y + 14),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIPanels.TEXT_PANEL)
