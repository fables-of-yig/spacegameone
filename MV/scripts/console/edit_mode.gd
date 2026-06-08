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
var _entity_mode := false
var _tile_idx := 0
var _solid := true
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
var _mode_tiles_btn: Button = null
var _mode_ents_btn: Button = null
var _sel_host: PanelContainer = null
var _save_dot: ColorRect = null
var _save_label: Label = null
var _status_label: Label = null
var _status_pill: Control = null
var _palette: CanvasLayer = null
var _palette_open := false
var _env: CanvasLayer = null
var _env_open := false
var _atlas: Dictionary = {}
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

	_mode_tiles_btn = NebulaUi.button("Tiles", "primary")
	_mode_tiles_btn.pressed.connect(func(): _set_mode(false))
	barrow.add_child(_mode_tiles_btn)
	_mode_ents_btn = NebulaUi.button("Entities", "ghost")
	_mode_ents_btn.pressed.connect(func(): _set_mode(true))
	barrow.add_child(_mode_ents_btn)

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


func _set_mode(entities: bool) -> void:
	_entity_mode = entities
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
	if event is InputEventMouseMotion:
		_update_hover()
		# Only tiles drag-paint; entities place per-click.
		if not _entity_mode:
			if _painting:
				_paint_tile()
			elif _erasing:
				_erase_tile()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_painting = mb.pressed
			if mb.pressed:
				_update_hover()
				if not _entity_mode:
					_begin_stroke()
				_apply_primary()
			elif not _entity_mode:
				_finish_stroke()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_erasing = mb.pressed
			if mb.pressed:
				_update_hover()
				if not _entity_mode:
					_begin_stroke()
				_apply_secondary()
			elif not _entity_mode:
				_finish_stroke()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		match ke.keycode:
			KEY_TAB:
				_entity_mode = not _entity_mode
				_refresh_hud()
				get_viewport().set_input_as_handled()
			KEY_BRACKETLEFT:
				_cycle(-1)
				get_viewport().set_input_as_handled()
			KEY_BRACKETRIGHT:
				_cycle(1)
				get_viewport().set_input_as_handled()
			KEY_P:
				if not _entity_mode:
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
	if _entity_mode:
		if not _entity_ids.is_empty():
			_entity_idx = wrapi(_entity_idx + dir, 0, _entity_ids.size())
	else:
		_tile_idx = maxi(0, _tile_idx + dir)
	_refresh_hud()


func _apply_primary() -> void:
	if _entity_mode:
		_place_entity()
	else:
		_paint_tile()


func _apply_secondary() -> void:
	if _entity_mode:
		_delete_entity()
	else:
		_erase_tile()


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
	if rm == null or not rm.cell_in_bounds(_hover):
		return
	_capture_stroke_cell(rm, _hover)
	if rm.paint_cell(_hover, _tile_idx, _solid, false):
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
	_atlas = rm.current_tileset_atlas()
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
	vbox.add_child(NebulaTheme.title_label("Tile Palette"))
	var lbl := Label.new()
	lbl.text = "click a tile   ·   P / Esc to close"
	lbl.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	vbox.add_child(lbl)
	var upload := NebulaUi.button("＋ Upload tileset…", "primary")
	upload.pressed.connect(_upload_tileset)
	vbox.add_child(upload)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_theme_stylebox_override("panel", NebulaTheme.well_box())
	vbox.add_child(scroll)
	if not _atlas.is_empty() and _atlas.get("texture") != null:
		var tex: Texture2D = _atlas["texture"]
		var tr := TextureRect.new()
		tr.texture = tex
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.custom_minimum_size = Vector2(tex.get_width(), tex.get_height())
		tr.mouse_filter = Control.MOUSE_FILTER_STOP
		tr.gui_input.connect(_on_palette_click)
		scroll.add_child(tr)
	else:
		var empty := Label.new()
		empty.text = "No tileset on this room yet.\nUpload a PNG (16px grid) to start painting."
		empty.add_theme_color_override("font_color", NebulaTheme.C_DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		scroll.add_child(empty)
	_palette.visible = true
	_palette_open = true


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
	rm.set_current_room_tileset(idx)
	_mark_dirty()
	_atlas = rm.current_tileset_atlas()
	if _palette_open:
		_open_palette()
	_set_status("added tileset #%d (%dx%d) — Ctrl+S to keep" % [idx, probe.get_width(), probe.get_height()])


func _on_palette_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var ts: int = int(_atlas.get("tile_size", BLOCK))
		var cols: int = int(_atlas.get("cols", 1))
		var pos: Vector2 = (event as InputEventMouseButton).position
		var col := int(pos.x / ts)
		var row := int(pos.y / ts)
		_tile_idx = maxi(0, row * cols + col)
		_entity_mode = false
		_refresh_hud()
		_close_palette()


func _close_palette() -> void:
	_palette_open = false
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
	vbox.add_child(NebulaTheme.title_label("Environment"))
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
	vbox.add_child(_env_note("Shader FX is screen-space over the whole room. Tip: parallax backdrop import is coming next."))

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


# Apply the room-wide shader FX (none = clear) — reloads the room to re-render.
func _env_apply_shader() -> void:
	if _s_preset == null:
		return
	var regions: Array = []
	if SHADER_PRESETS[_s_preset.selected] != "none":
		var info := _rm().current_room()
		regions.append({
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
	_rm().set_current_room_shader_regions(regions)
	_mark_dirty()
	# load_room rebuilt the world; the env panel CanvasLayer is our own child and
	# survives, so no rebuild needed here.


func _close_environment() -> void:
	_env_open = false
	if _env != null:
		_env.visible = false
		for ch in _env.get_children():
			ch.queue_free()


# ── Cursor ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	if not _active:
		return
	var rm := _rm()
	if rm == null or not rm.cell_in_bounds(_hover):
		return
	var rect := Rect2(Vector2(_hover.x * BLOCK, _hover.y * BLOCK), Vector2(BLOCK, BLOCK))
	if _entity_mode:
		var c := NebulaTheme.C_ACCENT
		draw_rect(rect, Color(c.r, c.g, c.b, 0.15), true)
		draw_rect(rect, c, false, 1.0)
		draw_circle(rect.position + Vector2(BLOCK, BLOCK) * 0.5, 2.5, c)
	else:
		var edge := NebulaTheme.C_ERROR if _erasing else NebulaTheme.C_SUCCESS
		draw_rect(rect, Color(edge.r, edge.g, edge.b, 0.18), true)
		draw_rect(rect, edge, false, 1.0)


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
	if _mode_tiles_btn == null:
		return
	_mode_tiles_btn.self_modulate = Color.WHITE if not _entity_mode else NebulaTheme.C_BORDER
	_mode_ents_btn.self_modulate = Color.WHITE if _entity_mode else NebulaTheme.C_BORDER
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
	if _entity_mode:
		var id := _current_entity_id()
		var lbl := Label.new()
		lbl.text = id if not id.is_empty() else "—"
		lbl.add_theme_color_override("font_color", NebulaTheme.C_BODY)
		lbl.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_sel_host.add_child(lbl)
		return
	var atlas := _rm().current_tileset_atlas() if _rm() != null else {}
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
