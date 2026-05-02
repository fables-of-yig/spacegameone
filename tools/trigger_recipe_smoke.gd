extends SceneTree

const ContentValidator := preload("res://Space/scripts/editor/content_validator.gd")
const PedIO := preload("res://Space/scripts/editor/ped/ped_io.gd")
const EntIO := preload("res://Space/scripts/editor/ent/ent_io.gd")
const QuestIO := preload("res://Space/scripts/editor/quest_io.gd")
const TriggerRecipes := preload("res://Space/scripts/editor/dlg/trigger_recipes.gd")

const PACK_ID := "trigger_recipe_smoke"


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	var ok := _run()
	quit(0 if ok else 1)


func _run() -> bool:
	if not MvPackLoader.create_empty_pack(PACK_ID, "Trigger Recipe Smoke"):
		push_error("trigger_recipe_smoke: bootstrap failed")
		return false
	if not _seed_recipe_refs():
		return false

	var rules: Array = []
	var recipe_ids := [
		TriggerRecipes.PICKUP_UNLOCKS_GATE,
		TriggerRecipes.NPC_STARTS_DIALOGUE,
		TriggerRecipes.BOSS_INTRO,
		TriggerRecipes.BOSS_DEFEATED,
		TriggerRecipes.UI_BUTTON_EVENT,
		TriggerRecipes.QUEST_START_ON_ZONE,
		TriggerRecipes.QUEST_OBJECTIVE_ON_PICKUP,
		TriggerRecipes.QUEST_COMPLETE_ON_BOSS,
	]
	for recipe_id in recipe_ids:
		var rule_v: Variant = TriggerRecipes.build_recipe_rule(recipe_id, PACK_ID)
		if typeof(rule_v) != TYPE_DICTIONARY:
			push_error("trigger_recipe_smoke: recipe %d did not return a rule" % recipe_id)
			return false
		var rule: Dictionary = rule_v
		if str(rule.get("id", "")).strip_edges().is_empty():
			push_error("trigger_recipe_smoke: recipe %d returned an empty id" % recipe_id)
			return false
		rules.append(rule)

	if not PedIO.save_triggers(PACK_ID, {"triggers": rules, "libraries": []}):
		push_error("trigger_recipe_smoke: generated recipes failed PedIO validation")
		return false
	return _validate_pack()


func _seed_recipe_refs() -> bool:
	if not PedIO.save_abilities(PACK_ID, {
		"abilities": [
			{"id": "phase_dash", "name": "Phase Dash", "category": "movement", "description": "", "params": {}},
		],
	}):
		return false
	if not PedIO.save_items(PACK_ID, {
		"items": [
			{"id": "coin", "name": "Coin", "description": "Currency.", "max_stack": 9999, "price": 1, "category": "currency", "use_effect": "", "use_amount": 0, "use_arg": ""},
			{"id": "key_silver", "name": "Silver Key", "description": "Gate key.", "max_stack": 1, "price": 25, "category": "key", "use_effect": "", "use_amount": 0, "use_arg": ""},
			{"id": "boss_core", "name": "Boss Core", "description": "Boss reward.", "max_stack": 9, "price": 100, "category": "quest", "use_effect": "", "use_amount": 0, "use_arg": ""},
		],
	}):
		return false
	if not EntIO.save_entities(PACK_ID, {
		"entities": [
			_entity("pickup", "Pickup", "pickup"),
			_entity("trigger_volume", "Trigger Volume", "logic"),
			_entity("golden_shopkeeper", "Golden Shopkeeper", "interactable"),
			_entity("golden_boss", "Golden Boss", "boss"),
		],
	}):
		return false
	if not QuestIO.save(PACK_ID, {
		"quests": [
			{
				"id": "boss_gate",
				"title": "Boss Gate",
				"description": "A recipe smoke quest.",
				"repeatable": false,
				"stages": [
					{
						"id": "prepare",
						"title": "Prepare",
						"description": "Find the key.",
						"objectives": [{"id": "get_key", "type": "collect_item", "item_id": "key_silver", "count": 1}],
						"rewards": {"items": [], "abilities": [], "events": []},
					},
					{
						"id": "clear_boss",
						"title": "Clear Boss",
						"description": "Defeat the boss.",
						"objectives": [{"id": "defeat_boss", "type": "kill_entity", "entity_id": "golden_boss", "count": 1}],
						"rewards": {"items": ["boss_core"], "abilities": [], "events": ["boss_gate_complete"]},
					},
				],
			},
		],
	}):
		return false
	return PedIO.save_dialogue(PACK_ID, "golden_shopkeep", {
		"id": "golden_shopkeep",
		"lines": [{"speaker": "NPC", "text": "Ready.", "actions": [], "choices": []}],
	})


func _entity(id: String, display_name: String, category: String) -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"category": category,
		"description": "",
		"scene": "",
		"sprite_set": "",
		"behavior": "",
		"movement_mode": "ground",
		"hp": 1,
		"attack_damage": 0,
		"contact_damage": 0,
		"contact_cooldown": 0.8,
		"move_speed": 0,
		"projectile_damage": 0,
		"projectile_speed": 0,
		"melee_range": 0,
		"melee_attack_trigger_frame": -1,
		"projectile_range": 0,
		"projectile_attack_trigger_frame": -1,
	}


func _validate_pack() -> bool:
	var issues := ContentValidator.validate(PACK_ID)
	var errors := 0
	for issue_v in issues:
		if issue_v != null and issue_v.severity == "error":
			errors += 1
			push_error("[trigger_recipe_smoke] %s - %s" % [issue_v.source, issue_v.message])
	if errors > 0:
		push_error("trigger_recipe_smoke: validation failed with %d error(s)" % errors)
		return false
	print("[trigger_recipe_smoke] PASS recipes=%d issues=%d" % [8, issues.size()])
	return true
