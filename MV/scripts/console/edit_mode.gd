class_name MvEditMode
extends Node2D

# In-game edit mode — Slices 2-3 of the in-game authoring build.
# Toggle with F2 (wired in MvMain._input). While active the simulation is
# frozen (MvGame.simulation_paused). Two sub-modes, swapped with Tab:
#
#   TILES (default):
#     LMB paint  ·  RMB erase  (hold + drag)  ·  [ ] tile index  ·  S solid/deco
#   ENTITIES:
#     LMB place  ·  RMB delete nearest  ·  [ ] entity type
#
#   Ctrl+S  save the room to the user pack   ·   Esc / F2  exit
#
# Painting/placement reuse MvRoomManager (paint_cell / erase_cell /
# place_entity / remove_entity_near) which mutate the live room data, re-render,
# and rebuild colliders. Drag strokes defer the (whole-room) collider rebuild to
# mouse-release. Entities spawn live AND are recorded in entities[] so they
# persist + respawn; exit edit mode (unfreeze) to fight them, F2 to tweak.
#
# Save reads the pack's current rooms.json, patches the edited room's tile /
# collision / bts / entities (same representation as the runtime data), and
# writes the user copy via EnvIO.save_rooms — copy-on-write, shipped untouched.

const EnvIO := preload("res://Space/scripts/shared/env/env_io.gd")
const BLOCK := 16

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
var _hud: CanvasLayer = null
var _info_label: Label = null
var _status_label: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 4096
	z_as_relative = false
	_build_hud()
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
	if event is InputEventMouseMotion:
		_update_hover()
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
				_apply_primary()
			else:
				_rebuild_collision()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_erasing = mb.pressed
			if mb.pressed:
				_update_hover()
				_apply_secondary()
			else:
				_rebuild_collision()
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


func _paint_tile() -> void:
	var rm := _rm()
	if rm == null or not rm.cell_in_bounds(_hover):
		return
	if rm.paint_cell(_hover, _tile_idx, _solid, false):
		queue_redraw()


func _erase_tile() -> void:
	var rm := _rm()
	if rm == null or not rm.cell_in_bounds(_hover):
		return
	if rm.erase_cell(_hover, false):
		queue_redraw()


func _place_entity() -> void:
	var rm := _rm()
	var id := _current_entity_id()
	if rm == null or id.is_empty():
		return
	if rm.place_entity(id, get_global_mouse_position()) != "":
		_set_status("placed '%s'" % id)


func _delete_entity() -> void:
	var rm := _rm()
	if rm == null:
		return
	if rm.remove_entity_near(get_global_mouse_position()):
		_set_status("deleted entity")


func _current_entity_id() -> String:
	if _entity_idx >= 0 and _entity_idx < _entity_ids.size():
		return str(_entity_ids[_entity_idx])
	return ""


func _rebuild_collision() -> void:
	var rm := _rm()
	if rm != null:
		rm.rebuild_collision_from_current()


func _process(_delta: float) -> void:
	if _active:
		_update_hover()


func _update_hover() -> void:
	var rm := _rm()
	if rm == null:
		return
	var cell := rm.world_to_cell(get_global_mouse_position())
	if cell != _hover:
		_hover = cell
		queue_redraw()


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
		_set_status("save failed: room '%s' not in rooms.json (variant rooms aren't saved yet)" % addr)
		return
	var raw_room: Dictionary = rooms[addr]
	# Only tile/collision/bts/entities are touched — same representation in the
	# runtime info and the on-disk room — so all other authored fields survive.
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


# Runtime entity records carry position as a Vector2; the on-disk shape uses
# separate x/y (see MvRoomManager._parse_room_info). Convert here.
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
		_info_label.text = "EDIT · ENTITIES · %s   ·   Tab=tiles  [ ] type  LMB place  RMB delete  Ctrl+S save  Esc exit" % label
	else:
		_info_label.text = "EDIT · TILES · tile #%d · %s   ·   Tab=entities  [ ] tile  S solid  LMB paint  RMB erase  Ctrl+S save  Esc exit" % [
			_tile_idx, "SOLID" if _solid else "deco"]


func _set_status(msg: String) -> void:
	if _status_label != null:
		_status_label.text = msg
