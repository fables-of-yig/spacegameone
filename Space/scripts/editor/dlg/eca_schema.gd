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
    "door_enter", "door_use_attempt", "door_use_success", "door_use_blocked", "door_arrived", "region_enter",
    "zone_enter", "zone_exit",
    "ability_grant", "ability_revoke",
    "enemy_spawn", "enemy_defeated",
    "boss_arena_lock", "boss_arena_unlock", "boss_phase", "boss_defeated",
    "projectile_explode", "bomb_explode",
    "dialogue_choice",
    "quest_started", "quest_stage_changed", "quest_objective_completed", "quest_stage_completed", "quest_completed",
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
    "door_use_attempt": "Fires whenever the player tries to use a door zone before access checks are applied.",
    "door_use_success": "Fires when a door use passes enabled/lock checks and begins transitioning.",
    "door_use_blocked": "Fires when a door is disabled or locked without satisfying its requirements.",
    "door_arrived": "Fires after the destination room loads and the player is spawned from the target door.",
    "region_enter": "Fires when a region is entered from the Space-to-MV landing handoff.",
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
    "quest_started": "Fires after a trigger action starts a quest.",
    "quest_stage_changed": "Fires after a trigger action moves a quest to a new stage.",
    "quest_objective_completed": "Fires after a trigger action completes one quest objective.",
    "quest_stage_completed": "Fires after a trigger action completes one quest stage.",
    "quest_completed": "Fires after a trigger action marks a quest complete.",
    "trigger_sequence_finished": "Fires when a trigger sequence completes execution.",
    "space_system_enter": "Fires when entering a space system in the ship layer.",
    "space_station_destroyed": "Fires when a space station is destroyed.",
    "space_poi_interact": "Fires when the player interacts with a point of interest in space.",
    "save_game": "Fires after a save completes.",
    "load_game": "Fires after a save is loaded.",
    "ui_button": "Fires from authored UI buttons and includes screen, host, action, and element metadata in the payload.",
}

const EVENT_LABELS: Dictionary = {
    "pickup": "When the player picks something up",
    "interact": "When the player uses an object or talks to someone",
    "item_gain": "When the player gains an item",
    "item_loss": "When the player loses an item",
    "item_use": "When the player uses an item",
    "item_sell": "When the player sells an item",
    "game_started": "When the game starts",
    "player_spawn": "When the player appears",
    "player_damage": "When the player takes damage",
    "player_death": "When the player dies",
    "door_enter": "When the player enters a door",
    "door_use_attempt": "When the player tries a door",
    "door_use_success": "When a door opens",
    "door_use_blocked": "When a door is blocked",
    "door_arrived": "When the player arrives through a door",
    "region_enter": "When the player enters a region",
    "zone_enter": "When the player enters a zone",
    "zone_exit": "When the player leaves a zone",
    "ability_grant": "When the player gains an ability",
    "ability_revoke": "When the player loses an ability",
    "enemy_spawn": "When an enemy appears",
    "enemy_defeated": "When an enemy is defeated",
    "boss_arena_lock": "When a boss arena locks",
    "boss_arena_unlock": "When a boss arena unlocks",
    "boss_phase": "When a boss changes phase",
    "boss_defeated": "When a boss is defeated",
    "projectile_explode": "When a projectile explodes",
    "bomb_explode": "When a bomb explodes",
    "dialogue_choice": "When the player picks a dialogue choice",
    "quest_started": "When a quest starts",
    "quest_stage_changed": "When a quest changes stage",
    "quest_objective_completed": "When a quest objective completes",
    "quest_stage_completed": "When a quest stage completes",
    "quest_completed": "When a quest completes",
    "trigger_sequence_finished": "When another trigger sequence finishes",
    "space_system_enter": "When the ship enters a star system",
    "space_station_destroyed": "When a station is destroyed",
    "space_poi_interact": "When the player interacts with a space point",
    "save_game": "When the game is saved",
    "load_game": "When a save is loaded",
    "ui_button": "When a UI button is pressed",
}

const CONDITION_TYPES: Array = [
    {"type": "has_item", "label": "Player has item",
     "fields": [["id", "item id", "string"], ["min_count", "min count", "int"]],
     "help": "True when the player inventory contains at least `min_count` of the given item id (defaults to 1)."},
    {"type": "has_ability", "label": "Player has ability",
     "fields": [["id", "ability id", "string"]],
     "help": "True when the player has been granted the named ability (checked against PlayerInventory.abilities)."},
    {"type": "has_tag", "label": "Trigger has tag",
     "fields": [["tag", "tag", "string"]],
     "help": "True when the triggering payload includes the given tag (e.g. an entity firing a trigger broadcasts its tags)."},
    {"type": "entity_has_tag", "label": "Triggering entity has tag",
     "fields": [["tag", "tag", "string"]],
     "help": "Alias of has_tag — reads the payload.tags array. Use when the trigger is scoped to a specific entity event."},
    {"type": "has_global_tag", "label": "World has tag",
     "fields": [["tag", "tag", "string"]],
     "help": "True when the world-level tag set (set by add_tag) contains the given tag."},
    {"type": "has_flag", "label": "Story flag is on/off",
     "fields": [["name", "flag name", "string"], ["value", "value (true/false)", "bool"]],
     "help": "Only allow this if the named on/off story flag matches the value you choose."},
    {"type": "quest_status", "label": "Quest status is",
     "fields": [["quest_id", "quest id", "string"], ["status", "status", "string"]],
     "help": "Only allow this if a quest is inactive, active, or complete."},
    {"type": "quest_stage", "label": "Quest stage is",
     "fields": [["quest_id", "quest id", "string"], ["stage_id", "stage id", "string"]],
     "help": "Only allow this if the quest's current stage id matches."},
    {"type": "quest_objective_done", "label": "Quest objective is done",
     "fields": [["quest_id", "quest id", "string"], ["stage_id", "stage id", "string"], ["objective_id", "objective id", "string"]],
     "help": "Only allow this after a trigger action has completed the named quest objective."},
    {"type": "var_eq", "label": "Story number equals",
     "fields": [["name", "var name", "string"], ["value", "value", "int"]],
     "help": "Only allow this if the named number variable is exactly this value. Unset vars count as 0."},
    {"type": "var_gte", "label": "Story number is at least",
     "fields": [["name", "var name", "string"], ["value", "threshold", "int"]],
     "help": "Only allow this if the named number variable is at least this amount."},
    {"type": "chance_roll", "label": "Random chance",
     "fields": [["percent", "percent", "float"]],
     "help": "Roll a d100-style probability gate. True when the roll lands under the given percent."},
    {"type": "local_var_eq", "label": "This trigger's value equals",
     "fields": [["name", "local name", "string"], ["value", "value", "string"]],
     "help": "True when this trigger instance's local variable equals the given value."},
    {"type": "local_var_gte", "label": "This trigger's value is at least",
     "fields": [["name", "local name", "string"], ["value", "threshold", "float"]],
     "help": "True when this trigger instance's local numeric variable is at least `value`."},
    {"type": "payload_eq", "label": "Triggering value equals",
     "fields": [["key", "payload key", "string"], ["value", "value", "string"]],
     "help": "True when the triggering payload's string field `key` equals `value` (both stringified)."},
]

const ACTION_TYPES: Array = [
    {"type": "comment", "label": "Comment",
     "fields": [["text", "text", "opt_string"]],
     "help": "Authoring note only. No runtime effect."},
    {"type": "delay", "label": "Wait",
     "fields": [["seconds", "seconds", "float"]],
     "help": "Pause this trigger's action sequence for a number of real-time seconds, WC3-style."},
    {"type": "wait_for_event", "label": "Wait for event",
     "fields": [["event", "event name", "string"], ["key", "payload key", "opt_string"], ["value", "payload value", "opt_string"], ["timeout", "timeout", "opt_float"], ["result_local", "result local", "opt_string"]],
     "help": "Suspend this sequence until another event fires. Optionally require a payload key/value match, a timeout in seconds, and a local variable to receive true/false for success vs timeout."},
    {"type": "wait_for_move", "label": "Wait for movement",
     "fields": [["entity", "entity ref", "string"], ["timeout", "timeout", "opt_float"], ["result_local", "result local", "opt_string"]],
     "help": "Suspend the trigger sequence until the target actor finishes its current scripted move. Use `player` for the player. Optional timeout stores success/failure into a local variable when needed."},
    {"type": "wait_for_anim", "label": "Wait for animation",
     "fields": [["entity", "entity ref", "string"], ["anim", "anim name", "opt_string"], ["timeout", "timeout", "opt_float"], ["result_local", "result local", "opt_string"]],
     "help": "Suspend the trigger sequence until the target actor finishes its current scripted animation. Leave `anim` blank to wait for whichever scripted anim is active. Optional timeout stores success/failure into a local variable when needed."},
    {"type": "wait_for_camera", "label": "Wait for camera",
     "fields": [["timeout", "timeout", "opt_float"], ["result_local", "result local", "opt_string"]],
     "help": "Suspend the trigger sequence until the active camera pan/focus completes. Use timeout to fail open after a number of seconds and optionally store the result into a local variable."},
    {"type": "wait_for_dialogue", "label": "Wait for conversation",
     "fields": [["timeout", "timeout", "opt_float"], ["result_local", "result local", "opt_string"]],
     "help": "Suspend the trigger sequence until the active dialogue closes. Optional timeout lets the sequence fail open and store the success result in a local variable."},
    {"type": "give_item", "label": "Give player item",
     "fields": [["id", "item id", "string"], ["count", "count", "int"]],
     "help": "Add `count` of the item to the player inventory."},
    {"type": "take_item", "label": "Take player item",
     "fields": [["id", "item id", "string"], ["count", "count", "int"]],
     "help": "Remove `count` of the item from the player inventory. No-op if inventory would go negative."},
    {"type": "give_ability", "label": "Give player ability",
     "fields": [["id", "ability id", "string"]],
     "help": "Grant the named ability to the player. Abilities unlock player controller moves (e.g. double_jump)."},
    {"type": "revoke_ability", "label": "Remove player ability",
     "fields": [["id", "ability id", "string"]],
     "help": "Remove an ability from the player. Use for timed or conditional ability loss."},
    {"type": "add_tag", "label": "Add world tag",
     "fields": [["tag", "tag", "string"]],
     "help": "Add a tag to the world-level tag set. Readable via has_global_tag."},
    {"type": "remove_tag", "label": "Remove world tag",
     "fields": [["tag", "tag", "string"]],
     "help": "Remove a tag from the world-level tag set."},
    {"type": "set_flag", "label": "Turn story flag on/off",
     "fields": [["name", "flag name", "string"], ["value", "value", "bool"]],
     "help": "Turn a named story flag on or off. Good for marking progress like met_mayor = true."},
    {"type": "quest_start", "label": "Start quest",
     "fields": [["quest_id", "quest id", "string"], ["stage_id", "stage id", "opt_string"]],
     "help": "Mark a quest active. Optionally set its starting stage."},
    {"type": "quest_set_stage", "label": "Set quest stage",
     "fields": [["quest_id", "quest id", "string"], ["stage_id", "stage id", "string"]],
     "help": "Move an active quest to a specific stage."},
    {"type": "quest_complete_objective", "label": "Complete quest objective",
     "fields": [["quest_id", "quest id", "string"], ["stage_id", "stage id", "opt_string"], ["objective_id", "objective id", "string"]],
     "help": "Mark one objective complete. Leave stage blank to use the quest's current stage."},
    {"type": "quest_complete_stage", "label": "Complete quest stage",
     "fields": [["quest_id", "quest id", "string"], ["stage_id", "stage id", "opt_string"]],
     "help": "Mark a quest stage complete. Leave stage blank to use the quest's current stage."},
    {"type": "quest_complete", "label": "Complete quest",
     "fields": [["quest_id", "quest id", "string"]],
     "help": "Mark the quest complete."},
    {"type": "set_var", "label": "Set story number",
     "fields": [["name", "var name", "string"], ["value", "value", "int"]],
     "help": "Set a named number variable to an exact value."},
    {"type": "add_var", "label": "Change story number",
     "fields": [["name", "var name", "string"], ["delta", "delta", "int"]],
     "help": "Increase or decrease a named number variable. Use a negative number to subtract."},
    {"type": "set_local_var", "label": "Remember value in this trigger",
     "fields": [["name", "local name", "string"], ["value", "value", "string"]],
     "help": "Assign a value into this trigger instance's local variable store."},
    {"type": "add_local_var", "label": "Change this trigger's value",
     "fields": [["name", "local name", "string"], ["delta", "delta", "float"]],
     "help": "Add a numeric delta to a local trigger variable."},
    {"type": "teleport_player", "label": "Move player instantly",
     "fields": [["room", "room addr", "opt_string"], ["x", "x px", "int"], ["y", "y px", "int"]],
     "help": "Teleport the player to (x, y) in world pixels. If `room` is set and differs from current, the room is loaded first."},
    {"type": "lock_player", "label": "Pause player control", "fields": [],
     "help": "Disable player input handling. Used for cutscenes and scripted sequences."},
    {"type": "unlock_player", "label": "Return player control", "fields": [],
     "help": "Re-enable player input handling after a lock_player."},
    {"type": "spawn_player", "label": "Place player",
     "fields": [["room", "room addr", "opt_string"], ["zone_id", "zone id", "opt_string"], ["entry_direction", "entry direction", "opt_string"], ["facing", "facing", "opt_string"], ["x", "x px", "opt_string"], ["y", "y px", "opt_string"], ["emit_event", "emit event", "bool"]],
     "help": "Spawn or respawn the player. Use room plus zone_id for authored door/entry placement, or x/y for an explicit pixel position. entry_direction and facing are optional overrides."},
    {"type": "spawn_entity", "label": "Create entity",
     "fields": [["id", "entity id", "string"], ["x", "x px", "int"], ["y", "y px", "int"]],
     "help": "Spawn an entity at the given world position. Entity id must exist in Entities.json."},
    {"type": "spawn_entity_at_zone", "label": "Create entity at zone",
     "fields": [["id", "entity id", "string"], ["zone_id", "zone id", "string"]],
     "help": "Spawn an entity at the center of a named trigger-volume zone in the current room."},
    {"type": "spawn_space_ship", "label": "Spawn Space Ship",
     "fields": [["class", "class id", "string"], ["anchor", "anchor", "string"], ["x", "x offset/world", "float"], ["y", "y offset/world", "float"], ["wormhole", "wormhole", "bool"], ["delay", "delay", "opt_float"]],
     "help": "Spawn a hostile space ship by class id. `anchor=player` treats x/y as offsets from the player, `anchor=world` uses absolute world coords, and `anchor=system` offsets from the current system star."},
    {"type": "despawn_entity", "label": "Remove entity",
     "fields": [["id", "entity id", "string"]],
     "help": "Despawn all entities matching the given id in the current room."},
    {"type": "move_entity_to_zone", "label": "Move actor to zone",
     "fields": [["entity", "entity ref", "string"], ["zone_id", "zone id", "string"], ["speed", "speed px/s", "float"]],
     "help": "Move a room actor to the named zone. Use `player` to drive the player; otherwise `entity` matches a room instance_id first, then falls back to entity id/name."},
    {"type": "play_entity_anim", "label": "Play actor animation",
     "fields": [["entity", "entity ref", "string"], ["anim", "anim name", "string"], ["loop", "loop", "bool"], ["speed", "speed scale", "float"]],
     "help": "Play a named authored animation on the target actor. Use `player` to drive the player pose table, or an entity instance_id for NPCs/enemies. `speed` scales playback rate."},
    {"type": "set_entity_facing", "label": "Turn actor",
     "fields": [["entity", "entity ref", "string"], ["direction", "direction", "string"], ["zone_id", "zone id", "opt_string"]],
     "help": "Force facing on the target actor. direction supports `left`, `right`, `toward_zone`, or `away_from_zone`. zone_id is only used for the zone-relative modes."},
    {"type": "camera_focus", "label": "Move camera",
     "fields": [["mode", "mode", "string"], ["target", "target", "opt_string"], ["x", "x px", "opt_float"], ["y", "y px", "opt_float"], ["duration", "duration", "opt_float"], ["speed", "speed px/s", "opt_float"]],
     "help": "Move camera focus to `player`, an `entity`, a `zone`, or a raw `position`. Use mode values `player`, `entity`, `zone`, or `position`. `target` is the entity ref or zone id. `duration` pans over time; 0 snaps instantly. If `speed` is set above 0, it overrides duration and pans based on world distance."},
    {"type": "camera_unlock", "label": "Return camera to player", "fields": [],
     "help": "Return camera follow to the player immediately."},
    {"type": "set_room_weather", "label": "Set Room Weather",
     "fields": [["room", "room addr", "opt_string"], ["preset", "preset", "string"], ["color", "color html", "opt_string"], ["intensity", "intensity", "opt_float"], ["speed", "speed", "opt_float"]],
     "help": "Apply a simple room weather overlay. preset supports `none`, `rain`, or `snow`. Leave `room` blank for the current room. `color` accepts an HTML color like cfe8ffff."},
    {"type": "fire_event", "label": "Start another event",
     "fields": [["event", "event name", "string"], ["key", "payload key", "opt_string"], ["value", "payload value", "opt_string"], ["inherit_payload", "inherit payload", "bool"]],
     "help": "Dispatch another trigger event from this trigger. Optionally copy the current payload and/or add one extra key/value pair."},
    {"type": "set_trigger_enabled", "label": "Enable or disable trigger",
     "fields": [["id", "trigger id", "string"], ["enabled", "enabled", "bool"]],
     "help": "Turn another trigger on or off at runtime, similar to SC2 trigger on/off state."},
    {"type": "set_door_enabled", "label": "Set Door Enabled",
     "fields": [["id", "door id", "string"], ["enabled", "enabled", "bool"]],
     "help": "Toggle a door's enabled state by door id. Disabled doors always fail before lock checks."},
    {"type": "set_door_locked", "label": "Set Door Locked",
     "fields": [["id", "door id", "string"], ["locked", "locked", "bool"]],
     "help": "Toggle a door's locked state by door id. Locked doors require their authored access requirements to pass."},
    {"type": "start_dialogue", "label": "Start conversation",
     "fields": [["id", "dialogue id", "string"]],
     "help": "Immediately open another conversation by its dialogue id."},
    {"type": "start_shop", "label": "Open shop",
     "fields": [["id", "shop id", "string"]],
     "help": "Open the shop UI on the named shop asset."},
    {"type": "play_sfx", "label": "Play sound",
     "fields": [["name", "sfx name", "string"]],
     "help": "Play a short sound effect by name."},
    {"type": "save_checkpoint", "label": "Save Checkpoint",
     "fields": [["slot", "save slot", "int"]],
     "help": "Persist the current game state to the given save slot."},
    {"type": "return_to_space", "label": "Return To Space", "fields": [],
     "help": "Exit the MV room layer, snapshot the planet state, and return to the ship's orbit position."},
    {"type": "end_dialogue", "label": "End conversation", "fields": [],
     "help": "Close the conversation window right away."},
    {"type": "log", "label": "Write debug message",
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


static func event_label(type_name: String) -> String:
    var clean := str(type_name).strip_edges()
    if EVENT_LABELS.has(clean):
        return str(EVENT_LABELS[clean])
    return _title_from_id(clean)


static func event_option_labels() -> Array:
    var out: Array = []
    for event_name in EVENT_TYPES:
        out.append(event_label(str(event_name)))
    return out


static func condition_summary(condition: Dictionary) -> String:
    var type_name := str(condition.get("type", "")).strip_edges()
    match type_name:
        "has_item":
            return "Player has at least %d %s" % [
                int(condition.get("min_count", 1)),
                _title_from_id(str(condition.get("id", "item"))),
            ]
        "has_ability":
            return "Player has ability %s" % _title_from_id(str(condition.get("id", "ability")))
        "has_tag":
            return "Trigger includes tag %s" % _quoted(condition.get("tag", ""))
        "entity_has_tag":
            return "Triggering entity has tag %s" % _quoted(condition.get("tag", ""))
        "has_global_tag":
            return "World has tag %s" % _quoted(condition.get("tag", ""))
        "has_flag":
            return "Story flag %s is %s" % [
                _quoted(condition.get("name", "")),
                "on" if bool(condition.get("value", true)) else "off",
            ]
        "quest_status":
            return "Quest %s status is %s" % [
                _title_from_id(str(condition.get("quest_id", "quest"))),
                str(condition.get("status", "")),
            ]
        "quest_stage":
            return "Quest %s is on stage %s" % [
                _title_from_id(str(condition.get("quest_id", "quest"))),
                _quoted(condition.get("stage_id", "")),
            ]
        "quest_objective_done":
            return "Quest %s objective %s is done" % [
                _title_from_id(str(condition.get("quest_id", "quest"))),
                _quoted(condition.get("objective_id", "")),
            ]
        "var_eq":
            return "Story number %s is %s" % [
                _quoted(condition.get("name", "")),
                str(condition.get("value", 0)),
            ]
        "var_gte":
            return "Story number %s is at least %s" % [
                _quoted(condition.get("name", "")),
                str(condition.get("value", 0)),
            ]
        "chance_roll":
            return "Random chance succeeds %s%% of the time" % str(condition.get("percent", 0))
        "local_var_eq":
            return "This trigger's %s is %s" % [
                _quoted(condition.get("name", "")),
                _quoted(condition.get("value", "")),
            ]
        "local_var_gte":
            return "This trigger's %s is at least %s" % [
                _quoted(condition.get("name", "")),
                str(condition.get("value", 0)),
            ]
        "payload_eq":
            return "Triggering %s is %s" % [
                _title_from_id(str(condition.get("key", "value"))).to_lower(),
                _quoted(condition.get("value", "")),
            ]
        _:
            var schema := find_condition_schema(type_name)
            if not schema.is_empty():
                return str(schema.get("label", type_name))
            return _title_from_id(type_name) if not type_name.is_empty() else "No requirement"


static func action_summary(action: Dictionary) -> String:
    var type_name := str(action.get("type", "")).strip_edges()
    match type_name:
        "comment":
            return "Note: %s" % str(action.get("text", "")).strip_edges()
        "delay":
            return "Wait %s seconds" % _num(action.get("seconds", 0))
        "wait_for_event":
            return "Wait until %s" % event_label(str(action.get("event", "")))
        "wait_for_move":
            return "Wait for %s to finish moving" % _actor(action.get("entity", "actor"))
        "wait_for_anim":
            return "Wait for %s to finish animation %s" % [
                _actor(action.get("entity", "actor")),
                _quoted(action.get("anim", "current")),
            ]
        "wait_for_camera":
            return "Wait for the camera move to finish"
        "wait_for_dialogue":
            return "Wait for the conversation to close"
        "give_item":
            return "Give player %d %s" % [
                int(action.get("count", 1)),
                _title_from_id(str(action.get("id", "item"))),
            ]
        "take_item":
            return "Take %d %s from player" % [
                int(action.get("count", 1)),
                _title_from_id(str(action.get("id", "item"))),
            ]
        "give_ability":
            return "Give player ability %s" % _title_from_id(str(action.get("id", "ability")))
        "revoke_ability":
            return "Remove player ability %s" % _title_from_id(str(action.get("id", "ability")))
        "add_tag":
            return "Add world tag %s" % _quoted(action.get("tag", ""))
        "remove_tag":
            return "Remove world tag %s" % _quoted(action.get("tag", ""))
        "set_flag":
            return "Turn story flag %s %s" % [
                _quoted(action.get("name", "")),
                "on" if bool(action.get("value", true)) else "off",
            ]
        "quest_start":
            return "Start quest %s" % _title_from_id(str(action.get("quest_id", "quest")))
        "quest_set_stage":
            return "Set quest %s to stage %s" % [
                _title_from_id(str(action.get("quest_id", "quest"))),
                _quoted(action.get("stage_id", "")),
            ]
        "quest_complete_objective":
            return "Complete quest %s objective %s" % [
                _title_from_id(str(action.get("quest_id", "quest"))),
                _quoted(action.get("objective_id", "")),
            ]
        "quest_complete_stage":
            return "Complete quest %s stage %s" % [
                _title_from_id(str(action.get("quest_id", "quest"))),
                _quoted(action.get("stage_id", "current")),
            ]
        "quest_complete":
            return "Complete quest %s" % _title_from_id(str(action.get("quest_id", "quest")))
        "set_var":
            return "Set story number %s to %s" % [
                _quoted(action.get("name", "")),
                str(action.get("value", 0)),
            ]
        "add_var":
            return "Change story number %s by %s" % [
                _quoted(action.get("name", "")),
                str(action.get("delta", 0)),
            ]
        "set_local_var":
            return "Remember %s as %s for this trigger" % [
                _quoted(action.get("name", "")),
                _quoted(action.get("value", "")),
            ]
        "add_local_var":
            return "Change this trigger's %s by %s" % [
                _quoted(action.get("name", "")),
                str(action.get("delta", 0)),
            ]
        "teleport_player":
            return "Move player to %s at %s, %s" % [
                str(action.get("room", "current room")),
                str(action.get("x", 0)),
                str(action.get("y", 0)),
            ]
        "lock_player":
            return "Pause player control"
        "unlock_player":
            return "Give control back to the player"
        "spawn_player":
            return "Place the player at %s" % str(action.get("zone_id", action.get("room", "the start point")))
        "spawn_entity":
            return "Create %s at %s, %s" % [
                _title_from_id(str(action.get("id", "entity"))),
                str(action.get("x", 0)),
                str(action.get("y", 0)),
            ]
        "spawn_entity_at_zone":
            return "Create %s at zone %s" % [
                _title_from_id(str(action.get("id", "entity"))),
                _quoted(action.get("zone_id", "")),
            ]
        "spawn_space_ship":
            return "Create space ship class %s" % _quoted(action.get("class", ""))
        "despawn_entity":
            return "Remove all %s from the room" % _title_from_id(str(action.get("id", "entity")))
        "move_entity_to_zone":
            return "Move %s to zone %s" % [
                _actor(action.get("entity", "actor")),
                _quoted(action.get("zone_id", "")),
            ]
        "play_entity_anim":
            return "Play animation %s on %s" % [
                _quoted(action.get("anim", "")),
                _actor(action.get("entity", "actor")),
            ]
        "set_entity_facing":
            return "Make %s face %s" % [
                _actor(action.get("entity", "actor")),
                str(action.get("direction", "direction")),
            ]
        "camera_focus":
            return "Move camera focus to %s" % str(action.get("target", action.get("mode", "target")))
        "camera_unlock":
            return "Return camera to the player"
        "set_room_weather":
            return "Set room weather to %s" % _title_from_id(str(action.get("preset", "weather")))
        "fire_event":
            return "Start event %s" % event_label(str(action.get("event", "")))
        "set_trigger_enabled":
            return "%s trigger %s" % [
                "Enable" if bool(action.get("enabled", true)) else "Disable",
                _quoted(action.get("id", "")),
            ]
        "set_door_enabled":
            return "%s door %s" % [
                "Enable" if bool(action.get("enabled", true)) else "Disable",
                _quoted(action.get("id", "")),
            ]
        "set_door_locked":
            return "%s door %s" % [
                "Lock" if bool(action.get("locked", true)) else "Unlock",
                _quoted(action.get("id", "")),
            ]
        "start_dialogue":
            return "Start conversation %s" % _title_from_id(str(action.get("id", "dialogue")))
        "start_shop":
            return "Open shop %s" % _title_from_id(str(action.get("id", "shop")))
        "play_sfx":
            return "Play sound %s" % _title_from_id(str(action.get("name", "sound")))
        "save_checkpoint":
            return "Save checkpoint in slot %s" % str(action.get("slot", 0))
        "return_to_space":
            return "Return to space"
        "end_dialogue":
            return "End the conversation"
        "log":
            return "Write debug message: %s" % str(action.get("message", "")).strip_edges()
        _:
            var schema := find_action_schema(type_name)
            if not schema.is_empty():
                return str(schema.get("label", type_name))
            return _title_from_id(type_name) if not type_name.is_empty() else "Do nothing"


static func _title_from_id(value: String) -> String:
    var clean := value.strip_edges()
    if clean.is_empty():
        return ""
    return clean.replace("_", " ").replace("-", " ").capitalize()


static func _quoted(value: Variant) -> String:
    var text := str(value).strip_edges()
    if text.is_empty():
        return "\"\""
    return "\"%s\"" % text


static func _actor(value: Variant) -> String:
    var text := str(value).strip_edges()
    if text == "player":
        return "the player"
    return _title_from_id(text) if not text.is_empty() else "the actor"


static func _num(value: Variant) -> String:
    var f := float(value)
    if is_equal_approx(f, roundf(f)):
        return str(int(f))
    return "%.2f" % f
