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
var _info_label: Label = null
var _status_label: Label = null
var _palette: CanvasLayer = null
var _palette_open := false
var _atlas: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 4096
	z_as_relative = false
	_build_hud()
	_palette = CanvasLayer.new()
	_palette.layer = 131
	_palette.visible = false
	add_child(_palette)
	visible = false


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 130
	_hud.visible = false
	add_child(_hud)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)
	_info_label = Label.new()
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_info_label)
	_status_label = Label.new()
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_status_label)
	_refresh_hud()


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
	if _active and not _palette_open:
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
		_set_status("placed '%s'" % id)


func _delete_entity() -> void:
	var rm := _rm()
	if rm == null:
		return
	var rec := rm.remove_entity_near(get_global_mouse_position())
	if not rec.is_empty():
		_undo.append({"op": "entity_delete", "record": rec})
		_trim_undo()
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
	_atlas = rm.current_tileset_atlas()
	if _atlas.is_empty() or _atlas.get("texture") == null:
		_set_status("no tileset atlas to show")
		return
	for ch in _palette.get_children():
		ch.queue_free()
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_palette.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_palette.add_child(margin)
	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	var lbl := Label.new()
	lbl.text = "TILE PALETTE — click a tile   ·   P / Esc to close"
	vbox.add_child(lbl)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var tex: Texture2D = _atlas["texture"]
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(tex.get_width(), tex.get_height())
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	tr.gui_input.connect(_on_palette_click)
	scroll.add_child(tr)
	_palette.visible = true
	_palette_open = true


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


# ── Cursor ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	if not _active:
		return
	var rm := _rm()
	if rm == null or not rm.cell_in_bounds(_hover):
		return
	var rect := Rect2(Vector2(_hover.x * BLOCK, _hover.y * BLOCK), Vector2(BLOCK, BLOCK))
	if _entity_mode:
		var c := Color(0.4, 0.8, 1.0, 0.95)
		draw_rect(rect, Color(c.r, c.g, c.b, 0.15), true)
		draw_rect(rect, c, false, 1.0)
		draw_circle(rect.position + Vector2(BLOCK, BLOCK) * 0.5, 2.5, c)
	else:
		var edge := Color(1.0, 0.4, 0.4, 0.95) if _erasing else Color(0.45, 1.0, 0.5, 0.95)
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
	rooms[addr] = raw_room
	raw["rooms"] = rooms
	if EnvIO.save_rooms(pack.pack_id, raw):
		_set_status("saved '%s' → user pack '%s'" % [addr, pack.pack_id])
	else:
		_set_status("save failed: write error")


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
	if _info_label == null:
		return
	if _entity_mode:
		var id := _current_entity_id()
		var label := id if not id.is_empty() else "(pack has no entities)"
		_info_label.text = "EDIT · ENTITIES · %s   ·   Tab=tiles  [ ] type  LMB place  RMB delete  Ctrl+Z undo  Ctrl+S save  Esc exit" % label
	else:
		_info_label.text = "EDIT · TILES · tile #%d · %s   ·   Tab=entities  [ ] tile  P palette  S solid  LMB paint  RMB erase  Ctrl+Z undo  Ctrl+S save" % [
			_tile_idx, "SOLID" if _solid else "deco"]


func _set_status(msg: String) -> void:
	if _status_label != null:
		_status_label.text = msg
