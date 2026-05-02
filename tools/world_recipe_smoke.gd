extends SceneTree

const PlanetLandingBossRecipe := preload("res://Space/scripts/editor/recipes/planet_landing_boss_recipe.gd")

const PACK_ID := "world_recipe_smoke"


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	var ok := _run()
	quit(0 if ok else 1)


func _run() -> bool:
	if not MvPackLoader.create_empty_pack(PACK_ID, "World Recipe Smoke"):
		push_error("world_recipe_smoke: bootstrap failed")
		return false
	var result := PlanetLandingBossRecipe.apply(PACK_ID, {
		"system_id": "start",
		"planet_name": "Recipe Landing",
		"key_item_id": "key_silver",
		"boss_entity_id": "golden_boss",
	})
	if not bool(result.get("ok", false)):
		for error_v in result.get("errors", []):
			push_error("[world_recipe_smoke] %s" % str(error_v))
		return false
	print("[world_recipe_smoke] PASS start_room='%s' issues=%d" % [
		str(result.get("start_room", "")),
		int(result.get("issue_count", 0)),
	])
	return true
