extends SceneTree

# Headless data-layer smoke for the authored-FX system. Autoload-free (run with
# --script), so it exercises only the pieces that don't need a live pack/room:
#   - spawn_fx is registered in the ECA action schema
#   - EffIO default effects are present and well-formed
#   - MvAuthoredFx.setup() runs on a real def without error
# Run: godot --headless --path <proj> --script res://tools/fx_smoke.gd

const EffIO := preload("res://Space/scripts/shared/eff/eff_io.gd")
const EcaSchema := preload("res://Space/scripts/editor/dlg/eca_schema.gd")
const AuthoredFx := preload("res://MV/scripts/authored_fx.gd")


func _init() -> void:
	var ok := true

	if EcaSchema.find_action_schema("spawn_fx").is_empty():
		push_error("FXSMOKE: spawn_fx action missing from EcaSchema")
		ok = false
	else:
		print("FXSMOKE: spawn_fx schema present")

	var defs := EffIO.default_effects()
	if defs.size() < 3:
		push_error("FXSMOKE: expected >=3 default effects, got %d" % defs.size())
		ok = false
	for d_v in defs:
		var d: Dictionary = d_v
		for key in ["id", "name", "count", "colors", "lifetime"]:
			if not d.has(key):
				push_error("FXSMOKE: default effect '%s' missing '%s'" % [d.get("id", "?"), key])
				ok = false
	print("FXSMOKE: %d default effects" % defs.size())

	var blank := EffIO.default_effect("probe")
	if not blank.has("colors") or not blank.has("spread"):
		push_error("FXSMOKE: default_effect() shape is wrong")
		ok = false

	var fx = AuthoredFx.new()
	fx.setup(defs[0], Vector2(10, 10), Vector2.RIGHT)
	fx.setup(blank, Vector2.ZERO, Vector2.ZERO)
	fx.free()
	print("FXSMOKE: MvAuthoredFx.setup OK")

	print("FXSMOKE: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
