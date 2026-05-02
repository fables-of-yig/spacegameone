extends SceneTree

const ContentValidator := preload("res://Space/scripts/editor/content_validator.gd")
const RegIO := preload("res://Space/scripts/editor/reg/reg_io.gd")
const EnvIO := preload("res://Space/scripts/editor/env/env_io.gd")
const SystemIO := preload("res://Space/scripts/editor/system_io.gd")
const PedIO := preload("res://Space/scripts/editor/ped/ped_io.gd")
const EntIO := preload("res://Space/scripts/editor/ent/ent_io.gd")
const BehIO := preload("res://Space/scripts/editor/beh/beh_io.gd")
const PspIO := preload("res://Space/scripts/editor/psp/psp_io.gd")

const DEFAULT_PACK_ID := "golden_path"
const ADVANCED_PACK_ID := "advanced_golden_path"
const DEMO_PACK_ID := "demo"
const REALM_ID := RegIO.DEFAULT_REALM_ID
const REGION_ID := RegIO.DEFAULT_REGION_ID
const START_ROOM := "start"
const PICKUP_ROOM := "pickup_room"
const SHOP_ROOM := "shop_room"
const GATE_ROOM := "gate_room"
const BOSS_ROOM := "boss_room"
const ARMORY_ROOM := "armory_room"
const LOWER_ROOM := "lower_vault"
const TOWER_ROOM := "signal_tower"
const RELIC_ROOM := "relic_cache"
const GAUNTLET_ROOM := "gauntlet"
const RETURN_ROOM := "return_lift"
const BLOCK_SIZE := EnvIO.BLOCK_SIZE
const ROOM_W := EnvIO.DEFAULT_ROOM_W_BLOCKS
const ROOM_H := EnvIO.DEFAULT_ROOM_H_BLOCKS
const FLOOR_BLOCK := RegIO.STARTER_SOLID_BLOCK
const SMOKE_SLOT_DEFAULT := 6


func _init() -> void:
	_run_and_quit.call_deferred(OS.get_cmdline_user_args())


func _run_and_quit(args: Array) -> void:
	var ok := await _run(args)
	quit(0 if ok else 1)


func _run(args: Array) -> bool:
	var command := "build"
	var pack_id := DEFAULT_PACK_ID
	var clean := false
	var slot := SMOKE_SLOT_DEFAULT
	if not args.is_empty() and not str(args[0]).begins_with("--"):
		command = str(args[0]).strip_edges()
	var i := 1 if not args.is_empty() and command == str(args[0]).strip_edges() else 0
	while i < args.size():
		var arg := str(args[i])
		match arg:
			"--pack":
				i += 1
				if i < args.size():
					pack_id = str(args[i]).strip_edges()
			"--clean":
				clean = true
			"--slot":
				i += 1
				if i < args.size():
					slot = int(args[i])
			_:
				push_error("golden_pack_cli: unknown arg '%s'" % arg)
				return false
		i += 1

	if pack_id.is_empty():
		push_error("golden_pack_cli: empty pack id")
		return false

	match command:
		"build":
			return _build_pack(pack_id, clean)
		"validate":
			return _validate_pack(pack_id)
		"smoke":
			if not _build_pack(pack_id, clean):
				return false
			if not _validate_pack(pack_id):
				return false
			return await _run_runtime_smoke(pack_id, slot)
		_:
			push_error("golden_pack_cli: unknown command '%s'" % command)
			return false


func _build_pack(pack_id: String, clean: bool) -> bool:
	if clean:
		if not _clean_user_pack(pack_id):
			return false
	if not MvPackLoader.create_empty_pack(pack_id, _pack_display_name(pack_id)):
		push_error("golden_pack_cli: failed to scaffold pack '%s'" % pack_id)
		return false

	if _is_advanced_pack(pack_id):
		if not _copy_advanced_demo_assets(pack_id):
			return false
		if not PspIO.apply_preset(pack_id, "adventurer_male"):
			return false
	if not _write_manifest(pack_id):
		return false
	if not _write_combat_data(pack_id):
		return false
	if not _write_progression_data(pack_id):
		return false
	if not _write_dialogue_and_shop(pack_id):
		return false
	if not _write_world(pack_id):
		return false
	if not _write_systems(pack_id):
		return false
	if not _write_triggers(pack_id):
		return false

	print("[golden_pack_cli] built pack '%s'" % pack_id)
	return true


func _write_manifest(pack_id: String) -> bool:
	var path := "user://Packs/%s/Pack.json" % pack_id
	var manifest := {
		"schema_version": "1.0",
		"pack_id": pack_id,
		"name": _pack_display_name(pack_id),
		"version": "0.4.0" if _is_advanced_pack(pack_id) else "0.3.0",
		"author": "Codex",
		"description": "Larger authored demo-content vertical slice with branching rooms, demo sprites, item drops, shops, triggers, locks, and boss flow." if _is_advanced_pack(pack_id) else "Executable golden-path pack covering space POIs, authored rooms, pickups, NPCs, shops, triggers, locked doors, enemies, and boss flow.",
		"start_system": SystemIO.STARTER_SYSTEM_ID,
		"start_ship_template": "startship",
		"start_realm": REALM_ID,
		"entry_room": RegIO.runtime_room_addr(REALM_ID, REGION_ID, START_ROOM),
	}
	return _write_json(path, manifest)


func _is_advanced_pack(pack_id: String) -> bool:
	return pack_id.strip_edges() == ADVANCED_PACK_ID


func _pack_display_name(pack_id: String) -> String:
	return "Advanced Golden Path" if _is_advanced_pack(pack_id) else "Golden Path"


func _write_progression_data(pack_id: String) -> bool:
	if not PedIO.save_abilities(pack_id, {
		"abilities": [
			{
				"id": "phase_dash",
				"name": "Phase Dash",
				"category": "movement",
				"description": "Lets the player phase through silver security gates.",
				"params": {"dash_speed": 360, "duration": 0.18},
			},
			{
				"id": "high_jump",
				"name": "High Jump Boots",
				"category": "movement",
				"description": "Jump higher for tower routes and vertical backtracking.",
				"params": {"jump_multiplier": 1.4},
			},
		],
	}):
		return false
	if not PedIO.save_items(pack_id, {
		"items": [
			{
				"id": "coin",
				"name": "Gold",
				"description": "Spendable currency.",
				"max_stack": 9999,
				"price": 1,
				"category": "currency",
				"use_effect": "add_gold",
				"use_amount": 1,
				"use_arg": "",
				"auto_use_on_gain": true,
			},
			{
				"id": "missile_launcher",
				"name": "Missile Launcher",
				"description": "Equips the launcher that maps Secondary Fire to missiles.",
				"max_stack": 1,
				"price": 0,
				"category": "equipment",
				"use_effect": "equip_item",
				"use_amount": 1,
				"use_arg": "missile_launcher",
				"auto_use_on_gain": true,
			},
			{
				"id": "missile_expansion",
				"name": "Missile Expansion",
				"description": "Increases missile capacity by 5.",
				"max_stack": 99,
				"price": 5,
				"category": "upgrade",
				"use_effect": "max_ammo_up",
				"use_amount": 5,
				"use_arg": "missile",
				"auto_use_on_gain": true,
			},
			{
				"id": "missile_pickup",
				"name": "Missile Pickup",
				"description": "Restores 3 missiles, up to current capacity.",
				"max_stack": 99,
				"price": 0,
				"category": "ammo",
				"use_effect": "add_ammo",
				"use_amount": 3,
				"use_arg": "missile",
				"auto_use_on_gain": true,
			},
			{
				"id": "energy_pickup",
				"name": "Energy Pickup",
				"description": "Restores 5 energy.",
				"max_stack": 99,
				"price": 0,
				"category": "consumable",
				"use_effect": "heal_hp",
				"use_amount": 5,
				"use_arg": "",
				"auto_use_on_gain": true,
			},
			{
				"id": "heart_container",
				"name": "Heart Container",
				"description": "Increases maximum energy by 99.",
				"max_stack": 99,
				"price": 10,
				"category": "upgrade",
				"use_effect": "max_hp_up",
				"use_amount": 99,
				"use_arg": "",
				"auto_use_on_gain": true,
			},
			{
				"id": "high_jump_boots_item",
				"name": "High Jump Boots",
				"description": "Equips boots that grant the High Jump ability.",
				"max_stack": 1,
				"price": 20,
				"category": "equipment",
				"use_effect": "equip_item",
				"use_amount": 1,
				"use_arg": "hi_jump_boots",
				"auto_use_on_gain": true,
			},
			{
				"id": "key_silver",
				"name": "Silver Key",
				"description": "Opens the phase-locked boss gate.",
				"max_stack": 1,
				"price": 25,
				"category": "key",
				"use_effect": "",
				"use_amount": 0,
				"use_arg": "",
			},
			{
				"id": "archive_relic",
				"name": "Archive Relic",
				"description": "A recovered memory core for the field archivist.",
				"max_stack": 1,
				"price": 50,
				"category": "quest",
				"use_effect": "",
				"use_amount": 0,
				"use_arg": "",
			},
			{
				"id": "boss_core",
				"name": "Boss Core",
				"description": "Proof that the sentinel was defeated.",
				"max_stack": 9,
				"price": 100,
				"category": "quest",
				"use_effect": "",
				"use_amount": 0,
				"use_arg": "",
			},
		],
	}):
		return false
	if not PedIO.save_equipment(pack_id, {
		"equipment": [
			{
				"id": "cadet_blade",
				"name": "Cadet Blade",
				"description": "Starter melee weapon wired to the default three-hit authored combo.",
				"slot": "RightHand",
				"grants_abilities": [],
				"stat_mods": {},
				"weapon": "combo_slash_1",
				"secondary_attack": "",
				"secondary_ammo_key": "",
				"secondary_ammo_cost": 1,
				"sprite_sheet": "equipment_sheet.png",
				"frame_width": 16,
				"frame_height": 16,
				"frame_index": 0,
			},
			{
				"id": "missile_launcher",
				"name": "Missile Launcher",
				"description": "Secondary-fire equipment that launches authored missiles.",
				"slot": "LeftHand",
				"grants_abilities": [],
				"stat_mods": {},
				"weapon": "",
				"secondary_attack": "missile_shot",
				"secondary_ammo_key": "missile",
				"secondary_ammo_cost": 1,
				"sprite_sheet": "equipment_sheet.png",
				"frame_width": 16,
				"frame_height": 16,
				"frame_index": 1,
			},
			{
				"id": "hi_jump_boots",
				"name": "High Jump Boots",
				"description": "Movement equipment that grants the High Jump ability.",
				"slot": "Head",
				"grants_abilities": ["high_jump"],
				"stat_mods": {},
				"weapon": "",
				"secondary_attack": "",
				"secondary_ammo_key": "",
				"secondary_ammo_cost": 1,
				"sprite_sheet": "",
				"frame_width": 16,
				"frame_height": 16,
				"frame_index": 0,
			},
		],
	}):
		return false
	if not BehIO.save_behaviors(pack_id, {
		"behaviors": [
			{
				"id": "npc_idle",
				"name": "NPC Idle",
				"description": "Passive idle behavior.",
				"root": {"type": "action", "name": "Idle", "action": "idle", "params": {}},
			},
			{
				"id": "golden_chaser",
				"name": "Golden Chaser",
				"description": "Pursues the player once nearby, otherwise idles.",
				"root": {
					"type": "selector",
					"name": "Chase or Idle",
					"params": {},
					"children": [
						{
							"type": "sequence_reactive",
							"name": "Pursue Nearby Player",
							"params": {},
							"children": [
								{"type": "condition", "name": "Player Near", "condition": "player_near", "params": {"range": 220}},
								{"type": "action", "name": "Pursue", "action": "pursue", "params": {"speed": 65}},
							],
						},
						{"type": "action", "name": "Idle", "action": "idle", "params": {}},
					],
				},
			},
		],
	}):
		return false
	if _is_advanced_pack(pack_id):
		var advanced_behaviors := MvPackLoader.read_json_dict("res://Content/%s/Entities/behaviors.json" % DEMO_PACK_ID)
		var advanced_behavior_entries_v: Variant = advanced_behaviors.get("behaviors", [])
		var advanced_behavior_entries: Array = advanced_behavior_entries_v if typeof(advanced_behavior_entries_v) == TYPE_ARRAY else []
		_upsert_by_id(advanced_behavior_entries, {
			"id": "golden_chaser",
			"name": "Golden Chaser",
			"description": "Pursues the player once nearby, otherwise idles.",
			"root": {
				"type": "selector",
				"name": "Chase or Idle",
				"params": {},
				"children": [
					{
						"type": "sequence_reactive",
						"name": "Pursue Nearby Player",
						"params": {},
						"children": [
							{"type": "condition", "name": "Player Near", "condition": "player_near", "params": {"range": 220}},
							{"type": "action", "name": "Pursue", "action": "pursue", "params": {"speed": 65}},
						],
					},
					{"type": "action", "name": "Idle", "action": "idle", "params": {}},
				],
			},
		})
		advanced_behaviors["behaviors"] = advanced_behavior_entries
		if not BehIO.save_behaviors(pack_id, advanced_behaviors):
			return false
	var patroller := _base_entity("golden_patroller", "Golden Patroller", "enemy", "golden_chaser", 24, 0, 8, 55)
	if _is_advanced_pack(pack_id):
		patroller["sprite_set"] = "Sprites/001_Enemies/robots_pixel_pack_3"
	patroller["item_drops"] = [
		{"id": "coin", "chance": 1.0, "count": 25, "pickup_entity": "pickup_coin" if _is_advanced_pack(pack_id) else "pickup"},
		{"id": "missile_pickup", "chance": 0.5, "count": 1, "pickup_entity": "pickup_missile_ammo" if _is_advanced_pack(pack_id) else "pickup"},
		{"id": "energy_pickup", "chance": 0.5, "count": 1, "pickup_entity": "pickup_energy" if _is_advanced_pack(pack_id) else "pickup"},
	]
	var shopkeeper := _base_entity("golden_shopkeeper", "Golden Shopkeeper", "interactable", "npc_idle", 1, 0, 0, 0)
	if _is_advanced_pack(pack_id):
		shopkeeper["sprite_set"] = "Sprites/trader_cyberpunk_1_shopman"
	var entities := [
		_base_entity("pickup", "Pickup", "pickup", "", 1, 0, 0, 0),
		_base_entity("trigger_volume", "Trigger Volume", "logic", "", 1, 0, 0, 0),
		shopkeeper,
		patroller,
		_boss_entity(pack_id),
	]
	entities.append_array(_pickup_entities(pack_id))
	if _is_advanced_pack(pack_id):
		entities.append_array(_advanced_entities())
	return EntIO.save_entities(pack_id, {
		"entities": entities,
	})


func _base_entity(id: String, display_name: String, category: String, behavior: String,
		hp: int, attack_damage: int, contact_damage: int, move_speed: int) -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"category": category,
		"description": "",
		"scene": "",
		"sprite_set": "",
		"behavior": behavior,
		"movement_mode": "ground",
		"hp": hp,
		"attack_damage": attack_damage,
		"contact_damage": contact_damage,
		"contact_cooldown": 0.8,
		"move_speed": move_speed,
		"projectile_damage": 0,
		"projectile_speed": 0,
		"melee_range": 28,
		"melee_attack_trigger_frame": -1,
		"projectile_range": 0,
		"projectile_attack_trigger_frame": -1,
		"placement_folder": "Golden Path",
	}


func _boss_entity(pack_id: String) -> Dictionary:
	var boss := _base_entity("golden_boss", "Golden Sentinel", "boss", "golden_chaser", 120, 12, 16, 48)
	if _is_advanced_pack(pack_id):
		boss["sprite_set"] = "Sprites/001_Enemies/basement_bosses_pack_1"
	boss["arena_lock"] = true
	boss["phases"] = [
		{"hp_pct": 0.5, "behavior": "golden_chaser"},
	]
	boss["item_drops"] = [
		{"id": "boss_core", "chance": 1.0, "count": 1},
	]
	return boss


func _advanced_entities() -> Array:
	var drone := _base_entity("rust_drone", "Rust Drone", "enemy", "patrol_basic", 18, 0, 6, 48)
	drone["sprite_set"] = "Sprites/001_Enemies/robots_pixel_pack_1"
	drone["item_drops"] = [
		{"id": "coin", "chance": 1.0, "count": 8, "pickup_entity": "pickup_coin"},
		{"id": "energy_pickup", "chance": 0.35, "count": 1, "pickup_entity": "pickup_energy"},
	]
	var shooter := _base_entity("vault_shooter", "Vault Shooter", "enemy", "ranged_attacker", 28, 0, 5, 36)
	shooter["sprite_set"] = "Sprites/001_Enemies/robots_pixel_pack_2"
	shooter["projectile_damage"] = 7
	shooter["projectile_speed"] = 170
	shooter["projectile_range"] = 220
	shooter["item_drops"] = [
		{"id": "coin", "chance": 1.0, "count": 12, "pickup_entity": "pickup_coin"},
		{"id": "missile_pickup", "chance": 0.4, "count": 1, "pickup_entity": "pickup_missile_ammo"},
	]
	var crawler := _base_entity("tower_crawler", "Tower Crawler", "enemy", "jumper", 20, 0, 7, 42)
	crawler["sprite_set"] = "Sprites/001_Enemies/ruin_enemy_4_bug"
	crawler["item_drops"] = [
		{"id": "coin", "chance": 1.0, "count": 10, "pickup_entity": "pickup_coin"},
		{"id": "energy_pickup", "chance": 0.45, "count": 1, "pickup_entity": "pickup_energy"},
	]
	var guardian := _base_entity("relic_guardian", "Relic Guardian", "enemy", "melee_aggressive", 42, 0, 10, 52)
	guardian["sprite_set"] = "Sprites/001_Enemies/robots_pixel_pack_2"
	guardian["item_drops"] = [
		{"id": "coin", "chance": 1.0, "count": 35, "pickup_entity": "pickup_coin"},
		{"id": "missile_pickup", "chance": 0.75, "count": 1, "pickup_entity": "pickup_missile_ammo"},
	]
	return [drone, shooter, crawler, guardian]


func _pickup_entities(pack_id: String) -> Array:
	var advanced := _is_advanced_pack(pack_id)
	return [
		_pickup_entity("pickup_coin", "Gold Pickup", "Sprites/Pickups/gold" if advanced else ""),
		_pickup_entity("pickup_energy", "Energy Pickup", "Sprites/Pickups/energy" if advanced else ""),
		_pickup_entity("pickup_missile_ammo", "Missile Ammo Pickup", "Sprites/Pickups/missile_ammo" if advanced else ""),
		_pickup_entity("pickup_missile_expansion", "Missile Expansion Pickup", "Sprites/Pickups/missile_expansion" if advanced else ""),
		_pickup_entity("pickup_high_jump", "High Jump Boots Pickup", "Sprites/Pickups/high_jump" if advanced else ""),
		_pickup_entity("pickup_relic", "Archive Relic Pickup", "Sprites/Pickups/relic" if advanced else ""),
		_pickup_entity("pickup_key", "Silver Key Pickup", "Sprites/Pickups/key" if advanced else ""),
	]


func _pickup_entity(id: String, display_name: String, sprite_set: String) -> Dictionary:
	var entity := _base_entity(id, display_name, "pickup", "", 1, 0, 0, 0)
	entity["sprite_set"] = sprite_set
	return entity


func _write_combat_data(pack_id: String) -> bool:
	var projectiles := PedIO.load_projectiles(pack_id)
	var projectile_entries_v: Variant = projectiles.get("projectiles", [])
	var projectile_entries: Array = projectile_entries_v if typeof(projectile_entries_v) == TYPE_ARRAY else []
	_upsert_by_id(projectile_entries, _missile_projectile_def())
	projectiles["projectiles"] = projectile_entries
	if not PedIO.save_projectiles(pack_id, projectiles):
		return false

	var attacks := PedIO.load_attacks(pack_id)
	var attack_entries_v: Variant = attacks.get("attacks", [])
	var attack_entries: Array = attack_entries_v if typeof(attack_entries_v) == TYPE_ARRAY else []
	_upsert_by_id(attack_entries, _missile_attack_def())
	attacks["attacks"] = attack_entries
	return PedIO.save_attacks(pack_id, attacks)


func _upsert_by_id(entries: Array, replacement: Dictionary) -> void:
	var replacement_id := str(replacement.get("id", "")).strip_edges()
	if replacement_id.is_empty():
		return
	for i in range(entries.size()):
		if typeof(entries[i]) != TYPE_DICTIONARY:
			continue
		if str((entries[i] as Dictionary).get("id", "")).strip_edges() == replacement_id:
			entries[i] = replacement.duplicate(true)
			return
	entries.append(replacement.duplicate(true))


func _missile_attack_def() -> Dictionary:
	return {
		"id": "missile_shot",
		"name": "Missile",
		"type": "projectile",
		"projectile_id": "missile",
		"cooldown_ticks": 20,
		"cost_mp": 0,
		"player_pose": 207,
		"hold_behavior": "single_press",
		"charge_ticks": 0,
		"charged_attack_id": "",
		"combo_next_id": "",
		"hit_frames": [],
		"hitbox_x": 0,
		"hitbox_y": 0,
		"hitbox_w": 0,
		"hitbox_h": 0,
		"damage": 0,
		"knockback": 0,
		"muzzle_x": 22,
		"muzzle_y": -8,
		"sprite_sheet": "",
		"frame_width": 32,
		"frame_height": 32,
		"frame_index": 0,
		"frame_count": 1,
		"frame_tick": 6,
	}


func _missile_projectile_def() -> Dictionary:
	return {
		"id": "missile",
		"name": "Missile",
		"sprite_sheet": "projectiles_sheet.png",
		"frame_width": 16,
		"frame_height": 8,
		"frame_index": 2,
		"frame_count": 1,
		"frame_tick": 10,
		"speed": 360,
		"gravity": 0,
		"lifetime_ticks": 150,
		"damage": 45,
		"pierces": false,
		"homing": false,
		"homing_strength": 0,
		"hitbox_w": 12,
		"hitbox_h": 6,
		"rotate_to_velocity": true,
		"trail_color": "#ffdd66",
		"explosive": true,
		"blast_radius": 40,
		"explosion_damage": 45,
		"explode_on_hit": true,
		"explode_on_timeout": false,
		"break_blocks": true,
		"bomb_jump": false,
		"bomb_jump_speed": 0,
	}


func _write_dialogue_and_shop(pack_id: String) -> bool:
	if not PedIO.save_shop(pack_id, "golden_shop", {
		"id": "golden_shop",
		"items": [
			{"stock_id": "missile_expansion_stock", "id": "missile_expansion", "name": "Missile Expansion (+5)", "price": 5, "count": 1, "use_effect": "max_ammo_up", "use_amount": 5, "use_arg": "missile", "auto_use_on_gain": true},
			{"stock_id": "heart_container_stock", "id": "heart_container", "name": "Heart Container (+99 Energy)", "price": 10, "count": 1, "use_effect": "max_hp_up", "use_amount": 99, "use_arg": "", "auto_use_on_gain": true},
			{"stock_id": "key_silver_stock", "id": "key_silver", "name": "Silver Key", "price": 25, "count": 1},
			{"stock_id": "high_jump_boots_stock", "id": "high_jump_boots_item", "name": "High Jump Boots", "price": 20, "count": 1, "use_effect": "equip_item", "use_amount": 1, "use_arg": "hi_jump_boots", "auto_use_on_gain": true},
		],
	}):
		return false
	return PedIO.save_dialogue(pack_id, "golden_shopkeep", {
		"id": "golden_shopkeep",
		"lines": [
			{
				"speaker": "Archivist",
				"text": "The gate listens for the silver key. The lower vault carries missile stock, and the tower cache still has movement gear if you can reach it.",
				"actions": [],
				"choices": [
					{"text": "Trade supplies.", "actions": [{"type": "start_shop", "id": "golden_shop"}]},
					{"text": "Leave.", "actions": []},
				],
			},
		],
	})


func _write_world(pack_id: String) -> bool:
	if _is_advanced_pack(pack_id):
		return _write_advanced_world(pack_id)

	var realm := RegIO.default_realm(REALM_ID, "Golden Path")
	realm["start_region"] = REGION_ID
	realm["regions"] = [{"id": REGION_ID, "name": "Golden Circuit", "col": 0, "row": 0, "span_w": 1, "span_h": 1}]
	if not RegIO.save_realm(pack_id, REALM_ID, realm):
		return false

	var region := RegIO.default_region(REGION_ID, "Golden Circuit")
	region["cell_blocks_x"] = ROOM_W
	region["cell_blocks_y"] = ROOM_H
	region["grid_cells_x"] = 12
	region["grid_cells_y"] = 4
	if not RegIO.save_region_meta(pack_id, REALM_ID, REGION_ID, region):
		return false

	var rooms := {
		START_ROOM: _make_room(START_ROOM, "Landing Walkway", 0, _start_room_entities(), [
			_door_zone("start_to_pickup", PICKUP_ROOM, "pickup_to_start", "right", 28, 11, 2, 3),
		]),
		PICKUP_ROOM: _make_room(PICKUP_ROOM, "Key Cache", 1, _pickup_room_entities(), [
			_door_zone("pickup_to_start", START_ROOM, "start_to_pickup", "left", 0, 11, 2, 3),
			_door_zone("pickup_to_shop", SHOP_ROOM, "shop_to_pickup", "right", 28, 11, 2, 3),
		]),
		SHOP_ROOM: _make_room(SHOP_ROOM, "Archivist Market", 2, _shop_room_entities(), [
			_door_zone("shop_to_pickup", PICKUP_ROOM, "pickup_to_shop", "left", 0, 11, 2, 3),
			_door_zone("shop_to_gate", GATE_ROOM, "gate_to_shop", "right", 28, 11, 2, 3),
		]),
		GATE_ROOM: _make_room(GATE_ROOM, "Silver Gate", 3, _gate_room_entities(), [
			_door_zone("gate_to_shop", SHOP_ROOM, "shop_to_gate", "left", 0, 11, 2, 3),
			_door_zone("gate_to_boss", BOSS_ROOM, "boss_to_gate", "right", 28, 11, 2, 3, true, "key_silver", "golden_gate_blocked"),
		]),
		BOSS_ROOM: _make_room(BOSS_ROOM, "Sentinel Arena", 4, _boss_room_entities(), [
			_door_zone("boss_to_gate", GATE_ROOM, "gate_to_boss", "left", 0, 11, 2, 3),
			_door_zone("boss_exit", "", "", "right", 28, 9, 2, 5, true, "", "golden_exit_blocked", ["exit_to_space"]),
		]),
	}

	var rooms_root := {
		"version": "3.0",
		"region_id": REGION_ID,
		"start_room": START_ROOM,
		"rooms": rooms,
	}
	return RegIO.save_region_rooms(pack_id, REALM_ID, REGION_ID, rooms_root)


func _write_advanced_world(pack_id: String) -> bool:
	var realm := RegIO.default_realm(REALM_ID, "Advanced Golden Path")
	realm["start_region"] = REGION_ID
	realm["regions"] = [{"id": REGION_ID, "name": "Sunken Archive", "col": 0, "row": 0, "span_w": 4, "span_h": 3}]
	if not RegIO.save_realm(pack_id, REALM_ID, realm):
		return false

	var region := RegIO.default_region(REGION_ID, "Sunken Archive")
	region["cell_blocks_x"] = ROOM_W
	region["cell_blocks_y"] = ROOM_H
	region["grid_cells_x"] = 12
	region["grid_cells_y"] = 8
	region["music_id"] = "dark_space"
	if not RegIO.save_region_meta(pack_id, REALM_ID, REGION_ID, region):
		return false

	var rooms := {
		START_ROOM: _advanced_room(START_ROOM, "Dropship Walkway", 0, 1, 0, _start_room_entities(), [
			_door_zone("start_to_shop", SHOP_ROOM, "shop_to_start", "right", 28, 11, 2, 3),
		]),
		SHOP_ROOM: _advanced_room(SHOP_ROOM, "Field Bazaar", 1, 1, 0, _shop_room_entities(), [
			_door_zone("shop_to_start", START_ROOM, "start_to_shop", "left", 0, 11, 2, 3),
			_door_zone("shop_to_pickup", PICKUP_ROOM, "pickup_to_shop", "right", 28, 11, 2, 3),
		]),
		PICKUP_ROOM: _advanced_room(PICKUP_ROOM, "Old Key Cache", 2, 1, 0, _pickup_room_entities(), [
			_door_zone("pickup_to_shop", SHOP_ROOM, "shop_to_pickup", "left", 0, 11, 2, 3),
			_door_zone("pickup_to_lower", LOWER_ROOM, "lower_to_pickup", "right", 28, 11, 2, 3),
		]),
		LOWER_ROOM: _advanced_room(LOWER_ROOM, "Flooded Service Vault", 3, 1, 1, _lower_room_entities(), [
			_door_zone("lower_to_pickup", PICKUP_ROOM, "pickup_to_lower", "left", 0, 11, 2, 3),
			_door_zone("lower_to_armory", ARMORY_ROOM, "armory_to_lower", "right", 28, 11, 2, 3),
		]),
		ARMORY_ROOM: _advanced_room(ARMORY_ROOM, "Missile Armory", 4, 1, 1, _armory_room_entities(), [
			_door_zone("armory_to_lower", LOWER_ROOM, "lower_to_armory", "left", 0, 11, 2, 3),
			_door_zone("armory_to_tower", TOWER_ROOM, "tower_to_armory", "right", 28, 11, 2, 3),
		]),
		TOWER_ROOM: _advanced_room(TOWER_ROOM, "Signal Tower", 5, 1, 0, _tower_room_entities(), [
			_door_zone("tower_to_armory", ARMORY_ROOM, "armory_to_tower", "left", 0, 11, 2, 3),
			_door_zone("tower_to_relic", RELIC_ROOM, "relic_to_tower", "right", 28, 8, 2, 4),
		]),
		RELIC_ROOM: _advanced_room(RELIC_ROOM, "Archive Relic Cache", 6, 1, 0, _relic_room_entities(), [
			_door_zone("relic_to_tower", TOWER_ROOM, "tower_to_relic", "left", 0, 8, 2, 4),
			_door_zone("relic_to_gate", GATE_ROOM, "gate_to_relic", "right", 28, 11, 2, 3),
		]),
		GATE_ROOM: _advanced_room(GATE_ROOM, "Silver Gate Hub", 7, 1, 0, _gate_room_entities(), [
			_door_zone("gate_to_relic", RELIC_ROOM, "relic_to_gate", "left", 0, 11, 2, 3),
			_door_zone("gate_to_boss", BOSS_ROOM, "boss_to_gate", "right", 28, 11, 2, 3, true, "key_silver", "golden_gate_blocked"),
		]),
		BOSS_ROOM: _advanced_room(BOSS_ROOM, "Sentinel Engine", 8, 1, 1, _boss_room_entities(), [
			_door_zone("boss_to_gate", GATE_ROOM, "gate_to_boss", "left", 0, 11, 2, 3),
			_door_zone("boss_exit", RETURN_ROOM, "return_to_boss", "right", 28, 9, 2, 5, true, "", "golden_exit_blocked"),
		]),
		RETURN_ROOM: _advanced_room(RETURN_ROOM, "Return Lift", 9, 1, 0, _return_room_entities(), [
			_door_zone("return_to_boss", BOSS_ROOM, "boss_exit", "left", 0, 11, 2, 3),
			_door_zone("return_to_space", "", "", "right", 28, 9, 2, 5, false, "", "", ["exit_to_space"]),
		]),
	}

	var rooms_root := {
		"version": "3.0",
		"region_id": REGION_ID,
		"start_room": START_ROOM,
		"rooms": rooms,
	}
	return RegIO.save_region_rooms(pack_id, REALM_ID, REGION_ID, rooms_root)


func _make_room(addr: String, friendly_name: String, region_col: int, entities: Array, zones: Array) -> Dictionary:
	var room := RegIO.make_room_from_mask(addr, friendly_name, [[0, 0]], region_col, 0, ROOM_W, ROOM_H, 0)
	_paint_floor(room)
	room["entities"] = entities
	room["zones"] = zones
	room["doors"] = zones.duplicate(true)
	return room


func _advanced_room(addr: String, friendly_name: String, region_col: int, region_row: int,
		tileset_id: int, entities: Array, zones: Array) -> Dictionary:
	var room := RegIO.make_room_from_mask(addr, friendly_name, [[0, 0]], region_col, region_row, ROOM_W, ROOM_H, tileset_id)
	_paint_floor(room)
	_paint_advanced_room_tiles(room, tileset_id)
	room["entities"] = entities
	room["zones"] = zones
	room["doors"] = zones.duplicate(true)
	room["parallax_enabled"] = true
	room["backdrop_image"] = ""
	room["backdrop_scroll_speed_x"] = 1.0
	room["backdrop_scroll_speed_y"] = 1.0
	return room


func _paint_floor(room: Dictionary) -> void:
	var collision_v: Variant = room.get("collision", [])
	if typeof(collision_v) != TYPE_ARRAY:
		return
	var collision: Array = collision_v
	for y in range(maxi(0, ROOM_H - 2), ROOM_H):
		if y < 0 or y >= collision.size() or typeof(collision[y]) != TYPE_ARRAY:
			continue
		var row: Array = collision[y]
		for x in range(row.size()):
			row[x] = FLOOR_BLOCK


func _paint_advanced_room_tiles(room: Dictionary, tileset_id: int) -> void:
	var layers_v: Variant = room.get("tile_layers", [])
	if typeof(layers_v) != TYPE_ARRAY or (layers_v as Array).is_empty():
		return
	var layer: Dictionary = (layers_v as Array)[0] if typeof((layers_v as Array)[0]) == TYPE_DICTIONARY else {}
	var tiles_v: Variant = layer.get("tiles", [])
	if typeof(tiles_v) != TYPE_ARRAY:
		return
	var tiles: Array = tiles_v
	for y in range(ROOM_H):
		if y < 0 or y >= tiles.size() or typeof(tiles[y]) != TYPE_ARRAY:
			continue
		var row: Array = tiles[y]
		for x in range(row.size()):
			if y >= ROOM_H - 2:
				row[x] = _tile(1 + ((x + tileset_id) % 3), tileset_id)
			elif y == ROOM_H - 5 and x % 9 >= 2 and x % 9 <= 5:
				row[x] = _tile(5 + (x % 2), tileset_id)
			elif x == 0 or x == row.size() - 1:
				row[x] = _tile(8, tileset_id)


func _tile(metatile_idx: int, tileset_id: int) -> int:
	return metatile_idx | (tileset_id << 12) | (1 << 20)


func _start_room_entities() -> Array:
	return [
		{"type": "player_spawn", "x": 80.0, "y": 208.0, "properties": {"instance_id": "player_spawn"}},
	]


func _pickup_room_entities() -> Array:
	return [
		{
			"type": "pickup_key",
			"x": 220.0,
			"y": 208.0,
			"properties": {"instance_id": "pickup_silver_key", "item_id": "key_silver", "count": 1},
		},
	]


func _shop_room_entities() -> Array:
	return [
		{
			"type": "golden_shopkeeper",
			"x": 220.0,
			"y": 208.0,
			"properties": {"instance_id": "npc_shopkeeper", "dialogue_id": "golden_shopkeep", "shop_id": "golden_shop"},
		},
	]


func _gate_room_entities() -> Array:
	return [
		{"type": "golden_patroller", "x": 260.0, "y": 208.0, "properties": {"instance_id": "gate_patroller"}},
	]


func _lower_room_entities() -> Array:
	return [
		{"type": "rust_drone", "x": 160.0, "y": 208.0, "properties": {"instance_id": "lower_drone_a"}},
		{"type": "rust_drone", "x": 320.0, "y": 208.0, "properties": {"instance_id": "lower_drone_b"}},
	]


func _armory_room_entities() -> Array:
	return [
		{"type": "pickup_missile_expansion", "x": 150.0, "y": 208.0, "properties": {"instance_id": "pickup_missile_expansion", "item_id": "missile_expansion", "count": 1}},
		{"type": "vault_shooter", "x": 320.0, "y": 208.0, "properties": {"instance_id": "armory_shooter"}},
	]


func _tower_room_entities() -> Array:
	return [
		{"type": "pickup_high_jump", "x": 120.0, "y": 112.0, "properties": {"instance_id": "pickup_high_jump_boots", "item_id": "high_jump_boots_item", "count": 1}},
		{"type": "tower_crawler", "x": 260.0, "y": 208.0, "properties": {"instance_id": "tower_crawler_a"}},
		{"type": "tower_crawler", "x": 360.0, "y": 144.0, "properties": {"instance_id": "tower_crawler_b"}},
	]


func _relic_room_entities() -> Array:
	return [
		{"type": "pickup_relic", "x": 120.0, "y": 208.0, "properties": {"instance_id": "pickup_archive_relic", "item_id": "archive_relic", "count": 1}},
		{"type": "relic_guardian", "x": 300.0, "y": 208.0, "properties": {"instance_id": "relic_guardian"}},
	]


func _boss_room_entities() -> Array:
	return [
		{
			"type": "trigger_volume",
			"x": 220.0,
			"y": 188.0,
			"properties": {"instance_id": "boss_intro_volume", "zone_id": "boss_intro", "event_name": "zone_enter", "width": 72, "height": 80, "once": true},
		},
	]


func _return_room_entities() -> Array:
	return [
		{"type": "pickup_energy", "x": 180.0, "y": 208.0, "properties": {"instance_id": "pickup_return_energy", "item_id": "energy_pickup", "count": 1}},
		{"type": "pickup_missile_ammo", "x": 220.0, "y": 208.0, "properties": {"instance_id": "pickup_return_missiles", "item_id": "missile_pickup", "count": 1}},
	]


func _door_zone(id: String, target_room: String, target_door_id: String, direction: String,
		x_blocks: float, y_blocks: float, width_blocks: float, height_blocks: float,
		locked: bool = false, required_item_id: String = "", blocked_event_name: String = "",
		tags: Array = []) -> Dictionary:
	var target := target_room
	if not target.is_empty():
		target = RegIO.runtime_room_addr(REALM_ID, REGION_ID, target_room)
	return {
		"id": id,
		"kind": "door",
		"target_room": target,
		"target_door_id": target_door_id,
		"direction": direction,
		"x_blocks": x_blocks,
		"y_blocks": y_blocks,
		"width_blocks": width_blocks,
		"height_blocks": height_blocks,
		"locked": locked,
		"required_item_id": required_item_id,
		"required_item_count": 1,
		"blocked_event_name": blocked_event_name,
		"tags": tags,
	}


func _write_systems(pack_id: String) -> bool:
	if _is_advanced_pack(pack_id):
		var advanced_systems := {
			SystemIO.STARTER_SYSTEM_ID: _system(
				"Archive Approach",
				[500, 500],
				["outer_rim"],
				[
					_planet_poi(pack_id, "Sunken Archive", "Demo-asset metroidvania slice with branch rooms and a boss return lift.", 860, 0, START_ROOM, [80.0, 208.0], "sunken_archive"),
					_event_poi("Home Beacon", "Existing event-data integration check.", 1020, 270, "home_station"),
				]
			),
			"outer_rim": _system(
				"Outer Rim",
				[860, 390],
				[SystemIO.STARTER_SYSTEM_ID],
				[
					_event_poi("Tutorial Relay", "Secondary authored system and event hook.", 900, 20, "intro_tutorial"),
				]
			),
		}
		return SystemIO.save(pack_id, advanced_systems)
	var systems := {
		SystemIO.STARTER_SYSTEM_ID: _system(
			"Golden Traverse",
			[500, 500],
			["outer_rim"],
			[
				_planet_poi(pack_id, "Golden Landing", "Primary vertical-slice landing point.", 860, 0, START_ROOM, [80.0, 208.0], "golden_landing"),
				_event_poi("Home Beacon", "Existing event-data integration check.", 1020, 270, "home_station"),
			]
		),
		"outer_rim": _system(
			"Outer Rim",
			[860, 390],
			[SystemIO.STARTER_SYSTEM_ID],
			[
				_event_poi("Tutorial Relay", "Secondary authored system and event hook.", 900, 20, "intro_tutorial"),
			]
		),
	}
	return SystemIO.save(pack_id, systems)


func _system(name: String, position: Array, connections: Array, pois: Array) -> Dictionary:
	return {
		"name": name,
		"position": position,
		"star_class": "G",
		"star_color": [1.0, 0.93, 0.68],
		"star_size": 64,
		"star_sprite": "",
		"star_anim_frames": 1,
		"star_anim_fps": 0.0,
		"star_gravity": 0,
		"background_image": "",
		"description": "Golden-path authoring fixture system.",
		"threat_level": 1,
		"faction": "independent",
		"connections": connections,
		"pois": pois,
		"spawn_triggers": [],
		"placed_npcs": [],
	}


func _planet_poi(pack_id: String, name: String, description: String, orbit_dist: float, orbit_angle: float,
		spawn_room: String, spawn_pos: Array, planet_key: String) -> Dictionary:
	return {
		"name": name,
		"type": "planet",
		"description": description,
		"event_id": "",
		"orbit_dist": orbit_dist,
		"orbit_angle": orbit_angle,
		"sprite": "",
		"visual_scale": 1.0,
		"anim_frames": 1,
		"anim_fps": 0.0,
		"gravity_radius": 0,
		"planet_data": {
			"name": name,
			"pack_id": pack_id,
			"realm_id": REALM_ID,
			"region_id": REGION_ID,
			"spawn_room": spawn_room,
			"spawn_pos": spawn_pos,
			"planet_key": planet_key,
			"sky_color": [0.35, 0.43, 0.62],
			"horizon_color": [0.72, 0.58, 0.32],
			"terrain_colors": [[0.18, 0.22, 0.26], [0.25, 0.22, 0.17], [0.09, 0.11, 0.14]],
			"roughness": 0.62,
			"turret_count": [0, 0],
			"patrol_count": [0, 0],
			"surface_pois": [],
		},
	}


func _event_poi(name: String, description: String, orbit_dist: float, orbit_angle: float, event_id: String) -> Dictionary:
	return {
		"name": name,
		"type": "station",
		"description": description,
		"event_id": event_id,
		"orbit_dist": orbit_dist,
		"orbit_angle": orbit_angle,
		"sprite": "",
		"visual_scale": 1.0,
		"anim_frames": 1,
		"anim_fps": 0.0,
		"gravity_radius": 0,
	}


func _write_triggers(pack_id: String) -> bool:
	return PedIO.save_triggers(pack_id, {
		"version": "2.0",
		"libraries": [
			{"id": "golden_path", "name": "Golden Path", "description": "End-to-end authoring fixture triggers."},
		],
		"triggers": [
			{
				"id": "golden_starting_loadout",
				"name": "Start with gold and missiles",
				"event": "player_spawn",
				"enabled": true,
				"once": true,
				"library_id": "golden_path",
				"locals": [],
				"conditions": [],
				"actions": [
					{"type": "give_item", "id": "missile_launcher", "count": 1},
					{"type": "set_var", "name": "gold", "value": 15},
					{"type": "set_var", "name": "max_ammo_missile", "value": 5},
					{"type": "set_var", "name": "ammo_missile", "value": 5},
				],
			},
			{
				"id": "golden_pickup_unlocks_gate",
				"name": "Silver key unlocks the boss route",
				"event": "pickup",
				"enabled": true,
				"once": true,
				"library_id": "golden_path",
				"locals": [],
				"conditions": [{"type": "payload_eq", "key": "item_id", "value": "key_silver"}],
				"actions": [
					{"type": "give_ability", "id": "phase_dash"},
					{"type": "set_var", "name": "has_silver_key", "value": 1},
					{"type": "set_door_locked", "id": "gate_to_boss", "locked": false},
					{"type": "fire_event", "event": "golden_gate_unlocked", "inherit_payload": true},
				],
			},
			{
				"id": "golden_gate_unlocked_tag",
				"name": "Remember unlocked gate",
				"event": "golden_gate_unlocked",
				"enabled": true,
				"library_id": "golden_path",
				"locals": [],
				"conditions": [],
				"actions": [{"type": "add_tag", "tag": "golden_gate_unlocked"}],
			},
			{
				"id": "golden_boss_intro",
				"name": "Spawn the golden sentinel",
				"event": "zone_enter",
				"enabled": true,
				"once": true,
				"library_id": "golden_path",
				"locals": [],
				"conditions": [{"type": "payload_eq", "key": "zone_id", "value": "boss_intro"}],
				"actions": [
					{"type": "camera_focus", "mode": "position", "x": 320.0, "y": 176.0, "duration": 0.0},
					{"type": "spawn_entity_at_zone", "id": "golden_boss", "zone_id": "boss_intro", "data": {"properties": {"instance_id": "golden_boss"}}},
					{"type": "camera_unlock"},
				],
			},
			{
				"id": "golden_boss_defeated",
				"name": "Boss core opens the return route",
				"event": "boss_defeated",
				"enabled": true,
				"once": true,
				"library_id": "golden_path",
				"locals": [],
				"conditions": [{"type": "payload_eq", "key": "entity_id", "value": "golden_boss"}],
				"actions": [
					{"type": "give_item", "id": "boss_core", "count": 1},
					{"type": "set_door_locked", "id": "boss_exit", "locked": false},
					{"type": "add_tag", "tag": "golden_boss_defeated"},
				],
			},
			{
				"id": "advanced_relic_reward",
				"name": "Archive relic updates world state",
				"event": "pickup",
				"enabled": true,
				"once": true,
				"library_id": "golden_path",
				"locals": [],
				"conditions": [{"type": "payload_eq", "key": "item_id", "value": "archive_relic"}],
				"actions": [
					{"type": "add_tag", "tag": "archive_relic_recovered"},
					{"type": "add_var", "name": "gold", "delta": 20},
					{"type": "fire_event", "event": "archive_relic_recovered", "inherit_payload": true},
				],
			},
		],
	})


func _validate_pack(pack_id: String) -> bool:
	var issues := ContentValidator.validate(pack_id)
	var errors := 0
	for issue_v in issues:
		if issue_v == null:
			continue
		if issue_v.severity == "error":
			errors += 1
			push_error("[golden_pack_cli] %s - %s" % [issue_v.source, issue_v.message])
	if errors > 0:
		push_error("golden_pack_cli: validation failed with %d error(s)" % errors)
		return false
	print("[golden_pack_cli] PASS validate pack='%s' issues=%d" % [pack_id, issues.size()])
	return true


func _run_runtime_smoke(pack_id: String, slot: int) -> bool:
	var pi := root.get_node_or_null("PlanetaryInterface")
	var inv := root.get_node_or_null("PlayerInventory")
	var room_state := root.get_node_or_null("MvRoomState")
	var trigger_engine := root.get_node_or_null("MvTriggerEngine")
	if pi == null or inv == null or room_state == null or trigger_engine == null:
		push_error("golden_pack_cli: required autoload missing")
		return false

	MvPackLoader.clear_runtime_state()
	pi.call("reset_runtime_state", true, true)

	var save_path := "user://saves/save_%d.json" % slot
	var save_backup := _read_text_if_exists(save_path)
	var had_save := FileAccess.file_exists(save_path)

	var space_scene := load("res://Space/scenes/main.tscn") as PackedScene
	if space_scene == null:
		push_error("golden_pack_cli: failed to load Space main scene")
		return false
	var space := space_scene.instantiate()
	root.add_child(space)
	await process_frame
	await process_frame

	paused = false
	space.set("menu_open", false)
	var main_menu: Variant = space.get("main_menu")
	if main_menu != null:
		main_menu.visible = false

	var planet_data := _golden_planet_data(pack_id)
	space.call("_on_planet_entered", planet_data)
	var mv := await _wait_for_planet_main(space, 120)
	if mv == null:
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("golden_pack_cli: MV runtime did not boot")
		return false

	var current_room := str(mv.call("get_current_room_addr")).strip_edges()
	var expected_start := RegIO.runtime_room_addr(REALM_ID, REGION_ID, START_ROOM)
	if current_room != expected_start:
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("golden_pack_cli: expected room '%s' but loaded '%s'" % [expected_start, current_room])
		return false
	if not _has_trigger_rule(trigger_engine.call("get_rules"), "golden_pickup_unlocks_gate"):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("golden_pack_cli: golden triggers were not loaded")
		return false
	if not await _run_boot_control_smoke(mv, inv):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		return false
	if not await _run_player_pickup_smoke(mv, inv, room_state):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		return false
	if not await _run_npc_interact_smoke(mv, inv):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		return false
	if not await _run_enemy_contact_smoke(mv, inv):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		return false
	if not await _run_boss_intro_zone_smoke(mv):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		return false

	trigger_engine.call("fire_event", "pickup", {"item_id": "key_silver"})
	await process_frame
	await process_frame
	if not bool(inv.call("has_ability", "phase_dash")):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("golden_pack_cli: pickup trigger did not grant phase_dash")
		return false
	if int(inv.call("get_var", "has_silver_key", 0)) != 1:
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("golden_pack_cli: pickup trigger did not set has_silver_key")
		return false
	if bool(room_state.call("get_door_locked", "gate_to_boss", true)):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("golden_pack_cli: pickup trigger did not unlock gate_to_boss")
		return false
	if not bool(trigger_engine.call("has_global_tag", "golden_gate_unlocked")):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("golden_pack_cli: gate-unlocked tag was not set")
		return false

	trigger_engine.call("fire_event", "boss_defeated", {"entity_id": "golden_boss"})
	await process_frame
	await process_frame
	if not bool(inv.call("has_item", "boss_core", 1)):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("golden_pack_cli: boss trigger did not grant boss_core")
		return false
	if bool(room_state.call("get_door_locked", "boss_exit", true)):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("golden_pack_cli: boss trigger did not unlock boss_exit")
		return false
	if not bool(trigger_engine.call("has_global_tag", "golden_boss_defeated")):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("golden_pack_cli: boss-defeated tag was not set")
		return false

	if not await _run_reentry_persistence_smoke(space, planet_data, mv, pi, inv, room_state, trigger_engine):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		return false

	_restore_save(save_path, had_save, save_backup)
	space.queue_free()
	print("[golden_pack_cli] PASS smoke pack='%s'" % pack_id)
	return true


func _golden_planet_data(pack_id: String) -> Dictionary:
	return {
		"name": "Sunken Archive" if _is_advanced_pack(pack_id) else "Golden Landing",
		"pack_id": pack_id,
		"realm_id": REALM_ID,
		"region_id": REGION_ID,
		"spawn_room": START_ROOM,
		"spawn_pos": [80.0, 208.0],
		"planet_key": "sunken_archive" if _is_advanced_pack(pack_id) else "golden_landing",
	}


func _wait_for_planet_main(space: Node, max_frames: int) -> Node:
	for _i in range(max_frames):
		var mv: Variant = space.get("planet_main_instance")
		if mv != null:
			return mv
		await process_frame
	return null


func _run_boot_control_smoke(mv: Node, inv: Node) -> bool:
	var player: Node2D = mv.get("_player")
	if player == null:
		push_error("golden_pack_cli: boot control smoke could not find player")
		return false
	for _i in range(12):
		if int(inv.call("get_var", "gold", 0)) == 15 \
				and int(inv.call("get_var", "max_ammo_missile", 0)) == 5 \
				and int(inv.call("get_var", "ammo_missile", 0)) == 5:
			break
		await process_frame
	if int(inv.call("get_var", "gold", 0)) != 15:
		push_error("golden_pack_cli: starting gold was not initialized to 15")
		return false
	if int(inv.call("get_var", "max_ammo_missile", 0)) != 5 or int(inv.call("get_var", "ammo_missile", 0)) != 5:
		push_error("golden_pack_cli: starting missile capacity/ammo was not initialized to 5")
		return false
	if str(inv.call("equipped_in", "LeftHand")) != "missile_launcher":
		push_error("golden_pack_cli: starting loadout did not equip missile_launcher")
		return false
	if player.has_method("is_locked") and bool(player.call("is_locked")):
		push_error("golden_pack_cli: player is locked immediately after boot")
		return false
	var before: Vector2 = player.global_position
	Input.action_press("move_right")
	for _i in range(12):
		await physics_frame
	Input.action_release("move_right")
	var after: Vector2 = player.global_position
	if after.x <= before.x + 1.0:
		var mv_game := root.get_node_or_null("MvGame")
		var sim_paused := false
		if mv_game != null:
			sim_paused = bool(mv_game.get("simulation_paused"))
		push_error("golden_pack_cli: player did not respond to move_right after boot (before=%s after=%s tree_paused=%s sim_paused=%s physics=%s mode=%s input=%s)" % [
			before,
			after,
			str(paused),
			str(sim_paused),
			str(player.is_physics_processing()),
			str(player.process_mode),
			str(Input.is_action_pressed("move_right")),
		])
		return false
	Input.action_press("fire_secondary")
	Input.action_press("ranged_attack")
	await physics_frame
	Input.action_release("fire_secondary")
	Input.action_release("ranged_attack")
	await physics_frame
	if int(inv.call("get_var", "ammo_missile", 0)) != 5:
		push_error("golden_pack_cli: fire_secondary toggle spent a missile")
		return false
	if not bool(player.call("is_secondary_mode_active")):
		push_error("golden_pack_cli: fire_secondary did not toggle missile mode on")
		return false
	Input.action_press("ranged_attack")
	await physics_frame
	Input.action_release("ranged_attack")
	await physics_frame
	if int(inv.call("get_var", "ammo_missile", 0)) != 4:
		push_error("golden_pack_cli: ranged_attack in missile mode did not spend one missile")
		return false
	Input.action_press("fire_secondary")
	await physics_frame
	Input.action_release("fire_secondary")
	await physics_frame
	if bool(player.call("is_secondary_mode_active")):
		push_error("golden_pack_cli: fire_secondary did not toggle missile mode off")
		return false
	inv.call("set_var", "ammo_missile", 2)
	inv.call("add_item", "missile_pickup", 1)
	if int(inv.call("get_var", "ammo_missile", 0)) != 5:
		push_error("golden_pack_cli: missile_pickup did not restore 3 missiles")
		return false
	inv.call("set_var", "ammo_missile", 4)
	inv.call("add_item", "missile_pickup", 1)
	if int(inv.call("get_var", "ammo_missile", 0)) != 5:
		push_error("golden_pack_cli: missile_pickup exceeded max missile capacity")
		return false
	var max_hp := int(player.get("max_hp"))
	var hurt_hp := maxi(max_hp - 10, 0)
	player.set("hp", hurt_hp)
	inv.call("add_item", "energy_pickup", 1)
	if int(player.get("hp")) != mini(hurt_hp + 5, max_hp):
		push_error("golden_pack_cli: energy_pickup did not restore 5 energy")
		return false
	player.set("hp", max_hp)
	inv.call("set_var", "ammo_missile", 5)
	return true


func _run_player_pickup_smoke(mv: Node, inv: Node, room_state: Node) -> bool:
	var room_manager: Node = mv.get("_room_manager")
	var player: Node = mv.get("_player")
	if room_manager == null or player == null:
		push_error("golden_pack_cli: pickup smoke missing room manager or player")
		return false
	var pickup_room := RegIO.runtime_room_addr(REALM_ID, REGION_ID, PICKUP_ROOM)
	room_manager.call("load_room", pickup_room)
	player.call("spawn_at", Vector2(220.0, 208.0))
	await physics_frame
	await physics_frame
	await process_frame
	if not bool(inv.call("has_item", "key_silver", 1)):
		push_error("golden_pack_cli: touching the key pickup did not add key_silver")
		return false
	if not bool(inv.call("has_ability", "phase_dash")):
		push_error("golden_pack_cli: touching the key pickup did not grant phase_dash")
		return false
	if bool(room_state.call("get_door_locked", "gate_to_boss", true)):
		push_error("golden_pack_cli: touching the key pickup did not unlock gate_to_boss")
		return false
	return true


func _run_npc_interact_smoke(mv: Node, inv: Node) -> bool:
	var room_manager: Node = mv.get("_room_manager")
	var player: Node = mv.get("_player")
	var runner := root.get_node_or_null("MvDialogueRunner")
	var shop_ui := root.get_node_or_null("MvShopUI")
	if room_manager == null or player == null or runner == null or shop_ui == null:
		push_error("golden_pack_cli: npc smoke missing runtime nodes")
		return false
	var shop_room := RegIO.runtime_room_addr(REALM_ID, REGION_ID, SHOP_ROOM)
	room_manager.call("load_room", shop_room)
	player.call("spawn_at", Vector2(220.0, 208.0))
	await physics_frame
	await physics_frame
	player.call("_try_interact")
	await process_frame
	var state: Dictionary = runner.call("current_ui_state")
	if str(state.get("dialogue_id", "")) != "golden_shopkeep":
		push_error("golden_pack_cli: interacting with shopkeeper did not start dialogue")
		return false
	runner.call("_on_choice_pressed", 0)
	await process_frame
	if not bool(shop_ui.get("visible")) or not bool(shop_ui.get("_active")):
		push_error("golden_pack_cli: choosing shop dialogue did not open MvShopUI")
		return false
	if int(shop_ui.get("process_mode")) != Node.PROCESS_MODE_ALWAYS:
		push_error("golden_pack_cli: MvShopUI is not PROCESS_MODE_ALWAYS")
		return false
	var authored_screen: Variant = shop_ui.get("_authored_screen")
	if authored_screen != null and int((authored_screen as Node).process_mode) != Node.PROCESS_MODE_ALWAYS:
		push_error("golden_pack_cli: authored shop screen is not PROCESS_MODE_ALWAYS")
		return false
	var mv_game := root.get_node_or_null("MvGame")
	if mv_game != null and not bool(mv_game.get("simulation_paused")):
		push_error("golden_pack_cli: MvShopUI did not keep simulation paused after dialogue handoff")
		return false
	var gold_before := int(inv.call("get_var", "gold", 0))
	var max_missiles_before := int(inv.call("get_var", "max_ammo_missile", 0))
	shop_ui.call("_on_authored_action", "buy_item", "missile_expansion_stock", "shop_vendor_items::item::0")
	await process_frame
	if int(inv.call("get_var", "max_ammo_missile", 0)) != max_missiles_before + 5:
		push_error("golden_pack_cli: authored buy_item did not increase max missiles")
		return false
	if int(inv.call("get_var", "gold", 0)) != gold_before - 5:
		push_error("golden_pack_cli: authored buy_item did not spend 5 gold")
		return false
	if not str(shop_ui.call("status_message")).begins_with("Bought"):
		push_error("golden_pack_cli: authored buy_item did not set visible shop status")
		return false
	var max_hp_before := int(player.get("max_hp"))
	shop_ui.call("_on_authored_action", "buy_item", "heart_container_stock", "shop_vendor_items::item::1")
	await process_frame
	if int(player.get("max_hp")) != max_hp_before + 99:
		push_error("golden_pack_cli: authored buy_item did not increase max hp")
		return false
	shop_ui.call("_on_authored_action", "close_screen", "", "shop_close")
	await process_frame
	if bool(shop_ui.get("visible")) or bool(shop_ui.get("_active")):
		push_error("golden_pack_cli: authored close action did not close MvShopUI")
		return false
	return true


func _run_enemy_contact_smoke(mv: Node, inv: Node) -> bool:
	var room_manager: Node = mv.get("_room_manager")
	var player: Node = mv.get("_player")
	if room_manager == null or player == null:
		push_error("golden_pack_cli: enemy contact smoke missing room manager or player")
		return false
	var gate_room := RegIO.runtime_room_addr(REALM_ID, REGION_ID, GATE_ROOM)
	room_manager.call("load_room", gate_room)
	player.call("spawn_at", Vector2(260.0, 208.0))
	var hp_before := int(player.get("hp"))
	await physics_frame
	await physics_frame
	await physics_frame
	if int(player.get("hp")) >= hp_before:
		push_error("golden_pack_cli: contact with golden_patroller did not damage player")
		return false
	var gold_before := int(inv.call("get_var", "gold", 0))
	var enemy: Variant = room_manager.call("find_entity_node", "gate_patroller")
	if enemy == null or not (enemy as Node).has_method("take_damage"):
		push_error("golden_pack_cli: could not find damageable golden_patroller")
		return false
	(enemy as Node).call("take_damage", 999, player.global_position)
	for _i in range(8):
		await physics_frame
		await process_frame
	if int(inv.call("get_var", "gold", 0)) < gold_before + 25:
		push_error("golden_pack_cli: defeating golden_patroller did not drop collectible gold")
		return false
	return true


func _run_boss_intro_zone_smoke(mv: Node) -> bool:
	var room_manager: Node = mv.get("_room_manager")
	var player: Node = mv.get("_player")
	if room_manager == null or player == null:
		push_error("golden_pack_cli: boss intro smoke missing room manager or player")
		return false
	var boss_room := RegIO.runtime_room_addr(REALM_ID, REGION_ID, BOSS_ROOM)
	room_manager.call("load_room", boss_room)
	player.call("spawn_at", Vector2(120.0, 208.0))
	await physics_frame
	player.global_position = Vector2(220.0, 188.0)
	await physics_frame
	await physics_frame
	await process_frame
	var boss: Variant = room_manager.call("find_entity_node", "golden_boss")
	if boss == null:
		push_error("golden_pack_cli: entering boss_intro zone did not spawn golden_boss")
		return false
	return true


func _run_reentry_persistence_smoke(space: Node, planet_data: Dictionary, mv: Node,
		pi: Node, inv: Node, room_state: Node, trigger_engine: Node) -> bool:
	var player: Node = mv.get("_player")
	if player == null:
		push_error("golden_pack_cli: reentry smoke missing player")
		return false
	if not bool(inv.call("equip_item_by_id", "hi_jump_boots")):
		push_error("golden_pack_cli: reentry smoke could not equip hi_jump_boots")
		return false
	inv.call("set_var", "gold", 77)
	inv.call("set_var", "max_ammo_missile", 12)
	inv.call("set_var", "ammo_missile", 9)
	player.max_hp = 198
	player.hp = 177
	var before_room := str(mv.call("get_current_room_addr")).strip_edges()
	var before_pos: Vector2 = player.position

	pi.call("begin_launch", mv)
	for _i in range(90):
		await process_frame
		if space.get("planet_main_instance") == null and not bool(space.get("on_surface")):
			break
	if space.get("planet_main_instance") != null or bool(space.get("on_surface")):
		push_error("golden_pack_cli: reentry smoke launch did not return to space")
		return false

	space.call("_on_planet_entered", planet_data)
	var mv2 := await _wait_for_planet_main(space, 120)
	if mv2 == null:
		push_error("golden_pack_cli: reentry smoke did not reland")
		return false
	var player2: Node = mv2.get("_player")
	if player2 == null:
		push_error("golden_pack_cli: reentry smoke missing restored player")
		return false
	var restored_room := str(mv2.call("get_current_room_addr")).strip_edges()
	if restored_room != before_room:
		push_error("golden_pack_cli: reentry restored room '%s' instead of '%s'" % [restored_room, before_room])
		return false
	if player2.position.distance_to(before_pos) > 2.0:
		push_error("golden_pack_cli: reentry restored position mismatch")
		return false
	if int(inv.call("get_var", "gold", 0)) != 77:
		push_error("golden_pack_cli: reentry did not restore gold")
		return false
	if int(inv.call("get_var", "max_ammo_missile", 0)) != 12 or int(inv.call("get_var", "ammo_missile", 0)) != 9:
		push_error("golden_pack_cli: reentry did not restore missile ammo vars")
		return false
	if str(inv.call("equipped_in", "Head")) != "hi_jump_boots" or not bool(inv.call("has_ability", "high_jump")):
		push_error("golden_pack_cli: reentry did not restore equipment ability")
		return false
	if not bool(inv.call("has_ability", "phase_dash")):
		push_error("golden_pack_cli: reentry did not restore trigger-granted ability")
		return false
	if not bool(inv.call("has_item", "boss_core", 1)):
		push_error("golden_pack_cli: reentry did not restore inventory items")
		return false
	if int(player2.max_hp) != 198 or int(player2.hp) != 177:
		push_error("golden_pack_cli: reentry did not restore player hp/max hp")
		return false
	if bool(room_state.call("get_door_locked", "boss_exit", true)):
		push_error("golden_pack_cli: reentry did not restore room state")
		return false
	if not bool(trigger_engine.call("has_global_tag", "golden_boss_defeated")):
		push_error("golden_pack_cli: reentry did not restore trigger tags")
		return false

	pi.call("begin_launch", mv2)
	for _i in range(90):
		await process_frame
		if space.get("planet_main_instance") == null and not bool(space.get("on_surface")):
			break
	if space.get("planet_main_instance") != null or bool(space.get("on_surface")):
		push_error("golden_pack_cli: cross-planet smoke launch did not return to space")
		return false
	var planet2: Dictionary = planet_data.duplicate(true)
	planet2["planet_key"] = "cross_planet_progression_smoke"
	planet2["name"] = "Cross Planet Progression Smoke"
	space.call("_on_planet_entered", planet2)
	var mv3 := await _wait_for_planet_main(space, 120)
	if mv3 == null:
		push_error("golden_pack_cli: cross-planet smoke did not land")
		return false
	var player3: Node = mv3.get("_player")
	if player3 == null:
		push_error("golden_pack_cli: cross-planet smoke missing player")
		return false
	if int(inv.call("get_var", "gold", 0)) != 77:
		push_error("golden_pack_cli: cross-planet did not retain gold")
		return false
	if int(inv.call("get_var", "max_ammo_missile", 0)) != 12 or int(inv.call("get_var", "ammo_missile", 0)) != 9:
		push_error("golden_pack_cli: cross-planet did not retain missile ammo vars")
		return false
	if str(inv.call("equipped_in", "Head")) != "hi_jump_boots" or not bool(inv.call("has_ability", "high_jump")):
		push_error("golden_pack_cli: cross-planet did not retain equipment ability")
		return false
	if not bool(inv.call("has_ability", "phase_dash")):
		push_error("golden_pack_cli: cross-planet did not retain trigger-granted ability")
		return false
	if int(player3.max_hp) != 198 or int(player3.hp) != 177:
		push_error("golden_pack_cli: cross-planet did not retain player hp/max hp")
		return false
	return true


func _has_trigger_rule(rules_v: Variant, rule_id: String) -> bool:
	if typeof(rules_v) != TYPE_ARRAY:
		return false
	for rule_v in rules_v:
		if typeof(rule_v) == TYPE_DICTIONARY and str((rule_v as Dictionary).get("id", "")) == rule_id:
			return true
	return false


func _copy_advanced_demo_assets(pack_id: String) -> bool:
	var sprite_sets := [
		"Sprites/trader_cyberpunk_1_shopman",
		"Sprites/001_Enemies/robots_pixel_pack_1",
		"Sprites/001_Enemies/robots_pixel_pack_2",
		"Sprites/001_Enemies/robots_pixel_pack_3",
		"Sprites/001_Enemies/ruin_enemy_4_bug",
		"Sprites/001_Enemies/basement_bosses_pack_1",
	]
	for rel in sprite_sets:
		var dst_dir := "user://Packs/%s/%s" % [pack_id, rel]
		if not _copy_demo_dir(rel, dst_dir):
			return false
		if rel.begins_with("Sprites/001_Enemies/"):
			if not _normalize_horizontal_strip_sprite_poses(dst_dir):
				return false
	for file_rel in [
		"Tilesets/tileset_00_atlas.png",
		"Tilesets/tileset_00_atlas_hi.png",
		"Tilesets/tileset_00_atlas_lo.png",
		"Tilesets/tileset_01_atlas.png",
		"Tilesets/tileset_01_atlas_hi.png",
		"Tilesets/tileset_01_atlas_lo.png",
		"Backdrops/Parallax/desert_ocean_composite.png",
		"Backdrops/Parallax/ruined_hull_bay_composite.png",
	]:
		if not _copy_demo_file(file_rel, "user://Packs/%s/%s" % [pack_id, file_rel]):
			return false
	var pickup_icons := {
		"gold": "Sprites/VFX/imported/10-magic-effects-pixel-art-pack/PNG/icons/light.png",
		"energy": "Sprites/VFX/imported/10-magic-effects-pixel-art-pack/PNG/icons/water.png",
		"missile_ammo": "Sprites/VFX/imported/10-magic-effects-pixel-art-pack/PNG/icons/comet.png",
		"missile_expansion": "Sprites/VFX/imported/10-magic-effects-pixel-art-pack/PNG/icons/tesla_ball.png",
		"high_jump": "Sprites/VFX/imported/10-magic-effects-pixel-art-pack/PNG/icons/tornado.png",
		"relic": "Sprites/VFX/imported/10-magic-effects-pixel-art-pack/PNG/icons/gypno.png",
		"key": "Sprites/VFX/imported/10-magic-effects-pixel-art-pack/PNG/icons/ice.png",
	}
	for key_v in pickup_icons.keys():
		var key := str(key_v)
		if not _copy_demo_file(str(pickup_icons[key]), "user://Packs/%s/Sprites/Pickups/%s/idle.png" % [pack_id, key]):
			return false
	return true


func _normalize_horizontal_strip_sprite_poses(sprite_dir: String) -> bool:
	var dir := DirAccess.open(sprite_dir)
	if dir == null:
		push_error("golden_pack_cli: cannot normalize missing sprite dir %s" % sprite_dir)
		return false
	var poses_path := "%s/poses.json" % sprite_dir
	var poses_root: Dictionary = {}
	if FileAccess.file_exists(poses_path):
		var file := FileAccess.open(poses_path, FileAccess.READ)
		if file == null:
			push_error("golden_pack_cli: cannot read sprite poses %s" % poses_path)
			return false
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			var parsed_dict: Dictionary = parsed
			var existing_poses: Variant = parsed_dict.get("poses", {})
			if typeof(existing_poses) == TYPE_DICTIONARY:
				poses_root = existing_poses
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if dir.current_is_dir() or name.begins_with(".") or not name.to_lower().ends_with(".png"):
			continue
		var image := Image.new()
		var image_path := "%s/%s" % [sprite_dir, name]
		if image.load(image_path) != OK:
			dir.list_dir_end()
			push_error("golden_pack_cli: cannot inspect sprite sheet %s" % image_path)
			return false
		var frame_height: float = max(1.0, float(image.get_height()))
		var calculated_frames: int = int(round(float(image.get_width()) / frame_height))
		var frame_count: int = max(1, calculated_frames)
		var pose: Dictionary = {}
		var existing_pose: Variant = poses_root.get(name, {})
		if typeof(existing_pose) == TYPE_DICTIONARY:
			pose = existing_pose
		pose["frames"] = frame_count
		pose["fps"] = int(pose.get("fps", 8))
		pose["loop_from"] = int(pose.get("loop_from", 0))
		poses_root[name] = pose
	dir.list_dir_end()
	return _write_json(poses_path, {"poses": poses_root})


func _copy_demo_dir(rel_dir: String, dst_dir: String) -> bool:
	var src_dir := "res://Content/%s/%s" % [DEMO_PACK_ID, rel_dir]
	var dir := DirAccess.open(src_dir)
	if dir == null:
		push_error("golden_pack_cli: missing demo asset dir %s" % src_dir)
		return false
	DirAccess.make_dir_recursive_absolute(dst_dir)
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name.begins_with("."):
			continue
		var src_child := "%s/%s" % [src_dir, name]
		var dst_child := "%s/%s" % [dst_dir, name]
		if dir.current_is_dir():
			if not _copy_demo_dir("%s/%s" % [rel_dir, name], dst_child):
				dir.list_dir_end()
				return false
		elif name.to_lower().ends_with(".png") or name.to_lower().ends_with(".json"):
			if not _copy_file_bytes(src_child, dst_child):
				dir.list_dir_end()
				return false
	dir.list_dir_end()
	return true


func _copy_demo_file(rel_path: String, dst_path: String) -> bool:
	return _copy_file_bytes("res://Content/%s/%s" % [DEMO_PACK_ID, rel_path], dst_path)


func _copy_file_bytes(src_path: String, dst_path: String) -> bool:
	var src := FileAccess.open(src_path, FileAccess.READ)
	if src == null:
		push_error("golden_pack_cli: cannot read asset %s" % src_path)
		return false
	DirAccess.make_dir_recursive_absolute(dst_path.get_base_dir())
	var dst := FileAccess.open(dst_path, FileAccess.WRITE)
	if dst == null:
		src.close()
		push_error("golden_pack_cli: cannot write asset %s" % dst_path)
		return false
	dst.store_buffer(src.get_buffer(src.get_length()))
	src.close()
	dst.close()
	return true


func _clean_user_pack(pack_id: String) -> bool:
	var path := "user://Packs/%s" % pack_id
	if not path.begins_with("user://Packs/") or pack_id.strip_edges().is_empty() or pack_id == "." or pack_id == "..":
		push_error("golden_pack_cli: refusing unsafe clean path '%s'" % path)
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


func _write_json(path: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("golden_pack_cli: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


func _read_text_if_exists(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _restore_save(path: String, had_save: bool, backup: String) -> void:
	if had_save:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(backup)
			file.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
