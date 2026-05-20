extends Node


const FactionsIO := preload("res://Space/scripts/shared/factions_io.gd")


var modules: Dictionary = {}
var crew: Dictionary = {}
var systems: Dictionary = {}
var events: Dictionary = {}
var enemy_classes: Dictionary = {}
var missions: Dictionary = {}
var loot_data: Dictionary = {}
var crew_templates: Dictionary = {}
var encounter_art: Dictionary = {}
var crops: Dictionary = {}
var livestock_types: Dictionary = {}
var cooking_recipes: Dictionary = {}

var galaxy_seed: int = 0
var galaxy_size: int = 120
var galaxy_data: Dictionary = {}

func _ready():
    modules = _load_json("res://Space/data/modules/starter_modules.json")
    events = _load_json("res://Space/data/events/starter_events.json")
    enemy_classes = _load_json("res://Space/data/enemies/enemy_classes.json")
    loot_data = _load_json("res://Space/data/loot/loot_tables.json")

    for eid in GENERIC_EVENTS:
        if not events.has(eid):
            events[eid] = GENERIC_EVENTS[eid]

    var encounters = _load_json("res://Space/data/encounters/encounters.json")
    if not encounters.is_empty():
        EncounterManager.load_encounters(encounters)

    encounter_art = _load_json("res://Space/data/encounters/encounter_art_map.json")
    _load_sector_atlas()

func _load_sector_atlas():
    var atlas = _load_json("res://Space/data/systems/sector_atlas.json")
    if not atlas.is_empty():
        systems = atlas
        var first_key = atlas.keys()[0] if not atlas.is_empty() else ""
        if first_key != "" and GameManager.current_system == "":
            GameManager.current_system = first_key
            GameManager.visited_systems = [first_key]

# Reads the active pack's Factions/factions.json into galaxy_data["factions"].
# Called by MvPackLoader.load_pack right after current_pack is assigned, so
# every consumer of DataManager.galaxy_data.get("factions", {}) sees the
# pack's authored faction table before runtime code (npc_ship, station_entity,
# star_map, etc.) starts dereferencing it. Empty result is fine — runtime
# lookups already fall back to per-call defaults for unknown ids.
func load_pack_factions(pack_id: String) -> void:
    var factions := FactionsIO.load_or_empty(pack_id)
    galaxy_data["factions"] = factions

func get_loot_table(threat: int) -> Array:
    var tables = loot_data.get("tables", {})
    var key = str(threat)
    if tables.has(key):
        return tables[key]
    return tables.get("1", [])

func get_drop_chance(threat: int) -> float:
    var base = loot_data.get("drop_chance_base", 0.25)
    var per = loot_data.get("drop_chance_per_threat", 0.05)
    return base + threat * per

func get_shop_stock(system_id: String) -> Array:
    var stock = loot_data.get("shop_stock", {}).get(system_id, [])
    if stock.is_empty() and systems.has(system_id):

        stock = _gen_shop_stock(system_id)
    return stock

func _gen_shop_stock(system_id: String) -> Array:
    var sys = systems.get(system_id, {})
    var threat = int(sys.get("threat_level", 1))
    var rng = RandomNumberGenerator.new()
    rng.seed = system_id.hash()
    var stock: Array = []

    var basics = ["conduit_mk1", "armor_plate_mk1", "pulse_laser_mk1", "shield_gen_mk1", "thruster_mk1", "micro_reactor"]
    for b in basics:
        if rng.randf() < 0.6:
            stock.append(b)

    var facilities = ["crew_quarters_mk1", "mess_hall_mk1", "life_support_mk1", "cargo_bay_mk1"]
    for f in facilities:
        if rng.randf() < 0.4:
            stock.append(f)

    if threat >= 2:
        var mk2s = ["autocannon_mk1", "sensor_mk1", "fuel_scoop_mk1", "mining_laser_mk1"]
        for m in mk2s:
            if rng.randf() < 0.35:
                stock.append(m)
    if threat >= 3:
        var advanced = ["reactor_mk2", "thruster_mk2", "shield_gen_mk2", "fuel_scoop_mk2", "mining_laser_mk2"]
        for a in advanced:
            if modules.has(a) and rng.randf() < 0.25:
                stock.append(a)
    return stock

func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_warning("Data file not found: " + path)
        return {}
    var file = FileAccess.open(path, FileAccess.READ)
    var text = file.get_as_text()
    file.close()
    var json = JSON.new()
    var err = json.parse(text)
    if err != OK:
        push_error("JSON parse error in %s: %s" % [path, json.get_error_message()])
        return {}
    return json.data

func get_random_bark(crew_id: String, category: String) -> String:
    if not crew.has(crew_id):
        return ""
    var member = crew[crew_id]
    if not member.has("barks") or not member["barks"].has(category):
        return ""
    var barks: Array = member["barks"][category]
    if barks.is_empty():
        return ""
    return barks.pick_random()

func get_crew_name(crew_id: String) -> String:
    if crew.has(crew_id):
        return crew[crew_id].get("short_name", crew_id)
    return crew_id

func get_available_missions(system_id: String) -> Array:

    generate_radiant_missions(system_id)
    var available: Array = []
    var sys = systems.get(system_id, {})
    var threat = sys.get("threat_level", 1)
    for mid in missions:
        var m = missions[mid]
        if m.get("min_threat", 0) > threat:
            continue

        var avail_at = m.get("available_at", "")
        if avail_at != "" and avail_at != system_id:
            continue
        var mtype = m.get("type", "")
        match mtype:
            "cargo_haul":
                if m.get("origin_system", "") == system_id:
                    available.append(mid)
            "bounty":
                available.append(mid)
            "salvage":
                available.append(mid)
            "gather":
                available.append(mid)
    return available



# The STAR_PREFIXES / STAR_SUFFIXES / STAR_TAGS / STAR_CLASSES /
# FACTION_NAMES / POI_TEMPLATES / PLANET_THEMES / DESCRIPTIONS constants
# used to live here as procedural galaxy-generation data. Deleted with
# the procedural new-game flow; system content is now per-pack authored
# via systems.json + the System Editor.


const GENERIC_EVENTS: Dictionary = {
    "proc_station": {
        "title": "Station", 
        "nodes": {
            "start": {
                "text": "You dock at the station. The air recyclers hum as the airlock cycles. What do you need?", 
                "choices": [
                    {"label": "Browse the shop", "effects": [{"type": "open_shop"}]}, 
                    {"label": "Check the mission board", "effects": [{"type": "open_missions"}]}, 
                    {"label": "Undock", "next": ""}
                ]
            }
        }
    }, 
    "proc_salvage": {
        "title": "Salvage Site", 
        "nodes": {
            "start": {
                "text": "Twisted metal and frozen cargo drift in the void. Your scanners pick up useful materials.", 
                "choices": [
                    {"label": "Search the wreckage", "next": "search"}, 
                    {"label": "Leave it alone", "next": ""}
                ]
            }, 
            "search": {
                "text": "Your crew pulls in some useful components from the wreckage.", 
                "effects": [{"type": "give_module", "module_id": "conduit_mk1", "count": 1}], 
                "choices": [{"label": "Continue", "next": ""}]
            }
        }
    }, 
    "proc_anomaly": {
        "title": "Anomaly", 
        "nodes": {
            "start": {
                "text": "Strange readings emanate from this location. The instruments can't agree on what they're seeing.", 
                "choices": [
                    {"label": "Investigate closer", "next": "investigate"}, 
                    {"label": "Keep your distance", "next": ""}
                ]
            }, 
            "investigate": {
                "text": "The anomaly surges — your shields flare but hold. Your sensors captured valuable data.", 
                "effects": [{"type": "repair", "amount": 20}], 
                "choices": [{"label": "Continue", "next": ""}]
            }
        }
    }, 
    "proc_ruin": {
        "title": "Ancient Ruins", 
        "nodes": {
            "start": {
                "text": "Pre-human structures float silently in space. Their purpose is unknown, but their construction is remarkable.", 
                "choices": [
                    {"label": "Send a team to explore", "next": "explore"}, 
                    {"label": "Move on", "next": ""}
                ]
            }, 
            "explore": {
                "text": "The ruins yield nothing obvious, but your engineer is fascinated by the alloy composition. Morale improves.", 
                "choices": [{"label": "Continue", "next": ""}]
            }
        }
    }, 
    "proc_resource": {
        "title": "Resource Deposit", 
        "nodes": {
            "start": {
                "text": "Your sensors detect rich deposits here — minerals, gases, and other extractable materials. Worth stopping for.", 
                "choices": [
                    {"label": "Mine the deposit", "next": "mine"}, 
                    {"label": "Move on", "next": ""}
                ]
            }, 
            "mine": {
                "text": "Your crew extracts a haul of useful materials from the deposit.", 
                "effects": [{"type": "give_resource_random", "min": 3, "max": 8}], 
                "choices": [{"label": "Good haul.", "next": ""}]
            }
        }
    }, 
    "proc_debris_field": {
        "title": "Debris Field", 
        "nodes": {
            "start": {
                "text": "A massive field of shattered hulls and torn metal stretches before you. The remains of a battle or a catastrophe — hard to tell which.", 
                "choices": [
                    {"label": "Pick through the wreckage", "next": "search"}, 
                    {"label": "Scan from a safe distance", "next": "scan"}, 
                    {"label": "Too dangerous. Move on.", "next": ""}
                ]
            }, 
            "search": {
                "text": "Your crew navigates the debris carefully. Between hull fragments and frozen cargo, they find salvageable components.", 
                "effects": [{"type": "give_resource_random", "min": 2, "max": 6}], 
                "choices": [{"label": "Take what we can carry.", "next": ""}]
            }, 
            "scan": {
                "text": "Long-range scans pick up a few intact cargo pods on the edge of the field. Easy retrieval.", 
                "effects": [{"type": "give_resource_random", "min": 1, "max": 3}], 
                "choices": [{"label": "Grab them and go.", "next": ""}]
            }
        }
    }, 
    "proc_derelict": {
        "title": "Derelict Ship", 
        "nodes": {
            "start": {
                "text": "A dead ship drifts in the void. Running lights off, no transponder. Hull intact but scarred. No life signs.", 
                "choices": [
                    {"label": "Board and search", "next": "board"}, 
                    {"label": "Strip the hull externally", "next": "strip"}, 
                    {"label": "Leave it. Could be a trap.", "next": ""}
                ]
            }, 
            "board": {
                "text": "The interior is dark and cold. Emergency lights flicker. Your team finds the cargo bay — still loaded.", 
                "effects": [{"type": "give_module", "module_id": "conduit_mk1", "count": 2}, {"type": "give_resource_random", "min": 3, "max": 8}], 
                "choices": [{"label": "Good haul. Pull out.", "next": ""}]
            }, 
            "strip": {
                "text": "External salvage yields hull plating and some intact conduits. Quick and safe.", 
                "effects": [{"type": "give_module", "module_id": "conduit_mk1", "count": 1}], 
                "choices": [{"label": "Better than nothing.", "next": ""}]
            }
        }
    }, 
    "proc_distress_signal": {
        "title": "Distress Signal", 
        "nodes": {
            "start": {
                "text": "An automated distress beacon pulses on emergency frequencies. The signal is weak — could be hours or days old.", 
                "choices": [
                    {"label": "Move in to investigate", "next": "investigate"}, 
                    {"label": "It could be bait. Ignore it.", "next": ""}
                ]
            }, 
            "investigate": {
                "text": "You find a damaged shuttle — two survivors in cryo pods. They're alive but in rough shape.", 
                "choices": [
                    {"label": "Bring them aboard", "next": "rescue"}, 
                    {"label": "Take their supplies and leave", "next": "loot"}
                ]
            }, 
            "rescue": {
                "text": "The survivors recover in your medbay. Grateful, they offer to join your crew — or at least share what credits they have.", 
                "effects": [{"type": "credits", "amount": 50}], 
                "choices": [{"label": "Welcome aboard.", "next": ""}]
            }, 
            "loot": {
                "text": "The shuttle has some fuel and supplies. Your crew is quiet about it.", 
                "effects": [{"type": "give_resource_random", "min": 2, "max": 5}], 
                "choices": [{"label": "Move on.", "next": ""}]
            }
        }
    }, 
}



const FACTION_SPEAKERS: Dictionary = {
    "terran_union": ["Union Officer", "Commander", "Quartermaster"], 
    "independent": ["Station Boss", "Bartender", "Fixer"], 
    "korrath": ["Korrath Overseer", "Warden", "Korrath Trader"], 
    "syndicate": ["Broker", "Handler", "Syndicate Contact"], 
    "nomads": ["Elder", "Nomad Chief", "Trade Speaker"], 
    "free_traders": ["Dock Chief", "Merchant Prince", "Trade Captain"], 
    "void_church": ["Acolyte", "Void Priest", "Oracle"], 
    "iron_pact": ["Iron Marshal", "Forge Master", "Pact Enforcer"], 
    "uncharted": ["Lone Spacer", "Scavenger", "Drifter"], 
}

const STATION_ARRIVALS: Array = [
    "Dock clamps engage. The air is stale but warm. %s doesn't see many visitors.", 
    "The airlock cycles. Fluorescent light and engine grease. %s is busier than expected.", 
    "A dock worker waves you in. Carbon scoring marks the walls — recent combat damage.", 
    "Your ship settles into the cradle. A display scrolls: 'Welcome to %s. Weapons cold, credits ready.'", 
    "The station hums. Traders argue over prices while mechanics crawl over damaged ships.", 
    "Half the bays sit dark. A tech looks up from a sparking panel. 'Haven't had a ship in weeks.'", 
    "Docking is smooth. %s runs tight — clean corridors, guards at every junction.", 
    "Barely through the airlock and the noise hits. Traders, mechanics, three languages. %s is a crossroads.", 
    "Port authority waves you through without checking your manifest. Relaxed security or an invitation.", 
    "Ships crowd the ring. Miners, traders, a military corvette that's seen better days.", 
]

const STATION_ENCOUNTERS: Array = [
    {"label": "Talk to a stranger watching your ship", "type": "stranger"}, 
    {"label": "Answer the open distress frequency", "type": "distress"}, 
    {"label": "Hear out a trader with surplus stock", "type": "merchant"}, 
    {"label": "Join a table of off-duty spacers", "type": "rumor"}, 
    {"label": "Check the station supply depot", "type": "supply"}, 
]

const SALVAGE_OPENINGS: Array = [
    {"text": "A cargo hauler drifts dead ahead, hull breached and venting. No transponder. Whatever happened was fast.", "speaker": "Sensor Officer"}, 
    {"text": "The wreck spins slowly. Blast marks along the hull tell the story. Days old at least.", "speaker": "Navigator"}, 
    {"text": "Twisted metal and frozen cargo spread across kilometers. Someone's fleet took heavy losses.", "speaker": ""}, 
    {"text": "Sensors light up with contacts — all debris. An entire convoy, torn apart.", "speaker": "Sensor Officer"}, 
    {"text": "Power running through that hull, but no life signs. Running lights blink in an automated pattern.", "speaker": "Science Officer"}, 
    {"text": "A ship, intact and powered, drifting without course corrections. Crew either dead or gone.", "speaker": "First Mate"}, 
    {"text": "Something big went down hard here. The impact crater is still warm, radiation spiking.", "speaker": ""}, 
    {"text": "Fragments scattered across the asteroid surface. The black box should still be intact.", "speaker": "Engineer"}, 
    {"text": "A fleet tender, split clean in half. Both sections still have atmosphere in sealed compartments.", "speaker": "Sensor Officer"}, 
    {"text": "Mining rig, abandoned in haste. Tools still magnetic-locked to the hull. Someone left fast.", "speaker": "Engineer"}, 
    {"text": "Three ships, locked together by collision. Impact foam hardened around the junction. Messy.", "speaker": "Navigator"}, 
    {"text": "A luxury yacht, completely intact. No crew, no logs, food still warm in the galley.", "speaker": "First Mate"}, 
]

const ANOMALY_OPENINGS: Array = [
    {"text": "Instruments are haywire. Magnetic readings off the scale, gravitational lensing visible to the naked eye.", "speaker": "Science Officer"}, 
    {"text": "Something is out there. Sensors can't agree — mass readings shift every few seconds.", "speaker": "Navigator"}, 
    {"text": "A pocket of folded space. Your ship's clock is already drifting. This is bending reality.", "speaker": "Science Officer"}, 
    {"text": "Radiation bursts in a repeating pattern. Too regular to be natural. Something is broadcasting.", "speaker": "Sensor Officer"}, 
    {"text": "The void looks different here. Stars behind the anomaly are shifted, light bent around something invisible.", "speaker": ""}, 
    {"text": "Your shields fluctuate without cause. Energy drawn from somewhere — or pushed into your systems.", "speaker": "Engineer"}, 
    {"text": "A dark spot in space. No light, no emissions, no mass. But something is there.", "speaker": ""}, 
    {"text": "Quantum interference scrambles comms. Short-range shows a sphere of distorted space, 200 meters across.", "speaker": "Science Officer"}, 
    {"text": "Time dilation. Your chronometer and the nav computer disagree by eleven minutes. And counting.", "speaker": "Navigator"}, 
    {"text": "A sphere of perfect darkness. No reflection, no emission. It eats light.", "speaker": "Science Officer"}, 
    {"text": "Gravity waves pulse outward in concentric rings. Something at the center is breathing.", "speaker": ""}, 
    {"text": "Your crew reports déjà vu. All of them. At the same moment. Instruments confirm a temporal echo.", "speaker": "Science Officer"}, 
]

const RUIN_OPENINGS: Array = [
    {"text": "A structure hangs in the void, impossibly old. Surfaces smooth, unmarred by micrometeorites. Not human.", "speaker": "Science Officer"}, 
    {"text": "The construct is enormous — crystalline spars and alloy lattice. Scanners date it at twelve thousand years.", "speaker": ""}, 
    {"text": "A monolith of dark stone, covered in symbols that glow when your sensors sweep over them.", "speaker": "Science Officer"}, 
    {"text": "Partially collapsed, but one chamber appears sealed and pressurized. Built to last.", "speaker": ""}, 
    {"text": "A relay of some kind. Pre-human tech, still drawing power from an unidentifiable internal source.", "speaker": "Engineer"}, 
    {"text": "The structure pulses with dim light at regular intervals. Like a heartbeat. Like it's waiting.", "speaker": ""}, 
    {"text": "The geometry defies known engineering. Whatever species built this understood physics we don't.", "speaker": "First Mate"}, 
    {"text": "Carved from a single piece of unidentifiable material. Its surface is warm to the touch.", "speaker": "Science Officer"}, 
    {"text": "An orbital ring, shattered but still rotating. Sections are pressurized, lit from within.", "speaker": "Sensor Officer"}, 
    {"text": "Geometric patterns etched into an asteroid. Not natural. The angles are mathematically perfect.", "speaker": "Science Officer"}, 
    {"text": "A beacon, ancient beyond measure. It activates when your ship approaches, broadcasting coordinates.", "speaker": "Navigator"}, 
    {"text": "Machinery of unknown origin, partially buried in a moon's surface. Still warm. Still running.", "speaker": "Engineer"}, 
]

const RESOURCE_OPENINGS: Array = [
    {"text": "Rich deposits ahead. Mining sensors paint the rocks like a treasure map — thick veins.", "speaker": "Mining Chief"}, 
    {"text": "Dense asteroid cluster, each one packed with extractable materials. Good haul if you stop.", "speaker": "Engineer"}, 
    {"text": "Gas clouds swirl around mineral-rich formations. Composition readings are promising.", "speaker": "Navigator"}, 
    {"text": "Crystal formations jut from the surface, catching starlight. Valuable and beautiful.", "speaker": ""}, 
    {"text": "The deposit stretches several hundred meters. More than you can carry, but worth stopping for.", "speaker": "Mining Chief"}, 
    {"text": "Scans show a mix of heavy metals and rare compounds. Some of this is worth real money.", "speaker": "Sensor Officer"}, 
    {"text": "A comet trail loaded with rare isotopes. Easy pickings if you match its velocity.", "speaker": "Navigator"}, 
    {"text": "Volcanic vents on a nearby moon are spewing mineral-rich plumes into orbit. Free resources.", "speaker": "Science Officer"}, 
    {"text": "An ice field riddled with metallic inclusions. Every chunk is worth cracking open.", "speaker": "Mining Chief"}, 
    {"text": "Sensor ghosts resolve into a motherlode. This belt hasn't been touched. Everything here is yours.", "speaker": ""}, 
]

const OUTCOME_TEXTS: Dictionary = {
    "salvage_board_good": [
        "Boarding party reports back. Cargo bay's half full — sealed crates, intact. Good find.", 
        "Your crew finds sealed containers in the engine room. Whoever left these was in a hurry.", 
        "The ship's armory was untouched. Your team hauls back what they can carry.", 
        "Between cargo hold and medbay, your crew pulls a solid haul of useful gear.", 
    ], 
    "salvage_board_bad": [
        "The hull groans. A bulkhead collapses. They pull back, shaken and bruised.", 
        "Booby-trapped. Airlock seals, explosive decompression rips through the corridor. They barely make it.", 
        "Structural failure. Deck gives way, crew drops two levels. They're hurt.", 
        "Automated defenses still active. Sentry fire before they can disable them.", 
    ], 
    "salvage_scan": [
        "External scans reveal components bolted to the outer hull. Cut free without going inside.", 
        "Careful scanning finds a detached cargo pod. Easy retrieval, minimal risk.", 
        "Strip what you can from outside. Not a fortune, but solid work.", 
        "A sealed crate wedged in the wreckage. Careful maneuvering and it's yours.", 
    ], 
    "anomaly_good": [
        "Shields channel the energy surge. When it settles, your capacitors are overcharged.", 
        "Sensors capture a data burst. Cross-referencing reveals navigational data worth credits.", 
        "The anomaly pulses once, hard. Hull rings — but your engineer is grinning. Free energy.", 
        "Careful approach pays off. The energy patterns encode what looks like an ancient star map.", 
    ], 
    "anomaly_bad": [
        "The anomaly collapses inward, then erupts. Shields buckle. Hull takes a hit.", 
        "Reality tears. When it snaps back, instruments are fried and hull is scorched.", 
        "A gravitational spike yanks the ship sideways. Armor buckles, systems spark.", 
        "Field reverses polarity. Power grid overloads. You barely pull away.", 
    ], 
    "anomaly_observe": [
        "From safe distance, sensors collect detailed readings. Enough data to sell.", 
        "Passive observation captures frequency patterns. Could be worth something.", 
        "You log readings and move on. Safe approach, small reward. Smart play.", 
        "Data collected at range is limited but clean. Good enough for a payout.", 
    ], 
    "ruin_good": [
        "Deep inside, a sealed chamber. Within it, alien technology — still functional after millennia.", 
        "The ruins yield an alloy that shouldn't exist. Its properties could be revolutionary.", 
        "In the structure's heart, a technology repository. Some is beyond understanding, some applicable.", 
        "A vault sealed for thousands of years. Inside: components of unknown material.", 
    ], 
    "ruin_bad": [
        "Defense systems awaken. Crystalline turrets force your team into a fighting retreat.", 
        "The floor gives way. Crew drops into a lower chamber as the structure seals above.", 
        "Something stirs in the dark. Your team comes back shaken, refusing to talk about it.", 
        "Ancient containment fails. Whatever was inside is now on your hull, eating into armor.", 
    ], 
    "ruin_study": [
        "Remote scans capture surface details — patterns, composition. Academic interest.", 
        "You catalog the exterior and sell coordinates to researchers.", 
        "Symbols resist translation, but structural data alone is worth documenting.", 
        "Passive scanning reveals age and composition. A xeno-archaeologist would pay for this.", 
    ], 
    "resource_mine": [
        "Your crew sets to work. The deposit yields a solid haul.", 
        "Mining goes smoothly. Rich vein, clean extraction.", 
        "Straightforward extraction. Good ore, easy access. Hold fills up.", 
        "Laser cutters and cargo drones make quick work of it.", 
    ], 
    "resource_deep_good": [
        "Drilling deeper pays off. The core is incredibly rich — premium grade.", 
        "Beneath the surface layer, composition shifts to something far more valuable.", 
        "The deposit runs deeper than expected. A bounty of high-quality resources.", 
        "Full extraction reveals rare compounds hidden beneath common ore.", 
    ], 
    "resource_deep_bad": [
        "The formation is unstable. A collapse sends fragments hammering your hull.", 
        "Drilling triggers a gas pocket eruption. Your ship takes a beating.", 
        "The deposit crumbles mid-extraction. An asteroid chunk clips your hull.", 
        "Rock shelf fractures. Your ship is caught in the cascade.", 
    ], 
}

const RUMOR_TEXTS: Array = [
    "Word is there's a derelict loaded with pre-war tech. Nobody's been crazy enough to go after it.", 
    "The factions have been moving ships through here. Something big is coming.", 
    "A crew came through last week, half dead. Said they found something alive out in the deep.", 
    "Fuel prices are about to spike. Supply ships keep getting hit.", 
    "There's a bounty on a pirate captain in this sector. Big money for the fighting type.", 
    "Ancient tech buried on one of the planets around here. Precursor stuff, they say.", 
    "Don't trust the nav beacons in the outer systems. Someone's been moving them.", 
    "The Void Church is buying alien artifacts. No questions asked. Top credit.", 
    "A convoy vanished last month. No wreckage, no distress call. Just gone.", 
    "The nomads know routes through the deep that aren't on any chart. For a price.", 
]

const MISSION_GIVERS: Dictionary = {
    "terran_union": ["Commander Voss", "Admiral Chen", "Lt. Mercer", "Union Dispatch", "Captain Okafor"], 
    "independent": ["Station Control", "Frontier Council", "Old Yara", "Fixer Dax", "Harbor Master"], 
    "korrath": ["Warlord Thane", "Korrath Command", "Overseer Zel", "War Council"], 
    "syndicate": ["The Broker", "Handler Nyx", "Syndicate Board", "Shadow Contact"], 
    "nomads": ["Elder Soren", "Pathfinder Kai", "Trade Council", "Nomad Speaker"], 
    "free_traders": ["Guild Master", "Trade Captain", "Merchant Pax", "Factor Stel"], 
    "void_church": ["Oracle Mira", "High Priest", "Temple Authority", "Voice of the Void"], 
    "iron_pact": ["Forge Master", "Iron Marshal", "Commander Torr", "Pact Authority"], 
    "uncharted": ["Anonymous", "Dead Drop", "Signal Source", "Lone Operator"], 
}

const BOUNTY_TARGETS: Array = [
    "pirate patrols", "raider squads", "hostile fighters", "bandit wings", 
    "corsair packs", "rogue drones", "marauder ships", "outlaw convoys", 
]

const BOUNTY_REASONS: Array = [
    "They've been disrupting trade routes.", 
    "Merchant convoys are taking losses.", 
    "Local settlements can't hold them off.", 
    "Our patrols can't cover this sector.", 
    "Intelligence suggests they're planning a raid.", 
    "They hit a supply ship last week.", 
    "The bounty board's been listing them for months.", 
    "Colonists need breathing room.", 
]

const CARGO_GOODS: Array = [
    {"id": "medical", "name": "Medical Supplies"}, 
    {"id": "parts", "name": "Ship Components"}, 
    {"id": "food_crates", "name": "Ration Crates"}, 
    {"id": "equipment", "name": "Mining Equipment"}, 
    {"id": "electronics", "name": "Electronics"}, 
    {"id": "weapons", "name": "Weapons Crate"}, 
    {"id": "fuel_cells", "name": "Fuel Cells"}, 
    {"id": "settlers", "name": "Settler Supplies"}, 
    {"id": "data_cores", "name": "Data Cores"}, 
    {"id": "refugees", "name": "Passengers"}, 
]

func _pick_from(pool: Array, rng: RandomNumberGenerator):
    return pool[rng.randi() % pool.size()]

func _pick_text(key: String, rng: RandomNumberGenerator) -> String:
    var pool: Array = OUTCOME_TEXTS.get(key, ["..."])
    return pool[rng.randi() % pool.size()]

func _faction_speaker(faction: String, rng: RandomNumberGenerator) -> String:
    var speakers: Array = FACTION_SPEAKERS.get(faction, FACTION_SPEAKERS["independent"])
    return speakers[rng.randi() % speakers.size()]

func generate_proc_event(event_type: String, poi_name: String, sys_data: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
    var sys_name = sys_data.get("name", "Unknown")
    var faction = sys_data.get("faction", "independent")
    var threat = int(sys_data.get("threat_level", 1))
    match event_type:
        "station", "hostile_station":
            return _gen_station_event(poi_name, sys_name, faction, threat, rng)
        "salvage":
            return _gen_salvage_event(poi_name, threat, rng)
        "anomaly":
            return _gen_anomaly_event(poi_name, threat, rng)
        "ruin":
            return _gen_ruin_event(poi_name, threat, rng)
        "resource":
            return _gen_resource_event(poi_name, threat, rng)
    return {"title": poi_name, "nodes": {"start": {"text": "Nothing of note.", "choices": [{"label": "Leave", "next": ""}]}}}

func _gen_station_event(poi_name: String, _sys_name: String, faction: String, threat: int, rng: RandomNumberGenerator) -> Dictionary:
    var arrival_t: String = _pick_from(STATION_ARRIVALS, rng)
    var arrival = arrival_t.replace("%s", poi_name)
    var speaker = _faction_speaker(faction, rng)
    var nodes: Dictionary = {}
    var choices: Array = []

    if rng.randf() < 0.4:
        var enc: Dictionary = _pick_from(STATION_ENCOUNTERS, rng)
        choices.append({"label": enc["label"], "next": "encounter"})
        var enc_type: String = enc.get("type", "rumor")
        match enc_type:
            "stranger":
                var reward = 20 + threat * 15
                nodes["encounter"] = {
                    "text": "A weathered spacer slides over. 'Heard you get things done. Got coordinates to a cache — yours. Professional courtesy.'", 
                    "speaker": "Spacer", 
                    "effects": [{"type": "give_credits", "amount": reward}], 
                    "choices": [{"label": "Pocket the data (+%d cr)" % reward, "next": ""}]
                }
            "distress":
                var roles: Array = ["engineer", "gunner", "medic", "deckhand", "marine", "pilot"]
                var role: String = _pick_from(roles, rng)
                nodes["encounter"] = {
                    "text": "A weak signal from system's edge. Someone stranded — engine failure, running out of air.", 
                    "speaker": "Comm Officer", 
                    "choices": [
                        {"label": "Launch a rescue", "next": "enc_rescue"}, 
                        {"label": "Report it to station authority", "next": "enc_report"}, 
                    ]
                }
                nodes["enc_rescue"] = {
                    "text": "You found them — a lone %s in a crippled shuttle. Grateful and willing to sign on." % role, 
                    "speaker": "Rescued Spacer", 
                    "effects": [{"type": "give_crew", "role": role}], 
                    "choices": [{"label": "Welcome aboard", "next": ""}]
                }
                nodes["enc_report"] = {
                    "text": "Station dispatches a rescue tug. They transfer a small finder's fee.", 
                    "effects": [{"type": "give_credits", "amount": 15 + threat * 5}], 
                    "choices": [{"label": "Continue", "next": ""}]
                }
            "merchant":
                var mod_pool: Array = ["conduit_mk1", "armor_plate_mk1"]
                if threat >= 2:
                    mod_pool.append_array(["pulse_laser_mk1", "shield_gen_mk1"])
                var mod_id: String = _pick_from(mod_pool, rng)
                var mod_name = modules.get(mod_id, {}).get("name", mod_id)
                nodes["encounter"] = {
                    "text": "A trader pulls you aside. 'Surplus from a cancelled contract. Take it — I just need the bay space.'", 
                    "speaker": "Trader", 
                    "effects": [{"type": "give_module", "module_id": mod_id, "count": 1}], 
                    "choices": [{"label": "Take the %s" % mod_name, "next": ""}]
                }
            "rumor":
                var rumor: String = _pick_from(RUMOR_TEXTS, rng)
                nodes["encounter"] = {
                    "text": rumor, 
                    "speaker": "Off-Duty Spacer", 
                    "choices": [{"label": "Thanks for the intel", "next": ""}]
                }
            "supply":
                nodes["encounter"] = {
                    "text": "The quartermaster checks inventory. 'Got surplus rations and fuel cells. Yours if you want them.'", 
                    "speaker": "Quartermaster", 
                    "effects": [{"type": "give_fuel", "amount": 5}, {"type": "give_food", "amount": 5}], 
                    "choices": [{"label": "Much appreciated", "next": ""}]
                }

    choices.append({"label": "Request docking clearance", "next": "dock_granted"})
    choices.append({"label": "Move on", "next": ""})
    nodes["dock_granted"] = {
        "text": "\"Clearance granted, proceed to docking bay %d. Welcome to %s.\"" % [rng.randi_range(1, 12), poi_name], 
        "speaker": speaker, 
        "effects": [{"type": "enter_station"}], 
        "choices": [{"label": "Dock", "next": ""}]
    }
    nodes["start"] = {"text": arrival, "speaker": speaker, "choices": choices}
    return {"title": poi_name, "nodes": nodes}

func _gen_salvage_event(poi_name: String, threat: int, rng: RandomNumberGenerator) -> Dictionary:
    var opening: Dictionary = _pick_from(SALVAGE_OPENINGS, rng)
    var nodes: Dictionary = {}
    var common: Array = ["conduit_mk1", "armor_plate_mk1"]
    var good: Array = ["pulse_laser_mk1", "shield_gen_mk1", "thruster_mk1", "sensor_mk1"]
    var great: Array = ["autocannon_mk1", "fuel_scoop_mk1", "mining_laser_mk1", "repair_module_mk1"]
    var scan_mod: String = _pick_from(common, rng)
    var board_mod: String = _pick_from(good, rng)
    if threat >= 3:
        board_mod = _pick_from(great, rng)
    var board_success = rng.randf() < (0.65 - float(threat) * 0.05)
    var start_choices: Array = [
        {"label": "Board and search the interior", "next": "board"}, 
        {"label": "Scan and salvage from outside", "next": "scan"}, 
        {"label": "Leave it alone", "next": ""}, 
    ]
    if rng.randf() < 0.25:
        var roles: Array = ["engineer", "gunner", "medic", "deckhand", "marine"]
        var role: String = _pick_from(roles, rng)
        start_choices.insert(1, {"label": "Check for survivors first", "next": "survivors"})
        nodes["survivors"] = {
            "text": "Life signs! Faint but there. Your crew pulls a survivor — barely conscious. A %s by their uniform." % role, 
            "speaker": "Medical Officer", 
            "choices": [
                {"label": "Take them aboard", "next": "survivor_rescue"}, 
                {"label": "Not our problem", "next": ""}, 
            ]
        }
        nodes["survivor_rescue"] = {
            "text": "The survivor comes to in your medbay. Grateful — and willing to join your crew.", 
            "effects": [{"type": "give_crew", "role": role}], 
            "choices": [{"label": "Welcome aboard, spacer", "next": ""}]
        }
    nodes["start"] = {"text": opening.get("text", "Wreckage ahead."), "speaker": opening.get("speaker", ""), "choices": start_choices}
    if board_success:
        var mod_name = modules.get(board_mod, {}).get("name", board_mod)
        nodes["board"] = {
            "text": _pick_text("salvage_board_good", rng), "speaker": "Boarding Party", 
            "effects": [{"type": "give_module", "module_id": board_mod, "count": 1}], 
            "choices": [{"label": "Haul it back (+%s)" % mod_name, "next": ""}]
        }
    else:
        nodes["board"] = {
            "text": _pick_text("salvage_board_bad", rng), "speaker": "Boarding Party", 
            "effects": [{"type": "damage_hull", "amount": 15 + threat * 5}], 
            "choices": [{"label": "Fall back!", "next": "board_retreat"}]
        }
        nodes["board_retreat"] = {
            "text": "Crew pulls back, battered. They grabbed a few components on the way out.", 
            "effects": [{"type": "give_module", "module_id": _pick_from(common, rng), "count": 1}], 
            "choices": [{"label": "At least we got something", "next": ""}]
        }
    nodes["scan"] = {
        "text": _pick_text("salvage_scan", rng), "speaker": "Sensor Officer", 
        "effects": [{"type": "give_module", "module_id": scan_mod, "count": 1}], 
        "choices": [{"label": "Good enough", "next": ""}]
    }
    return {"title": poi_name, "nodes": nodes}

func _gen_anomaly_event(poi_name: String, threat: int, rng: RandomNumberGenerator) -> Dictionary:
    var opening: Dictionary = _pick_from(ANOMALY_OPENINGS, rng)
    var credit_reward = 40 + threat * 25
    var investigate_success = rng.randf() < (0.6 - float(threat) * 0.05)
    var nodes: Dictionary = {}
    nodes["start"] = {"text": opening.get("text", "Strange readings."), "speaker": opening.get("speaker", ""), 
        "choices": [
            {"label": "Move in to investigate", "next": "investigate"}, 
            {"label": "Observe from safe distance", "next": "observe"}, 
            {"label": "Not worth the risk", "next": ""}, 
        ]}
    if investigate_success:
        nodes["investigate"] = {"text": _pick_text("anomaly_good", rng), "speaker": "Science Officer", 
            "effects": [{"type": "give_credits", "amount": credit_reward}, {"type": "repair", "amount": 15}], 
            "choices": [{"label": "Log the data (+%d cr)" % credit_reward, "next": ""}]}
    else:
        var damage = 20 + threat * 8
        nodes["investigate"] = {"text": _pick_text("anomaly_bad", rng), "speaker": "Engineer", 
            "effects": [{"type": "damage_hull", "amount": damage}], 
            "choices": [{"label": "Pull back!", "next": "inv_retreat"}]}
        var partial = int(credit_reward * 0.3)
        nodes["inv_retreat"] = {"text": "Sensors captured some data before things went sideways. Not a total loss.", 
            "effects": [{"type": "give_credits", "amount": partial}], 
            "choices": [{"label": "Better than nothing (+%d cr)" % partial, "next": ""}]}
    var observe_reward = int(credit_reward * 0.5)
    nodes["observe"] = {"text": _pick_text("anomaly_observe", rng), "speaker": "Science Officer", 
        "effects": [{"type": "give_credits", "amount": observe_reward}], 
        "choices": [{"label": "Move on (+%d cr)" % observe_reward, "next": ""}]}
    return {"title": poi_name, "nodes": nodes}

func _gen_ruin_event(poi_name: String, threat: int, rng: RandomNumberGenerator) -> Dictionary:
    var opening: Dictionary = _pick_from(RUIN_OPENINGS, rng)
    var explore_success = rng.randf() < (0.55 - float(threat) * 0.05)
    var credit_reward = 30 + threat * 15
    var reward_mod = "sensor_mk1"
    if threat >= 2:
        reward_mod = _pick_from(["ecm_jammer_mk1", "repair_module_mk1", "sensor_mk1"], rng)
    if threat >= 4:
        reward_mod = _pick_from(["beam_emitter_mk1", "point_defense_mk1", "afterburner_mk1"], rng)
    var nodes: Dictionary = {}
    nodes["start"] = {"text": opening.get("text", "Ancient structure."), "speaker": opening.get("speaker", ""), 
        "choices": [
            {"label": "Send a team to explore inside", "next": "explore"}, 
            {"label": "Study from the ship", "next": "study"}, 
            {"label": "Move on", "next": ""}, 
        ]}
    if explore_success:
        var mod_name = modules.get(reward_mod, {}).get("name", reward_mod)
        nodes["explore"] = {"text": _pick_text("ruin_good", rng), "speaker": "Exploration Team", 
            "effects": [{"type": "give_module", "module_id": reward_mod, "count": 1}], 
            "choices": [{"label": "Secure the find (+%s)" % mod_name, "next": ""}]}
    else:
        nodes["explore"] = {"text": _pick_text("ruin_bad", rng), "speaker": "Exploration Team", 
            "effects": [{"type": "damage_hull", "amount": 15 + threat * 5}], 
            "choices": [{"label": "Fall back and regroup", "next": "explore_retreat"}]}
        nodes["explore_retreat"] = {"text": "Team pulls out shaken, but they grabbed fragments on the way.", 
            "effects": [{"type": "give_resource_random", "min": 2, "max": 5}], 
            "choices": [{"label": "Something is better than nothing", "next": ""}]}
    nodes["study"] = {"text": _pick_text("ruin_study", rng), "speaker": "Science Officer", 
        "effects": [{"type": "give_credits", "amount": credit_reward}], 
        "choices": [{"label": "Log the findings (+%d cr)" % credit_reward, "next": ""}]}
    return {"title": poi_name, "nodes": nodes}

func _gen_resource_event(poi_name: String, threat: int, rng: RandomNumberGenerator) -> Dictionary:
    var opening: Dictionary = _pick_from(RESOURCE_OPENINGS, rng)
    var deep_success = rng.randf() < (0.6 - float(threat) * 0.04)
    var base_min = 3 + threat
    var base_max = 6 + threat * 2
    var nodes: Dictionary = {}
    nodes["start"] = {"text": opening.get("text", "Deposits ahead."), "speaker": opening.get("speaker", ""), 
        "choices": [
            {"label": "Standard extraction", "next": "mine"}, 
            {"label": "Deep drill — go for the good stuff", "next": "deep"}, 
            {"label": "Not worth stopping", "next": ""}, 
        ]}
    nodes["mine"] = {"text": _pick_text("resource_mine", rng), "speaker": "Mining Chief", 
        "effects": [{"type": "give_resource_random", "min": base_min, "max": base_max}], 
        "choices": [{"label": "Good haul", "next": ""}]}
    if deep_success:
        nodes["deep"] = {"text": _pick_text("resource_deep_good", rng), "speaker": "Mining Chief", 
            "effects": [{"type": "give_resource_random", "min": base_min * 2, "max": base_max * 2}], 
            "choices": [{"label": "Excellent find", "next": ""}]}
    else:
        nodes["deep"] = {"text": _pick_text("resource_deep_bad", rng), "speaker": "Engineer", 
            "effects": [{"type": "damage_hull", "amount": 10 + threat * 4}, {"type": "give_resource_random", "min": base_min, "max": base_max}], 
            "choices": [{"label": "Patch the hull and move on", "next": ""}]}
    return {"title": poi_name, "nodes": nodes}



func generate_radiant_missions(system_id: String) -> void :
    var sys = systems.get(system_id, {})
    if sys.is_empty() or sys.get("_missions_generated", false):
        return
    sys["_missions_generated"] = true
    var rng = RandomNumberGenerator.new()
    rng.seed = system_id.hash() ^ (galaxy_seed + 31337)
    var threat = int(sys.get("threat_level", 1))
    var faction = sys.get("faction", "independent")
    var connections: Array = sys.get("connections", [])
    var num_missions = rng.randi_range(2, 3 + mini(threat, 2))
    for i in num_missions:
        var mid = "radiant_%s_%d" % [system_id, i]
        if missions.has(mid):
            continue
        var mission = _build_radiant_mission(mid, system_id, connections, threat, faction, rng)
        if not mission.is_empty():
            missions[mid] = mission

func _build_radiant_mission(_mid: String, origin_id: String, connections: Array, threat: int, faction: String, rng: RandomNumberGenerator) -> Dictionary:
    var type_roll = rng.randf()
    var mtype: String
    if type_roll < 0.3: mtype = "bounty"
    elif type_roll < 0.6: mtype = "cargo_haul"
    elif type_roll < 0.8: mtype = "salvage"
    else: mtype = "gather"
    var givers: Array = MISSION_GIVERS.get(faction, MISSION_GIVERS["independent"])
    var giver: String = _pick_from(givers, rng)
    var base_credits = 80 + threat * 60
    var reward_credits = base_credits + rng.randi_range(-20, 40)
    var dest_id = origin_id
    if not connections.is_empty():
        dest_id = connections[rng.randi() % connections.size()]
    var dest_name = systems.get(dest_id, {}).get("name", dest_id)
    var mission: Dictionary = {}
    match mtype:
        "bounty":
            var kill_count = 3 + threat + rng.randi_range(0, 3)
            var target_desc: String = _pick_from(BOUNTY_TARGETS, rng)
            var reason: String = _pick_from(BOUNTY_REASONS, rng)
            var titles: Array = ["Clear %s in %s" % [target_desc, dest_name], "%s Sweep" % dest_name, "Bounty: %s" % dest_name]
            mission = {"title": _pick_from(titles, rng), "type": "bounty", 
                "description": "%s Eliminate %d hostiles in %s." % [reason, kill_count, dest_name], 
                "giver": giver, "target_system": dest_id, "kill_target": kill_count, 
                "reward_credits": reward_credits, "reward_text": "%d credits" % reward_credits, 
                "min_threat": 0, "reward_modules": {}, "available_at": origin_id}
        "cargo_haul":
            var cargo: Dictionary = _pick_from(CARGO_GOODS, rng)
            var cargo_size = 1 + rng.randi_range(0, mini(threat, 3))
            reward_credits = int(reward_credits * 1.2)
            var titles: Array = ["Deliver %s to %s" % [cargo["name"], dest_name], "%s Shipment" % dest_name, "Freight Run to %s" % dest_name]
            mission = {"title": _pick_from(titles, rng), "type": "cargo_haul", 
                "description": "Transport %s to %s." % [cargo["name"], dest_name], 
                "giver": giver, "origin_system": origin_id, "destination_system": dest_id, 
                "cargo_id": cargo["id"], "cargo_name": cargo["name"], "cargo_size": cargo_size, 
                "reward_credits": reward_credits, "reward_text": "%d credits" % reward_credits, 
                "min_threat": 0, "time_limit": 0, "reward_modules": {}, "available_at": origin_id}
        "salvage":
            var dest_pois: Array = systems.get(dest_id, {}).get("pois", [])
            var target_poi = "Unknown Signal"
            if not dest_pois.is_empty():
                target_poi = dest_pois[rng.randi() % dest_pois.size()].get("name", target_poi)
            var titles: Array = ["Recovery: %s" % target_poi, "Salvage in %s" % dest_name, "Search %s" % dest_name]
            mission = {"title": _pick_from(titles, rng), "type": "salvage", 
                "description": "Locate %s in %s. Visit the POI to complete recovery." % [target_poi, dest_name], 
                "giver": giver, "target_system": dest_id, "target_poi": target_poi, 
                "reward_credits": reward_credits, "reward_text": "%d credits" % reward_credits, 
                "min_threat": 0, "reward_modules": {}, "available_at": origin_id}
        "gather":
            var res_keys = GameManager.RESOURCE_TYPES.keys()
            var res_type: String = res_keys[rng.randi() % res_keys.size()]
            var res_name = GameManager.RESOURCE_TYPES.get(res_type, {}).get("name", res_type)
            var amount = 5 + threat * 3 + rng.randi_range(0, 5)
            reward_credits = int(reward_credits * 0.9)
            var titles: Array = ["Gather %s" % res_name, "Resource Contract: %s" % res_name, "Supply %d %s" % [amount, res_name]]
            mission = {"title": _pick_from(titles, rng), "type": "gather", 
                "description": "Collect %d units of %s through mining, salvage, or trade." % [amount, res_name], 
                "giver": giver, "gather_resource": res_type, "gather_target": amount, 
                "reward_credits": reward_credits, "reward_text": "%d credits" % reward_credits, 
                "min_threat": 0, "reward_modules": {}, "available_at": origin_id}
    return mission
