class_name SpaceDevConsole
extends CanvasLayer

# Space-side in-game dev console — Slices 4-5 of the in-game authoring build.
# The Space twin of MvDevConsole, scoped to Space authoring. Space main has no
# _input, so this handles its own (backtick toggles). While open it flags
# PlanetaryInterface.edit_session_active so edit state is consistent across the
# MV<->Space scene swap (Slice 4).
#
# Commands:
#   add_poi <type> <name>   place a POI in the current system at the ship's
#                           position (orbit derived from distance + angle to the
#                           star), spawned live and saved to Systems/systems.json
#   flag <name>=<value>     set a global flag (PlanetaryInterface)
#   save                    re-save the current systems to the user pack
#   help / clear
#
# `host` is the Space Main node (Node2D, no class_name) — reached via Object.get
# for its `_spawn` (SpawnManager), `player`, and `system_world_positions`.

const SystemIO := preload("res://Space/scripts/shared/system_io.gd")
const POI_TYPES := ["station", "hostile_station", "salvage", "resource", "anomaly", "ruin", "npc_colony"]

var host: Node = null
var _log_view: RichTextLabel = null
var _entry: TextEdit = null
var _open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 127
	_build_ui()
	visible = false


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.05, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)
	var title := Label.new()
	title.text = "SPACE CONSOLE   ·   Ctrl+Enter run   ·   Esc / ` close"
	vbox.add_child(title)
	_log_view = RichTextLabel.new()
	_log_view.bbcode_enabled = true
	_log_view.scroll_active = true
	_log_view.scroll_following = true
	_log_view.focus_mode = Control.FOCUS_NONE
	_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_log_view)
	_entry = TextEdit.new()
	_entry.placeholder_text = "Type a command (help)…"
	_entry.custom_minimum_size = Vector2(0, 48)
	_entry.size_flags_vertical = Control.SIZE_SHRINK_END
	vbox.add_child(_entry)


# ── Open / close ──

func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	PlanetaryInterface.edit_session_active = true
	if _log_view.get_parsed_text().strip_edges().is_empty():
		_print_help()
	_entry.grab_focus.call_deferred()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	PlanetaryInterface.edit_session_active = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_QUOTELEFT and not ke.ctrl_pressed and not ke.alt_pressed:
			get_viewport().set_input_as_handled()
			toggle()
			return
		if not _open:
			return
		if ke.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()
		elif (ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER) and ke.ctrl_pressed:
			get_viewport().set_input_as_handled()
			_submit()


# ── Dispatch ──

func _submit() -> void:
	var text := _entry.text.strip_edges()
	if text.is_empty():
		return
	_log("[color=#8ab4ff]> %s[/color]" % _escape(text))
	var ok := _handle_command(text)
	if ok:
		_entry.text = ""
	else:
		_entry.select_all()
	_entry.grab_focus.call_deferred()


func _handle_command(text: String) -> bool:
	var sp := text.find(" ")
	var cmd := (text if sp < 0 else text.substr(0, sp)).strip_edges().to_lower()
	var rest := "" if sp < 0 else text.substr(sp + 1).strip_edges()
	match cmd:
		"help":
			_print_help()
			return true
		"clear":
			_log_view.clear()
			return true
		"flag":
			return _cmd_flag(rest)
		"add_poi":
			return _cmd_add_poi(rest)
		"save":
			return _cmd_save()
		_:
			_err("unknown command '%s' — type 'help'" % cmd)
			return false


func _cmd_add_poi(rest: String) -> bool:
	if host == null:
		_err("no Space host")
		return false
	var sp := rest.find(" ")
	var poi_type := (rest if sp < 0 else rest.substr(0, sp)).strip_edges().to_lower()
	var poi_name := "" if sp < 0 else rest.substr(sp + 1).strip_edges()
	if not POI_TYPES.has(poi_type):
		_err("usage: add_poi <type> <name>  ·  type one of %s" % str(POI_TYPES))
		return false
	if poi_name.is_empty():
		poi_name = poi_type.capitalize()
	var sys := str(GameManager.current_system)
	if sys.is_empty():
		_err("no current system")
		return false
	var rel := _player_pos() - _system_center(sys)
	var poi := {
		"id": "%s_%d" % [_slug(poi_name), Time.get_ticks_msec()],
		"name": poi_name,
		"type": poi_type,
		"description": "placed in-game",
		"event_id": "",
		"orbit_dist": rel.length(),
		"orbit_angle": rad_to_deg(rel.angle()),
		"sprite": "",
		"visual_scale": 1.0,
		"anim_frames": 1,
		"anim_fps": 0.0,
		"gravity_radius": 0,
	}
	var systems: Dictionary = DataManager.systems
	var sysd_v: Variant = systems.get(sys, null)
	if typeof(sysd_v) != TYPE_DICTIONARY:
		_err("system '%s' has no data" % sys)
		return false
	var sysd: Dictionary = sysd_v
	var pois_v: Variant = sysd.get("pois", [])
	var pois: Array = pois_v if typeof(pois_v) == TYPE_ARRAY else []
	pois.append(poi)
	sysd["pois"] = pois
	systems[sys] = sysd
	DataManager.systems = systems
	var saved := SystemIO.save(_pack_id(), systems)
	_respawn_pois(sys)
	if saved:
		_ok("added '%s' (%s) in '%s' — live + saved" % [poi_name, poi_type, sys])
	else:
		_warn("added '%s' live, but the disk save failed" % poi_name)
	return true


func _cmd_flag(rest: String) -> bool:
	var eq := rest.find("=")
	if eq < 0:
		_err("usage: flag <name>=<value>")
		return false
	var flag_name := rest.substr(0, eq).strip_edges()
	var raw := rest.substr(eq + 1).strip_edges()
	if flag_name.is_empty():
		_err("flag name is empty")
		return false
	PlanetaryInterface.set_global_flag(flag_name, _coerce(raw))
	_ok("set global flag '%s' = %s" % [flag_name, raw])
	return true


func _cmd_save() -> bool:
	if SystemIO.save(_pack_id(), DataManager.systems):
		_ok("saved systems → user pack '%s'" % _pack_id())
		return true
	_err("save failed")
	return false


# ── Host access (Space main has no class_name; reach members via Object.get) ──

func _system_center(sys: String) -> Vector2:
	if host != null:
		var swp: Variant = host.get("system_world_positions")
		if typeof(swp) == TYPE_DICTIONARY:
			return (swp as Dictionary).get(sys, Vector2.ZERO)
	return Vector2.ZERO


func _player_pos() -> Vector2:
	if host != null:
		var p: Variant = host.get("player")
		if p is Node2D:
			return (p as Node2D).global_position
	return Vector2.ZERO


func _respawn_pois(sys: String) -> void:
	if host == null:
		return
	var spawn: Variant = host.get("_spawn")
	if spawn != null and is_instance_valid(spawn):
		spawn.clear_pois()
		spawn.spawn_system_pois(sys)


func _pack_id() -> String:
	if MvPackLoader.current_pack != null:
		return str(MvPackLoader.current_pack.pack_id)
	if not str(PlanetaryInterface.pending_pack_id).is_empty():
		return str(PlanetaryInterface.pending_pack_id)
	return "demo"


# ── Helpers ──

func _coerce(raw: String) -> Variant:
	var low := raw.to_lower()
	if low == "true":
		return true
	if low == "false":
		return false
	if raw.is_valid_int():
		return raw.to_int()
	if raw.is_valid_float():
		return raw.to_float()
	return raw


func _slug(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch == " " or ch == "_" or ch == "-":
			out += "_"
	return out if not out.is_empty() else "poi"


func _print_help() -> void:
	_log("[color=#8ab4ff]── space console ──[/color]")
	_log("  add_poi <type> <name>   place a POI at the ship, live + saved")
	_log("     types: %s" % str(POI_TYPES))
	_log("  flag <name>=<value>     set a global flag")
	_log("  save                    re-save systems to the user pack")
	_log("  clear                   clear this log       help   show this")


func _log(line: String) -> void:
	if _log_view != null:
		_log_view.append_text(line + "\n")


func _ok(m: String) -> void:
	_log("[color=#7fdc7f]✓ %s[/color]" % _escape(m))


func _warn(m: String) -> void:
	_log("[color=#ffd166]! %s[/color]" % _escape(m))


func _err(m: String) -> void:
	_log("[color=#ff7b7b]✗ %s[/color]" % _escape(m))


func _escape(s: String) -> String:
	return s.replace("[", "[lb]")
