extends RefCounted

const UiContract := preload("res://Space/scripts/ui/ui_contract.gd")

# Resolves dot-path binding strings (e.g. "player.hp", "inventory.items")
# to current game values by querying PlayerInventory, the MvPlayer node,
# MvGame.room_manager, and game variables.
#
# All lookups are safe: missing nodes, unregistered autoloads, and absent
# methods return sensible zero-values so screens can render before every
# backing system is online.

const _WEAPON_NAMES := {
	0: "Beam",
	1: "Grenade Launcher",
}

const _WEAPON_ICONS := {
	0: "res://Content/demo/Beams/power.png",
	1: "res://Content/demo/Beams/power.png",
}

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
	return null


static func has_binding(path: String) -> bool:
	return UiContract.binding_has_runtime_support(path)


# ---- player.hp, player.max_hp, player.position, player.facing -----------

static func _resolve_player(parts: Array) -> Variant:
	if parts.size() < 2:
		return null
	var player: Node = _get_player()
	if player == null:
		return _player_default(parts[1])
	var key: String = parts[1]
	match key:
		"hp":
			return int(player.get("hp")) if "hp" in player else 0
		"max_hp":
			return int(player.get("max_hp")) if "max_hp" in player else 0
		"position":
			return player.get("position") if "position" in player else Vector2.ZERO
		"facing":
			# MvPlayer stores facing in _right (private), but we can read
			# the sprite flip as a proxy.
			var sprite: Node = player.get_node_or_null("Sprite2D")
			if sprite != null and "flip_h" in sprite:
				return "left" if sprite.get("flip_h") else "right"
			return "right"
		"velocity":
			return player.get("velocity") if "velocity" in player else Vector2.ZERO
		"locked":
			if player.has_method("is_locked"):
				return player.is_locked()
			return false
	return null


static func _player_default(key: String) -> Variant:
	match key:
		"hp", "max_hp":
			return 0
		"position", "velocity":
			return Vector2.ZERO
		"facing":
			return "right"
		"locked":
			return false
	return null


# ---- inventory.items, inventory.abilities, inventory.equipment ----------

static func _resolve_inventory(parts: Array) -> Variant:
	if parts.size() < 2:
		return null
	var inv: Node = _get_inventory()
	if inv == null:
		return _inventory_default(parts[1])
	var key: String = parts[1]
	match key:
		"items":
			# PlayerInventory._items is private; snapshot() exposes it.
			if inv.has_method("snapshot"):
				var snap: Dictionary = inv.snapshot()
				return snap.get("items", {})
			return {}
		"abilities":
			if inv.has_method("get_abilities"):
				return inv.get_abilities()
			return []
		"equipment":
			if inv.has_method("snapshot"):
				var snap: Dictionary = inv.snapshot()
				return snap.get("equipment", {})
			return {}
		"item_count":
			# inventory.item_count.<id> — drill one level deeper
			if parts.size() >= 3 and inv.has_method("item_count"):
				return inv.item_count(parts[2])
			return 0
		"has_ability":
			if parts.size() >= 3 and inv.has_method("has_ability"):
				return inv.has_ability(parts[2])
			return false
		"equipped_in":
			if parts.size() >= 3 and inv.has_method("equipped_in"):
				return inv.equipped_in(parts[2])
			return ""
	return _inventory_default(key)


static func _inventory_default(key: String) -> Variant:
	match key:
		"items", "equipment":
			return {}
		"abilities":
			return []
		"item_count":
			return 0
		"has_ability":
			return false
		"equipped_in":
			return ""
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
			return ""
		"type":
			if inv != null and inv.has_method("get_active_weapon_type"):
				return inv.get_active_weapon_type()
			return 0
		"ammo":
			# Ammo system not yet implemented; return -1 for "infinite".
			return -1
		"icon":
			if inv != null and inv.has_method("get_active_weapon_type"):
				var wt2: int = inv.get_active_weapon_type()
				return _WEAPON_ICONS.get(wt2, "")
			return ""
	return null


# ---- room.name, room.addr -----------------------------------------------

static func _resolve_room(parts: Array) -> Variant:
	if parts.size() < 2:
		return null
	var rm: Node = _get_room_manager()
	if rm == null:
		return _room_default(parts[1])
	var key: String = parts[1]
	match key:
		"name":
			if rm.has_method("current_room"):
				var info: Dictionary = rm.current_room()
				return str(info.get("name", ""))
			return ""
		"addr":
			if rm.has_method("current_room_addr"):
				return rm.current_room_addr()
			return ""
		"width":
			if rm.has_method("current_room"):
				var info: Dictionary = rm.current_room()
				return int(info.get("width_px", 0))
			return 0
		"height":
			if rm.has_method("current_room"):
				var info: Dictionary = rm.current_room()
				return int(info.get("height_px", 0))
			return 0
	return null


static func _room_default(key: String) -> Variant:
	match key:
		"name", "addr":
			return ""
		"width", "height":
			return 0
	return null


# ---- dialogue.speaker, dialogue.text (placeholder) ----------------------

static func _resolve_dialogue(parts: Array) -> Variant:
	if parts.size() < 2:
		return null
	var runner: Node = _get_dialogue_runner()
	var state: Dictionary = runner.current_ui_state() if runner != null and runner.has_method("current_ui_state") else {}
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
	var key: String = parts[1]
	match key:
		"items":
			if shop_ui != null and shop_ui.has_method("current_items"):
				return shop_ui.current_items()
			return []
	return null


# ---- map.rooms -----------------------------------------------------------

static func _resolve_map(parts: Array) -> Variant:
	if parts.size() < 2:
		return null
	var map_screen: Node = _get_map_screen()
	var key: String = parts[1]
	match key:
		"rooms":
			if map_screen != null and map_screen.has_method("current_map_rooms"):
				return map_screen.current_map_rooms()
			return []
	return null


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
	# PlayerInventory is an autoload — lives directly under /root.
	return tree.root.get_node_or_null("PlayerInventory")


static func _get_room_manager() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	# MvGame is an autoload; its .room_manager property holds the handle.
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


static func _warn_unknown_binding(path: String) -> void:
	var trimmed := path.strip_edges()
	if trimmed.is_empty() or _warned_unknown_bindings.has(trimmed):
		return
	_warned_unknown_bindings[trimmed] = true
	push_warning("UiBindingResolver: binding '%s' is outside the supported UI contract" % trimmed)
