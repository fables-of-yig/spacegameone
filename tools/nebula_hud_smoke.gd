extends SceneTree

# Smoke: actually invokes every NebulaHud draw path (tank gauge incl. danger +
# partial fill, ability bar with/without ammo+name, minimap) inside a real
# Control._draw so bad draw-API usage surfaces. Prints PASS/FAIL.

var _ok := false
var _err := ""
var _frames := 0


func _initialize() -> void:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.draw.connect(_paint.bind(c))
	root.add_child(c)
	c.queue_redraw()


func _paint(c: Control) -> void:
	# HP gauge in danger (forces crystal tone + partial pip + low blink).
	NebulaHud.draw_tank_gauge(c, Vector2(20, 20), {
		"label": "HP", "value": 140, "max": 1400, "total": 14,
		"tone": "energy", "danger_tone": "crystal", "danger_at": 0.2,
		"per_row": 7, "size": 30.0, "low_at": 2.0, "glyph": "hp"})
	# Energy gauge (cyan, partial).
	NebulaHud.draw_tank_gauge(c, Vector2(20, 160), {
		"label": "Energy", "value": 380, "max": 1000, "total": 10,
		"tone": "magic", "per_row": 5, "size": 30.0, "low_at": 1.0, "glyph": "bolt"})
	# Ability bar: slot with ammo+name+cooldown+selected, and a bare spell slot.
	var slots := [
		{"key": "1", "tex": NebulaHud.icon("comet"), "glow": NebulaHud.C_ACCENT, "cd": 0.4, "selected": true, "ammo": 2, "ammo_max": 8, "name": "Missiles"},
		{"key": "2", "tex": NebulaHud.icon("bolt"), "glow": NebulaHud.C_ACCENT, "cd": 0.0},
		{"key": "3", "tex": NebulaHud.icon("crystal"), "glow": NebulaHud.C_ACCENT, "cd": 0.0, "ammo": -1, "ammo_max": -1, "name": "Lance"},
	]
	NebulaHud.draw_ability_bar(c, 700, 20, "Weapons", slots, 52.0, true)
	# Minimap grid.
	var cells := [
		{"col": 0, "row": 0, "w": 1, "h": 1, "state": "cur"},
		{"col": 1, "row": 0, "w": 2, "h": 1, "state": "exp", "marker": "item"},
		{"col": 0, "row": 1, "w": 1, "h": 1, "state": "unx", "marker": "boss"},
	]
	NebulaHud.draw_minimap(c, Vector2(1200, 20), cells, 3, 2, 22.0, "Map", "S7")
	_ok = true


func _process(_d: float) -> bool:
	_frames += 1
	if _frames >= 3:
		print("NEBULA_HUD_SMOKE: ", "PASS" if _ok else "FAIL (Control._draw never fired)")
		quit()
	return false
