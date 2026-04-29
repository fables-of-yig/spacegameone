extends Control

# Physics profile editor tab for the player editor. All MvPhysicsProfile
# fields as labeled LineEdits grouped by category. Loads/saves the .tres
# resource from the current content pack.


signal status_changed(text: String)

var _pack_id: String = ""
var _profile: MvPhysicsProfile = null
var _dirty: bool = false
var _suppress: bool = false
var _fields: Dictionary = {}
var _scroll: ScrollContainer = null

var _undo: RefCounted = null

const SECTIONS: Array = [
	{
		"name": "Gravity & Falling",
		"fields": [
			["gravity", "float"],
			["max_fall", "float"],
		]
	},
	{
		"name": "Jumping",
		"fields": [
			["jump_speed", "float"],
		]
	},
	{
		"name": "Ground Run",
		"fields": [
			["run_accel", "float"],
			["run_max", "float"],
			["run_decel", "float"],
		]
	},
	{
		"name": "Air Control",
		"fields": [
			["air_accel", "float"],
			["air_decel", "float"],
		]
	},
	{
		"name": "Collision",
		"fields": [
			["collision_width", "int"],
		]
	},
	{
		"name": "Beam",
		"fields": [
			["beam_cooldown", "float"],
			["max_beams", "int"],
			["beam_charge_seconds", "float"],
		]
	},
	{
		"name": "Grapple — General",
		"fields": [
			["grapple_mode", "int"],
		]
	},
	{
		"name": "Grapple — Pendulum",
		"fields": [
			["grapple_gravity", "float"],
			["grapple_pump_power", "float"],
			["grapple_damping", "float"],
			["grapple_release_boost", "float"],
		]
	},
	{
		"name": "Grapple — Classic",
		"fields": [
			["grapple_rotate_speed", "float"],
			["grapple_length_rate", "float"],
			["grapple_min_len", "float"],
			["grapple_max_len", "float"],
		]
	},
	{
		"name": "Misc",
		"fields": [
			["show_boss_hp_bar", "bool"],
		]
	},
]


func open(pack_id: String) -> void:
	_pack_id = pack_id
	_profile = _load_profile()
	_populate()
	_dirty = false
	if _undo != null:
		_undo.clear()


func _capture_state() -> Dictionary:
	if _profile == null:
		return {}
	var data: Dictionary = {}
	for section in SECTIONS:
		for field_def in section["fields"]:
			var field_name: String = field_def[0]
			data[field_name] = _profile.get(field_name)
	return {"profile": data, "dirty": _dirty}


func _apply_state(snap: Dictionary) -> void:
	if _profile == null:
		return
	var data_v: Variant = snap.get("profile", null)
	if typeof(data_v) == TYPE_DICTIONARY:
		for field_name in (data_v as Dictionary).keys():
			_profile.set(str(field_name), (data_v as Dictionary)[field_name])
	_dirty = bool(snap.get("dirty", false))
	_populate()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _has_text_focus():
			return
		if _undo != null and _undo.handle_key(event):
			get_viewport().set_input_as_handled()


func _has_text_focus() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null:
		return false
	return focused is LineEdit or focused is TextEdit


func save() -> bool:
	if not _validate_fields():
		return false
	_flush()
	if not _save_profile():
		return false
	_dirty = false
	status_changed.emit("Physics profile saved")
	return true


func is_dirty() -> bool:
	return _dirty


const _PHYSICS_TIPS: Dictionary = {
	"gravity": "Downward acceleration in pixels/tick^2. Higher = heavier feel. The player accelerates toward max_fall at this rate.",
	"max_fall": "Terminal velocity in pixels/tick when falling. Caps how fast the player drops regardless of gravity.",
	"jump_speed": "Initial upward velocity when jumping, in pixels/tick. Higher = higher jumps. Gravity pulls this back down each tick.",
	"run_accel": "Ground acceleration in pixels/tick^2. How quickly the player reaches run_max speed when holding a direction.",
	"run_max": "Maximum ground speed in pixels/tick. The player can't accelerate past this on the ground.",
	"run_decel": "Ground deceleration when the player releases the direction key. Higher = snappier stop, lower = icy slide.",
	"air_accel": "Horizontal acceleration while airborne. Usually lower than run_accel for floatier air control.",
	"air_decel": "Horizontal deceleration while airborne with no input. Lower values let the player coast further.",
	"collision_width": "Half-width of the player's collision box in pixels. The full box is 2x this value wide.",
	"beam_cooldown": "Seconds between beam shots. Prevents rapid-fire.",
	"max_beams": "Maximum number of beam projectiles alive at once. Firing a new one when at the limit despawns the oldest.",
	"beam_charge_seconds": "Seconds the player must hold the fire button to fully charge a beam shot.",
	"grapple_mode": "0 = pendulum (physics swing), 1 = classic (rotate + reel). Determines which grapple parameter set applies.",
	"grapple_gravity": "Pendulum mode: gravity pulling the player downward while swinging. Separate from normal gravity.",
	"grapple_pump_power": "Pendulum mode: how much speed the player gains by pumping (pressing toward swing direction).",
	"grapple_damping": "Pendulum mode: friction factor that slows the swing each tick. 1.0 = no damping, lower = more drag.",
	"grapple_release_boost": "Pendulum mode: velocity multiplier applied when the player releases the grapple at the arc's peak.",
	"grapple_rotate_speed": "Classic mode: angular speed in radians/tick when rotating around the grapple point.",
	"grapple_length_rate": "Classic mode: pixels/tick the rope shortens or lengthens when the player reels in or out.",
	"grapple_min_len": "Classic mode: shortest the rope can get, in pixels. Prevents clipping into the grapple point.",
	"grapple_max_len": "Classic mode: longest the rope can extend, in pixels.",
	"show_boss_hp_bar": "When ON, the HUD displays a boss HP bar during boss encounters.",
}


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	set_process(true)
	_undo = EditorUndo.new(_capture_state, _apply_state)
	_build_ui()


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	_update_tooltips()


func _update_tooltips() -> void:
	var gmp := get_global_mouse_position()
	for field_name in _fields:
		var control: Control = _fields[field_name]
		if control == null or not control.is_visible_in_tree():
			continue
		if control.get_global_rect().has_point(gmp):
			if _PHYSICS_TIPS.has(field_name):
				EditorTooltip.show_text(_PHYSICS_TIPS[field_name])
			return


func _build_ui() -> void:
	_scroll = ScrollContainer.new()
	_scroll.anchor_right = 1.0
	_scroll.anchor_bottom = 1.0
	add_child(_scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(vbox)

	for section in SECTIONS:
		var header := Label.new()
		header.text = section["name"]
		header.add_theme_font_size_override("font_size", 13)
		header.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
		vbox.add_child(header)

		for field_def in section["fields"]:
			var field_name: String = field_def[0]
			var field_type: String = field_def[1]

			var row := HBoxContainer.new()
			var lbl := Label.new()
			lbl.text = field_name
			lbl.custom_minimum_size = Vector2(200, 0)
			lbl.add_theme_font_size_override("font_size", 11)
			row.add_child(lbl)

			if field_type == "bool":
				var cb := CheckBox.new()
				cb.toggled.connect(func(_v): _mark_dirty())
				row.add_child(cb)
				_fields[field_name] = cb
			else:
				var edit := LineEdit.new()
				edit.custom_minimum_size = Vector2(120, 0)
				edit.text_changed.connect(func(_t): _mark_dirty())
				row.add_child(edit)
				_fields[field_name] = edit

			vbox.add_child(row)

		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 8)
		vbox.add_child(spacer)


func _populate() -> void:
	if _profile == null:
		return
	_suppress = true
	for field_name in _fields:
		var control = _fields[field_name]
		var value = _profile.get(field_name)
		if control is CheckBox:
			control.button_pressed = bool(value)
		elif control is LineEdit:
			control.text = str(value)
	_suppress = false


func _flush() -> void:
	if _profile == null:
		return
	for section in SECTIONS:
		for field_def in section["fields"]:
			var field_name: String = field_def[0]
			var field_type: String = field_def[1]
			var control = _fields.get(field_name)
			if control == null:
				continue
			if field_type == "bool" and control is CheckBox:
				_profile.set(field_name, control.button_pressed)
			elif field_type == "int" and control is LineEdit:
				_profile.set(field_name, int(control.text))
			elif field_type == "float" and control is LineEdit:
				_profile.set(field_name, float(control.text))


func _validate_fields() -> bool:
	for section in SECTIONS:
		for field_def in section["fields"]:
			var field_name: String = field_def[0]
			var field_type: String = field_def[1]
			var control = _fields.get(field_name)
			if control == null or not (control is LineEdit):
				continue
			var text := (control as LineEdit).text.strip_edges()
			if field_type == "int" and not _is_valid_int_string(text):
				status_changed.emit("Physics field '%s' must be a whole number" % field_name)
				return false
			if field_type == "float" and not _is_valid_float_string(text):
				status_changed.emit("Physics field '%s' must be a number" % field_name)
				return false
	return true


func _load_profile() -> MvPhysicsProfile:
	if MvPackLoader.current_pack != null and MvPackLoader.current_pack.physics != null:
		return MvPackLoader.current_pack.physics
	return MvPhysicsProfile.new()


func _save_profile() -> bool:
	if _profile == null:
		return false
	var pack := MvPackLoader.current_pack
	if pack == null:
		push_error("[PhysicsTab] no current pack — cannot save")
		return false
	var path := pack.user_path + "PhysicsProfile.tres"
	var dir := path.substr(0, path.rfind("/"))
	DirAccess.make_dir_recursive_absolute(dir)
	var err := ResourceSaver.save(_profile, path)
	if err != OK:
		push_error("[PhysicsTab] save failed (err=%d) for %s" % [err, path])
		return false
	return true


func _mark_dirty() -> void:
	if _suppress:
		return
	_dirty = true


func _is_valid_int_string(text: String) -> bool:
	if text.is_empty():
		return false
	var start := 0
	if text.begins_with("-"):
		if text.length() == 1:
			return false
		start = 1
	for i in range(start, text.length()):
		var ch := text.unicode_at(i)
		if ch < 48 or ch > 57:
			return false
	return true


func _is_valid_float_string(text: String) -> bool:
	if text.is_empty():
		return false
	var start := 0
	var saw_dot := false
	var saw_digit := false
	if text.begins_with("-"):
		if text.length() == 1:
			return false
		start = 1
	for i in range(start, text.length()):
		var ch := text.unicode_at(i)
		if ch == 46:
			if saw_dot:
				return false
			saw_dot = true
			continue
		if ch < 48 or ch > 57:
			return false
		saw_digit = true
	return saw_digit
