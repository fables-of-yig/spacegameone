extends RefCounted


# Resolves dot-path binding strings (e.g. "player.hp", "inventory.items")
# to current game values by querying PlayerInventory, the MvPlayer node,
# MvGame.room_manager, and game variables.
#
# All lookups are safe: missing nodes, unregistered autoloads, and absent
# methods return null so AuthoredScreenRuntime can render a visible
# diagnostic instead of silently treating missing live data as zero/empty.

const _WEAPON_NAMES := {
	0: "Beam",
	1: "Grenade Launcher",
}

const _WEAPON_ICONS := {
	0: "res://Content/demo/Beams/power.png",
	1: "res://Content/demo/Beams/power.png",
}

const QuestIO := preload("res://Space/scripts/editor/quest_io.gd")

static var _warned_unknown_bindings: Dictionary = {}


static func resolve(path: String) -> Variant:
	if not has_binding(path):
		_warn_unknown_binding(path)
		return null
	var parts := path.split(".", false)
	if parts.is_empty():
		return null
	var root: String = parts[0]
	match root:
		"player":
			return _resolve_player(parts)
		"inventory":
			return _resolve_inventory(parts)
		"game_var":
			return _resolve_game_var(parts)
		"current_weapon":
			return _resolve_weapon(parts)
		"room":
			return _resolve_room(parts)
		"dialogue":
			return _resolve_dialogue(parts)
		"shop":
			return _resolve_shop(parts)
		"map":
			return _resolve_map(parts)
		"quest":
			return _resolve_quest(parts)
	return null


static func has_binding(path: String) -> bool:
	return UiContract.binding_has_runtime_support(path)


# ---- player.hp, player.max_hp, player.position, player.facing -----------

static func _resolve_player(parts: Array) -> Variant:
	if parts.size() < 2:
		return null
	var player: Node = _get_player()
	if player == null:
		return null
	var key: String = parts[1]
	match key:
		"hp":
			return int(player.get("hp"))
		"max_hp":
			return int(player.get("max_hp"))
		"position":
			return player.get("position")
		"facing":
			var sprite: Node = player.get_node_or_null("Sprite2D")
			if sprite != null:
				return "left" if sprite.get("flip_h") else "right"
			return null
		"velocity":
			return player.get("velocity")
		"locked":
			if player.has_method("is_locked"):
				return player.is_locked()
			return null
	return null


# ---- inventory.items, inventory.abilities, inventory.equipment ----------

static func _resolve_inventory(parts: Array) -> Variant:
	if parts.size() < 2:
		return null
	var inv: Node = _get_inventory()
	if inv == null:
		return null
	var key: String = parts[1]
	match key:
		"items":
			if inv.has_method("snapshot"):
				var snap: Dictionary = inv.snapshot()
				return snap.get("items", {})
			return null
		"abilities":
			if inv.has_method("get_abilities"):
				return inv.get_abilities()
			return null
		"equipment":
			if inv.has_method("snapshot"):
				var snap: Dictionary = inv.snapshot()
				return snap.get("equipment", {})
			return null
		"item_count":
			if parts.size() >= 3 and inv.has_method("item_count"):
				return inv.item_count(parts[2])
			return null
		"has_ability":
			if parts.size() >= 3 and inv.has_method("has_ability"):
				return inv.has_ability(parts[2])
			return null
		"equipped_in":
			if parts.size() >= 3 and inv.has_method("equipped_in"):
				return inv.equipped_in(parts[2])
			return null
	return null


# ---- game_var.<name> ----------------------------------------------------

static func _resolve_game_var(parts: Array) -> Variant:
	if parts.size() < 2:
		return null
	var inv: Node = _get_inventory()
	if inv == null or not inv.has_method("get_var"):
		return null
	return inv.get_var(parts[1])


# ---- current_weapon.name, current_weapon.ammo ---------------------------

static func _resolve_weapon(parts: Array) -> Variant:
	if parts.size() < 2:
		return null
	var inv: Node = _get_inventory()
	var key: String = parts[1]
	match key:
		"name":
			if inv != null and inv.has_method("get_active_attack_id") and inv.has_method("get_attack_definition"):
				var attack_id := str(inv.get_active_attack_id())
				if not attack_id.is_empty():
					var attack_def: Dictionary = inv.get_attack_definition(attack_id)
					var attack_name := str(attack_def.get("name", "")).strip_edges()
					if not attack_name.is_empty():
						return attack_name
			if inv != null and inv.has_method("get_active_weapon_type"):
				var wt: int = inv.get_active_weapon_type()
				return _WEAPON_NAMES.get(wt, "Unknown")
			return null
		"type":
			if inv != null and inv.has_method("get_active_weapon_type"):
				return inv.get_active_weapon_type()
			return null
		"ammo":
			return null
		"icon":
			if inv != null and inv.has_method("get_active_weapon_type"):
				var wt2: int = inv.get_active_weapon_type()
				return _WEAPON_ICONS.get(wt2, "")
			return null
	return null


# ---- room.name, room.addr -----------------------------------------------

static func _resolve_room(parts: Array) -> Variant:
	if parts.size() < 2:
		return null
	var rm: Node = _get_room_manager()
	if rm == null:
		return null
	var key: String = parts[1]
	match key:
		"name":
			if rm.has_method("current_room"):
				var info: Dictionary = rm.current_room()
				return str(info.get("name", ""))
			return null
		"addr":
			if rm.has_method("current_room_addr"):
				return rm.current_room_addr()
			return null
		"width":
			if rm.has_method("current_room"):
				var info: Dictionary = rm.current_room()
				return int(info.get("width_px", 0))
			return null
		"height":
			if rm.has_method("current_room"):
				var info: Dictionary = rm.current_room()
				return int(info.get("height_px", 0))
			return null
	return null


# ---- dialogue.speaker, dialogue.text ------------------------------------

static func _resolve_dialogue(parts: Array) -> Variant:
	if parts.size() < 2:
		return null
	var runner: Node = _get_dialogue_runner()
	if runner == null or not runner.has_method("current_ui_state"):
		return null
	var state: Dictionary = runner.current_ui_state()
	var key: String = parts[1]
	match key:
		"speaker":
			return str(state.get("speaker", ""))
		"text":
			return str(state.get("text", ""))
		"full_text":
			return str(state.get("full_text", ""))
		"choices":
			return state.get("choices", [])
	return null


# ---- shop.items ----------------------------------------------------------

static func _resolve_shop(parts: Array) -> Variant:
	if parts.size() < 2:
		return null
	var shop_ui: Node = _get_shop_ui()
	if shop_ui == null:
		return null
	var key: String = parts[1]
	match key:
		"items":
			if shop_ui.has_method("current_items"):
				return shop_ui.current_items()
			return null
		"message":
			if shop_ui.has_method("status_message"):
				return shop_ui.status_message()
			return ""
	return null


# ---- map.rooms -----------------------------------------------------------

static func _resolve_map(parts: Array) -> Variant:
	if parts.size() < 2:
		return null
	var map_screen: Node = _get_map_screen()
	if map_screen == null:
		return null
	var key: String = parts[1]
	match key:
		"rooms":
			if map_screen.has_method("current_map_rooms"):
				return map_screen.current_map_rooms()
			return null
	return null


# ---- quest.active, quest.current.* --------------------------------------

static func _resolve_quest(parts: Array) -> Variant:
	if parts.size() < 2:
		return null
	var key: String = parts[1]
	match key:
		"active":
			return _quest_rows("active")
		"completed":
			return _quest_rows("complete")
		"current":
			if parts.size() < 3:
				return null
			var current := _current_quest_row()
			var subkey: String = parts[2]
			match subkey:
				"title":
					return str(current.get("title", ""))
				"stage_title":
					return str(current.get("stage_title", ""))
				"status":
					return str(current.get("status", ""))
				"objectives":
					return current.get("objectives", [])
	return null


static func _quest_rows(status_filter: String) -> Array:
	var state_root := _quest_state_root()
	var defs := _quest_definitions_by_id()
	var out: Array = []
	for quest_id_v in state_root.keys():
		var quest_id := str(quest_id_v).strip_edges()
		if quest_id.is_empty():
			continue
		var state_v: Variant = state_root.get(quest_id, {})
		if typeof(state_v) != TYPE_DICTIONARY:
			continue
		var state: Dictionary = state_v
		if str(state.get("status", "inactive")) != status_filter:
			continue
		out.append(_quest_row(quest_id, state, defs.get(quest_id, {})))
	return out


static func _current_quest_row() -> Dictionary:
	var active := _quest_rows("active")
	if active.is_empty():
		return {"title": "", "stage_title": "", "status": "", "objectives": []}
	return active[0] if typeof(active[0]) == TYPE_DICTIONARY else {}


static func _quest_row(quest_id: String, state: Dictionary, quest_def: Dictionary) -> Dictionary:
	var title := str(quest_def.get("title", quest_id)).strip_edges()
	var stage_id := str(state.get("stage_id", "")).strip_edges()
	var stage_def := _quest_stage_def(quest_def, stage_id)
	var stage_title := str(stage_def.get("title", stage_id)).strip_edges()
	var status := str(state.get("status", "inactive"))
	var row := {
		"id": quest_id,
		"title": title,
		"status": status,
		"stage_id": stage_id,
		"stage_title": stage_title,
		"label": "%s: %s" % [title, stage_title] if not stage_title.is_empty() else title,
		"objectives": _quest_objective_rows(stage_def, state),
	}
	return row


static func _quest_stage_def(quest_def: Dictionary, stage_id: String) -> Dictionary:
	var stages_v: Variant = quest_def.get("stages", [])
	if typeof(stages_v) != TYPE_ARRAY:
		return {}
	for stage_v in stages_v:
		if typeof(stage_v) != TYPE_DICTIONARY:
			continue
		var stage: Dictionary = stage_v
		if str(stage.get("id", "")).strip_edges() == stage_id:
			return stage
	return {}


static func _quest_objective_rows(stage_def: Dictionary, state: Dictionary) -> Array:
	var objectives_v: Variant = stage_def.get("objectives", [])
	if typeof(objectives_v) != TYPE_ARRAY:
		return []
	var stage_id := str(stage_def.get("id", "")).strip_edges()
	var completed_root_v: Variant = state.get("completed_objectives", {})
	var completed_root: Dictionary = completed_root_v if typeof(completed_root_v) == TYPE_DICTIONARY else {}
	var stage_completed_v: Variant = completed_root.get(stage_id, {})
	var stage_completed: Dictionary = stage_completed_v if typeof(stage_completed_v) == TYPE_DICTIONARY else {}
	var out: Array = []
	for objective_v in objectives_v:
		if typeof(objective_v) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objective_v
		var objective_id := str(objective.get("id", "")).strip_edges()
		if objective_id.is_empty():
			continue
		var label := str(objective.get("title", objective_id)).strip_edges()
		var done := bool(stage_completed.get(objective_id, false))
		out.append({
			"id": objective_id,
			"label": "%s%s" % ["Done: " if done else "", label],
			"done": done,
			"type": str(objective.get("type", "")),
		})
	return out


static func _quest_state_root() -> Dictionary:
	var engine := _get_trigger_engine()
	if engine == null or not engine.has_method("get_quest_state"):
		return {}
	var state_v: Variant = engine.get_quest_state()
	return state_v if typeof(state_v) == TYPE_DICTIONARY else {}


static func _quest_definitions_by_id() -> Dictionary:
	var pack_id := _current_pack_id()
	if pack_id.is_empty():
		return {}
	var quests_v: Variant = QuestIO.load_or_init(pack_id).get("quests", [])
	if typeof(quests_v) != TYPE_ARRAY:
		return {}
	var out: Dictionary = {}
	for quest_v in quests_v:
		if typeof(quest_v) != TYPE_DICTIONARY:
			continue
		var quest: Dictionary = quest_v
		var quest_id := str(quest.get("id", "")).strip_edges()
		if not quest_id.is_empty():
			out[quest_id] = quest
	return out


# ---- Node accessors (safe) ----------------------------------------------

static func _get_player() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group("mv_player")


static func _get_inventory() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("PlayerInventory")


static func _get_room_manager() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var mv_game: Node = tree.root.get_node_or_null("MvGame")
	if mv_game == null:
		return null
	return mv_game.get("room_manager")


static func _get_dialogue_runner() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("MvDialogueRunner")


static func _get_shop_ui() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("MvShopUI")


static func _get_map_screen() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("MvMapScreen")


static func _get_trigger_engine() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("MvTriggerEngine")


static func _current_pack_id() -> String:
	if MvPackLoader.current_pack == null:
		return ""
	return str(MvPackLoader.current_pack.pack_id).strip_edges()


static func _warn_unknown_binding(path: String) -> void:
	var trimmed := path.strip_edges()
	if trimmed.is_empty() or _warned_unknown_bindings.has(trimmed):
		return
	_warned_unknown_bindings[trimmed] = true
	push_warning("UiBindingResolver: binding '%s' is outside the supported UI contract" % trimmed)
