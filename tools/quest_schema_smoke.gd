extends SceneTree

const ContentReferenceIndex := preload("res://Space/scripts/editor/content_reference_index.gd")
const ContentReferenceRefactor := preload("res://Space/scripts/editor/content_reference_refactor.gd")
const ContentValidator := preload("res://Space/scripts/editor/content_validator.gd")
const PedIO := preload("res://Space/scripts/editor/ped/ped_io.gd")
const QuestIO := preload("res://Space/scripts/editor/quest_io.gd")
const PlanetLandingBossRecipe := preload("res://Space/scripts/editor/recipes/planet_landing_boss_recipe.gd")
const UiBindingResolver := preload("res://MV/scripts/ui_binding_resolver.gd")

const PACK_ID := "quest_schema_smoke"
const OLD_ITEM_ID := "key_silver"
const NEW_ITEM_ID := "key_quest_renamed"
const BOSS_ID := "golden_boss"
const QUEST_ID := "boss_gate"
const DIALOGUE_ID := "quest_giver"
const SHOP_ID := "supply_shop"
const ROOM_ADDR := "realm_main/region_default/landing"


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	var ok: bool = await _run()
	quit(0 if ok else 1)


func _run() -> bool:
	if not _clean_user_pack(PACK_ID):
		return false
	if not MvPackLoader.create_empty_pack(PACK_ID, "Quest Schema Smoke"):
		push_error("quest_schema_smoke: bootstrap failed")
		return false
	var recipe_result := PlanetLandingBossRecipe.apply(PACK_ID, {
		"system_id": "start",
		"planet_name": "Quest Landing",
		"key_item_id": OLD_ITEM_ID,
		"boss_entity_id": BOSS_ID,
	})
	if not bool(recipe_result.get("ok", false)):
		for error_v in recipe_result.get("errors", []):
			push_error("[quest_schema_smoke] %s" % str(error_v))
		return false
	if not _seed_dialogue_and_shop():
		return false
	if not _seed_quest(OLD_ITEM_ID):
		return false
	if not _seed_quest_triggers(OLD_ITEM_ID):
		return false
	if not _validate_clean("initial"):
		return false
	if MvPackLoader.load_pack(PACK_ID) == null:
		push_error("quest_schema_smoke: pack load failed before runtime binding smoke")
		return false
	if not await _run_trigger_quest_state_smoke(OLD_ITEM_ID):
		return false

	var index := ContentReferenceIndex.build(PACK_ID)
	if not _has_definition(index, "quest", QUEST_ID):
		push_error("quest_schema_smoke: missing quest definition")
		return false
	if not _has_reference(index, "item", OLD_ITEM_ID, "Quest '%s'" % QUEST_ID):
		push_error("quest_schema_smoke: missing quest item objective reference")
		return false
	if not _has_reference(index, "entity", BOSS_ID, "Quest '%s'" % QUEST_ID):
		push_error("quest_schema_smoke: missing quest entity objective reference")
		return false
	if not _has_reference(index, "room", ROOM_ADDR, "Quest '%s'" % QUEST_ID):
		push_error("quest_schema_smoke: missing quest room objective reference")
		return false
	if not _has_reference(index, "dialogue", DIALOGUE_ID, "Quest '%s'" % QUEST_ID):
		push_error("quest_schema_smoke: missing quest dialogue objective reference")
		return false
	if not _has_reference(index, "shop", SHOP_ID, "Quest '%s'" % QUEST_ID):
		push_error("quest_schema_smoke: missing quest shop objective reference")
		return false
	if not _has_reference(index, "ability", "phase_dash", "Quest '%s'" % QUEST_ID):
		push_error("quest_schema_smoke: missing quest ability reward reference")
		return false
	if not _has_reference(index, "quest", QUEST_ID, "quest_start"):
		push_error("quest_schema_smoke: missing trigger quest action reference")
		return false

	var refactor := ContentReferenceRefactor.rename_references(PACK_ID, "item", OLD_ITEM_ID, NEW_ITEM_ID)
	if not bool(refactor.get("ok", false)):
		for error_v in refactor.get("errors", []):
			push_error("[quest_schema_smoke] %s" % str(error_v))
		return false
	if int(refactor.get("changed_refs", 0)) < 3:
		push_error("quest_schema_smoke: expected item refs to update, got %d" % int(refactor.get("changed_refs", 0)))
		return false
	if not _rename_item_definition():
		return false
	if not _validate_clean("renamed"):
		return false
	var renamed_index := ContentReferenceIndex.build(PACK_ID)
	if not ContentReferenceIndex.find_references_in_index(renamed_index, "item", OLD_ITEM_ID).is_empty():
		push_error("quest_schema_smoke: old item id still has references")
		return false
	if not _has_reference(renamed_index, "item", NEW_ITEM_ID, "Quest '%s'" % QUEST_ID):
		push_error("quest_schema_smoke: renamed quest item reference missing")
		return false

	print("[quest_schema_smoke] PASS definitions=%d references=%d changed_refs=%d" % [
		_as_array(renamed_index.get("definitions", [])).size(),
		_as_array(renamed_index.get("references", [])).size(),
		int(refactor.get("changed_refs", 0)),
	])
	return true


func _seed_dialogue_and_shop() -> bool:
	if not PedIO.save_dialogue(PACK_ID, DIALOGUE_ID, {
		"id": DIALOGUE_ID,
		"name": "Quest Giver",
		"lines": [
			{"id": "start", "speaker": "Guide", "text": "Find the key and clear the gate.", "condition": {}, "actions": [], "choices": []},
		],
	}):
		push_error("quest_schema_smoke: dialogue seed failed")
		return false
	if not PedIO.save_shop(PACK_ID, SHOP_ID, {
		"id": SHOP_ID,
		"name": "Supply Shop",
		"items": [
			{"stock_id": "coin_pack", "id": "coin", "name": "Coin Pack", "price": 0, "count": 1, "use_effect": "", "use_amount": 0, "use_arg": ""},
		],
	}):
		push_error("quest_schema_smoke: shop seed failed")
		return false
	return true


func _seed_quest(item_id: String) -> bool:
	return QuestIO.save(PACK_ID, {
		"quests": [
			{
				"id": QUEST_ID,
				"title": "Open the Boss Gate",
				"description": "A full cross-reference quest schema smoke test.",
				"repeatable": false,
				"stages": [
					{
						"id": "prepare",
						"title": "Prepare",
						"objectives": [
							{"id": "get_key", "type": "collect_item", "item_id": item_id, "count": 1},
							{"id": "visit_landing", "type": "visit_room", "room": ROOM_ADDR},
							{"id": "talk_guide", "type": "talk_dialogue", "dialogue_id": DIALOGUE_ID},
							{"id": "open_supply", "type": "open_shop", "shop_id": SHOP_ID},
						],
						"rewards": {"items": [], "abilities": [], "events": []},
					},
					{
						"id": "clear_boss",
						"title": "Clear Boss",
						"objectives": [
							{"id": "defeat_boss", "type": "kill_entity", "entity_id": BOSS_ID, "count": 1},
							{"id": "boss_event", "type": "trigger_event", "event": "boss_defeated"},
						],
						"rewards": {
							"items": [{"id": "boss_core", "count": 1}],
							"abilities": ["phase_dash"],
							"events": ["quest_boss_gate_complete"],
						},
					},
				],
			},
		],
	})


func _seed_quest_triggers(item_id: String) -> bool:
	return PedIO.save_triggers(PACK_ID, {
		"triggers": [
			{
				"id": "quest_start",
				"event": "zone_enter",
				"conditions": [{"type": "payload_eq", "key": "zone_id", "value": "quest_start_zone"}],
				"actions": [{"type": "quest_start", "quest_id": QUEST_ID, "stage_id": "prepare"}],
			},
			{
				"id": "quest_key_pickup",
				"event": "pickup",
				"conditions": [{"type": "payload_eq", "key": "item_id", "value": item_id}],
				"actions": [{"type": "quest_complete_objective", "quest_id": QUEST_ID, "stage_id": "prepare", "objective_id": "get_key"}],
			},
			{
				"id": "quest_boss_defeated",
				"event": "enemy_defeated",
				"conditions": [{"type": "payload_eq", "key": "entity_id", "value": BOSS_ID}],
				"actions": [
					{"type": "quest_set_stage", "quest_id": QUEST_ID, "stage_id": "clear_boss"},
					{"type": "quest_complete_objective", "quest_id": QUEST_ID, "stage_id": "clear_boss", "objective_id": "defeat_boss"},
					{"type": "quest_complete_stage", "quest_id": QUEST_ID, "stage_id": "clear_boss"},
					{"type": "quest_complete", "quest_id": QUEST_ID},
				],
			},
		],
		"libraries": [],
	})


func _run_trigger_quest_state_smoke(item_id: String) -> bool:
	var trigger_engine := _trigger_engine()
	if trigger_engine == null:
		push_error("quest_schema_smoke: MvTriggerEngine autoload not found")
		return false
	trigger_engine.clear()
	trigger_engine.load_triggers(PACK_ID)
	trigger_engine.fire_event("zone_enter", {"zone_id": "quest_start_zone"})
	await _drain_trigger_actions()
	var state: Dictionary = trigger_engine.get_quest_state(QUEST_ID)
	if str(state.get("status", "")) != "active" or str(state.get("stage_id", "")) != "prepare":
		push_error("quest_schema_smoke: quest_start action did not activate prepare stage")
		return false
	if str(UiBindingResolver.resolve("quest.current.title")) != "Open the Boss Gate":
		push_error("quest_schema_smoke: quest.current.title binding did not resolve active quest")
		return false
	var objectives_v: Variant = UiBindingResolver.resolve("quest.current.objectives")
	if typeof(objectives_v) != TYPE_ARRAY or (objectives_v as Array).is_empty():
		push_error("quest_schema_smoke: quest.current.objectives binding did not resolve active stage objectives")
		return false
	trigger_engine.fire_event("pickup", {"item_id": item_id})
	await _drain_trigger_actions()
	if not trigger_engine.is_quest_objective_complete(QUEST_ID, "prepare", "get_key"):
		push_error("quest_schema_smoke: quest_complete_objective action did not mark pickup objective")
		return false
	trigger_engine.fire_event("enemy_defeated", {"entity_id": BOSS_ID})
	await _drain_trigger_actions()
	state = trigger_engine.get_quest_state(QUEST_ID)
	if str(state.get("status", "")) != "complete":
		push_error("quest_schema_smoke: quest_complete action did not complete quest")
		return false
	if not trigger_engine.is_quest_objective_complete(QUEST_ID, "clear_boss", "defeat_boss"):
		push_error("quest_schema_smoke: boss objective was not completed")
		return false
	var snap: Dictionary = trigger_engine.snapshot_runtime_state()
	trigger_engine.clear()
	trigger_engine.restore_runtime_state(snap)
	if str(trigger_engine.get_quest_state(QUEST_ID).get("status", "")) != "complete":
		push_error("quest_schema_smoke: quest state did not survive trigger runtime snapshot")
		return false
	return true


func _trigger_engine() -> Node:
	return root.get_node_or_null("MvTriggerEngine")


func _drain_trigger_actions() -> void:
	await process_frame
	await process_frame


func _rename_item_definition() -> bool:
	var data := PedIO.load_items(PACK_ID)
	for item_v in _as_array(data.get("items", [])):
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_v
		if str(item.get("id", "")).strip_edges() == OLD_ITEM_ID:
			item["id"] = NEW_ITEM_ID
			item["name"] = "Renamed Quest Key"
			return PedIO.save_items(PACK_ID, data)
	push_error("quest_schema_smoke: item definition not found")
	return false


func _validate_clean(label: String) -> bool:
	var issues := ContentValidator.validate(PACK_ID)
	for issue_v in issues:
		if issue_v != null and issue_v.severity == "error":
			push_error("[quest_schema_smoke:%s] %s - %s" % [label, issue_v.source, issue_v.message])
			return false
	return true


func _has_definition(index: Dictionary, kind: String, id: String) -> bool:
	for def_v in _as_array(index.get("definitions", [])):
		if typeof(def_v) != TYPE_DICTIONARY:
			continue
		var definition: Dictionary = def_v
		if str(definition.get("kind", "")) == kind and str(definition.get("id", "")) == id:
			return true
	return false


func _has_reference(index: Dictionary, kind: String, id: String, source_fragment: String) -> bool:
	for ref_v in ContentReferenceIndex.find_references_in_index(index, kind, id):
		if typeof(ref_v) != TYPE_DICTIONARY:
			continue
		var ref: Dictionary = ref_v
		if str(ref.get("source", "")).contains(source_fragment):
			return true
	return false


func _clean_user_pack(pack_id: String) -> bool:
	var root := "user://Packs/%s" % pack_id
	if not DirAccess.dir_exists_absolute(root):
		return true
	return _remove_tree(root)


func _remove_tree(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var child := "%s/%s" % [path, name]
		if dir.current_is_dir():
			if not _remove_tree(child):
				dir.list_dir_end()
				return false
		else:
			var err := DirAccess.remove_absolute(child)
			if err != OK:
				dir.list_dir_end()
				push_error("quest_schema_smoke: could not remove %s (%s)" % [child, error_string(err)])
				return false
		name = dir.get_next()
	dir.list_dir_end()
	var remove_err := DirAccess.remove_absolute(path)
	if remove_err != OK:
		push_error("quest_schema_smoke: could not remove %s (%s)" % [path, error_string(remove_err)])
		return false
	return true


func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
