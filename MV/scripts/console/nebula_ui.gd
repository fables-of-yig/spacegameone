class_name NebulaUi
extends RefCounted

# Nebula UI component builders — Godot Control recreations of the Claude Design
# "Nebula" reference components (nebulous/components/** + ui_kits/**). These build
# the chrome the guided editors share: framed work panels, section headers, the
# numbered step rail, track-select cards, and variant nav buttons. Colors/sizes
# come from NebulaTheme so they track the active scale profile.
#
# These are used by the modal editors (Combat Workshop, wizards) which render at
# full window resolution (the "full" profile) — see MvCombatWorkshop's content-
# scale flip and NebulaTheme's SCALE PROFILES note.

const NT := preload("res://MV/scripts/console/nebula_theme.gd")


# WorkPanel — a framed section card with an UPPERCASE cyan heading. Returns
# {"root": PanelContainer, "body": VBoxContainer} so callers fill the body.
static func work_panel(title: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)
	if not title.is_empty():
		outer.add_child(section_header(title))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	return {"root": panel, "body": body}


# SectionHeader — cyan marker + UPPERCASE label + hairline rule.
static func section_header(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var marker := PanelContainer.new()
	marker.add_theme_stylebox_override("panel", _solid_box(NT.C_ACCENT, 2))
	marker.custom_minimum_size = Vector2(4, 16)
	row.add_child(marker)
	var lbl := Label.new()
	lbl.text = text.to_upper()
	lbl.add_theme_color_override("font_color", NT.C_TITLE)
	lbl.add_theme_font_size_override("font_size", NT.size("section"))
	if NT.font() != null:
		lbl.add_theme_font_override("font", NT.font())
	row.add_child(lbl)
	var rule := PanelContainer.new()
	rule.add_theme_stylebox_override("panel", _solid_box(Color(NT.C_BORDER.r, NT.C_BORDER.g, NT.C_BORDER.b, 0.25), 1))
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rule)
	return row


# Labeled control row — fixed-width label + control filling the rest.
static func labeled(text: String, control: Control, label_w := 200) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", NT.C_BODY)
	l.custom_minimum_size = Vector2(label_w, 0)
	hb.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(control)
	return hb


# Nav / action button. variant: "primary" (cyan), "gold" (▶ Test), "ghost" (steel).
static func button(text: String, variant := "primary") -> Button:
	var b := Button.new()
	b.text = text
	match variant:
		"gold":
			b.self_modulate = NT.C_ACCENT_2
		"ghost":
			b.self_modulate = NT.C_BORDER
		_:
			pass
	return b


# StepRail — vertical numbered step list. `current` is the active index; steps
# before it render as done (green check). Clicking a row calls on_pick(index).
static func step_rail(titles: Array, subs: Array, current: int, on_pick: Callable) -> Control:
	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 4)
	for i in titles.size():
		rail.add_child(_step_row(i, str(titles[i]), str(subs[i]) if i < subs.size() else "", current, on_pick))
	return rail


static func _step_row(i: int, title: String, sub: String, current: int, on_pick: Callable) -> Control:
	var on := i == current
	var done := i < current
	var row := PanelContainer.new()
	if on:
		row.add_theme_stylebox_override("panel", NT.card_box(true))
	else:
		row.add_theme_stylebox_override("panel", _solid_box(Color(0, 0, 0, 0), 0))
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			on_pick.call(i))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	row.add_child(hb)
	hb.add_child(_step_badge(i, on, done))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var t := Label.new()
	t.text = title
	t.add_theme_color_override("font_color", NT.C_TITLE if on else (NT.C_BODY if done else NT.C_DIM))
	col.add_child(t)
	if not sub.is_empty():
		var s := Label.new()
		s.text = sub
		s.add_theme_color_override("font_color", NT.C_DIM)
		s.add_theme_font_size_override("font_size", NT.size("hint"))
		col.add_child(s)
	hb.add_child(col)
	return row


static func _step_badge(i: int, on: bool, done: bool) -> Control:
	var badge := PanelContainer.new()
	var d := 30 if NT.profile() == "full" else 20
	badge.custom_minimum_size = Vector2(d, d)
	var bg := NT.C_ACCENT if on else (NT.C_SUCCESS if done else NT.C_PANEL_ALT)
	var box := _solid_box(bg, 0)
	box.set_corner_radius_all(d / 2)
	if not on and not done:
		box.border_color = NT.C_BORDER
		box.set_border_width_all(1)
	badge.add_theme_stylebox_override("panel", box)
	var lbl := Label.new()
	lbl.text = "✓" if done else str(i + 1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", NT.C_INK if (on or done) else NT.C_DIM)
	badge.add_child(lbl)
	return badge


# TrackCard — a large clickable card for the entry track-select screen.
static func track_card(title: String, desc: String, on_pick: Callable, enabled := true) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_box())
	card.custom_minimum_size = Vector2(360, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	if enabled:
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				on_pick.call())
	else:
		card.modulate = Color(1, 1, 1, 0.5)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)
	var t := Label.new()
	t.text = title.to_upper()
	t.add_theme_color_override("font_color", NT.C_TITLE)
	t.add_theme_font_size_override("font_size", NT.size("title"))
	if NT.font() != null:
		t.add_theme_font_override("font", NT.font())
	col.add_child(t)
	var d := Label.new()
	d.text = desc
	d.add_theme_color_override("font_color", NT.C_BODY)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(320, 0)
	col.add_child(d)
	return card


# PreviewPane — a recessed well with a centered placeholder body and proportional
# hit/hurt box overlays (mockup's sprite-preview pane). `boxes` is an array of
# {x,y,w,h (0..1 fractions), color: Color, fill: bool, label: String}. An optional
# `sprite` Texture2D is drawn centered when provided (else a dashed placeholder).
static func preview_pane(label_text: String, boxes: Array, sprite: Texture2D = null, height := 300) -> Control:
	var pane := PanelContainer.new()
	pane.add_theme_stylebox_override("panel", NT.well_box())
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.custom_minimum_size = Vector2(0, height)
	var area := Control.new()
	area.set_anchors_preset(Control.PRESET_FULL_RECT)
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(area)

	if sprite != null:
		var tex := TextureRect.new()
		tex.texture = sprite
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		area.add_child(tex)
	else:
		var ph := PanelContainer.new()
		ph.add_theme_stylebox_override("panel", _outline_box(Color(NT.C_BORDER.r, NT.C_BORDER.g, NT.C_BORDER.b, 0.5)))
		_anchor_frac(ph, 0.42, 0.28, 0.58, 0.72)
		var pl := Label.new()
		pl.text = "placeholder\nbody"
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pl.add_theme_color_override("font_color", NT.C_DIM)
		pl.add_theme_font_size_override("font_size", NT.size("hint"))
		ph.add_child(pl)
		area.add_child(ph)

	for b_v in boxes:
		var b: Dictionary = b_v
		area.add_child(_overlay_box(b))

	var lbl := Label.new()
	lbl.text = label_text.to_upper()
	lbl.add_theme_color_override("font_color", NT.C_DIM)
	lbl.add_theme_font_size_override("font_size", NT.size("hint"))
	lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	lbl.position += Vector2(8, -8)
	area.add_child(lbl)
	return pane


static func _overlay_box(b: Dictionary) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_frac(c, float(b.get("x", 0.4)), float(b.get("y", 0.3)),
		float(b.get("x", 0.4)) + float(b.get("w", 0.2)), float(b.get("y", 0.3)) + float(b.get("h", 0.4)))
	var col: Color = b.get("color", NT.C_ACCENT)
	var border := PanelContainer.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := _outline_box(col)
	if bool(b.get("fill", false)):
		box.bg_color = Color(col.r, col.g, col.b, 0.14)
	border.add_theme_stylebox_override("panel", box)
	c.add_child(border)
	var lbl := Label.new()
	lbl.text = str(b.get("label", ""))
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_font_size_override("font_size", NT.size("hint"))
	lbl.position = Vector2(0, -16)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(lbl)
	return c


static func _anchor_frac(ctrl: Control, l: float, t: float, r: float, b: float) -> void:
	ctrl.anchor_left = l
	ctrl.anchor_top = t
	ctrl.anchor_right = r
	ctrl.anchor_bottom = b
	ctrl.offset_left = 0
	ctrl.offset_top = 0
	ctrl.offset_right = 0
	ctrl.offset_bottom = 0


# --- low-level boxes ---

static func _outline_box(border_col: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0, 0, 0, 0)
	b.set_corner_radius_all(3)
	b.set_content_margin_all(0)
	b.border_color = border_col
	b.set_border_width_all(2)
	return b

static func _panel_box() -> StyleBoxFlat:
	var compact := NT.profile() == "compact"
	var b := StyleBoxFlat.new()
	b.bg_color = NT.C_PANEL_BG
	b.set_corner_radius_all(6 if compact else 10)
	b.set_content_margin_all(12 if compact else 18)
	b.border_color = Color(NT.C_BORDER.r, NT.C_BORDER.g, NT.C_BORDER.b, 0.3)
	b.set_border_width_all(1)
	return b


static func _solid_box(col: Color, radius: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = col
	if radius > 0:
		b.set_corner_radius_all(radius)
	b.set_content_margin_all(0)
	return b
