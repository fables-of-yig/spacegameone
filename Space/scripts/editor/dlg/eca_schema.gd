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
    "game_started", "new_game_started",
    "player_spawn", "player_damage", "player_death",
    "door_enter", "door_use_attempt", "door_use_success", "door_use_blocked", "door_arrived",
    "region_enter", "region_exit",
    "zone_enter", "zone_exit",
    "ability_grant", "ability_revoke",
    "enemy_spawn", "enemy_defeated",
    "boss_arena_lock", "boss_arena_unlock", "boss_phase", "boss_defeated",
    "projectile_explode", "bomb_explode",
    "dialogue_started", "dialogue_ended", "dialogue_choice",
    "shop_opened", "shop_closed",
    "quest_started", "quest_stage_changed", "quest_objective_completed", "quest_stage_completed", "quest_completed", "quest_failed",
    "trigger_sequence_finished",
    "space_system_enter", "space_station_destroyed", "space_poi_interact",
    "space_proximity_band",
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
    "game_started": "Fires once after the game finishes loading the actual start room and placing the player. Use this for intro cutscenes, opening dialogue, and first-room setup that must only run on boot.",
    "new_game_started": "Fires once on a fresh boot BEFORE game_started, only when the player started a brand-new game (no save snapshot, no restored progression). When any rule matches this event, the runtime skips its automatic player-spawn so your cutscene can place the player using spawn_player or teleport_player. Use this to author the opening cinematic.",
    "player_spawn": "Fires every time the player is placed in a room — at boot, from a scripted spawn_player action, or on any respawn. Use this for camera resets, room intros that should replay, or anything that must react to placement. For boot-only logic prefer game_started.",
    "player_damage": "Fires when the player takes damage.",
    "player_death": "Fires when the player dies.",
    "door_enter": "Fires when the player enters a door transition.",
    "door_use_attempt": "Fires whenever the player tries to use a door zone before access checks are applied.",
    "door_use_success": "Fires when a door use passes enabled/lock checks and begins transitioning.",
    "door_use_blocked": "Fires when a door is disabled or locked without satisfying its requirements.",
    "door_arrived": "Fires after the destination room loads and the player is spawned from the target door.",
    "region_enter": "Fires when a region is entered from the Space-to-MV landing handoff.",
    "region_exit": "Fires when the player leaves the current region (typically by traversing a launch_to_space door or being launched back to Space). Use for region-scoped cleanup or save bookmarks.",
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
    "dialogue_started": "Fires when a conversation begins (whether opened by the start_dialogue action, an interactable's dialogue_id, or any other path).",
    "dialogue_ended": "Fires when a conversation closes — natural end, player dismissal, or the end_dialogue action.",
    "dialogue_choice": "Fires when the player chooses a dialogue option.",
    "shop_opened": "Fires when a shop UI opens.",
    "shop_closed": "Fires when a shop UI closes.",
    "quest_started": "Fires after a trigger action starts a quest.",
    "quest_stage_changed": "Fires after a trigger action moves a quest to a new stage.",
    "quest_objective_completed": "Fires after a trigger action completes one quest objective.",
    "quest_stage_completed": "Fires after a trigger action completes one quest stage.",
    "quest_completed": "Fires after a trigger action marks a quest complete.",
    "quest_failed": "Fires after a trigger action marks a quest as failed.",
    "trigger_sequence_finished": "Fires when a trigger sequence completes execution.",
    "space_system_enter": "Fires when entering a space system in the ship layer.",
    "space_station_destroyed": "Fires when a space station is destroyed.",
    "space_poi_interact": "Fires when the player interacts with a point of interest in space.",
    "space_proximity_band": "Fires once each time the player ship enters the [band_min, band_max] distance ring around the star of `system_id`. Re-arms when the ship leaves the ring. Use event_params to bind a rule to a specific system + band.",
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
    "game_started": "When the game starts (once at boot)",
    "new_game_started": "When a fresh game starts (for intro cutscenes)",
    "player_spawn": "When the player is placed in a room (boot or respawn)",
    "player_damage": "When the player takes damage",
    "player_death": "When the player dies",
    "door_enter": "When the player enters a door",
    "door_use_attempt": "When the player tries a door",
    "door_use_success": "When a door opens",
    "door_use_blocked": "When a door is blocked",
    "door_arrived": "When the player arrives through a door",
    "region_enter": "When the player enters a region",
    "region_exit": "When the player leaves a region",
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
    "dialogue_started": "When a conversation begins",
    "dialogue_ended": "When a conversation ends",
    "dialogue_choice": "When the player picks a dialogue choice",
    "shop_opened": "When a shop opens",
    "shop_closed": "When a shop closes",
    "quest_started": "When a quest starts",
    "quest_stage_changed": "When a quest changes stage",
    "quest_objective_completed": "When a quest objective completes",
    "quest_stage_completed": "When a quest stage completes",
    "quest_completed": "When a quest completes",
    "quest_failed": "When a quest fails",
    "trigger_sequence_finished": "When another trigger sequence finishes",
    "space_system_enter": "When the ship enters a star system",
    "space_station_destroyed": "When a station is destroyed",
    "space_poi_interact": "When the player interacts with a space point",
    "space_proximity_band": "When the ship enters a star-distance band",
    "save_game": "When the game is saved",
    "load_game": "When a save is loaded",
    "ui_button": "When a UI button is pressed",
}

# Per-event source parameter schema. When the user picks an event whose id
# appears here, the trigger editor renders these inputs below the event
# OptionButton and serializes them into rule.event_params (NOT into
# rule.conditions[] — these are event-source bindings, not gate checks).
# The Space runtime reads event_params directly to know which proximity
# bands to track, which systems to listen to, etc.
#
# Field spec matches CONDITION_TYPES.fields: [key, label, kind]. Supported
# kinds: "string", "int", "float", "bool". A "system_id" kind would be
# nice (dropdown of authored systems) but for now treat it as "string"
# and let the author type it; system_editor.gd can offer copy-id helpers
# in a follow-up.
const EVENT_PARAMS: Dictionary = {
    "space_proximity_band": [
        ["system_id", "system id", "string"],
        ["band_min", "min distance (px)", "int"],
        ["band_max", "max distance (px)", "int"],
    ],
}

const EVENT_PARAMS_HELP: Dictionary = {
    "space_proximity_band": "Bind this rule to a specific star + distance ring. The runtime fires the event once per entry into [band_min, band_max] around the star of system_id, and re-arms when the ship leaves the ring.",
}

# Per-event payload keys published by the runtime when the event fires.
# Surfaced by the payload_eq condition form so authors pick a real key from
# a dropdown instead of guessing. Keys whose values are arrays/vectors
# (tags, position) are intentionally omitted — payload_eq stringifies both
# sides for comparison and array/vector matching belongs in dedicated
# conditions (has_tag for tags, dedicated comparisons for vectors).
const EVENT_PAYLOADS: Dictionary = {
    "pickup": ["entity_id", "item_id"],
    "interact": ["entity_id", "entity_type", "dialogue_id"],
    "item_gain": ["item_id", "count", "stock_id", "shop_id"],
    "item_loss": ["item_id", "count", "remaining"],
    "item_use": ["item_id", "count"],
    "item_sell": ["item_id", "price", "shop_id"],
    "game_started": [],
    "new_game_started": ["room", "fresh_boot", "restored_snapshot", "restored_player_progression", "playtest_spawn_override"],
    "player_spawn": ["room", "x", "y", "zone_id"],
    "player_damage": ["amount", "hp", "max_hp", "source"],
    "player_death": ["source"],
    "door_enter": ["door_id", "target_door_id", "from_room", "enabled", "locked"],
    "door_use_attempt": ["door_id", "target_door_id", "from_room"],
    "door_use_success": ["door_id", "target_door_id", "from_room", "enabled", "locked"],
    "door_use_blocked": ["door_id", "target_door_id", "from_room", "enabled", "locked", "block_reason"],
    "door_arrived": ["door_id", "target_door_id", "from_room", "arrival_door_id"],
    "region_enter": ["region_id", "music_id", "encounter_id", "visual_theme", "hazard_type", "gravity_mult"],
    "region_exit": ["region_id"],
    "zone_enter": ["entity_id", "zone_id"],
    "zone_exit": ["entity_id", "zone_id"],
    "ability_grant": ["ability_id"],
    "ability_revoke": ["ability_id"],
    "enemy_spawn": ["entity_id", "room_id"],
    "enemy_defeated": ["entity_id"],
    "boss_arena_lock": ["entity_id"],
    "boss_arena_unlock": ["entity_id"],
    "boss_phase": ["entity_id", "phase"],
    "boss_defeated": ["entity_id"],
    "projectile_explode": ["radius", "damage"],
    "bomb_explode": ["radius", "damage"],
    "dialogue_started": ["dialogue_id"],
    "dialogue_ended": ["dialogue_id"],
    "dialogue_choice": ["dialogue_id", "line_index", "choice_index", "choice_text"],
    "shop_opened": ["shop_id"],
    "shop_closed": ["shop_id"],
    "quest_started": ["quest_id", "stage_id"],
    "quest_stage_changed": ["quest_id", "stage_id"],
    "quest_objective_completed": ["quest_id", "stage_id", "objective_id"],
    "quest_stage_completed": ["quest_id", "stage_id"],
    "quest_completed": ["quest_id", "stage_id"],
    "quest_failed": ["quest_id", "stage_id"],
    "trigger_sequence_finished": ["rule_id"],
    "space_system_enter": ["system_id"],
    "space_station_destroyed": ["system_id", "station_key"],
    "space_poi_interact": ["system_id", "event_id"],
    "space_proximity_band": ["system_id", "band_min", "band_max", "distance", "rule_id"],
    "save_game": ["slot", "pack_id"],
    "load_game": ["slot", "pack_id"],
    "ui_button": ["screen_id", "element_id", "host", "action"],
}


static func event_payload_keys(event_name: String) -> Array:
    var v: Variant = EVENT_PAYLOADS.get(event_name, null)
    if v == null or typeof(v) != TYPE_ARRAY:
        return []
    return (v as Array).duplicate()


const CONDITION_TYPES: Array = [
    {"type": "has_item", "label": "Player has item",
     "fields": [["id", "item id", "string"], ["min_count", "min count", "int"]],
     "help": "True when the player inventory contains at least `min_count` of the given item id (defaults to 1)."},
    {"type": "has_ability", "label": "Player has ability",
     "fields": [["id", "ability id", "string"]],
     "help": "True when the player has been granted the named ability (checked against PlayerInventory.abilities)."},
    {"type": "has_tag", "label": "Triggering payload has tag",
     "fields": [["tag", "tag", "string"]],
     "help": "True when the firing event's payload includes the given tag (e.g. an entity firing a trigger broadcasts its tags). This is the per-event/per-payload tag scope; use \"World has tag\" for tags set globally via add_tag."},
    {"type": "has_global_tag", "label": "World has tag",
     "fields": [["tag", "tag", "string"]],
     "help": "True when the world-level tag set (set by add_tag) contains the given tag."},
    {"type": "has_flag", "label": "Story flag is on/off",
     "fields": [["name", "flag name", "string"], ["value", "value (true/false)", "bool"]],
     "help": "Only allow this if the named on/off story flag matches the value you choose. Flags are a separate keyspace from story numbers — a flag named 'gold' and a number named 'gold' do not collide."},
    {"type": "has_global_flag", "label": "Global flag is set (cross-system)",
     "fields": [["name", "flag name", "string"], ["value", "expected value", "bool"]],
     "help": "True when the named persistent global flag (PlanetaryInterface) matches the expected value. Unlike has_flag (per-session game_vars), global flags survive cross-system transitions. Set them with set_global_flag."},
    {"type": "quest_status", "label": "Quest status is",
     "fields": [["quest_id", "quest id", "string"], ["status", "status", "string"]],
     "help": "Only allow this if a quest's status matches. Valid statuses: inactive, active, complete, failed."},
    {"type": "quest_stage", "label": "Quest stage is",
     "fields": [["quest_id", "quest id", "string"], ["stage_id", "stage id", "string"]],
     "help": "Only allow this if the quest's current stage id matches."},
    {"type": "quest_objective_done", "label": "Quest objective is done",
     "fields": [["quest_id", "quest id", "string"], ["stage_id", "stage id", "string"], ["objective_id", "objective id", "string"]],
     "help": "Only allow this after a trigger action has completed the named quest objective."},
    {"type": "var_eq", "label": "Story number equals",
     "fields": [["name", "number name", "string"], ["value", "value", "int"]],
     "help": "Only allow this if the named story number is exactly this value. Unset numbers count as 0. Story numbers are a separate keyspace from story flags."},
    {"type": "var_gte", "label": "Story number is at least",
     "fields": [["name", "number name", "string"], ["value", "threshold", "int"]],
     "help": "Only allow this if the named story number is at least this amount."},
    {"type": "var_eq_var", "label": "Story number equals another number",
     "fields": [["name_a", "first number name", "string"], ["name_b", "second number name", "string"]],
     "help": "Only allow this if two named story numbers hold the same value. Unset numbers count as 0. Useful for comparing 'current_score == high_score' or 'gold == price'."},
    {"type": "var_gte_var", "label": "Story number is at least another",
     "fields": [["name_a", "first number name", "string"], ["name_b", "second number name", "string"]],
     "help": "Only allow this if the first story number is greater than or equal to the second. Useful for 'gold >= price' or 'kills >= quota'."},
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
    {"type": "heal_player", "label": "Heal player",
     "fields": [["amount", "amount", "int"]],
     "help": "Restore the given amount of HP to the player. Clamped to the player's max HP. No effect if amount is 0 or negative."},
    {"type": "damage_player", "label": "Hurt player",
     "fields": [["amount", "amount", "int"], ["source", "source label", "opt_string"]],
     "help": "Deal the given amount of damage to the player. The source label appears in the player_damage / player_death payload (e.g. 'spike', 'boss_phase_2')."},
    {"type": "spawn_fx", "label": "Spawn visual effect",
     "fields": [["effect_id", "effect id", "string"], ["x", "x px", "opt_string"], ["y", "y px", "opt_string"]],
     "help": "Spawn an authored visual effect by id. If x/y are left blank and the firing event carries a 'position', it spawns there; otherwise at (x, y)."},
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
    {"type": "set_flag", "label": "Set story flag (on/off)",
     "fields": [["name", "flag name", "string"], ["value", "value", "bool"]],
     "help": "Turn a named on/off story flag on or off. Good for marking progress like met_mayor = true. Flags are a separate keyspace from story numbers — a flag named 'gold' and a number named 'gold' do not collide."},
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
    {"type": "quest_fail", "label": "Fail quest",
     "fields": [["quest_id", "quest id", "string"]],
     "help": "Mark a quest as failed. Fires the quest_failed event. The quest's status becomes 'failed' — readable via the quest_status condition."},
    {"type": "set_var", "label": "Set story number",
     "fields": [["name", "number name", "string"], ["value", "value", "int"]],
     "help": "Set a named story number to an exact value. Story numbers are a separate keyspace from story flags — a flag named 'gold' and a number named 'gold' do not collide."},
    {"type": "add_var", "label": "Change story number",
     "fields": [["name", "number name", "string"], ["delta", "delta", "int"]],
     "help": "Increase or decrease a named story number. Use a negative delta to subtract."},
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
    {"type": "pause_game", "label": "Pause game simulation", "fields": [],
     "help": "Pause physics, projectiles, beams, melee, grenades, and camera follow. Same pause used by dialogue/inventory/map screens. Use for cutscenes that need a frozen world."},
    {"type": "resume_game", "label": "Resume game simulation", "fields": [],
     "help": "Resume the simulation after pause_game. Safe to call when not paused (no-op)."},
    {"type": "spawn_player", "label": "Place player",
     "fields": [["room", "room addr", "opt_string"], ["zone_id", "zone id", "opt_string"], ["entry_direction", "entry direction", "opt_string"], ["facing", "facing", "opt_string"], ["use_position", "use exact pixel position", "bool"], ["x", "x px", "int"], ["y", "y px", "int"], ["emit_event", "emit event", "bool"]],
     "help": "Spawn or respawn the player. Choose ONE positioning method: leave 'use exact pixel position' off to spawn at zone_id (or the room's player_spawn entity if no zone is set); turn it on to teleport to the explicit x/y pixel below. entry_direction and facing are optional overrides."},
    {"type": "spawn_entity", "label": "Create entity",
     "fields": [["id", "entity id", "string"], ["x", "x px", "int"], ["y", "y px", "int"]],
     "help": "Spawn an entity at the given world position. Entity id must exist in Entities.json."},
    {"type": "spawn_entity_at_zone", "label": "Create entity at zone",
     "fields": [["id", "entity id", "string"], ["zone_id", "zone id", "string"]],
     "help": "Spawn an entity at the center of a named trigger-volume zone in the current room."},
    {"type": "spawn_space_ship", "label": "Spawn Space Ship",
     "fields": [["class", "class id", "string"], ["anchor", "anchor", "string"], ["x", "x offset/world", "float"], ["y", "y offset/world", "float"], ["wormhole", "wormhole", "bool"], ["delay", "delay", "opt_float"]],
     "help": "Spawn a hostile space ship by class id. `anchor=player` treats x/y as offsets from the player, `anchor=world` uses absolute world coords, and `anchor=system` offsets from the current system star."},
    {"type": "spawn_space_enemies", "label": "Spawn Space Enemy Wave",
     "fields": [["class_id", "enemy class id", "string"], ["count", "count", "int"], ["dist_min", "spawn min dist (px)", "int"], ["dist_max", "spawn max dist (px)", "int"], ["use_wormhole", "use wormhole", "bool"]],
     "help": "Scatter `count` copies of `class_id` around the player at random angles, distance picked in [dist_min, dist_max]. Mirrors the old systems.json spawn_triggers behavior; pair with the space_proximity_band event for entry-band ambushes. dist_min is clamped to 600 and dist_max to dist_min+200 at runtime, matching spawn_manager."},
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
    {"type": "camera_shake", "label": "Shake the camera",
     "fields": [["intensity", "intensity (px)", "float"], ["duration", "duration (s)", "float"]],
     "help": "Vibrate the camera by up to `intensity` pixels for `duration` seconds. The shake amplitude tapers to zero linearly. Use for impacts, explosions, big boss arrivals. Stacks gracefully — a stronger or longer shake during one already in progress wins."},
    {"type": "screen_flash", "label": "Flash the screen",
     "fields": [["color", "color html", "string"], ["duration", "fade duration (s)", "float"]],
     "help": "Pop a fullscreen colored overlay at the chosen color, then fade its alpha to zero over `duration` seconds. Color is an HTML string like `ff0000aa` (red, ~67% alpha). Use for damage flashes, pickup highlights, boss-intro pops."},
    {"type": "set_player_invuln", "label": "Grant player invulnerability",
     "fields": [["seconds", "duration (s)", "float"]],
     "help": "Give the player iframes for `seconds`. Stacks by taking the max of the requested duration and any already-active invuln. Use after dialogue or scripted sequences to avoid one-shots on resume."},
    {"type": "show_toast", "label": "Show toast notification",
     "fields": [["message", "message", "string"], ["duration", "duration (s)", "opt_float"], ["style", "style", "opt_string"]],
     "help": "Pop a transient text card in the HUD's top-right toast stack. Style options: info (blue, default), success (green), warning (yellow), error (red). Duration defaults to 2.5s when 0 or blank. Authors can override the toast look-and-feel by creating an authored UI screen named 'toast' in their pack — the template receives a {message} binding and replaces the default styled card."},
    {"type": "reveal_system", "label": "Reveal star system on map",
     "fields": [["system_id", "system id", "string"]],
     "help": "Mark a star system as known on the star map without requiring the player to physically jump to it. Useful for storyline hints (an NPC tells the player about a new planet, a faction reveals their territory). Adds the id to GameManager.visited_systems if not already present."},
    {"type": "unlock_poi", "label": "Unlock hidden POI",
     "fields": [["system_id", "system id", "string"], ["poi_id", "poi id", "string"]],
     "help": "Make a `hidden: true` POI eligible to spawn the next time the player jumps into `system_id`. Records the poi_id in GameManager.unlocked_pois so it survives save/load. The POI must have its `hidden` flag set in the system editor and a stable `id` for this to bite; non-hidden POIs ignore the unlock list. Live: the change takes effect on the next system entry, not immediately if the player is already in-system."},
    {"type": "space_add_credits", "label": "Give space credits",
     "fields": [["amount", "amount", "int"]],
     "help": "Add credits to the Space-side player wallet (GameManager.credits). Use a negative amount to charge a fee. Credits floor at 0 — large negative amounts won't go below zero."},
    {"type": "space_set_credits", "label": "Set space credits",
     "fields": [["amount", "amount", "int"]],
     "help": "Set the Space-side credit balance directly. Clamped to a minimum of 0."},
    {"type": "set_global_flag", "label": "Set global flag (cross-system)",
     "fields": [["name", "flag name", "string"], ["value", "value", "bool"]],
     "help": "Set a persistent cross-system flag stored on PlanetaryInterface. Unlike the regular set_flag (which lives in PlayerInventory game_vars per session/pack), global flags survive launches and landings — use these for story progress that needs to be readable from both MV and Space."},
    {"type": "clear_global_flag", "label": "Clear global flag",
     "fields": [["name", "flag name", "string"]],
     "help": "Remove a global flag entirely. has_global_flag returns false afterward, regardless of value."},
    {"type": "space_spawn_ship_on_return", "label": "Queue space ship for system",
     "fields": [["class", "ship class id", "string"], ["system_id", "system id", "string"]],
     "help": "Queue a hostile space ship to spawn the next time the player jumps into `system_id`. The ship is created at the system's center using the standard spawn manager. Stacks — calling this twice with the same system queues two ships. Use for ambushes set up from an MV trigger that should land when the player returns to a specific system."},
    {"type": "random_pick", "label": "Random branch (weighted pick)",
     "fields": [["options", "options", "branches_block"]],
     "help": "Roll a weighted random pick over a list of action branches and run the chosen branch in place. Each branch has a weight (number) and an action list. The runtime rolls in [0, sum_of_weights), then runs the matching branch. Missing/zero weights default to 1. Branch actions inherit the parent rule's payload — waits, locals, and breakpoints work the same as in a flat sequence."},
    {"type": "if", "label": "If / then / else",
     "fields": [["conditions", "if all of these are true", "conditions_block"], ["then", "then do these actions", "actions_block"], ["else", "otherwise do these actions", "actions_block"]],
     "help": "Inline conditional branching. Evaluates the conditions; if all pass, runs the THEN action list; otherwise runs the ELSE list. Both branches inherit the parent rule's payload so waits, locals, and breakpoints behave the same as in the top-level sequence. Leave ELSE empty when you only need a one-armed gate."},
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
    {"type": "play_music", "label": "Play music",
     "fields": [["track", "music id", "string"]],
     "help": "Switch the ambient music track. Track ids come from the audio manifest. Pass the same id that already plays to no-op; this swaps gracefully."},
    {"type": "stop_music", "label": "Stop music", "fields": [],
     "help": "Silence the ambient music track."},
    {"type": "save_checkpoint", "label": "Save Checkpoint",
     "fields": [["slot", "save slot", "int"]],
     "help": "Persist the current game state to the given save slot."},
    {"type": "return_to_space", "label": "Return To Space", "fields": [],
     "help": "Exit the MV room layer, snapshot the planet state, and return to the ship's orbit position."},
    {"type": "end_game", "label": "End game (show game over)", "fields": [],
     "help": "Show the game over screen. Equivalent to player death without firing the player_death event. Use for non-combat failure paths."},
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


# Returns the [key, label, kind] field specs for the event-source parameters
# of `event_id`, or an empty Array if the event has no params. Editors use
# this to render inputs that bind a rule to a specific source instance
# (system, region, band, etc.) and serialize the values into rule.event_params.
static func event_params(event_id: String) -> Array:
    var entry: Variant = EVENT_PARAMS.get(event_id, [])
    return entry if entry is Array else []


static func event_params_help(event_id: String) -> String:
    return str(EVENT_PARAMS_HELP.get(event_id, ""))


static func has_event_params(event_id: String) -> bool:
    return EVENT_PARAMS.has(event_id) and not (event_params(event_id)).is_empty()


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
            return "Triggering payload includes tag %s" % _quoted(condition.get("tag", ""))
        "has_global_tag":
            return "World has tag %s" % _quoted(condition.get("tag", ""))
        "has_flag":
            return "Story flag %s is %s" % [
                _quoted(condition.get("name", "")),
                "on" if bool(condition.get("value", true)) else "off",
            ]
        "has_global_flag":
            return "Global flag %s is %s" % [
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
        "var_eq_var":
            return "Story number %s equals story number %s" % [
                _quoted(condition.get("name_a", "")),
                _quoted(condition.get("name_b", "")),
            ]
        "var_gte_var":
            return "Story number %s is at least story number %s" % [
                _quoted(condition.get("name_a", "")),
                _quoted(condition.get("name_b", "")),
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
        "heal_player":
            return "Heal player by %s HP" % str(action.get("amount", 0))
        "damage_player":
            var dmg_source := str(action.get("source", "")).strip_edges()
            if dmg_source.is_empty():
                return "Hurt player for %s damage" % str(action.get("amount", 0))
            return "Hurt player for %s damage (source: %s)" % [
                str(action.get("amount", 0)),
                _quoted(dmg_source),
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
        "quest_fail":
            return "Fail quest %s" % _title_from_id(str(action.get("quest_id", "quest")))
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
        "pause_game":
            return "Pause the game simulation"
        "resume_game":
            return "Resume the game simulation"
        "spawn_player":
            if bool(action.get("use_position", false)):
                return "Place the player at exact pixel (%s, %s)" % [
                    str(action.get("x", 0)),
                    str(action.get("y", 0)),
                ]
            var zone_str := str(action.get("zone_id", "")).strip_edges()
            if not zone_str.is_empty():
                return "Place the player at zone %s" % zone_str
            var room_str := str(action.get("room", "")).strip_edges()
            if not room_str.is_empty():
                return "Place the player in room %s (default spawn)" % room_str
            return "Place the player at the room's default spawn"
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
        "camera_shake":
            return "Shake the camera %sx for %ss" % [
                str(action.get("intensity", 0)),
                str(action.get("duration", 0)),
            ]
        "screen_flash":
            return "Flash the screen %s for %ss" % [
                _quoted(action.get("color", "")),
                str(action.get("duration", 0)),
            ]
        "set_player_invuln":
            return "Give the player %ss invulnerability" % str(action.get("seconds", 0))
        "show_toast":
            return "Show %s toast: %s" % [
                str(action.get("style", "info")),
                _quoted(action.get("message", "")),
            ]
        "reveal_system":
            return "Reveal star system %s on the map" % _quoted(action.get("system_id", ""))
        "unlock_poi":
            return "Unlock hidden POI %s in system %s" % [
                _quoted(action.get("poi_id", "")),
                _quoted(action.get("system_id", "")),
            ]
        "space_add_credits":
            var amt: int = int(action.get("amount", 0))
            if amt >= 0:
                return "Give the player %d space credits" % amt
            return "Charge the player %d space credits" % -amt
        "space_set_credits":
            return "Set space credits to %d" % int(action.get("amount", 0))
        "set_global_flag":
            return "Set global flag %s %s" % [
                _quoted(action.get("name", "")),
                "on" if bool(action.get("value", true)) else "off",
            ]
        "clear_global_flag":
            return "Clear global flag %s" % _quoted(action.get("name", ""))
        "space_spawn_ship_on_return":
            return "Queue space ship %s for system %s" % [
                _quoted(action.get("class", "")),
                _quoted(action.get("system_id", "")),
            ]
        "random_pick":
            var options_v: Variant = action.get("options", [])
            var n_opts: int = (options_v as Array).size() if typeof(options_v) == TYPE_ARRAY else 0
            return "Random pick — one of %d branch%s" % [
                n_opts,
                "" if n_opts == 1 else "es",
            ]
        "if":
            var if_conds_v: Variant = action.get("conditions", [])
            var if_then_v: Variant = action.get("then", [])
            var if_else_v: Variant = action.get("else", [])
            var n_conds: int = (if_conds_v as Array).size() if typeof(if_conds_v) == TYPE_ARRAY else 0
            var n_then: int = (if_then_v as Array).size() if typeof(if_then_v) == TYPE_ARRAY else 0
            var n_else: int = (if_else_v as Array).size() if typeof(if_else_v) == TYPE_ARRAY else 0
            if n_else > 0:
                return "If %d check%s pass: %d action%s, else %d action%s" % [
                    n_conds, "" if n_conds == 1 else "s",
                    n_then, "" if n_then == 1 else "s",
                    n_else, "" if n_else == 1 else "s",
                ]
            return "If %d check%s pass: %d action%s" % [
                n_conds, "" if n_conds == 1 else "s",
                n_then, "" if n_then == 1 else "s",
            ]
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
        "play_music":
            return "Play music %s" % _title_from_id(str(action.get("track", "track")))
        "stop_music":
            return "Stop music"
        "save_checkpoint":
            return "Save checkpoint in slot %s" % str(action.get("slot", 0))
        "return_to_space":
            return "Return to space"
        "end_game":
            return "End the game (show game over)"
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
