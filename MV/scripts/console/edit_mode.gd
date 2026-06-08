class_name MvEditMode
extends Node2D

# In-game edit mode — Slices 2-3 + fix-up pass (palette, undo).
# Toggle with F2 (wired in MvMain._input). Freezes the sim while active. Two
# sub-modes, swapped with Tab:
#
#   TILES (default):
#     LMB paint · RMB erase (hold + drag) · [ ] tile · S solid/deco · P palette
#   ENTITIES:
#     LMB place · RMB delete nearest · [ ] entity type
#
#   Ctrl+Z undo · Ctrl+S save · Esc / F2 exit
#
# Painting/placement go through MvRoomManager. Drag strokes defer the (whole-
# room) collider rebuild to mouse-release and are grouped into one undo step.
# The palette shows the room's tileset atlas; click a tile to select it.

const EnvIO := preload("res://Space/scripts/shared/env/env_io.gd")
const BLOCK := 16
const UNDO_LIMIT := 100

var _active := false
var _prev_paused := false
var _mode := "tiles"  # "tiles" | "collision" | "entities"
var _tile_idx := 0
var _tileset_id := -1  # selected tileset source (-1 = room's primary)
var _solid := true
# Paint brush: a WxH block from the palette (1x1 for a single tile). col0/row0
# are the atlas top-left; metatile for offset (dx,dy) = (row0+dy)*cols+(col0+dx).
var _brush := {"ts": -1, "col0": 0, "row0": 0, "w": 1, "h": 1, "cols": 1}
# Palette drag-select state.
var _drag_active := false
var _drag_start := Vector2i.ZERO
var _drag_atlas: Dictionary = {}
var _drag_sel: Panel = null
var _drag_disp := 16  # displayed tile size during a palette drag (tile_size * scale)
var _palette_collapsed: Dictionary = {}  # tileset idx -> collapsed bool

const MODES := ["tiles", "collision", "entities", "shaders"]
const MODE_LABELS := {"tiles": "Tiles", "collision": "Collision", "entities": "Entities", "shaders": "Shaders"}
const BT_SOLID := 0x8  # mirrors MvRoomManager.BT_SOLID (solid family >= 0x8)

# Shader-region painting (Shaders mode): free-drag a pixel rectangle.
var _shader_preset_idx := 1  # index into SHADER_PRESETS; [ ] cycles
var _shader_drag := false
var _shader_start_px := Vector2.ZERO
# Inline per-region editor.
var _shader_edit: CanvasLayer = null
var _shader_edit_id := ""
var _se_preset: OptionButton = null
var _se_tint: ColorPickerButton = null
var _se_str: SpinBox = null
var _se_spd: SpinBox = null
var _entity_ids: Array = []
var _entity_idx := 0
var _hover := Vector2i(-9999, -9999)
var _painting := false
var _erasing := false

var _undo: Array = []
var _stroke: Array = []
var _stroke_cells: Dictionary = {}

var _hud: CanvasLayer = null
var _hud_panel: PanelContainer = null
var _mode_btns: Dictionary = {}  # mode name -> Button
var _sel_host: PanelContainer = null
var _save_dot: ColorRect = null
var _save_label: Label = null
var _status_label: Label = null
var _status_pill: Control = null
var _palette: CanvasLayer = null
var _palette_open := false
# (per-tileset atlas info is fetched on demand from MvRoomManager.tileset_atlas_for)
var _env: CanvasLayer = null
var _env_open := false
var _dirty := false

const WEATHER_PRESETS := ["none", "rain", "snow"]
const SHADER_PRESETS := ["none", "flicker", "wave", "heat"]

var _w_preset: OptionButton = null
var _w_color: ColorPickerButton = null
var _w_int: SpinBox = null
var _w_spd: SpinBox = null
var _s_preset: OptionButton = null
var _s_tint: ColorPickerButton = null
var _s_str: SpinBox = null
var _s_spd: SpinBox = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 4096
	z_as_relative = false
	# HUD is built on enter() under the forced "compact" profile (it renders in
	# MV's 480x270 viewport, which the root-based ui_scale() can't see).
	_palette = CanvasLayer.new()
	_palette.layer = 131
	_palette.visible = false
	add_child(_palette)
	_env = CanvasLayer.new()
	_env.layer = 131
	_env.visible = false
	add_child(_env)
	_shader_edit = CanvasLayer.new()
	_shader_edit.layer = 132
	_shader_edit.visible = false
	add_child(_shader_edit)
	visible = false


# Edit HUD (Nebula mockup): a top toolbar (EDIT · mode tabs · selected swatch ·
# save state · undo/palette) plus a bottom-left key-hint pill and status pill.
# Stays in game space (overlays live play) — no content-scale flip.
func _build_hud() -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.queue_free()
	_hud = CanvasLayer.new()
	_hud.layer = 130
	_hud.visible = false
	add_child(_hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = NebulaTheme.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)

	# --- Top toolbar ---
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.offset_left = 8
	panel.offset_top = 8
	panel.offset_right = -8
	_hud_panel = panel
	var bar := StyleBoxFlat.new()
	bar.bg_color = Color(NebulaTheme.C_PANEL_BG.r, NebulaTheme.C_PANEL_BG.g, NebulaTheme.C_PANEL_BG.b, 0.94)
	bar.border_color = NebulaTheme.C_ACCENT
	bar.set_border_width_all(1)
	bar.border_width_bottom = 2
	bar.set_corner_radius_all(4)
	bar.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", bar)
	root.add_child(panel)
	var barrow := HBoxContainer.new()
	barrow.add_theme_constant_override("separation", 10)
	panel.add_child(barrow)

	var edit_lbl := Label.new()
	edit_lbl.text = "EDIT"
	edit_lbl.add_theme_color_override("font_color", NebulaTheme.C_TITLE)
	if NebulaTheme.font() != null:
		edit_lbl.add_theme_font_override("font", NebulaTheme.font())
	barrow.add_child(edit_lbl)

	_mode_btns = {}
	for m in MODES:
		var mb := NebulaUi.button(str(MODE_LABELS[m]), "primary" if m == _mode else "ghost")
		mb.pressed.connect(_set_mode.bind(str(m)))
		barrow.add_child(mb)
		_mode_btns[m] = mb

	var sel_lbl := Label.new()
	sel_lbl.text = "SEL"
	sel_lbl.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	sel_lbl.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
	barrow.add_child(sel_lbl)
	_sel_host = PanelContainer.new()
	_sel_host.add_theme_stylebox_override("panel", NebulaTheme.well_box())
	_sel_host.custom_minimum_size = Vector2(34, 34)
	barrow.add_child(_sel_host)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	barrow.add_child(spacer)

	_save_dot = ColorRect.new()
	_save_dot.custom_minimum_size = Vector2(9, 9)
	_save_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	barrow.add_child(_save_dot)
	_save_label = Label.new()
	barrow.add_child(_save_label)

	var undo_btn := NebulaUi.button("↶", "ghost")
	undo_btn.pressed.connect(_undo_last)
	barrow.add_child(undo_btn)
	var pal_btn := NebulaUi.button("▦", "ghost")
	pal_btn.pressed.connect(_open_palette)
	barrow.add_child(pal_btn)
	var env_btn := NebulaUi.button("Environment", "ghost")
	env_btn.pressed.connect(_open_environment)
	barrow.add_child(env_btn)

	# --- Bottom-left key hints + status pill ---
	var bl := VBoxContainer.new()
	bl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bl.position += Vector2(8, -8)
	bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bl.add_theme_constant_override("separation", 6)
	root.add_child(bl)
	var hints := PanelContainer.new()
	hints.add_theme_stylebox_override("panel", _pill_box())
	bl.add_child(hints)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hints.add_child(hb)
	for pair in [["LMB", "paint"], ["RMB", "erase"], ["Tab", "mode"], ["P", "palette"], ["Z", "undo"], ["S", "save"], ["Esc", "exit"]]:
		hb.add_child(_key_hint(str(pair[0]), str(pair[1])))
	_status_pill = PanelContainer.new()
	(_status_pill as PanelContainer).add_theme_stylebox_override("panel", _pill_box())
	_status_pill.visible = false
	bl.add_child(_status_pill)
	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", NebulaTheme.C_ACCENT)
	(_status_pill as PanelContainer).add_child(_status_label)
	_refresh_hud()


func _key_hint(k: String, label: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 5)
	var kbd := PanelContainer.new()
	var kb := StyleBoxFlat.new()
	kb.bg_color = NebulaTheme.C_PANEL_ALT
	kb.set_corner_radius_all(3)
	kb.content_margin_left = 5.0
	kb.content_margin_right = 5.0
	kb.content_margin_top = 2.0
	kb.content_margin_bottom = 2.0
	kbd.add_theme_stylebox_override("panel", kb)
	var kl := Label.new()
	kl.text = k
	kl.add_theme_color_override("font_color", NebulaTheme.C_TITLE)
	kl.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
	kbd.add_child(kl)
	hb.add_child(kbd)
	var ll := Label.new()
	ll.text = label
	ll.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	ll.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
	hb.add_child(ll)
	return hb


func _pill_box() -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color(NebulaTheme.C_PANEL_DARK.r, NebulaTheme.C_PANEL_DARK.g, NebulaTheme.C_PANEL_DARK.b, 0.85)
	b.set_corner_radius_all(999)
	b.content_margin_left = 12.0
	b.content_margin_right = 12.0
	b.content_margin_top = 6.0
	b.content_margin_bottom = 6.0
	b.border_color = Color(NebulaTheme.C_BORDER.r, NebulaTheme.C_BORDER.g, NebulaTheme.C_BORDER.b, 0.22)
	b.set_border_width_all(1)
	return b


func _set_mode(mode: String) -> void:
	if not MODES.has(mode):
		return
	_mode = mode
	if mode != "tiles":
		_close_palette()
	if mode != "shaders":
		_close_shader_editor()
	_refresh_hud()
	queue_redraw()


func _rm() -> MvRoomManager:
	return MvGame.room_manager as MvRoomManager


# ── Toggle ──────────────────────────────────────────────────────────────────

func toggle() -> void:
	if _active:
		exit()
	else:
		enter()


func enter() -> void:
	if _active:
		return
	var rm := _rm()
	if rm == null:
		push_warning("MvEditMode: no room loaded")
		return
	_active = true
	visible = true
	# Native resolution now — build the HUD fresh (full profile).
	_build_hud()
	if _hud != null:
		_hud.visible = true
	_prev_paused = MvGame.simulation_paused
	MvGame.simulation_paused = true
	PlanetaryInterface.edit_session_active = true
	_entity_ids = rm.entity_type_ids()
	_entity_idx = clampi(_entity_idx, 0, maxi(0, _entity_ids.size() - 1))
	_set_status("")
	_refresh_hud()
	queue_redraw()


func exit() -> void:
	if not _active:
		return
	_close_palette()
	_close_environment()
	_close_shader_editor()
	_active = false
	visible = false
	if _hud != null:
		_hud.visible = false
	_painting = false
	_erasing = false
	MvGame.simulation_paused = _prev_paused
	PlanetaryInterface.edit_session_active = false


# ── Input ───────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if _palette_open:
		# Palette is modal; only its close keys matter (mouse handled by its GUI).
		if event is InputEventKey and event.pressed and not event.echo:
			var pk := event as InputEventKey
			if pk.keycode == KEY_P or pk.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_close_palette()
		return
	if _env_open:
		# Environment panel is modal; its controls handle their own input.
		if event is InputEventKey and event.pressed and not event.echo:
			if (event as InputEventKey).keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_close_environment()
		return
	# Shaders mode is a marquee drag (rect), not per-cell paint.
	if _mode == "shaders" and (event is InputEventMouseMotion or event is InputEventMouseButton):
		_handle_shader_mouse(event)
		return
	if event is InputEventMouseMotion:
		_update_hover()
		# Tiles + collision drag-paint; entities place per-click.
		if _mode != "entities":
			if _painting:
				_apply_primary()
			elif _erasing:
				_apply_secondary()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_painting = mb.pressed
			if mb.pressed:
				_update_hover()
				if _mode != "entities":
					_begin_stroke()
				_apply_primary()
			elif _mode != "entities":
				_finish_stroke()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_erasing = mb.pressed
			if mb.pressed:
				_update_hover()
				if _mode != "entities":
					_begin_stroke()
				_apply_secondary()
			elif _mode != "entities":
				_finish_stroke()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		match ke.keycode:
			KEY_TAB:
				_cycle_mode()
				get_viewport().set_input_as_handled()
			KEY_BRACKETLEFT:
				_cycle(-1)
				get_viewport().set_input_as_handled()
			KEY_BRACKETRIGHT:
				_cycle(1)
				get_viewport().set_input_as_handled()
			KEY_P:
				if _mode == "tiles":
					_open_palette()
				get_viewport().set_input_as_handled()
			KEY_Z:
				if ke.ctrl_pressed:
					_undo_last()
					get_viewport().set_input_as_handled()
			KEY_S:
				if ke.ctrl_pressed:
					_save()
				else:
					_solid = not _solid
					_refresh_hud()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				exit()
				get_viewport().set_input_as_handled()


func _cycle(dir: int) -> void:
	if _mode == "entities":
		if not _entity_ids.is_empty():
			_entity_idx = wrapi(_entity_idx + dir, 0, _entity_ids.size())
	elif _mode == "shaders":
		_shader_preset_idx = wrapi(_shader_preset_idx + dir, 0, SHADER_PRESETS.size())
	else:
		_tile_idx = maxi(0, _tile_idx + dir)
		# [ ] cycles a single-tile brush on the active tileset.
		var atlas := _rm().tileset_atlas_for(_active_tileset_id()) if _rm() != null else {}
		var cols := maxi(1, int(atlas.get("cols", 1)))
		_brush = {"ts": _active_tileset_id(), "col0": _tile_idx % cols, "row0": _tile_idx / cols, "w": 1, "h": 1, "cols": cols}
	_refresh_hud()


func _cycle_mode() -> void:
	var i := MODES.find(_mode)
	_set_mode(str(MODES[wrapi(i + 1, 0, MODES.size())]))


func _apply_primary() -> void:
	match _mode:
		"entities":
			_place_entity()
		"collision":
			_paint_collision(true)
		_:
			_paint_tile()


func _apply_secondary() -> void:
	match _mode:
		"entities":
			_delete_entity()
		"collision":
			_paint_collision(false)
		_:
			_erase_tile()


func _paint_collision(solid: bool) -> void:
	var rm := _rm()
	if rm == null or not rm.cell_in_bounds(_hover):
		return
	_capture_stroke_cell(rm, _hover)
	if rm.paint_collision(_hover, solid, false):
		queue_redraw()


# Shaders mode: LMB free-drags a pixel rectangle to add a region; a tiny drag
# (a click) inside an existing region opens its inline editor. RMB removes the
# region under the cursor. [ ] cycles the effect the next painted region uses.
func _handle_shader_mouse(event: InputEvent) -> void:
	var rm := _rm()
	if rm == null:
		return
	if event is InputEventMouseMotion:
		if _shader_drag:
			queue_redraw()
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_shader_drag = true
			_shader_start_px = get_global_mouse_position()
		elif _shader_drag:
			_shader_drag = false
			var end_px := get_global_mouse_position()
			if _shader_start_px.distance_to(end_px) < 5.0:
				# A click — select the region under the cursor and edit it.
				var id := rm.shader_region_id_at(_shader_start_px / float(BLOCK))
				if not id.is_empty():
					_open_shader_editor(id)
			else:
				_commit_shader_region(_shader_start_px, end_px)
			queue_redraw()
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		var id := rm.shader_region_id_at(get_global_mouse_position() / float(BLOCK))
		if not id.is_empty() and rm.remove_shader_region_by_id(id):
			if id == _shader_edit_id:
				_close_shader_editor()
			_mark_dirty()
			queue_redraw()
		get_viewport().set_input_as_handled()


func _commit_shader_region(a_px: Vector2, b_px: Vector2) -> void:
	var preset := str(SHADER_PRESETS[_shader_preset_idx])
	if preset == "none":
		_set_status("pick an effect ([ ]) before painting a shader region")
		return
	var x0 := minf(a_px.x, b_px.x)
	var y0 := minf(a_px.y, b_px.y)
	# Stored in (fractional) block units; the runtime multiplies by BLOCK_SIZE.
	_rm().add_shader_region({
		"id": "fx_%d" % Time.get_ticks_msec(),
		"x_blocks": x0 / float(BLOCK),
		"y_blocks": y0 / float(BLOCK),
		"width_blocks": absf(b_px.x - a_px.x) / float(BLOCK),
		"height_blocks": absf(b_px.y - a_px.y) / float(BLOCK),
		"shader_preset": preset,
		"shader_tint": "ffffff",
		"shader_strength": 0.6,
		"shader_speed": 1.0,
	})
	_mark_dirty()
	queue_redraw()


func _process(_delta: float) -> void:
	if _active and not _palette_open and not _env_open:
		_update_hover()


func _update_hover() -> void:
	var rm := _rm()
	if rm == null:
		return
	var cell := rm.world_to_cell(get_global_mouse_position())
	if cell != _hover:
		_hover = cell
		queue_redraw()


# ── Tile ops (with undo capture) ─────────────────────────────────────────────

func _begin_stroke() -> void:
	_stroke = []
	_stroke_cells = {}


func _capture_stroke_cell(rm: MvRoomManager, cell: Vector2i) -> void:
	if _stroke_cells.has(cell):
		return
	_stroke_cells[cell] = true
	_stroke.append({"cell": cell, "before": rm.cell_state(cell)})


func _finish_stroke() -> void:
	var rm := _rm()
	if rm != null:
		rm.rebuild_collision_from_current()
	if not _stroke.is_empty():
		_undo.append({"op": "tile_stroke", "cells": _stroke.duplicate()})
		_trim_undo()
		_mark_dirty()
	_stroke = []
	_stroke_cells = {}


func _paint_tile() -> void:
	var rm := _rm()
	if rm == null:
		return
	var ts_id := int(_brush.get("ts", _tileset_id))
	var cols := maxi(1, int(_brush.get("cols", 1)))
	var col0 := int(_brush.get("col0", 0))
	var row0 := int(_brush.get("row0", 0))
	var bw := maxi(1, int(_brush.get("w", 1)))
	var bh := maxi(1, int(_brush.get("h", 1)))
	var painted := false
	for dy in bh:
		for dx in bw:
			var cell := _hover + Vector2i(dx, dy)
			if not rm.cell_in_bounds(cell):
				continue
			_capture_stroke_cell(rm, cell)
			if rm.paint_cell(cell, (row0 + dy) * cols + (col0 + dx), _solid, ts_id, false):
				painted = true
	if painted:
		queue_redraw()


func _erase_tile() -> void:
	var rm := _rm()
	if rm == null or not rm.cell_in_bounds(_hover):
		return
	_capture_stroke_cell(rm, _hover)
	if rm.erase_cell(_hover, false):
		queue_redraw()


# ── Entity ops ───────────────────────────────────────────────────────────────

func _place_entity() -> void:
	var rm := _rm()
	var id := _current_entity_id()
	if rm == null or id.is_empty():
		return
	var uid := rm.place_entity(id, get_global_mouse_position())
	if not uid.is_empty():
		_undo.append({"op": "entity_place", "uid": uid})
		_trim_undo()
		_mark_dirty()
		_set_status("placed '%s'" % id)


func _delete_entity() -> void:
	var rm := _rm()
	if rm == null:
		return
	var rec := rm.remove_entity_near(get_global_mouse_position())
	if not rec.is_empty():
		_undo.append({"op": "entity_delete", "record": rec})
		_trim_undo()
		_mark_dirty()
		_set_status("deleted entity")


func _current_entity_id() -> String:
	if _entity_idx >= 0 and _entity_idx < _entity_ids.size():
		return str(_entity_ids[_entity_idx])
	return ""


# ── Undo ─────────────────────────────────────────────────────────────────────

func _trim_undo() -> void:
	while _undo.size() > UNDO_LIMIT:
		_undo.pop_front()


func _undo_last() -> void:
	if _undo.is_empty():
		_set_status("nothing to undo")
		return
	var rm := _rm()
	if rm == null:
		return
	var op: Dictionary = _undo.pop_back()
	match str(op.get("op", "")):
		"tile_stroke":
			var cells: Array = op.get("cells", [])
			for i in range(cells.size() - 1, -1, -1):
				var entry: Dictionary = cells[i]
				var c: Vector2i = entry["cell"]
				var b: Dictionary = entry["before"]
				rm.set_cell_full(c, int(b["packed"]), int(b["collision"]), int(b["bts"]), false)
			rm.rebuild_collision_from_current()
			_set_status("undid tile edit")
		"entity_place":
			if rm.remove_entity_by_id(str(op.get("uid", ""))):
				_set_status("undid entity placement")
		"entity_delete":
			var rec: Dictionary = op.get("record", {})
			if not rec.is_empty() and rm.place_entity_record(rec):
				_set_status("undid entity deletion")
	queue_redraw()


# ── Palette ──────────────────────────────────────────────────────────────────

func _open_palette() -> void:
	var rm := _rm()
	if rm == null:
		return
	_close_environment()
	for ch in _palette.get_children():
		ch.queue_free()
	var bg := ColorRect.new()
	bg.color = Color(NebulaTheme.C_PANEL_DARK.r, NebulaTheme.C_PANEL_DARK.g, NebulaTheme.C_PANEL_DARK.b, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_palette.add_child(bg)
	# Right-docked panel. A Control under a CanvasLayer is sized by anchors/
	# offsets (not custom_minimum_size), so anchor the right ~55% explicitly.
	var margin := MarginContainer.new()
	margin.anchor_left = 0.45
	margin.anchor_top = 0.0
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 0
	margin.offset_top = 0
	margin.offset_right = 0
	margin.offset_bottom = 0
	margin.theme = NebulaTheme.theme()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_palette.add_child(margin)
	var frame := PanelContainer.new()
	margin.add_child(frame)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	frame.add_child(vbox)
	# Header: title + real close button (the frame-art ✕ is decorative).
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)
	header.add_child(NebulaTheme.title_label("Tile Palette"))
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(hsp)
	var close_btn := NebulaUi.button("✕", "ghost")
	close_btn.pressed.connect(_close_palette)
	header.add_child(close_btn)
	var lbl := Label.new()
	lbl.text = "click a tile · drag to select a block · headers collapse · P / Esc to close"
	lbl.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	vbox.add_child(lbl)
	var upload := NebulaUi.button("＋ Upload tileset…", "primary")
	upload.pressed.connect(_upload_tileset)
	vbox.add_child(upload)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_theme_stylebox_override("panel", NebulaTheme.well_box())
	vbox.add_child(scroll)
	var grid_col := VBoxContainer.new()
	grid_col.add_theme_constant_override("separation", 8)
	grid_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_col)
	# Fit atlases to ~half the panel width at an integer scale (crisp, not
	# stretched). Wide atlases stay 1x; small ones scale up for visibility.
	var avail := int(get_viewport().get_visible_rect().size.x * 0.42)
	var indices: Array = rm.available_tileset_indices()
	var any := false
	for idx_v in indices:
		var idx := int(idx_v)
		var atlas := rm.tileset_atlas_for(idx)
		var tex: Texture2D = atlas.get("texture")
		if tex == null:
			continue
		any = true
		var active := idx == _active_tileset_id()
		var collapsed := bool(_palette_collapsed.get(idx, false))
		var hdr := NebulaUi.button("%s Tileset %d%s" % ["▸" if collapsed else "▾", idx, "  ·  selected" if active else ""], "ghost")
		hdr.alignment = HORIZONTAL_ALIGNMENT_LEFT
		hdr.self_modulate = NebulaTheme.C_ACCENT if active else NebulaTheme.C_BORDER
		hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hdr.pressed.connect(func():
			_palette_collapsed[idx] = not bool(_palette_collapsed.get(idx, false))
			_open_palette())
		grid_col.add_child(hdr)
		if collapsed:
			continue
		var scale := clampi(int(float(avail) / float(maxi(1, tex.get_width()))), 1, 4)
		# HBox wrapper keeps the atlas left-aligned at native*scale (a VBox child
		# would otherwise stretch to the full panel width).
		var row := HBoxContainer.new()
		var tr := TextureRect.new()
		tr.texture = tex
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.custom_minimum_size = Vector2(tex.get_width() * scale, tex.get_height() * scale)
		tr.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		tr.mouse_filter = Control.MOUSE_FILTER_STOP
		tr.gui_input.connect(_on_palette_input.bind(idx, atlas, tr, scale))
		row.add_child(tr)
		grid_col.add_child(row)
	if not any:
		var empty := Label.new()
		empty.text = "No tileset on this room yet.\nUpload a PNG (16px grid) to start painting."
		empty.add_theme_color_override("font_color", NebulaTheme.C_DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid_col.add_child(empty)
	_palette.visible = true
	_palette_open = true


# The effective selected tileset id (resolves -1 to the room's primary).
func _active_tileset_id() -> int:
	if _tileset_id >= 0:
		return _tileset_id
	var info := _rm().current_room() if _rm() != null else {}
	return int(info.get("tileset", 0))


# Pick a PNG from disk and add it as this pack's next tileset atlas (16px grid),
# assign it to the current room, and re-render live. Persist with Ctrl+S.
func _upload_tileset() -> void:
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.use_native_dialog = true
	fd.title = "Choose a tileset PNG (16px grid)"
	fd.filters = PackedStringArray(["*.png ; PNG images"])
	fd.file_selected.connect(_on_tileset_file)
	fd.canceled.connect(fd.queue_free)
	fd.close_requested.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(900, 640))


func _on_tileset_file(src_path: String) -> void:
	var rm := _rm()
	var pack := MvPackLoader.current_pack
	if rm == null or pack == null:
		_set_status("upload failed: no pack/room")
		return
	var src := FileAccess.open(src_path, FileAccess.READ)
	if src == null:
		_set_status("upload failed: can't read file")
		return
	var bytes := src.get_buffer(src.get_length())
	src.close()
	var probe := Image.new()
	if probe.load_png_from_buffer(bytes) != OK:
		_set_status("upload failed: not a valid PNG")
		return
	var idx := rm.next_tileset_index()
	var dir := pack.tileset_user_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var out_path := dir.path_join("tileset_%02d_atlas.png" % idx)
	var w := FileAccess.open(out_path, FileAccess.WRITE)
	if w == null:
		_set_status("upload failed: can't write to pack")
		return
	w.store_buffer(bytes)
	w.close()
	# Keep the room's primary tileset (and existing cells) intact; just make the
	# new source available and select it for painting. The very first tileset on
	# a room with none becomes its primary so cells render at all.
	var had_tileset := not rm.current_tileset_atlas().is_empty()
	if had_tileset:
		rm.refresh_tilesets()
	else:
		rm.set_current_room_tileset(idx)
	_tileset_id = idx
	_mark_dirty()
	if _palette_open:
		_open_palette()
	_set_status("added tileset #%d (%dx%d) — Ctrl+S to keep" % [idx, probe.get_width(), probe.get_height()])


# Palette tile selection. Click picks one tile; click-and-drag selects a
# rectangular block to paint as a brush. A cyan overlay previews the selection.
func _on_palette_input(event: InputEvent, ts_idx: int, atlas: Dictionary, tr: TextureRect, scale: int) -> void:
	# The atlas is displayed at tile_size * scale, so map clicks through `disp`.
	var disp: int = maxi(1, int(atlas.get("tile_size", BLOCK)) * maxi(1, scale))
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		var cell := Vector2i(int(mb.position.x / disp), int(mb.position.y / disp))
		if mb.pressed:
			_drag_active = true
			_drag_start = cell
			_drag_atlas = atlas
			_drag_disp = disp
			_tileset_id = ts_idx
			_drag_sel = Panel.new()
			_drag_sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_drag_sel.add_theme_stylebox_override("panel", NebulaUi._outline_box(NebulaTheme.C_ACCENT))
			tr.add_child(_drag_sel)
			_update_drag_sel(cell)
		else:
			if _drag_active:
				_drag_active = false
				_set_brush_from_rect(ts_idx, atlas, _drag_start, cell)
				_mode = "tiles"
				_refresh_hud()
	elif event is InputEventMouseMotion and _drag_active:
		_update_drag_sel(Vector2i(int((event as InputEventMouseMotion).position.x / disp), int((event as InputEventMouseMotion).position.y / disp)))


func _update_drag_sel(cell: Vector2i) -> void:
	if _drag_sel == null:
		return
	var c0 := mini(_drag_start.x, cell.x)
	var r0 := mini(_drag_start.y, cell.y)
	var w := absi(cell.x - _drag_start.x) + 1
	var h := absi(cell.y - _drag_start.y) + 1
	_drag_sel.position = Vector2(c0 * _drag_disp, r0 * _drag_disp)
	_drag_sel.size = Vector2(w * _drag_disp, h * _drag_disp)


func _set_brush_from_rect(ts_idx: int, atlas: Dictionary, a: Vector2i, b: Vector2i) -> void:
	var cols: int = maxi(1, int(atlas.get("cols", 1)))
	var c0 := maxi(0, mini(a.x, b.x))
	var r0 := maxi(0, mini(a.y, b.y))
	_brush = {
		"ts": ts_idx,
		"col0": c0,
		"row0": r0,
		"w": absi(b.x - a.x) + 1,
		"h": absi(b.y - a.y) + 1,
		"cols": cols,
	}
	_tile_idx = r0 * cols + c0
	_tileset_id = ts_idx


func _close_palette() -> void:
	_palette_open = false
	_drag_active = false
	_drag_sel = null
	if _palette != null:
		_palette.visible = false
		for ch in _palette.get_children():
			ch.queue_free()


# ── Environment panel (weather + screen-space shader FX) ──────────────────────

func _open_environment() -> void:
	var rm := _rm()
	if rm == null:
		return
	_close_palette()
	for ch in _env.get_children():
		ch.queue_free()
	var info := rm.current_room()
	var bg := ColorRect.new()
	bg.color = Color(NebulaTheme.C_PANEL_DARK.r, NebulaTheme.C_PANEL_DARK.g, NebulaTheme.C_PANEL_DARK.b, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_env.add_child(bg)
	var margin := MarginContainer.new()
	margin.anchor_left = 0.4
	margin.anchor_top = 0.0
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.theme = NebulaTheme.theme()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	_env.add_child(margin)
	var frame := PanelContainer.new()
	margin.add_child(frame)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	var ehdr := HBoxContainer.new()
	ehdr.add_theme_constant_override("separation", 8)
	vbox.add_child(ehdr)
	ehdr.add_child(NebulaTheme.title_label("Environment"))
	var esp := Control.new()
	esp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ehdr.add_child(esp)
	var eclose := NebulaUi.button("✕", "ghost")
	eclose.pressed.connect(_close_environment)
	ehdr.add_child(eclose)
	var hint := Label.new()
	hint.text = "changes apply live · Ctrl+S to keep · Esc to close"
	hint.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	vbox.add_child(hint)

	# --- Weather ---
	var w: Dictionary = info.get("weather", {})
	vbox.add_child(NebulaUi.section_header("Weather"))
	_w_preset = OptionButton.new()
	for i in WEATHER_PRESETS.size():
		_w_preset.add_item(str(WEATHER_PRESETS[i]).capitalize(), i)
	_w_preset.selected = maxi(0, WEATHER_PRESETS.find(str(w.get("preset", "none"))))
	_w_preset.item_selected.connect(func(_i): _env_apply_weather())
	vbox.add_child(NebulaUi.labeled("Preset", _w_preset, 120))
	_w_color = ColorPickerButton.new()
	_w_color.custom_minimum_size = Vector2(0, 24)
	_w_color.color = w.get("color", Color(0.81, 0.91, 1.0))
	_w_color.color_changed.connect(func(_c): _env_apply_weather())
	vbox.add_child(NebulaUi.labeled("Tint", _w_color, 120))
	_w_int = _env_spin(0.0, 2.0, 0.05, float(w.get("intensity", 0.7)))
	_w_int.value_changed.connect(func(_v): _env_apply_weather())
	vbox.add_child(NebulaUi.labeled("Intensity", _w_int, 120))
	_w_spd = _env_spin(0.0, 4.0, 0.05, float(w.get("speed", 1.0)))
	_w_spd.value_changed.connect(func(_v): _env_apply_weather())
	vbox.add_child(NebulaUi.labeled("Speed", _w_spd, 120))

	# --- Screen-space shader FX (room-wide) ---
	var sr: Dictionary = {}
	var srs_v: Variant = info.get("shader_regions", [])
	if srs_v is Array and not (srs_v as Array).is_empty():
		sr = (srs_v as Array)[0]
	vbox.add_child(NebulaUi.section_header("Shader FX"))
	_s_preset = OptionButton.new()
	for i in SHADER_PRESETS.size():
		_s_preset.add_item(str(SHADER_PRESETS[i]).capitalize(), i)
	var cur_preset := str(sr.get("shader_preset", "none")) if not sr.is_empty() else "none"
	_s_preset.selected = maxi(0, SHADER_PRESETS.find(cur_preset))
	_s_preset.item_selected.connect(func(_i): _env_apply_shader())
	vbox.add_child(NebulaUi.labeled("Effect", _s_preset, 120))
	_s_tint = ColorPickerButton.new()
	_s_tint.custom_minimum_size = Vector2(0, 24)
	_s_tint.color = sr.get("shader_tint", Color.WHITE)
	_s_tint.color_changed.connect(func(_c): _env_apply_shader())
	vbox.add_child(NebulaUi.labeled("Tint", _s_tint, 120))
	_s_str = _env_spin(0.0, 2.0, 0.05, float(sr.get("shader_strength", 0.6)))
	_s_str.value_changed.connect(func(_v): _env_apply_shader())
	vbox.add_child(NebulaUi.labeled("Strength", _s_str, 120))
	_s_spd = _env_spin(0.0, 4.0, 0.05, float(sr.get("shader_speed", 1.0)))
	_s_spd.value_changed.connect(func(_v): _env_apply_shader())
	vbox.add_child(NebulaUi.labeled("Speed", _s_spd, 120))
	vbox.add_child(_env_note("This is the whole-room effect. For effects on PART of a room, use the Shaders edit mode (drag a rectangle). Parallax backdrop import is coming next."))

	_env.visible = true
	_env_open = true


func _env_spin(lo: float, hi: float, step: float, val: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = val
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sb


func _env_note(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	l.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
	return l


# Apply weather live (no reload) and mark dirty.
func _env_apply_weather() -> void:
	if _w_preset == null:
		return
	_rm().set_room_weather("", {
		"preset": WEATHER_PRESETS[_w_preset.selected],
		"color": _w_color.color.to_html(),
		"intensity": _w_int.value,
		"speed": _w_spd.value,
	})
	_mark_dirty()


# Apply the room-wide shader FX (none = clear). Updates only the "room_fx"
# whole-room region, preserving any painted regions (Shaders mode).
func _env_apply_shader() -> void:
	if _s_preset == null:
		return
	if SHADER_PRESETS[_s_preset.selected] == "none":
		_rm().set_room_fx_region({})
	else:
		var info := _rm().current_room()
		_rm().set_room_fx_region({
			"id": "room_fx",
			"x_blocks": 0.0,
			"y_blocks": 0.0,
			"width_blocks": float(info.get("width_blocks", 0)),
			"height_blocks": float(info.get("height_blocks", 0)),
			"shader_preset": SHADER_PRESETS[_s_preset.selected],
			"shader_tint": _s_tint.color.to_html(),
			"shader_strength": _s_str.value,
			"shader_speed": _s_spd.value,
		})
	_mark_dirty()


func _close_environment() -> void:
	_env_open = false
	if _env != null:
		_env.visible = false
		for ch in _env.get_children():
			ch.queue_free()


# ── Per-region shader editor (Shaders mode: click a region) ───────────────────

func _open_shader_editor(id: String) -> void:
	var reg := {}
	for r_v in _rm().shader_regions_list():
		if str((r_v as Dictionary).get("id", "")) == id:
			reg = r_v
			break
	if reg.is_empty():
		return
	_shader_edit_id = id
	for ch in _shader_edit.get_children():
		ch.queue_free()
	# Compact panel docked top-right; non-modal so the world stays editable.
	var margin := MarginContainer.new()
	margin.anchor_left = 1.0
	margin.anchor_top = 0.0
	margin.anchor_right = 1.0
	margin.anchor_bottom = 0.0
	margin.offset_left = -408
	margin.offset_top = 8
	margin.offset_right = -8
	margin.offset_bottom = 360
	margin.theme = NebulaTheme.theme()
	_shader_edit.add_child(margin)
	var frame := PanelContainer.new()
	margin.add_child(frame)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	frame.add_child(vbox)
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	vbox.add_child(hdr)
	hdr.add_child(NebulaTheme.title_label("Shader Region"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(sp)
	var x := NebulaUi.button("✕", "ghost")
	x.pressed.connect(_close_shader_editor)
	hdr.add_child(x)
	_se_preset = OptionButton.new()
	for i in SHADER_PRESETS.size():
		_se_preset.add_item(str(SHADER_PRESETS[i]).capitalize(), i)
	_se_preset.selected = maxi(0, SHADER_PRESETS.find(str(reg.get("shader_preset", "flicker"))))
	_se_preset.item_selected.connect(func(_i): _apply_shader_edit())
	vbox.add_child(NebulaUi.labeled("Effect", _se_preset, 110))
	_se_tint = ColorPickerButton.new()
	_se_tint.custom_minimum_size = Vector2(0, 24)
	_se_tint.color = reg.get("shader_tint", Color.WHITE)
	_se_tint.color_changed.connect(func(_c): _apply_shader_edit())
	vbox.add_child(NebulaUi.labeled("Tint", _se_tint, 110))
	_se_str = _env_spin(0.0, 2.0, 0.05, float(reg.get("shader_strength", 0.6)))
	_se_str.value_changed.connect(func(_v): _apply_shader_edit())
	vbox.add_child(NebulaUi.labeled("Strength", _se_str, 110))
	_se_spd = _env_spin(0.0, 4.0, 0.05, float(reg.get("shader_speed", 1.0)))
	_se_spd.value_changed.connect(func(_v): _apply_shader_edit())
	vbox.add_child(NebulaUi.labeled("Speed", _se_spd, 110))
	var del := NebulaUi.button("🗑 Delete region", "gold")
	del.pressed.connect(func():
		var rid := _shader_edit_id
		_close_shader_editor()
		if _rm().remove_shader_region_by_id(rid):
			_mark_dirty()
			queue_redraw())
	vbox.add_child(del)
	_shader_edit.visible = true
	queue_redraw()


func _apply_shader_edit() -> void:
	if _shader_edit_id.is_empty() or _se_preset == null:
		return
	_rm().update_shader_region(_shader_edit_id, {
		"shader_preset": SHADER_PRESETS[_se_preset.selected],
		"shader_tint": _se_tint.color.to_html(),
		"shader_strength": _se_str.value,
		"shader_speed": _se_spd.value,
	})
	_mark_dirty()


func _close_shader_editor() -> void:
	_shader_edit_id = ""
	if _shader_edit != null:
		_shader_edit.visible = false
		for ch in _shader_edit.get_children():
			ch.queue_free()
	queue_redraw()


# ── Cursor ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	if not _active:
		return
	var rm := _rm()
	if rm == null:
		return
	# Mode overlays draw regardless of the cursor (they cover the whole room).
	if _mode == "collision":
		_draw_collision_overlay(rm)
	elif _mode == "shaders":
		_draw_shader_overlay(rm)
	# The per-cursor brush rect needs a valid hovered cell.
	if not rm.cell_in_bounds(_hover):
		return
	var bw := maxi(1, int(_brush.get("w", 1))) if _mode == "tiles" else 1
	var bh := maxi(1, int(_brush.get("h", 1))) if _mode == "tiles" else 1
	var rect := Rect2(Vector2(_hover.x * BLOCK, _hover.y * BLOCK), Vector2(bw * BLOCK, bh * BLOCK))
	if _mode == "entities":
		var c := NebulaTheme.C_ACCENT
		draw_rect(rect, Color(c.r, c.g, c.b, 0.15), true)
		draw_rect(rect, c, false, 1.0)
		draw_circle(rect.position + Vector2(BLOCK, BLOCK) * 0.5, 2.5, c)
	else:
		var edge := NebulaTheme.C_ERROR if _erasing else NebulaTheme.C_SUCCESS
		draw_rect(rect, Color(edge.r, edge.g, edge.b, 0.18), true)
		draw_rect(rect, edge, false, 1.0)


func _draw_collision_overlay(rm: MvRoomManager) -> void:
	var rows: Array = rm.collision_rows()
	var fill := Color(NebulaTheme.C_ERROR.r, NebulaTheme.C_ERROR.g, NebulaTheme.C_ERROR.b, 0.22)
	for r in rows.size():
		var row_v: Variant = rows[r]
		if typeof(row_v) != TYPE_ARRAY:
			continue
		var row: Array = row_v
		for c in row.size():
			if int(row[c]) >= BT_SOLID:
				draw_rect(Rect2(Vector2(c * BLOCK, r * BLOCK), Vector2(BLOCK, BLOCK)), fill, true)


func _draw_shader_overlay(rm: MvRoomManager) -> void:
	var accent := NebulaTheme.C_ACCENT
	for r_v in rm.shader_regions_list():
		if typeof(r_v) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = r_v
		var rr := Rect2(
			Vector2(float(r.get("x_blocks", 0.0)) * BLOCK, float(r.get("y_blocks", 0.0)) * BLOCK),
			Vector2(float(r.get("width_blocks", 0.0)) * BLOCK, float(r.get("height_blocks", 0.0)) * BLOCK))
		draw_rect(rr, Color(accent.r, accent.g, accent.b, 0.10), true)
		draw_rect(rr, accent, false, 1.0)
	# In-progress free-drag rectangle (pixel precise).
	if _shader_drag:
		var cur := get_global_mouse_position()
		var dr := Rect2(Vector2(minf(_shader_start_px.x, cur.x), minf(_shader_start_px.y, cur.y)),
			Vector2(absf(cur.x - _shader_start_px.x), absf(cur.y - _shader_start_px.y)))
		var gold := NebulaTheme.C_ACCENT_2
		draw_rect(dr, Color(gold.r, gold.g, gold.b, 0.18), true)
		draw_rect(dr, gold, false, 2.0)
	# Highlight the region being edited.
	if not _shader_edit_id.is_empty():
		for r_v in rm.shader_regions_list():
			var r: Dictionary = r_v
			if str(r.get("id", "")) == _shader_edit_id:
				var er := Rect2(
					Vector2(float(r.get("x_blocks", 0.0)) * BLOCK, float(r.get("y_blocks", 0.0)) * BLOCK),
					Vector2(float(r.get("width_blocks", 0.0)) * BLOCK, float(r.get("height_blocks", 0.0)) * BLOCK))
				draw_rect(er, NebulaTheme.C_ACCENT_2, false, 2.0)


# ── Persistence ─────────────────────────────────────────────────────────────

func _save() -> void:
	var rm := _rm()
	if rm == null:
		_set_status("save failed: no room")
		return
	var pack := MvPackLoader.current_pack
	if pack == null:
		_set_status("save failed: no pack loaded")
		return
	var info := rm.current_room()
	if info.is_empty():
		_set_status("save failed: no room")
		return
	var addr := str(info.get("addr", rm.current_room_addr()))
	var src_path: String = pack.rooms_path()
	var f := FileAccess.open(src_path, FileAccess.READ)
	if f == null:
		_set_status("save failed: cannot read rooms.json")
		return
	var raw_v: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw_v) != TYPE_DICTIONARY:
		_set_status("save failed: rooms.json is not valid JSON")
		return
	var raw: Dictionary = raw_v
	var rooms: Dictionary = raw.get("rooms", {})
	if not rooms.has(addr):
		_set_status("save failed: room '%s' not found in rooms.json on disk" % addr)
		return
	var raw_room: Dictionary = rooms[addr]
	raw_room["collision"] = info.get("collision", [])
	raw_room["bts"] = info.get("bts", [])
	var rt_layers: Array = info.get("tile_layers", [])
	var raw_layers: Array = raw_room.get("tile_layers", [])
	for i in range(mini(rt_layers.size(), raw_layers.size())):
		(raw_layers[i] as Dictionary)["tiles"] = (rt_layers[i] as Dictionary).get("tiles", [])
	raw_room["tile_layers"] = raw_layers
	raw_room["entities"] = _serialize_entities(info.get("entities", []))
	raw_room["tileset"] = int(info.get("tileset", 0))
	raw_room["weather"] = _serialize_weather(info.get("weather", {}))
	raw_room["shader_regions"] = _serialize_shader_regions(info.get("shader_regions", []))
	rooms[addr] = raw_room
	raw["rooms"] = rooms
	if EnvIO.save_rooms(pack.pack_id, raw):
		_dirty = false
		_refresh_hud()
		_set_status("saved '%s' → user pack '%s'" % [addr, pack.pack_id])
	else:
		_set_status("save failed: write error")


func _mark_dirty() -> void:
	_dirty = true
	_refresh_hud()


# Serialize the parsed (Color-typed) weather/shader data back to JSON-safe dicts.
func _serialize_weather(w: Dictionary) -> Dictionary:
	if w.is_empty():
		return {}
	var col: Color = w.get("color", Color.WHITE)
	return {
		"preset": str(w.get("preset", "none")),
		"color": col.to_html(),
		"intensity": float(w.get("intensity", 0.7)),
		"speed": float(w.get("speed", 1.0)),
	}


func _serialize_shader_regions(regions_v: Variant) -> Array:
	var out: Array = []
	if not (regions_v is Array):
		return out
	for r_v in (regions_v as Array):
		if typeof(r_v) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = r_v
		var tint: Color = r.get("shader_tint", Color.WHITE)
		out.append({
			"id": str(r.get("id", "room_fx")),
			"x_blocks": float(r.get("x_blocks", 0.0)),
			"y_blocks": float(r.get("y_blocks", 0.0)),
			"width_blocks": float(r.get("width_blocks", 0.0)),
			"height_blocks": float(r.get("height_blocks", 0.0)),
			"shader_preset": str(r.get("shader_preset", "flicker")),
			"shader_tint": tint.to_html(),
			"shader_strength": float(r.get("shader_strength", 0.6)),
			"shader_speed": float(r.get("shader_speed", 1.0)),
		})
	return out


func _serialize_entities(entities: Array) -> Array:
	var out: Array = []
	for e_v in entities:
		if typeof(e_v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = e_v
		var pos: Vector2 = e.get("position", Vector2.ZERO)
		var rec := {"type": str(e.get("type", "")), "x": pos.x, "y": pos.y}
		var tags_v: Variant = e.get("tags", [])
		if typeof(tags_v) == TYPE_ARRAY and not (tags_v as Array).is_empty():
			rec["tags"] = tags_v
		var props_v: Variant = e.get("properties", {})
		if typeof(props_v) == TYPE_DICTIONARY and not (props_v as Dictionary).is_empty():
			rec["properties"] = props_v
		out.append(rec)
	return out


# ── HUD ─────────────────────────────────────────────────────────────────────

func _refresh_hud() -> void:
	if _mode_btns.is_empty():
		return
	for m in _mode_btns:
		(_mode_btns[m] as Button).self_modulate = Color.WHITE if m == _mode else NebulaTheme.C_BORDER
	_update_swatch()
	if _save_dot != null:
		_save_dot.color = NebulaTheme.C_ACCENT_2 if _dirty else NebulaTheme.C_BORDER
		_save_label.text = "Unsaved changes" if _dirty else "All saved"
		_save_label.add_theme_color_override("font_color", NebulaTheme.C_ACCENT_2 if _dirty else NebulaTheme.C_DIM)


# Selected swatch: the tile texture region in tiles mode, the entity id in ents.
func _update_swatch() -> void:
	if _sel_host == null:
		return
	for c in _sel_host.get_children():
		c.queue_free()
	if _mode != "tiles":
		var lbl := Label.new()
		if _mode == "entities":
			var id := _current_entity_id()
			lbl.text = id if not id.is_empty() else "—"
		elif _mode == "shaders":
			lbl.text = str(SHADER_PRESETS[_shader_preset_idx]).to_upper()
		else:
			lbl.text = "SOLID"
		lbl.add_theme_color_override("font_color", NebulaTheme.C_BODY)
		lbl.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_sel_host.add_child(lbl)
		return
	var atlas := _rm().tileset_atlas_for(_active_tileset_id()) if _rm() != null else {}
	var tex: Texture2D = atlas.get("texture")
	if tex != null:
		var ts: int = int(atlas.get("tile_size", BLOCK))
		var cols: int = maxi(1, int(atlas.get("cols", 1)))
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2((_tile_idx % cols) * ts, (_tile_idx / cols) * ts, ts, ts)
		var tr := TextureRect.new()
		tr.texture = at
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.custom_minimum_size = Vector2(30, 30)
		_sel_host.add_child(tr)
	else:
		var lbl := Label.new()
		lbl.text = "#%d" % _tile_idx
		lbl.add_theme_color_override("font_color", NebulaTheme.C_BODY)
		lbl.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_sel_host.add_child(lbl)


func _set_status(msg: String) -> void:
	if _status_label == null or _status_pill == null:
		return
	_status_label.text = msg
	_status_pill.visible = not msg.strip_edges().is_empty()
