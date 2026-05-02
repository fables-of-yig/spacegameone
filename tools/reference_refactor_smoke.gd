extends SceneTree

const ContentReferenceIndex := preload("res://Space/scripts/editor/content_reference_index.gd")
const ContentReferenceRefactor := preload("res://Space/scripts/editor/content_reference_refactor.gd")
const ContentValidator := preload("res://Space/scripts/editor/content_validator.gd")
const BehIO := preload("res://Space/scripts/editor/beh/beh_io.gd")
const EntIO := preload("res://Space/scripts/editor/ent/ent_io.gd")
const PedIO := preload("res://Space/scripts/editor/ped/ped_io.gd")
const RegIO := preload("res://Space/scripts/editor/reg/reg_io.gd")
const SystemIO := preload("res://Space/scripts/editor/system_io.gd")
const PlanetLandingBossRecipe := preload("res://Space/scripts/editor/recipes/planet_landing_boss_recipe.gd")

const PACK_ID := "reference_refactor_smoke"
const OLD_SYSTEM_ID := "start"
const NEW_SYSTEM_ID := "renamed_start"
const REALM_ID := "realm_main"
const REGION_ID := "region_default"
const OLD_ROOM_ID := "landing"
const NEW_ROOM_ID := "arrival"
const OLD_ENTITY_ID := "golden_boss"
const NEW_ENTITY_ID := "renamed_boss"
const OLD_BEHAVIOR_ID := "old_behavior"
const NEW_BEHAVIOR_ID := "new_behavior"
const OLD_ITEM_ID := "key_silver"
const NEW_ITEM_ID := "key_renamed"
const OLD_ABILITY_ID := "old_ability"
const NEW_ABILITY_ID := "new_ability"
const OLD_ATTACK_ID := "old_attack"
const NEW_ATTACK_ID := "new_attack"
const OLD_PROJECTILE_ID := "old_projectile"
const NEW_PROJECTILE_ID := "new_projectile"
const OLD_DIALOGUE_ID := "old_dialogue"
const NEW_DIALOGUE_ID := "new_dialogue"
const OLD_SHOP_ID := "old_shop"
const NEW_SHOP_ID := "new_shop"


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	var ok := _run()
	quit(0 if ok else 1)


func _run() -> bool:
	if not _clean_user_pack(PACK_ID):
		return false
	if not MvPackLoader.create_empty_pack(PACK_ID, "Reference Refactor Smoke"):
		push_error("reference_refactor_smoke: bootstrap failed")
		return false
	var recipe_result := PlanetLandingBossRecipe.apply(PACK_ID, {
		"system_id": "start",
		"planet_name": "Refactor Landing",
		"key_item_id": "key_silver",
		"boss_entity_id": OLD_ENTITY_ID,
	})
	if not bool(recipe_result.get("ok", false)):
		push_error("reference_refactor_smoke: recipe setup failed")
		return false
	if not _seed_behavior_reference():
		return false
	if not _seed_system_reference():
		return false
	if not _seed_room_reference():
		return false
	if not _seed_player_reference_data():
		return false
	if not _seed_dialogue_shop_reference_data():
		return false

	var refactor := ContentReferenceRefactor.rename_references(PACK_ID, "entity", OLD_ENTITY_ID, NEW_ENTITY_ID)
	if not bool(refactor.get("ok", false)):
		for error_v in refactor.get("errors", []):
			push_error("[reference_refactor_smoke] %s" % str(error_v))
		return false
	if int(refactor.get("changed_refs", 0)) < 2:
		push_error("reference_refactor_smoke: expected at least two entity references to update, got %d" % int(refactor.get("changed_refs", 0)))
		return false
	if not _rename_entity_definition():
		return false
	var behavior_refactor := ContentReferenceRefactor.rename_references(PACK_ID, "behavior", OLD_BEHAVIOR_ID, NEW_BEHAVIOR_ID)
	if not bool(behavior_refactor.get("ok", false)):
		for error_v in behavior_refactor.get("errors", []):
			push_error("[reference_refactor_smoke] %s" % str(error_v))
		return false
	if int(behavior_refactor.get("changed_refs", 0)) < 1:
		push_error("reference_refactor_smoke: expected behavior reference to update")
		return false
	if not _rename_behavior_definition():
		return false
	var item_refactor := ContentReferenceRefactor.rename_references(PACK_ID, "item", OLD_ITEM_ID, NEW_ITEM_ID)
	if not bool(item_refactor.get("ok", false)):
		for error_v in item_refactor.get("errors", []):
			push_error("[reference_refactor_smoke] %s" % str(error_v))
		return false
	if int(item_refactor.get("changed_refs", 0)) < 3:
		push_error("reference_refactor_smoke: expected item references to update")
		return false
	if not _rename_item_definition():
		return false
	var system_refactor := ContentReferenceRefactor.rename_references(PACK_ID, "system", OLD_SYSTEM_ID, NEW_SYSTEM_ID)
	if not bool(system_refactor.get("ok", false)):
		for error_v in system_refactor.get("errors", []):
			push_error("[reference_refactor_smoke] %s" % str(error_v))
		return false
	if int(system_refactor.get("changed_refs", 0)) < 2:
		push_error("reference_refactor_smoke: expected system start and connection references to update")
		return false
	if not _rename_system_definition():
		return false
	var room_refactor := _rename_room_and_references()
	if not bool(room_refactor.get("ok", false)):
		for error_v in room_refactor.get("errors", []):
			push_error("[reference_refactor_smoke] %s" % str(error_v))
		return false
	if int(room_refactor.get("changed_refs", 0)) < 2:
		push_error("reference_refactor_smoke: expected room references to update")
		return false
	var ability_refactor := ContentReferenceRefactor.rename_references(PACK_ID, "ability", OLD_ABILITY_ID, NEW_ABILITY_ID)
	if not bool(ability_refactor.get("ok", false)):
		for error_v in ability_refactor.get("errors", []):
			push_error("[reference_refactor_smoke] %s" % str(error_v))
		return false
	if int(ability_refactor.get("changed_refs", 0)) < 4:
		push_error("reference_refactor_smoke: expected ability references to update")
		return false
	if not _rename_ability_definition():
		return false
	var projectile_refactor := ContentReferenceRefactor.rename_references(PACK_ID, "projectile", OLD_PROJECTILE_ID, NEW_PROJECTILE_ID)
	if not bool(projectile_refactor.get("ok", false)):
		for error_v in projectile_refactor.get("errors", []):
			push_error("[reference_refactor_smoke] %s" % str(error_v))
		return false
	if int(projectile_refactor.get("changed_refs", 0)) < 2:
		push_error("reference_refactor_smoke: expected projectile references to update")
		return false
	if not _rename_projectile_definition():
		return false
	var attack_refactor := ContentReferenceRefactor.rename_references(PACK_ID, "attack", OLD_ATTACK_ID, NEW_ATTACK_ID)
	if not bool(attack_refactor.get("ok", false)):
		for error_v in attack_refactor.get("errors", []):
			push_error("[reference_refactor_smoke] %s" % str(error_v))
		return false
	if int(attack_refactor.get("changed_refs", 0)) < 4:
		push_error("reference_refactor_smoke: expected attack references to update")
		return false
	if not _rename_attack_definition():
		return false
	var dialogue_refactor := ContentReferenceRefactor.rename_references(PACK_ID, "dialogue", OLD_DIALOGUE_ID, NEW_DIALOGUE_ID)
	if not bool(dialogue_refactor.get("ok", false)):
		for error_v in dialogue_refactor.get("errors", []):
			push_error("[reference_refactor_smoke] %s" % str(error_v))
		return false
	if int(dialogue_refactor.get("changed_refs", 0)) < 2:
		push_error("reference_refactor_smoke: expected dialogue references to update")
		return false
	if not _rename_dialogue_definition():
		return false
	var shop_refactor := ContentReferenceRefactor.rename_references(PACK_ID, "shop", OLD_SHOP_ID, NEW_SHOP_ID)
	if not bool(shop_refactor.get("ok", false)):
		for error_v in shop_refactor.get("errors", []):
			push_error("[reference_refactor_smoke] %s" % str(error_v))
		return false
	if int(shop_refactor.get("changed_refs", 0)) < 2:
		push_error("reference_refactor_smoke: expected shop references to update")
		return false
	if not _rename_shop_definition():
		return false

	var issues := ContentValidator.validate(PACK_ID)
	for issue_v in issues:
		if issue_v != null and issue_v.severity == "error":
			push_error("[reference_refactor_smoke] %s - %s" % [issue_v.source, issue_v.message])
			return false

	var index := ContentReferenceIndex.build(PACK_ID)
	if not ContentReferenceIndex.find_references_in_index(index, "entity", OLD_ENTITY_ID).is_empty():
		push_error("reference_refactor_smoke: old entity id still has references")
		return false
	var new_refs := ContentReferenceIndex.find_references_in_index(index, "entity", NEW_ENTITY_ID)
	if new_refs.size() < 2:
		push_error("reference_refactor_smoke: renamed entity has too few references")
		return false
	if not ContentReferenceIndex.find_references_in_index(index, "behavior", OLD_BEHAVIOR_ID).is_empty():
		push_error("reference_refactor_smoke: old behavior id still has references")
		return false
	if ContentReferenceIndex.find_references_in_index(index, "behavior", NEW_BEHAVIOR_ID).is_empty():
		push_error("reference_refactor_smoke: renamed behavior has no references")
		return false
	if not ContentReferenceIndex.find_references_in_index(index, "item", OLD_ITEM_ID).is_empty():
		push_error("reference_refactor_smoke: old item id still has references")
		return false
	if ContentReferenceIndex.find_references_in_index(index, "item", NEW_ITEM_ID).is_empty():
		push_error("reference_refactor_smoke: renamed item has no references")
		return false
	if not ContentReferenceIndex.find_references_in_index(index, "system", OLD_SYSTEM_ID).is_empty():
		push_error("reference_refactor_smoke: old system id still has references")
		return false
	if ContentReferenceIndex.find_references_in_index(index, "system", NEW_SYSTEM_ID).is_empty():
		push_error("reference_refactor_smoke: renamed system has no references")
		return false
	var old_room_full := RegIO.runtime_room_addr(REALM_ID, REGION_ID, OLD_ROOM_ID)
	var new_room_full := RegIO.runtime_room_addr(REALM_ID, REGION_ID, NEW_ROOM_ID)
	if not ContentReferenceIndex.find_references_in_index(index, "room", old_room_full).is_empty():
		push_error("reference_refactor_smoke: old room address still has references")
		return false
	if not ContentReferenceIndex.find_references_in_index(index, "room", OLD_ROOM_ID).is_empty():
		push_error("reference_refactor_smoke: old local room id still has references")
		return false
	if ContentReferenceIndex.find_references_in_index(index, "room", new_room_full).is_empty():
		push_error("reference_refactor_smoke: renamed room address has no references")
		return false
	if not ContentReferenceIndex.find_references_in_index(index, "ability", OLD_ABILITY_ID).is_empty():
		push_error("reference_refactor_smoke: old ability id still has references")
		return false
	if ContentReferenceIndex.find_references_in_index(index, "ability", NEW_ABILITY_ID).is_empty():
		push_error("reference_refactor_smoke: renamed ability has no references")
		return false
	if not ContentReferenceIndex.find_references_in_index(index, "projectile", OLD_PROJECTILE_ID).is_empty():
		push_error("reference_refactor_smoke: old projectile id still has references")
		return false
	if ContentReferenceIndex.find_references_in_index(index, "projectile", NEW_PROJECTILE_ID).is_empty():
		push_error("reference_refactor_smoke: renamed projectile has no references")
		return false
	if not ContentReferenceIndex.find_references_in_index(index, "attack", OLD_ATTACK_ID).is_empty():
		push_error("reference_refactor_smoke: old attack id still has references")
		return false
	if ContentReferenceIndex.find_references_in_index(index, "attack", NEW_ATTACK_ID).is_empty():
		push_error("reference_refactor_smoke: renamed attack has no references")
		return false
	if not ContentReferenceIndex.find_references_in_index(index, "dialogue", OLD_DIALOGUE_ID).is_empty():
		push_error("reference_refactor_smoke: old dialogue id still has references")
		return false
	if ContentReferenceIndex.find_references_in_index(index, "dialogue", NEW_DIALOGUE_ID).is_empty():
		push_error("reference_refactor_smoke: renamed dialogue has no references")
		return false
	if not ContentReferenceIndex.find_references_in_index(index, "shop", OLD_SHOP_ID).is_empty():
		push_error("reference_refactor_smoke: old shop id still has references")
		return false
	if ContentReferenceIndex.find_references_in_index(index, "shop", NEW_SHOP_ID).is_empty():
		push_error("reference_refactor_smoke: renamed shop has no references")
		return false

	print("[reference_refactor_smoke] PASS entity_refs=%d behavior_refs=%d item_refs=%d system_refs=%d room_refs=%d ability_refs=%d projectile_refs=%d attack_refs=%d dialogue_refs=%d shop_refs=%d changed_files=%d new_refs=%d" % [
		int(refactor.get("changed_refs", 0)),
		int(behavior_refactor.get("changed_refs", 0)),
		int(item_refactor.get("changed_refs", 0)),
		int(system_refactor.get("changed_refs", 0)),
		int(room_refactor.get("changed_refs", 0)),
		int(ability_refactor.get("changed_refs", 0)),
		int(projectile_refactor.get("changed_refs", 0)),
		int(attack_refactor.get("changed_refs", 0)),
		int(dialogue_refactor.get("changed_refs", 0)),
		int(shop_refactor.get("changed_refs", 0)),
		_as_array(refactor.get("changed_files", [])).size() + _as_array(behavior_refactor.get("changed_files", [])).size() + _as_array(item_refactor.get("changed_files", [])).size() + _as_array(system_refactor.get("changed_files", [])).size() + _as_array(room_refactor.get("changed_files", [])).size() + _as_array(ability_refactor.get("changed_files", [])).size() + _as_array(projectile_refactor.get("changed_files", [])).size() + _as_array(attack_refactor.get("changed_files", [])).size() + _as_array(dialogue_refactor.get("changed_files", [])).size() + _as_array(shop_refactor.get("changed_files", [])).size(),
		new_refs.size(),
	])
	return true


func _seed_behavior_reference() -> bool:
	if not BehIO.save_behaviors(PACK_ID, {"behaviors": [_valid_behavior(OLD_BEHAVIOR_ID)]}):
		push_error("reference_refactor_smoke: could not seed behavior")
		return false
	var data := EntIO.load_or_init(PACK_ID)
	var entries := _as_array(data.get("entities", []))
	for entry_v in entries:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		if str(entry.get("id", "")).strip_edges() == OLD_ENTITY_ID:
			entry["behavior"] = OLD_BEHAVIOR_ID
			data["entities"] = entries
			return EntIO.save_entities(PACK_ID, data)
	push_error("reference_refactor_smoke: could not find entity for behavior reference")
	return false


func _seed_system_reference() -> bool:
	var systems := SystemIO.load_or_init(PACK_ID)
	if not systems.has(OLD_SYSTEM_ID):
		push_error("reference_refactor_smoke: missing starter system")
		return false
	var start_system: Dictionary = systems[OLD_SYSTEM_ID]
	start_system["connections"] = ["refactor_neighbor"]
	systems[OLD_SYSTEM_ID] = start_system
	systems["refactor_neighbor"] = {
		"name": "Refactor Neighbor",
		"position": [680, 500],
		"star_class": "K",
		"star_color": [0.9, 0.8, 0.55],
		"star_size": 48,
		"description": "System reference smoke neighbor.",
		"threat_level": 1,
		"faction": "independent",
		"connections": [OLD_SYSTEM_ID],
		"pois": [],
		"spawn_triggers": [],
		"placed_npcs": [],
	}
	return SystemIO.save(PACK_ID, systems)


func _seed_room_reference() -> bool:
	var old_full := RegIO.runtime_room_addr(REALM_ID, REGION_ID, OLD_ROOM_ID)
	var triggers := PedIO.load_triggers(PACK_ID)
	var rules := _as_array(triggers.get("triggers", []))
	rules.append({
		"id": "refactor_room_global",
		"name": "Refactor Room Global",
		"enabled": true,
		"event": "refactor_room_event",
		"conditions": [],
		"actions": [{"type": "teleport_player", "room": old_full, "x": 80, "y": 208}],
	})
	triggers["triggers"] = rules
	if not PedIO.save_triggers(PACK_ID, triggers):
		push_error("reference_refactor_smoke: could not seed global room trigger")
		return false

	var rooms_root := RegIO.load_region_rooms(PACK_ID, REALM_ID, REGION_ID)
	var rooms_v: Variant = rooms_root.get("rooms", {})
	if typeof(rooms_v) != TYPE_DICTIONARY:
		push_error("reference_refactor_smoke: region rooms missing")
		return false
	var rooms: Dictionary = rooms_v
	if not rooms.has("gate_room"):
		push_error("reference_refactor_smoke: gate room missing")
		return false
	var gate_room: Dictionary = rooms["gate_room"]
	var room_rules := _as_array(gate_room.get("triggers", []))
	room_rules.append({
		"id": "refactor_room_local",
		"name": "Refactor Room Local",
		"enabled": true,
		"event": "refactor_room_local_event",
		"conditions": [],
		"actions": [{"type": "set_room_weather", "room": old_full, "preset": "rain"}],
	})
	gate_room["triggers"] = room_rules
	rooms["gate_room"] = gate_room
	rooms_root["rooms"] = rooms
	if not RegIO.save_region_rooms(PACK_ID, REALM_ID, REGION_ID, rooms_root):
		push_error("reference_refactor_smoke: could not seed room trigger")
		return false
	RegIO.flatten_to_runtime(PACK_ID)
	return true


func _seed_player_reference_data() -> bool:
	var projectiles := PedIO.load_projectiles(PACK_ID)
	var projectile_entries := _as_array(projectiles.get("projectiles", []))
	projectile_entries.append({
		"id": OLD_PROJECTILE_ID,
		"name": "Old Projectile",
		"sprite_sheet": "projectiles_sheet.png",
		"frame_width": 16,
		"frame_height": 16,
		"frame_index": 0,
		"frame_count": 1,
		"frame_tick": 10,
		"speed": 220,
		"gravity": 0,
		"lifetime_ticks": 90,
		"damage": 7,
		"pierces": false,
		"hitbox_w": 8,
		"hitbox_h": 8,
		"trail_color": "#ffffff",
	})
	projectiles["projectiles"] = projectile_entries
	if not PedIO.save_projectiles(PACK_ID, projectiles):
		push_error("reference_refactor_smoke: could not seed projectile")
		return false

	var abilities := PedIO.load_abilities(PACK_ID)
	var ability_entries := _as_array(abilities.get("abilities", []))
	ability_entries.append({
		"id": OLD_ABILITY_ID,
		"name": "Old Ability",
		"description": "Ability reference smoke.",
		"category": "utility",
		"params": {"projectile_id": OLD_PROJECTILE_ID},
	})
	abilities["abilities"] = ability_entries
	if not PedIO.save_abilities(PACK_ID, abilities):
		push_error("reference_refactor_smoke: could not seed ability")
		return false

	var attacks := PedIO.load_attacks(PACK_ID)
	var attack_entries := _as_array(attacks.get("attacks", []))
	attack_entries.append({
		"id": OLD_ATTACK_ID,
		"name": "Old Attack",
		"type": "projectile",
		"projectile_id": OLD_PROJECTILE_ID,
		"cooldown_ticks": 12,
		"cost_mp": 0,
		"player_pose": 207,
		"hold_behavior": "full_auto",
		"charge_ticks": 0,
		"charged_attack_id": "",
		"combo_next_id": "",
		"hit_frames": [],
		"hitbox_x": 0,
		"hitbox_y": 0,
		"hitbox_w": 16,
		"hitbox_h": 16,
		"damage": 7,
		"knockback": 0,
		"muzzle_x": 20,
		"muzzle_y": -8,
		"sprite_sheet": "",
		"frame_width": 32,
		"frame_height": 32,
		"frame_index": 0,
		"frame_count": 1,
		"frame_tick": 6,
	})
	attacks["attacks"] = attack_entries
	if not PedIO.save_attacks(PACK_ID, attacks):
		push_error("reference_refactor_smoke: could not seed old attack")
		return false

	attacks = PedIO.load_attacks(PACK_ID)
	attack_entries = _as_array(attacks.get("attacks", []))
	attack_entries.append({
		"id": "refactor_attack_linker",
		"name": "Refactor Attack Linker",
		"type": "melee",
		"projectile_id": "",
		"cooldown_ticks": 12,
		"cost_mp": 0,
		"player_pose": 201,
		"hold_behavior": "single_press",
		"charge_ticks": 0,
		"charged_attack_id": OLD_ATTACK_ID,
		"combo_next_id": OLD_ATTACK_ID,
		"hit_frames": [1],
		"hitbox_x": 18,
		"hitbox_y": -6,
		"hitbox_w": 20,
		"hitbox_h": 20,
		"damage": 4,
		"knockback": 20,
		"muzzle_x": 0,
		"muzzle_y": 0,
		"sprite_sheet": "",
		"frame_width": 32,
		"frame_height": 32,
		"frame_index": 0,
		"frame_count": 1,
		"frame_tick": 6,
	})
	attacks["attacks"] = attack_entries
	if not PedIO.save_attacks(PACK_ID, attacks):
		push_error("reference_refactor_smoke: could not seed attacks")
		return false

	var equipment := PedIO.load_equipment(PACK_ID)
	var equipment_entries := _as_array(equipment.get("equipment", []))
	equipment_entries.append({
		"id": "refactor_equipment",
		"name": "Refactor Equipment",
		"description": "Reference smoke equipment.",
		"slot": "RightHand",
		"granted_ability": OLD_ABILITY_ID,
		"grants_abilities": [OLD_ABILITY_ID],
		"stat_mods": {},
		"weapon": OLD_ATTACK_ID,
		"sprite_sheet": "equipment_sheet.png",
		"frame_width": 16,
		"frame_height": 16,
		"frame_index": 0,
	})
	equipment["equipment"] = equipment_entries
	if not PedIO.save_equipment(PACK_ID, equipment):
		push_error("reference_refactor_smoke: could not seed equipment")
		return false

	var items := PedIO.load_items(PACK_ID)
	var item_entries := _as_array(items.get("items", []))
	item_entries.append({
		"id": "ability_ref_item",
		"name": "Ability Ref Item",
		"description": "Grants old ability.",
		"max_stack": 1,
		"price": 0,
		"category": "upgrade",
		"use_effect": "grant_ability",
		"use_amount": 1,
		"use_arg": OLD_ABILITY_ID,
	})
	item_entries.append({
		"id": "attack_ref_item",
		"name": "Attack Ref Item",
		"description": "Selects old attack.",
		"max_stack": 1,
		"price": 0,
		"category": "weapon",
		"use_effect": "set_weapon",
		"use_amount": 1,
		"use_arg": OLD_ATTACK_ID,
	})
	items["items"] = item_entries
	if not PedIO.save_items(PACK_ID, items):
		push_error("reference_refactor_smoke: could not seed item ability/attack refs")
		return false

	if not PedIO.save_shop(PACK_ID, "refactor_shop", {
		"id": "refactor_shop",
		"items": [
			{"stock_id": "ability_stock", "id": "ability_ref_item", "price": 1, "count": 1, "use_effect": "grant_ability", "use_arg": OLD_ABILITY_ID, "use_amount": 1},
			{"stock_id": "attack_stock", "id": "attack_ref_item", "price": 1, "count": 1, "use_effect": "set_weapon", "use_arg": OLD_ATTACK_ID, "use_amount": 1},
		],
	}):
		push_error("reference_refactor_smoke: could not seed shop ability/attack refs")
		return false

	var triggers := PedIO.load_triggers(PACK_ID)
	var rules := _as_array(triggers.get("triggers", []))
	rules.append({
		"id": "refactor_player_refs",
		"name": "Refactor Player Refs",
		"enabled": true,
		"event": "refactor_player_refs",
		"conditions": [{"type": "has_ability", "id": OLD_ABILITY_ID}],
		"actions": [{"type": "give_ability", "id": OLD_ABILITY_ID}],
	})
	triggers["triggers"] = rules
	if not PedIO.save_triggers(PACK_ID, triggers):
		push_error("reference_refactor_smoke: could not seed trigger ability refs")
		return false
	return true


func _seed_dialogue_shop_reference_data() -> bool:
	if not PedIO.save_dialogue(PACK_ID, OLD_DIALOGUE_ID, {
		"id": OLD_DIALOGUE_ID,
		"lines": [{"speaker": "Guide", "text": "Reference smoke dialogue."}],
	}):
		push_error("reference_refactor_smoke: could not seed dialogue")
		return false
	if not PedIO.save_shop(PACK_ID, OLD_SHOP_ID, {
		"id": OLD_SHOP_ID,
		"items": [{"stock_id": "key_stock", "id": OLD_ITEM_ID, "price": 1, "count": 1}],
	}):
		push_error("reference_refactor_smoke: could not seed shop")
		return false

	var rooms_root := RegIO.load_region_rooms(PACK_ID, REALM_ID, REGION_ID)
	var rooms_v: Variant = rooms_root.get("rooms", {})
	if typeof(rooms_v) != TYPE_DICTIONARY:
		push_error("reference_refactor_smoke: region rooms missing for dialogue/shop refs")
		return false
	var rooms: Dictionary = rooms_v
	if not rooms.has("gate_room"):
		push_error("reference_refactor_smoke: gate room missing for dialogue/shop refs")
		return false
	var gate_room: Dictionary = rooms["gate_room"]
	var entities := _as_array(gate_room.get("entities", []))
	entities.append({
		"type": "trigger_volume",
		"x": 160.0,
		"y": 200.0,
		"properties": {
			"instance_id": "dialogue_shop_ref",
			"dialogue_id": OLD_DIALOGUE_ID,
			"shop_id": OLD_SHOP_ID,
		},
	})
	gate_room["entities"] = entities
	rooms["gate_room"] = gate_room
	rooms_root["rooms"] = rooms
	if not RegIO.save_region_rooms(PACK_ID, REALM_ID, REGION_ID, rooms_root):
		push_error("reference_refactor_smoke: could not seed room dialogue/shop refs")
		return false
	RegIO.flatten_to_runtime(PACK_ID)

	var triggers := PedIO.load_triggers(PACK_ID)
	var rules := _as_array(triggers.get("triggers", []))
	rules.append({
		"id": "refactor_dialogue_shop_refs",
		"name": "Refactor Dialogue Shop Refs",
		"enabled": true,
		"event": "refactor_dialogue_shop_refs",
		"conditions": [],
		"actions": [
			{"type": "start_dialogue", "id": OLD_DIALOGUE_ID},
			{"type": "start_shop", "id": OLD_SHOP_ID},
		],
	})
	triggers["triggers"] = rules
	if not PedIO.save_triggers(PACK_ID, triggers):
		push_error("reference_refactor_smoke: could not seed trigger dialogue/shop refs")
		return false
	return true


func _valid_behavior(id: String) -> Dictionary:
	return {
		"id": id,
		"name": id.capitalize(),
		"description": "Reference refactor smoke behavior.",
		"root": {
			"type": "action",
			"name": "Idle",
			"action": "idle",
			"params": {},
		},
	}


func _rename_entity_definition() -> bool:
	var data := EntIO.load_or_init(PACK_ID)
	var entries := _as_array(data.get("entities", []))
	for entry_v in entries:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		if str(entry.get("id", "")).strip_edges() == OLD_ENTITY_ID:
			entry["id"] = NEW_ENTITY_ID
			data["entities"] = entries
			return EntIO.save_entities(PACK_ID, data)
	push_error("reference_refactor_smoke: could not find entity definition '%s'" % OLD_ENTITY_ID)
	return false


func _rename_behavior_definition() -> bool:
	var data := BehIO.load_or_init(PACK_ID)
	var entries := _as_array(data.get("behaviors", []))
	for entry_v in entries:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		if str(entry.get("id", "")).strip_edges() == OLD_BEHAVIOR_ID:
			entry["id"] = NEW_BEHAVIOR_ID
			data["behaviors"] = entries
			return BehIO.save_behaviors(PACK_ID, data)
	push_error("reference_refactor_smoke: could not find behavior definition '%s'" % OLD_BEHAVIOR_ID)
	return false


func _rename_item_definition() -> bool:
	var data := PedIO.load_items(PACK_ID)
	var entries := _as_array(data.get("items", []))
	for entry_v in entries:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		if str(entry.get("id", "")).strip_edges() == OLD_ITEM_ID:
			entry["id"] = NEW_ITEM_ID
			data["items"] = entries
			return PedIO.save_items(PACK_ID, data)
	push_error("reference_refactor_smoke: could not find item definition '%s'" % OLD_ITEM_ID)
	return false


func _rename_system_definition() -> bool:
	var systems := SystemIO.load_or_init(PACK_ID)
	if not systems.has(OLD_SYSTEM_ID):
		push_error("reference_refactor_smoke: could not find system definition '%s'" % OLD_SYSTEM_ID)
		return false
	var system: Dictionary = systems[OLD_SYSTEM_ID]
	systems.erase(OLD_SYSTEM_ID)
	systems[NEW_SYSTEM_ID] = system
	return SystemIO.save(PACK_ID, systems)


func _rename_room_and_references() -> Dictionary:
	var result := {
		"ok": false,
		"changed_files": [],
		"changed_refs": 0,
		"errors": ["Room rename did not run."],
	}
	if not RegIO.rename_room(PACK_ID, REALM_ID, REGION_ID, OLD_ROOM_ID, NEW_ROOM_ID, "Arrival"):
		result["errors"] = ["Could not rename room definition."]
		return result
	result = ContentReferenceRefactor.rename_room_references(
		PACK_ID,
		REALM_ID,
		REGION_ID,
		OLD_ROOM_ID,
		REALM_ID,
		REGION_ID,
		NEW_ROOM_ID
	)
	if bool(result.get("ok", false)):
		RegIO.flatten_to_runtime(PACK_ID)
	return result


func _rename_ability_definition() -> bool:
	var data := PedIO.load_abilities(PACK_ID)
	var entries := _as_array(data.get("abilities", []))
	for entry_v in entries:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		if str(entry.get("id", "")).strip_edges() == OLD_ABILITY_ID:
			entry["id"] = NEW_ABILITY_ID
			data["abilities"] = entries
			return PedIO.save_abilities(PACK_ID, data)
	push_error("reference_refactor_smoke: could not find ability definition '%s'" % OLD_ABILITY_ID)
	return false


func _rename_projectile_definition() -> bool:
	var data := PedIO.load_projectiles(PACK_ID)
	var entries := _as_array(data.get("projectiles", []))
	for entry_v in entries:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		if str(entry.get("id", "")).strip_edges() == OLD_PROJECTILE_ID:
			entry["id"] = NEW_PROJECTILE_ID
			data["projectiles"] = entries
			return PedIO.save_projectiles(PACK_ID, data)
	push_error("reference_refactor_smoke: could not find projectile definition '%s'" % OLD_PROJECTILE_ID)
	return false


func _rename_attack_definition() -> bool:
	var data := PedIO.load_attacks(PACK_ID)
	var entries := _as_array(data.get("attacks", []))
	for entry_v in entries:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		if str(entry.get("id", "")).strip_edges() == OLD_ATTACK_ID:
			entry["id"] = NEW_ATTACK_ID
			data["attacks"] = entries
			return _write_json(PedIO.user_file(PACK_ID, "Player", "attacks.json"), data)
	push_error("reference_refactor_smoke: could not find attack definition '%s'" % OLD_ATTACK_ID)
	return false


func _rename_dialogue_definition() -> bool:
	var data := PedIO.load_dialogue(PACK_ID, OLD_DIALOGUE_ID)
	data["id"] = NEW_DIALOGUE_ID
	if not PedIO.save_dialogue(PACK_ID, NEW_DIALOGUE_ID, data):
		return false
	_remove_user_json("Dialogue", OLD_DIALOGUE_ID)
	return true


func _rename_shop_definition() -> bool:
	var data := PedIO.load_shop(PACK_ID, OLD_SHOP_ID)
	data["id"] = NEW_SHOP_ID
	if not PedIO.save_shop(PACK_ID, NEW_SHOP_ID, data):
		return false
	_remove_user_json("Shops", OLD_SHOP_ID)
	return true


func _remove_user_json(folder: String, id: String) -> void:
	var path := PedIO.user_file(PACK_ID, folder, "%s.json" % id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _write_json(path: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


func _clean_user_pack(pack_id: String) -> bool:
	var path := "user://Packs/%s" % pack_id
	if not path.begins_with("user://Packs/") or pack_id.strip_edges().is_empty() or pack_id == "." or pack_id == "..":
		push_error("reference_refactor_smoke: refusing unsafe clean path '%s'" % path)
		return false
	if not DirAccess.dir_exists_absolute(path):
		return true
	_remove_dir_recursive(path)
	return true


func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name.begins_with("."):
			continue
		var child := "%s/%s" % [path, name]
		if dir.current_is_dir():
			_remove_dir_recursive(child)
		else:
			DirAccess.remove_absolute(child)
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
