extends SceneTree

# Headless compile/shape smoke for the player projectile FX hook. Autoload-free.
#   - MvAuthoredProjectile script parses (load returns a GDScript)
#   - the impact/explosion fx members and spawner methods exist
#   - starter projectile defs carry the new fx ids
# Run: godot --headless --path <proj> --script res://tools/proj_fx_smoke.gd

const PedIO := preload("res://Space/scripts/shared/ped/ped_io.gd")


func _init() -> void:
	var ok := true

	# Autoload-free run can't .new() this script (it references the PlayerInventory
	# autoload in a method body), so we verify the source carries the fx wiring and
	# that the starter defs seed the new fields. Full compile is covered by scene boot.
	var script := load("res://MV/scripts/authored_projectile.gd")
	if script == null:
		push_error("PROJFX: authored_projectile.gd failed to load (parse error)")
		quit(1)
		return
	print("PROJFX: authored_projectile.gd parsed")

	var src := str(script.source_code)
	for needle in ["_impact_fx", "_explosion_fx", "func _spawn_explosion_fx", "MvFx.spawn"]:
		if not src.contains(needle):
			push_error("PROJFX: authored_projectile.gd missing '%s'" % needle)
			ok = false

	var defs: Array = PedIO._starter_projectile_defs()
	var by_id := {}
	for d in defs:
		by_id[str(d.get("id", ""))] = d
	if str(by_id.get("beam_basic", {}).get("impact_fx", "")) != "spark_burst":
		push_error("PROJFX: beam_basic missing impact_fx seed")
		ok = false
	if str(by_id.get("grenade", {}).get("explosion_fx", "")) != "explosion_pop":
		push_error("PROJFX: grenade missing explosion_fx seed")
		ok = false
	print("PROJFX: starter defs carry fx ids")

	print("PROJFX: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
