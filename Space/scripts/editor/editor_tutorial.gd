extends Control

# Full-screen scrollable tutorial overlay. Opened by the TUTORIAL button
# in any editor's topbar. Shows step-by-step setup instructions specific
# to that editor. Press ESC or click CLOSE to dismiss.

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")

var _title: String = ""
var _steps: Array = []  # Array[String]
var _scroll_y: float = 0.0
var _close_rect: Rect2 = Rect2()


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    visible = false
    set_process(true)


func _process(_delta):
    if visible:
        queue_redraw()


func show_tutorial(title: String, steps: Array) -> void:
    _title = title
    _steps = steps
    _scroll_y = 0.0
    visible = true
    queue_redraw()


func _gui_input(event):
    if not visible:
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            if _close_rect.has_point(mb.position):
                visible = false
                accept_event()
                return
            accept_event()
            return
        if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
            _scroll_y = maxf(_scroll_y - 30.0, 0.0)
            accept_event()
        elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
            _scroll_y += 30.0
            accept_event()


func _input(event):
    if not visible:
        return
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        visible = false
        get_viewport().set_input_as_handled()


func _draw():
    if not visible:
        return
    UIPanels.draw_dim(self, Rect2(Vector2.ZERO, size), 0.7)

    var panel_w: float = minf(700.0, size.x - 60.0)
    var panel_h: float = size.y - 60.0
    var panel_x: float = (size.x - panel_w) * 0.5
    var panel_y: float = 30.0
    var panel_rect := Rect2(panel_x, panel_y, panel_w, panel_h)
    UIPanels.draw_panel(self, panel_rect, Color.WHITE, UIPanels.PanelVariant.MAIN)

    var font := ThemeDB.fallback_font
    var content_x := panel_x + 24.0
    var content_w := panel_w - 48.0
    var y := panel_y + 24.0 - _scroll_y

    # Title
    draw_string(font, Vector2(content_x, y + 18),
        _title, HORIZONTAL_ALIGNMENT_LEFT, int(content_w), 18, UIPanels.TEXT_PANEL)
    y += 36.0

    # Steps
    for i in _steps.size():
        var step: String = _steps[i]
        var step_label := "Step %d:" % (i + 1)
        var visible_y := y + _scroll_y

        if visible_y + 60.0 >= panel_y and visible_y < panel_y + panel_h:
            # Step number
            draw_string(font, Vector2(content_x, y + 16),
                step_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
                Color(0.4, 0.85, 1.0, 1.0))

            # Step text (wrap manually by splitting on newlines)
            var lines := step.split("\n")
            var line_y := y + 16.0
            for line in lines:
                # Word wrap within content_w
                var words := line.split(" ")
                var current_line := ""
                for word in words:
                    var test := current_line + (" " if not current_line.is_empty() else "") + word
                    if float(test.length()) * 6.5 > content_w - 70.0 and not current_line.is_empty():
                        draw_string(font, Vector2(content_x + 66, line_y),
                            current_line, HORIZONTAL_ALIGNMENT_LEFT, int(content_w - 70), 12,
                            UIPanels.TEXT_PANEL)
                        line_y += 16.0
                        current_line = word
                    else:
                        current_line = test
                if not current_line.is_empty():
                    draw_string(font, Vector2(content_x + 66, line_y),
                        current_line, HORIZONTAL_ALIGNMENT_LEFT, int(content_w - 70), 12,
                        UIPanels.TEXT_PANEL)
                    line_y += 16.0

            y = line_y + 8.0
        else:
            y += 40.0  # rough estimate for off-screen steps

    # Close button
    var close_w: float = 100.0
    var close_h: float = 32.0
    _close_rect = Rect2(panel_x + panel_w - close_w - 16, panel_y + panel_h - close_h - 12, close_w, close_h)
    var mouse_pos := get_local_mouse_position()
    UIPanels.draw_button_bg(self, _close_rect, _close_rect.has_point(mouse_pos), Color(0.4, 0.6, 0.9, 1.0))
    draw_string(font, _close_rect.position + Vector2(28, 21), "CLOSE",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 1))


# ─── Tutorial content per editor ────────────────────────────────────────

const TUTORIALS: Dictionary = {
    "player": {
        "title": "Player Editor Tutorial",
        "steps": [
            "SPRITES: Import a player sprite sheet PNG. Set the frame width/height to match your art grid. Click cells in the sheet to build animation sequences for each pose.",
            "STATS: Set base values for your player's stats (HP, MP, STR, etc.) and per-level growth rates. Use the STAT EFFECTS section below to bind stats to ManiaVars — the physics/gameplay variables they modify.",
            "ATTACKS: Define melee and projectile attacks. Melee attacks specify which animation frames have active hitboxes. Projectile attacks reference a projectile definition by ID.",
            "PROJECTILES: Set up projectile sprites, physics (speed, gravity, lifetime), combat stats (damage, hitbox), and optional homing behavior. The sprite preview shows your projectile animating.",
            "ABILITIES: Create binary unlock abilities (double_jump, wall_jump, grapple, etc.). Click KNOWN PARAMS to quickly add common ability parameters. Abilities are checked at runtime via has_ability(id).",
            "ITEMS: Define inventory items with stack limits, prices, and categories. Items are given to the player via triggers (pickup events) or shop transactions.",
            "EQUIPMENT: Define equippable gear with stat mods and ability grants. Each piece goes in a slot (Head, Body, Weapon, etc.) and can modify ManiaVars when equipped.",
            "PHYSICS: Fine-tune the player controller's movement feel. Every value derives from Super Metroid ROM constants — gravity, jump height, run speed, grapple behavior. Changes here affect ALL gameplay.",
        ],
    },
    "environment": {
        "title": "Environment Editor Tutorial",
        "steps": [
            "Import tilesets using the + button on the tileset panel (right side). For animated tiles, use 'Import as animation' to slice a sprite sheet.",
            "Select a tile layer (MAIN by default) from the left panel. Use PAINT tool (LMB) to place tiles. ERASE removes them. FILL flood-fills an area. PICK eyedrops a tile.",
            "Add background (BG) and foreground (FG) layers for parallax effects. Set scroll speed in the layer properties — 0.5 for half-speed parallax backgrounds.",
            "Switch to COLLISION mode to paint walkable/solid geometry. Paint SOLID for walls/floors, AIR for open space, SPIKE for hazards, DOOR for room transitions.",
            "For spike cells: use PICK tool on a spike to open the Spike Profile modal. Create profiles with damage, effects (burn/poison/slow), and knockback modes.",
            "Switch to ENTITIES mode to place player_spawn, enemies, NPCs, pickups, and signs. Each entity type shows as a colored marker.",
            "Switch to DOORS mode to place room transition doors. Use PICK to set target room addresses and directions.",
            "Use the ANIM tool on painted tiles to configure per-cell animation — select frames, set FPS, loop mode, and phase offset.",
            "Press Ctrl+9 to playtest the current room. The game launches with the player at the player_spawn entity.",
        ],
    },
    "entity": {
        "title": "Entity Editor Tutorial",
        "steps": [
            "Create entity templates for enemies, NPCs, and pickups that you'll place in rooms.",
            "ENEMIES: Set HP, melee damage, touch damage, move speed, projectile defaults, and category. Link to a behavior tree from the Behavior editor.",
            "NPCs/INTERACTABLES: Set category to 'interactable'. Link to a dialogue ID from the Dialogue editor.",
            "PICKUPS: Set what the pickup gives — items, abilities, health, or game variable changes.",
            "Entity templates are referenced by their ID when placed in the Environment Editor's ENTITIES mode.",
        ],
    },
    "behavior": {
        "title": "Behavior Editor Tutorial",
        "steps": [
            "Behavior trees control enemy AI using the Beehave framework.",
            "Each tree starts with a root Selector or Sequence node. Add child nodes using the + button.",
            "CONDITIONS check the game state: PlayerNearCondition (range), AlwaysCondition, etc.",
            "ACTIONS make the enemy do things: WalkAction (speed, toward_player), IdleAction (duration), etc.",
            "SEQUENCE: runs children left-to-right, stops on first failure. SELECTOR: runs children left-to-right, stops on first success.",
            "Assign a behavior tree to an enemy template in the Entity Editor.",
        ],
    },
    "trigger": {
        "title": "Trigger Editor Tutorial",
        "steps": [
            "Think of a trigger as: something happens -> optional checks pass -> do these actions. The editor is strongest when you approach it in that order.",
            "Start by deciding the source. Common sources are: `interact` for NPC/object use, `zone_enter` for walking into a named trigger volume, `dialogue_choice` for reacting to a selected response, `ui_button` for authored menu buttons, and `game_started` for intro/setup flow.",
            "Very important: the simplest NPC conversation path does NOT need a trigger. If an interactable entity has a `dialogue_id` property, it will open that dialogue automatically when used. Add an `interact` trigger only when you need extra gating or side effects.",
            "For zone logic, place a `trigger_volume` in the room, give it a `zone_id`, and leave its event as `zone_enter` unless you want a custom event name. Then make a trigger rule listening for `zone_enter` and react with camera, spawns, flags, dialogue, or movement.",
            "Conditions are mostly filters. `payload_eq key=entity_id` is the usual way to make one `interact` rule care about only one NPC. `has_flag`, `var_gte`, and inventory/ability checks are the usual story gates.",
            "Actions are the outcome. Beginner-friendly patterns are: `start_dialogue id=<dialogue_id>`, `set_flag name=<flag> value=true`, `fire_event event=<next_step>`, `camera_focus`, or spawning/moving entities at a named zone.",
            "If you are unsure whether something is linked correctly, use VALIDATE and then the trigger debugger during playtest. That closes the loop much faster than guessing.",
        ],
    },
    "dialogue": {
        "title": "Dialogue Editor Tutorial",
        "steps": [
            "Think of one dialogue file as one conversation. On the left, pick a conversation or create a new one. On the middle list, each entry is one line of that conversation.",
            "Start simple: add a line, type who is speaking, then type what they say. If you leave the speaker blank, the line works fine as narration or system text.",
            "A line can optionally have a requirement under 'When should this line be allowed?'. Leave it empty if the line should always appear. Use it when you want a line to show only after a flag is set, or only if the player has enough of something.",
            "A line can also fire effects as soon as it appears. This is where you do things like set a flag, add to a story variable, give an item, play a sound, or immediately start another dialogue.",
            "Add player choices when you want the conversation to pause and wait for an answer. Each choice has its own text, its own optional requirement, and its own optional effects when picked.",
            "A good beginner pattern is: line of NPC text -> two player choices -> each choice sets a flag or starts the next dialogue. You do not need to use raw JSON unless you want very complex nested logic.",
            "How conversations get opened: simplest path is an interactable entity with `dialogue_id = <this dialogue id>`. The trigger path is a `start_dialogue` action with the same id. Dialogue can also chain into more dialogue by using `start_dialogue` inside a line or choice action.",
            "When the player picks a choice, the runtime also emits `dialogue_choice` with `dialogue_id`, `line_index`, `choice_index`, and `choice_text`. Use that when you want triggers to react outside the conversation file itself.",
        ],
    },
    "shop": {
        "title": "Shop Editor Tutorial",
        "steps": [
            "Create shop files that trigger actions can open via start_shop.",
            "Each shop has a list of items. Each item has an ID (must match an Items registry entry), optional name override, price in gold, and count per purchase.",
            "PlayerInventory game_vars[\"gold\"] is the currency — triggers can grant it via add_var.",
            "Reference shops by ID in trigger actions: {\"type\": \"start_shop\", \"id\": \"<shop_id>\"}.",
            "Item IDs are cross-validated against the Items registry by the content validator.",
        ],
    },
    "audio": {
        "title": "Audio Editor Tutorial",
        "steps": [
            "Import audio clips (WAV/OGG) for SFX and music.",
            "Name each clip with a descriptive ID: jump, shoot, buy, sell, pickup, door, boss_intro, etc.",
            "Use the trim controls to cut clips to the right length. Preview with the play button.",
            "Clips are referenced by name in trigger actions (play_sfx) and attack definitions.",
        ],
    },
    "systems": {
        "title": "Solar System Map Tutorial",
        "steps": [
            "This is the galaxy/solar system map editor — where you author star systems, their positions, and the routes between them.",
            "Pan the map by dragging empty space. Click a system node to select it and edit its details in the side panel. Drag a selected system to reposition it on the galaxy map.",
            "Use the toolbar to create or delete systems. Draw a connection by picking two systems — the route shows up as a line and unlocks travel between them.",
            "Within a selected system, add Points of Interest (POIs): planets, stations, anomalies. Each POI has a name, type, orbital position/scale, gravity radius, and an optional event trigger fired on arrival.",
            "Add NPC ships to a system with waypoint routes — drag the path nodes to shape patrol/trade lanes.",
            "All map data saves to res://Space/data/systems/systems.json.",
        ],
    },
    "events": {
        "title": "Events / Dialogue Tutorial",
        "steps": [
            "The events editor builds branching dialogue and story beats — node graphs with a start node, branching choices, and end nodes.",
            "Create or delete events in the left list. Open an event to edit its node graph; click a node to set speaker name, body text, and choice labels that route to other nodes.",
            "Each choice or node can carry EFFECTS — concrete game-state changes triggered when that choice is taken or that node is entered (e.g., give_credits, damage_hull, spawn_enemies, queue_event, set_tag).",
            "The effect picker lists 20+ effect types, each with its own parameter fields filled in once you pick the type.",
            "Ctrl+Z / Ctrl+Y works throughout. Events save to res://Space/data/events/starter_events.json.",
        ],
    },
    "enemies": {
        "title": "Enemy Ship Editor Tutorial",
        "steps": [
            "This tab edits enemy SHIP definitions — each entry is an enemy class that can be spawned in a system or encounter.",
            "Pick an enemy in the left list to edit, or use the ADD button to create a new one from a template. DELETE removes the selected entry.",
            "Fields include name, max_health, speed, damage, ship_size, color_base, shape, weapon_type, and behavior. Nested dictionary/array values are editable inline.",
            "Ctrl+Z / Ctrl+Y undo/redo is supported.",
            "Saves to res://Space/data/enemies/enemy_classes.json.",
        ],
    },
    "modules": {
        "title": "Spaceship Module Editor Tutorial",
        "steps": [
            "Modules are the ship parts the player bolts onto their hex-grid ship — weapons, shields, engines, reactors, etc. This tab edits the module catalog.",
            "Pick a module in the left list to edit, or ADD a new one from template. DELETE removes it.",
            "Fields include name, type, subtype, tier, hex_size, and a nested stats dictionary for tier-specific values.",
            "There is a 'copy to inventory' button to spawn this module into the player's current inventory for quick playtesting.",
            "Saves to res://Space/data/modules/starter_modules.json.",
        ],
    },
    "loot": {
        "title": "Loot Tables & Shop Stock Tutorial",
        "steps": [
            "Two views: LOOT TABLES (what drops from fights by threat level 1–5) and SHOP STOCK (what each system's NPC shop carries).",
            "Loot tables: set base drop chance + per-threat chance. Add modules to the pool with a weight; +/− buttons adjust weights. Higher weight = more common drop.",
            "Shop stock: pick a system, then add modules to its inventory. Buy/sell prices display so you can balance trade routes at a glance.",
            "Saves to res://Space/data/loot/loot_tables.json.",
        ],
    },
    "inventory": {
        "title": "Player Inventory / Test Console Tutorial",
        "steps": [
            "This is a playtest console for the PLAYER's live inventory — not a campaign-setup step. Useful for reproducing bugs or testing late-game ships.",
            "Top section shows current credits with quick-adjust buttons (+100, −100, +1k).",
            "Bottom section lists every module in the catalog (type, tier, buy/sell). Click a module to push it into the player's inventory.",
            "Use SAVE GAME to commit these changes to the active save slot.",
            "Reads/writes GameManager.credits and GameManager.module_inventory directly — no JSON file of its own.",
        ],
    },
    "flags": {
        "title": "Flags Tutorial",
        "steps": [
            "Flags are persistent game-state variables — booleans, ints, and strings — that events, triggers, and modules can read and write.",
            "Two columns: PLANET FLAGS (scoped to the current planet, snapshotted per visit) and GLOBAL FLAGS (persist across every system).",
            "Click a flag row to toggle a bool or increment an int. Right-click decrements. The [×] on each row deletes that flag.",
            "The [Clear] button at the top of a column wipes every flag in that namespace — use carefully.",
            "Backed by the PlanetaryInterface autoload — the same bridge used by the MVMania trigger system and the main space loop.",
        ],
    },
    "theme": {
        "title": "Theme / UI Editor Tutorial",
        "steps": [
            "THEME MODE: Set panel art (9-slice textures), button styles, text colors, and font sizes. Changes preview live.",
            "SCREEN MODE: Toggle to Screen mode to build UI layouts. Select a screen (HUD, Inventory, Shop, etc.) from the left panel.",
            "Add elements from the palette: Panel, Label, Button, Progress Bar, Icon, List, Grid, Separator, Tab Bar, Conditional.",
            "Drag elements on the canvas to position them. Drag corner handles to resize. Click to select, then edit properties in the right panel.",
            "Set DATA BINDINGS on elements to connect them to live game state: player.hp, inventory.items, game_var.gold, etc.",
            "Set ACTIONS on buttons: open_screen, close_screen, buy_item, save_game, quit_to_menu, etc.",
            "The runtime loads screen JSONs and renders them data-driven. Hardcoded screens serve as fallbacks until you author replacements.",
        ],
    },
}


static func get_tutorial(editor_key: String) -> Dictionary:
    return TUTORIALS.get(editor_key, {"title": "Tutorial", "steps": ["No tutorial content available for this editor."]})
