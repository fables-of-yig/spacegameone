extends RefCounted

const PedIO := preload("res://Space/scripts/shared/ped/ped_io.gd")
const EntIO := preload("res://Space/scripts/shared/ent/ent_io.gd")

const PICKUP_UNLOCKS_GATE: int = 1
const NPC_STARTS_DIALOGUE: int = 2
const BOSS_INTRO: int = 3
const BOSS_DEFEATED: int = 4
const UI_BUTTON_EVENT: int = 5
const QUEST_START_ON_ZONE: int = 6
const QUEST_OBJECTIVE_ON_PICKUP: int = 7
const QUEST_COMPLETE_ON_BOSS: int = 8


static func build_recipe_rule(recipe_id: int, pack_id: String) -> Dictionary:
	match recipe_id:
		PICKUP_UNLOCKS_GATE:
			return _recipe_pickup_unlocks_gate(pack_id)
		NPC_STARTS_DIALOGUE:
			return _recipe_npc_starts_dialogue(pack_id)
		BOSS_INTRO:
			return _recipe_boss_intro(pack_id)
		BOSS_DEFEATED:
			return _recipe_boss_defeated(pack_id)
		UI_BUTTON_EVENT:
			return _recipe_ui_button_event()
		QUEST_START_ON_ZONE:
			return _recipe_quest_start_on_zone(pack_id)
		QUEST_OBJECTIVE_ON_PICKUP:
			return _recipe_quest_objective_on_pickup(pack_id)
		QUEST_COMPLETE_ON_BOSS:
			return _recipe_quest_complete_on_boss(pack_id)
	return {}


static func _recipe_pickup_unlocks_gate(pack_id: String) -> Dictionary:
	var item_id := _first_item_id(pack_id, "key_silver")
	var ability_id := _first_ability_id(pack_id, "phase_dash")
	var actions: Array = [
		{"type": "set_var", "name": "has_%s" % item_id, "value": 1},
		{"type": "set_door_locked", "id": "gate_to_boss", "locked": false},
		{"type": "add_tag", "tag": "gate_to_boss_unlocked"},
	]
	if not ability_id.is_empty():
		actions.insert(0, {"type": "give_ability", "id": ability_id})
	else:
		actions.append({"type": "log", "message": "Add an ability, then add a Give player ability action here."})
	return {
		"id": "pickup_unlocks_gate",
		"name": "Pickup unlocks a gate",
		"event": "pickup",
		"enabled": true,
		"once": true,
		"locals": [],
		"conditions": [{"type": "payload_eq", "key": "item_id", "value": item_id}],
		"actions": actions,
	}


static func _recipe_npc_starts_dialogue(pack_id: String) -> Dictionary:
	var entity_id := _first_entity_id(pack_id, "interactable", "npc_shopkeeper")
	var dialogue_id := _first_dialogue_id(pack_id, "golden_shopkeep")
	var actions: Array = []
	if not dialogue_id.is_empty():
		actions.append({"type": "start_dialogue", "id": dialogue_id})
	else:
		actions.append({"type": "log", "message": "Create a dialogue, then add a Start conversation action here."})
	return {
		"id": "npc_starts_dialogue",
		"name": "NPC starts a conversation",
		"event": "interact",
		"enabled": true,
		"once": false,
		"locals": [],
		"conditions": [{"type": "payload_eq", "key": "entity_id", "value": entity_id}],
		"actions": actions,
	}


static func _recipe_boss_intro(pack_id: String) -> Dictionary:
	var boss_id := _first_entity_id(pack_id, "boss", "golden_boss")
	var actions: Array = [
		{"type": "lock_player"},
		{"type": "camera_focus", "mode": "position", "x": 320.0, "y": 176.0, "duration": 0.0},
	]
	if not boss_id.is_empty():
		actions.append({"type": "spawn_entity_at_zone", "id": boss_id, "zone_id": "boss_intro"})
	else:
		actions.append({"type": "log", "message": "Create a boss entity, then add a Spawn entity at zone action here."})
	actions.append({"type": "camera_unlock"})
	actions.append({"type": "unlock_player"})
	return {
		"id": "boss_intro",
		"name": "Boss intro zone",
		"event": "zone_enter",
		"enabled": true,
		"once": true,
		"locals": [],
		"conditions": [{"type": "payload_eq", "key": "zone_id", "value": "boss_intro"}],
		"actions": actions,
	}


static func _recipe_boss_defeated(pack_id: String) -> Dictionary:
	var item_id := _first_item_id(pack_id, "boss_core")
	return {
		"id": "boss_defeated_reward",
		"name": "Boss defeated reward",
		"event": "boss_defeated",
		"enabled": true,
		"once": true,
		"locals": [],
		"conditions": [{"type": "payload_eq", "key": "entity_id", "value": _first_entity_id(pack_id, "boss", "golden_boss")}],
		"actions": [
			{"type": "give_item", "id": item_id, "count": 1},
			{"type": "set_door_locked", "id": "boss_exit", "locked": false},
			{"type": "add_tag", "tag": "boss_defeated"},
		],
	}


static func _recipe_ui_button_event() -> Dictionary:
	return {
		"id": "ui_button_fires_event",
		"name": "UI button fires a story event",
		"event": "ui_button",
		"enabled": true,
		"once": false,
		"locals": [],
		"conditions": [{"type": "payload_eq", "key": "action", "value": "start"}],
		"actions": [{"type": "fire_event", "event": "story_button_pressed", "inherit_payload": true}],
	}


static func _recipe_quest_start_on_zone(pack_id: String) -> Dictionary:
	var quest := _first_quest(pack_id)
	var quest_id := str(quest.get("id", "first_steps"))
	var stage_id := _first_stage_id(quest, "start")
	return {
		"id": "quest_starts_on_zone",
		"name": "Quest starts when entering a zone",
		"event": "zone_enter",
		"enabled": true,
		"once": true,
		"locals": [],
		"conditions": [{"type": "payload_eq", "key": "zone_id", "value": "quest_start_zone"}],
		"actions": [{"type": "quest_start", "quest_id": quest_id, "stage_id": stage_id}],
	}


static func _recipe_quest_objective_on_pickup(pack_id: String) -> Dictionary:
	var quest := _first_quest(pack_id)
	var quest_id := str(quest.get("id", "first_steps"))
	var target := _first_objective_for_type(quest, "collect_item")
	var stage_id := str(target.get("stage_id", _first_stage_id(quest, "start")))
	var objective_id := str(target.get("objective_id", "get_key"))
	var item_id := str(target.get("item_id", _first_item_id(pack_id, "key_silver")))
	return {
		"id": "quest_pickup_completes_objective",
		"name": "Pickup completes a quest objective",
		"event": "pickup",
		"enabled": true,
		"once": true,
		"locals": [],
		"conditions": [{"type": "payload_eq", "key": "item_id", "value": item_id}],
		"actions": [{"type": "quest_complete_objective", "quest_id": quest_id, "stage_id": stage_id, "objective_id": objective_id}],
	}


static func _recipe_quest_complete_on_boss(pack_id: String) -> Dictionary:
	var quest := _first_quest(pack_id)
	var quest_id := str(quest.get("id", "first_steps"))
	var target := _first_objective_for_type(quest, "kill_entity")
	var stage_id := str(target.get("stage_id", _last_stage_id(quest, "start")))
	var objective_id := str(target.get("objective_id", "defeat_boss"))
	var boss_id := str(target.get("entity_id", _first_entity_id(pack_id, "boss", "golden_boss")))
	return {
		"id": "quest_boss_completion",
		"name": "Boss defeated completes a quest",
		"event": "enemy_defeated",
		"enabled": true,
		"once": true,
		"locals": [],
		"conditions": [{"type": "payload_eq", "key": "entity_id", "value": boss_id}],
		"actions": [
			{"type": "quest_set_stage", "quest_id": quest_id, "stage_id": stage_id},
			{"type": "quest_complete_objective", "quest_id": quest_id, "stage_id": stage_id, "objective_id": objective_id},
			{"type": "quest_complete_stage", "quest_id": quest_id, "stage_id": stage_id},
			{"type": "quest_complete", "quest_id": quest_id},
		],
	}


static func _first_item_id(pack_id: String, preferred_id: String) -> String:
	var entries_v: Variant = PedIO.load_items(pack_id).get("items", [])
	if typeof(entries_v) != TYPE_ARRAY:
		return "coin"
	var fallback := ""
	for entry_v in entries_v:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var item_id := str((entry_v as Dictionary).get("id", "")).strip_edges()
		if item_id.is_empty():
			continue
		if item_id == preferred_id:
			return item_id
		if fallback.is_empty():
			fallback = item_id
	return fallback if not fallback.is_empty() else "coin"


static func _first_ability_id(pack_id: String, preferred_id: String) -> String:
	var entries_v: Variant = PedIO.load_abilities(pack_id).get("abilities", [])
	if typeof(entries_v) != TYPE_ARRAY:
		return ""
	var fallback := ""
	for entry_v in entries_v:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var ability_id := str((entry_v as Dictionary).get("id", "")).strip_edges()
		if ability_id.is_empty():
			continue
		if ability_id == preferred_id:
			return ability_id
		if fallback.is_empty():
			fallback = ability_id
	return fallback


static func _first_dialogue_id(pack_id: String, preferred_id: String) -> String:
	var ids := PedIO.list_dialogues(pack_id)
	if ids.has(preferred_id):
		return preferred_id
	for id_v in ids:
		var dialogue_id := str(id_v).strip_edges()
		if not dialogue_id.is_empty():
			return dialogue_id
	return ""


static func _first_entity_id(pack_id: String, preferred_category: String, preferred_id: String) -> String:
	var entries_v: Variant = EntIO.load_or_init(pack_id).get("entities", [])
	if typeof(entries_v) != TYPE_ARRAY:
		return preferred_id
	var category_fallback := ""
	var fallback := ""
	for entry_v in entries_v:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var entity_id := str(entry.get("id", "")).strip_edges()
		if entity_id.is_empty():
			continue
		if entity_id == preferred_id:
			return entity_id
		if fallback.is_empty():
			fallback = entity_id
		if category_fallback.is_empty() and str(entry.get("category", "")).strip_edges() == preferred_category:
			category_fallback = entity_id
	if not category_fallback.is_empty():
		return category_fallback
	return fallback if not fallback.is_empty() else preferred_id


static func _first_quest(pack_id: String) -> Dictionary:
	var quests_v: Variant = QuestIO.load_or_init(pack_id).get("quests", [])
	if typeof(quests_v) != TYPE_ARRAY:
		return QuestIO.starter_quest("first_steps")
	for quest_v in quests_v:
		if typeof(quest_v) != TYPE_DICTIONARY:
			continue
		var quest: Dictionary = quest_v
		if not str(quest.get("id", "")).strip_edges().is_empty():
			return quest
	return QuestIO.starter_quest("first_steps")


static func _first_stage_id(quest: Dictionary, fallback_id: String) -> String:
	var stages_v: Variant = quest.get("stages", [])
	if typeof(stages_v) == TYPE_ARRAY:
		for stage_v in stages_v:
			if typeof(stage_v) != TYPE_DICTIONARY:
				continue
			var stage_id := str((stage_v as Dictionary).get("id", "")).strip_edges()
			if not stage_id.is_empty():
				return stage_id
	return fallback_id


static func _last_stage_id(quest: Dictionary, fallback_id: String) -> String:
	var stages_v: Variant = quest.get("stages", [])
	var last := ""
	if typeof(stages_v) == TYPE_ARRAY:
		for stage_v in stages_v:
			if typeof(stage_v) != TYPE_DICTIONARY:
				continue
			var stage_id := str((stage_v as Dictionary).get("id", "")).strip_edges()
			if not stage_id.is_empty():
				last = stage_id
	return last if not last.is_empty() else fallback_id


static func _first_objective_for_type(quest: Dictionary, preferred_type: String) -> Dictionary:
	var first: Dictionary = {}
	var stages_v: Variant = quest.get("stages", [])
	if typeof(stages_v) != TYPE_ARRAY:
		return {}
	for stage_v in stages_v:
		if typeof(stage_v) != TYPE_DICTIONARY:
			continue
		var stage: Dictionary = stage_v
		var stage_id := str(stage.get("id", "")).strip_edges()
		var objectives_v: Variant = stage.get("objectives", [])
		if typeof(objectives_v) != TYPE_ARRAY:
			continue
		for objective_v in objectives_v:
			if typeof(objective_v) != TYPE_DICTIONARY:
				continue
			var objective: Dictionary = objective_v
			var objective_id := str(objective.get("id", "")).strip_edges()
			if objective_id.is_empty():
				continue
			var found := objective.duplicate(true)
			found["stage_id"] = stage_id
			found["objective_id"] = objective_id
			if first.is_empty():
				first = found
			if str(objective.get("type", "")).strip_edges() == preferred_type:
				return found
	return first
