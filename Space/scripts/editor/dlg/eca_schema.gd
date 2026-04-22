class_name EcaSchema
extends RefCounted

# Central registry of condition/action type schemas used by the form
# builders (condition_form.gd, actions_form.gd). Each entry lists the
# fields needed to author that type, rendered as labeled inputs.
#
# Field spec: [key, label, kind] where kind is one of:
#   "string" — LineEdit
#   "int"    — LineEdit parsed as int
#   "float"  — LineEdit parsed as float
#   "bool"   — CheckBox
#
# Each entry carries a "help" string used for per-type tooltips in the
# ECA editor forms. Compound conditions (and/or/not) can be authored via
# the condition form's raw-JSON mode.

const EVENT_TYPES: Array = [
    "pickup", "interact", "item_gain", "item_loss", "item_use", "item_sell",
    "game_started",
    "player_spawn", "player_damage", "player_death",
    "door_enter", "region_enter",
    "zone_enter", "zone_exit",
    "ability_grant", "ability_revoke",
    "enemy_spawn", "enemy_defeated",
    "boss_arena_lock", "boss_arena_unlock", "boss_phase", "boss_defeated",
    "projectile_explode", "bomb_explode",
    "dialogue_choice",
    "trigger_sequence_finished",
    "space_system_enter", "space_station_destroyed", "space_poi_interact",
    "save_game", "load_game",
    "ui_button",
]

const EVENT_HELP: Dictionary = {
    "pickup": "Fires when a pickup is collected. Payload commonly includes item or pickup identifiers.",
    "interact": "Fires when the player interacts with an entity or object that emits an interaction event.",
    "item_gain": "Fires after the player inventory gains an item.",
    "item_loss": "Fires after the player inventory loses an item.",
    "item_use": "Fires when the player uses an inventory item definition.",
    "item_sell": "Fires when an item is sold through a shop flow.",
    "game_started": "Fires once after the game finishes loading the actual start room and placing the player. Use this for intro cutscenes, opening dialogue, and first-room setup.",
    "player_spawn": "Fires when the player is spawned into the starting room at boot. Older startup hook; prefer game_started for authored intro flow.",
    "player_damage": "Fires when the player takes damage.",
    "player_death": "Fires when the player dies.",
    "door_enter": "Fires when the player enters a door transition.",
    "region_enter": "Fires when a region is entered from the overworld handoff.",
    "zone_enter": "Fires when the player enters a trigger-volume zone.",
    "zone_exit": "Fires when the player leaves a trigger-volume zone.",
    "ability_grant": "Fires when an ability is granted to the player.",
    "ability_revoke": "Fires when an ability is removed from the player.",
    "enemy_spawn": "Fires when an enemy entity is spawned.",
    "enemy_defeated": "Fires when an enemy is defeated.",
    "boss_arena_lock": "Fires when a boss arena is locked.",
    "boss_arena_unlock": "Fires when a boss arena is unlocked.",
    "boss_phase": "Fires when a boss changes phase.",
    "boss_defeated": "Fires when a boss is defeated.",
    "projectile_explode": "Fires when an authored projectile explodes.",
    "bomb_explode": "Fires when a bomb-style explosion occurs.",
    "dialogue_choice": "Fires when the player chooses a dialogue option.",
    "trigger_sequence_finished": "Fires when a trigger sequence completes execution.",
    "space_system_enter": "Fires when entering a space system in the ship layer.",
    "space_station_destroyed": "Fires when a space station is destroyed.",
    "space_poi_interact": "Fires when the player interacts with a point of interest in space.",
    "save_game": "Fires after a save completes.",
    "load_game": "Fires after a save is loaded.",
    "ui_button": "Fires from authored UI buttons and includes screen, host, action, and element metadata in the payload.",
}

const CONDITION_TYPES: Array = [
    {"type": "has_item", "label": "Has Item",
     "fields": [["id", "item id", "string"], ["min_count", "min count", "int"]],
     "help": "True when the player inventory contains at least `min_count` of the given item id (defaults to 1)."},
    {"type": "has_ability", "label": "Has Ability",
     "fields": [["id", "ability id", "string"]],
     "help": "True when the player has been granted the named ability (checked against PlayerInventory.abilities)."},
    {"type": "has_tag", "label": "Payload Has Tag",
     "fields": [["tag", "tag", "string"]],
     "help": "True when the triggering payload includes the given tag (e.g. an entity firing a trigger broadcasts its tags)."},
    {"type": "entity_has_tag", "label": "Entity Has Tag",
     "fields": [["tag", "tag", "string"]],
     "help": "Alias of has_tag — reads the payload.tags array. Use when the trigger is scoped to a specific entity event."},
    {"type": "has_global_tag", "label": "Has Global Tag",
     "fields": [["tag", "tag", "string"]],
     "help": "True when the world-level tag set (set by add_tag) contains the given tag."},
    {"type": "has_flag", "label": "Has Flag",
     "fields": [["name", "flag name", "string"], ["value", "value (true/false)", "bool"]],
     "help": "True when the named boolean flag equals the given value."},
    {"type": "var_eq", "label": "Var == Value",
     "fields": [["name", "var name", "string"], ["value", "value", "int"]],
     "help": "True when the named integer var equals the given value. Vars default to 0 when unset."},
    {"type": "var_gte", "label": "Var >= Value",
     "fields": [["name", "var name", "string"], ["value", "threshold", "int"]],
     "help": "True when the named integer var is at least `value`."},
    {"type": "chance_roll", "label": "Chance Roll %",
     "fields": [["percent", "percent", "float"]],
     "help": "Roll a d100-style probability gate. True when the roll lands under the given percent."},
    {"type": "local_var_eq", "label": "Local Var == Value",
     "fields": [["name", "local name", "string"], ["value", "value", "string"]],
     "help": "True when this trigger instance's local variable equals the given value."},
    {"type": "local_var_gte", "label": "Local Var >= Value",
     "fields": [["name", "local name", "string"], ["value", "threshold", "float"]],
     "help": "True when this trigger instance's local numeric variable is at least `value`."},
    {"type": "payload_eq", "label": "Payload Key == Value",
     "fields": [["key", "payload key", "string"], ["value", "value", "string"]],
     "help": "True when the triggering payload's string field `key` equals `value` (both stringified)."},
]

const ACTION_TYPES: Array = [
    {"type": "comment", "label": "Comment",
     "fields": [["text", "text", "opt_string"]],
     "help": "Authoring note only. No runtime effect."},
    {"type": "delay", "label": "Delay",
     "fields": [["seconds", "seconds", "float"]],
     "help": "Pause this trigger's action sequence for a number of real-time seconds, WC3-style."},
    {"type": "wait_for_event", "label": "Wait For Event",
     "fields": [["event", "event name", "string"], ["key", "payload key", "opt_string"], ["value", "payload value", "opt_string"], ["timeout", "timeout", "opt_float"], ["result_local", "result local", "opt_string"]],
     "help": "Suspend this sequence until another event fires. Optionally require a payload key/value match, a timeout in seconds, and a local variable to receive true/false for success vs timeout."},
    {"type": "wait_for_move", "label": "Wait For Move",
     "fields": [["entity", "entity ref", "string"], ["timeout", "timeout", "opt_float"], ["result_local", "result local", "opt_string"]],
     "help": "Suspend the trigger sequence until the target actor finishes its current scripted move. Use `player` for the player. Optional timeout stores success/failure into a local variable when needed."},
    {"type": "wait_for_anim", "label": "Wait For Anim",
     "fields": [["entity", "entity ref", "string"], ["anim", "anim name", "opt_string"], ["timeout", "timeout", "opt_float"], ["result_local", "result local", "opt_string"]],
     "help": "Suspend the trigger sequence until the target actor finishes its current scripted animation. Leave `anim` blank to wait for whichever scripted anim is active. Optional timeout stores success/failure into a local variable when needed."},
    {"type": "wait_for_camera", "label": "Wait For Camera",
     "fields": [["timeout", "timeout", "opt_float"], ["result_local", "result local", "opt_string"]],
     "help": "Suspend the trigger sequence until the active camera pan/focus completes. Use timeout to fail open after a number of seconds and optionally store the result into a local variable."},
    {"type": "give_item", "label": "Give Item",
     "fields": [["id", "item id", "string"], ["count", "count", "int"]],
     "help": "Add `count` of the item to the player inventory."},
    {"type": "take_item", "label": "Take Item",
     "fields": [["id", "item id", "string"], ["count", "count", "int"]],
     "help": "Remove `count` of the item from the player inventory. No-op if inventory would go negative."},
    {"type": "give_ability", "label": "Give Ability",
     "fields": [["id", "ability id", "string"]],
     "help": "Grant the named ability to the player. Abilities unlock player controller moves (e.g. double_jump)."},
    {"type": "revoke_ability", "label": "Revoke Ability",
     "fields": [["id", "ability id", "string"]],
     "help": "Remove an ability from the player. Use for timed or conditional ability loss."},
    {"type": "add_tag", "label": "Add Global Tag",
     "fields": [["tag", "tag", "string"]],
     "help": "Add a tag to the world-level tag set. Readable via has_global_tag."},
    {"type": "remove_tag", "label": "Remove Global Tag",
     "fields": [["tag", "tag", "string"]],
     "help": "Remove a tag from the world-level tag set."},
    {"type": "set_flag", "label": "Set Flag",
     "fields": [["name", "flag name", "string"], ["value", "value", "bool"]],
     "help": "Set the named boolean flag to the given value."},
    {"type": "set_var", "label": "Set Var",
     "fields": [["name", "var name", "string"], ["value", "value", "int"]],
     "help": "Set the named integer var to an absolute value."},
    {"type": "add_var", "label": "Add to Var",
     "fields": [["name", "var name", "string"], ["delta", "delta", "int"]],
     "help": "Add `delta` to the named integer var. Negative deltas subtract."},
    {"type": "set_local_var", "label": "Set Local Var",
     "fields": [["name", "local name", "string"], ["value", "value", "string"]],
     "help": "Assign a value into this trigger instance's local variable store."},
    {"type": "add_local_var", "label": "Add To Local Var",
     "fields": [["name", "local name", "string"], ["delta", "delta", "float"]],
     "help": "Add a numeric delta to a local trigger variable."},
    {"type": "teleport_player", "label": "Teleport Player",
     "fields": [["room", "room addr", "opt_string"], ["x", "x px", "int"], ["y", "y px", "int"]],
     "help": "Teleport the player to (x, y) in world pixels. If `room` is set and differs from current, the room is loaded first."},
    {"type": "lock_player", "label": "Lock Player Input", "fields": [],
     "help": "Disable player input handling. Used for cutscenes and scripted sequences."},
    {"type": "unlock_player", "label": "Unlock Player Input", "fields": [],
     "help": "Re-enable player input handling after a lock_player."},
    {"type": "spawn_entity", "label": "Spawn Entity",
     "fields": [["id", "entity id", "string"], ["x", "x px", "int"], ["y", "y px", "int"]],
     "help": "Spawn an entity at the given world position. Entity id must exist in Entities.json."},
    {"type": "spawn_entity_at_zone", "label": "Spawn Entity At Zone",
     "fields": [["id", "entity id", "string"], ["zone_id", "zone id", "string"]],
     "help": "Spawn an entity at the center of a named trigger-volume zone in the current room."},
    {"type": "spawn_space_ship", "label": "Spawn Space Ship",
     "fields": [["class", "class id", "string"], ["anchor", "anchor", "string"], ["x", "x offset/world", "float"], ["y", "y offset/world", "float"], ["wormhole", "wormhole", "bool"], ["delay", "delay", "opt_float"]],
     "help": "Spawn a hostile space ship by class id. `anchor=player` treats x/y as offsets from the player, `anchor=world` uses absolute world coords, and `anchor=system` offsets from the current system star."},
    {"type": "despawn_entity", "label": "Despawn Entity",
     "fields": [["id", "entity id", "string"]],
     "help": "Despawn all entities matching the given id in the current room."},
    {"type": "move_entity_to_zone", "label": "Move Entity To Zone",
     "fields": [["entity", "entity ref", "string"], ["zone_id", "zone id", "string"], ["speed", "speed px/s", "float"]],
     "help": "Move a room actor to the named zone. Use `player` to drive the player; otherwise `entity` matches a room instance_id first, then falls back to entity id/name."},
    {"type": "play_entity_anim", "label": "Play Entity Anim",
     "fields": [["entity", "entity ref", "string"], ["anim", "anim name", "string"], ["loop", "loop", "bool"], ["speed", "speed scale", "float"]],
     "help": "Play a named authored animation on the target actor. Use `player` to drive the player pose table, or an entity instance_id for NPCs/enemies. `speed` scales playback rate."},
    {"type": "set_entity_facing", "label": "Set Entity Facing",
     "fields": [["entity", "entity ref", "string"], ["direction", "direction", "string"], ["zone_id", "zone id", "opt_string"]],
     "help": "Force facing on the target actor. direction supports `left`, `right`, `toward_zone`, or `away_from_zone`. zone_id is only used for the zone-relative modes."},
    {"type": "camera_focus", "label": "Camera Focus",
     "fields": [["mode", "mode", "string"], ["target", "target", "opt_string"], ["x", "x px", "opt_float"], ["y", "y px", "opt_float"], ["duration", "duration", "opt_float"]],
     "help": "Move camera focus to `player`, an `entity`, a `zone`, or a raw `position`. Use mode values `player`, `entity`, `zone`, or `position`. `target` is the entity ref or zone id. `duration` pans over time; 0 snaps instantly."},
    {"type": "camera_unlock", "label": "Camera Unlock", "fields": [],
     "help": "Return camera follow to the player immediately."},
    {"type": "fire_event", "label": "Fire Event",
     "fields": [["event", "event name", "string"], ["key", "payload key", "opt_string"], ["value", "payload value", "opt_string"], ["inherit_payload", "inherit payload", "bool"]],
     "help": "Dispatch another trigger event from this trigger. Optionally copy the current payload and/or add one extra key/value pair."},
    {"type": "set_trigger_enabled", "label": "Set Trigger Enabled",
     "fields": [["id", "trigger id", "string"], ["enabled", "enabled", "bool"]],
     "help": "Turn another trigger on or off at runtime, similar to SC2 trigger on/off state."},
    {"type": "start_dialogue", "label": "Start Dialogue",
     "fields": [["id", "dialogue id", "string"]],
     "help": "Open the dialogue runner on the named dialogue asset."},
    {"type": "start_shop", "label": "Open Shop",
     "fields": [["id", "shop id", "string"]],
     "help": "Open the shop UI on the named shop asset."},
    {"type": "play_sfx", "label": "Play SFX",
     "fields": [["name", "sfx name", "string"]],
     "help": "Play the named SFX through the audio manager. Name comes from the Audio manifest."},
    {"type": "save_checkpoint", "label": "Save Checkpoint",
     "fields": [["slot", "save slot", "int"]],
     "help": "Persist the current game state to the given save slot."},
    {"type": "return_to_overworld", "label": "Return To Overworld",
     "fields": [["region_id", "region id", "opt_string"], ["x", "spawn x", "opt_string"], ["y", "spawn y", "opt_string"]],
     "help": "Exit the MV room layer and reopen the current realm's atmosphere overworld. Leave fields blank to return above the current region; set region_id to snap to a specific region cell, or x/y to use an explicit overworld position."},
    {"type": "end_dialogue", "label": "End Dialogue", "fields": [],
     "help": "Close the dialogue runner if it is open."},
    {"type": "log", "label": "Log Message",
     "fields": [["message", "message", "string"]],
     "help": "Print a message to the debug log. Useful for authoring and debugging triggers."},
]


static func find_condition_schema(type_name: String) -> Dictionary:
    for entry in CONDITION_TYPES:
        if (entry as Dictionary).get("type") == type_name:
            return entry
    return {}


static func find_action_schema(type_name: String) -> Dictionary:
    for entry in ACTION_TYPES:
        if (entry as Dictionary).get("type") == type_name:
            return entry
    return {}


static func condition_type_names() -> Array:
    var out: Array = []
    for entry in CONDITION_TYPES:
        out.append(str((entry as Dictionary).get("type")))
    return out


static func action_type_names() -> Array:
    var out: Array = []
    for entry in ACTION_TYPES:
        out.append(str((entry as Dictionary).get("type")))
    return out


static func condition_labels() -> Array:
    var out: Array = []
    for entry in CONDITION_TYPES:
        out.append(str((entry as Dictionary).get("label")))
    return out


static func action_labels() -> Array:
    var out: Array = []
    for entry in ACTION_TYPES:
        out.append(str((entry as Dictionary).get("label")))
    return out


static func condition_help(type_name: String) -> String:
    var entry := find_condition_schema(type_name)
    return str(entry.get("help", "")) if not entry.is_empty() else ""


static func action_help(type_name: String) -> String:
    var entry := find_action_schema(type_name)
    return str(entry.get("help", "")) if not entry.is_empty() else ""


static func event_type_names() -> Array:
    return EVENT_TYPES.duplicate()


static func event_help(type_name: String) -> String:
    return str(EVENT_HELP.get(type_name, ""))
