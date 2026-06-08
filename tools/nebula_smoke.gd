extends SceneTree

# Headless smoke for the Nebula design-system Theme. Autoload-free (run with
# --script): proves the Theme actually builds from the shipped assets rather than
# silently falling back — the source PNGs/TTF import, the 9-slice/button/input
# styleboxes are present, and the default font is set.
# Run: godot --headless --path <proj> --script res://tools/nebula_smoke.gd

const Nebula := preload("res://MV/scripts/console/nebula_theme.gd")


func _init() -> void:
	var ok := true

	for path in [Nebula.FONT_PATH, Nebula.FRAME_LANDSCAPE, Nebula.BTN_CYAN]:
		if not ResourceLoader.exists(path):
			push_error("NEBULASMOKE: missing asset %s" % path)
			ok = false

	var t := Nebula.theme()
	if t == null:
		push_error("NEBULASMOKE: theme() returned null")
		ok = false
	else:
		if t.default_font == null:
			push_error("NEBULASMOKE: theme has no default font (TTF failed to load)")
			ok = false
		if not t.has_stylebox("panel", "PanelContainer"):
			push_error("NEBULASMOKE: window frame stylebox missing")
			ok = false
		if not t.has_stylebox("normal", "Button"):
			push_error("NEBULASMOKE: button capsule stylebox missing")
			ok = false
		if not t.has_stylebox("focus", "LineEdit"):
			push_error("NEBULASMOKE: input focus stylebox missing")
			ok = false
		if t.get_stylebox("panel", "PanelContainer") is StyleBoxTexture:
			print("NEBULASMOKE: window frame is StyleBoxTexture (9-slice wired)")
		else:
			push_error("NEBULASMOKE: window frame is not a textured 9-slice")
			ok = false

	# Builder helpers must produce real styleboxes.
	if not (Nebula.card_box() is StyleBoxFlat) or not (Nebula.well_box() is StyleBoxFlat):
		push_error("NEBULASMOKE: card_box/well_box builders broken")
		ok = false
	if not (Nebula.title_label("x") is Label):
		push_error("NEBULASMOKE: title_label builder broken")
		ok = false

	print("NEBULASMOKE: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
