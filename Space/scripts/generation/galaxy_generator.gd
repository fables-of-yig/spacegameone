class_name GalaxyGenerator






const PREFIXES = [
    "Ash", "Vel", "Kor", "Sear", "Frost", "Grim", "Haze", "Blaze", 
    "Iron", "Jade", "Onyx", "Pale", "Void", "Dusk", "Dawn", "Ember", 
    "Storm", "Rust", "Drift", "Rift", "Shadow", "Star", "Cinder", 
    "Thorn", "Veil", "Mist", "Shade", "Gloom", "Brine", "Char", 
    "Flux", "Raven", "Wolf", "Bone", "Forge", "Crown", "Anvil", 
    "Rend", "Scorch", "Wither", "Shroud", "Soot", "Salt", "Far", 
    "Deep", "Bright", "Silver", "Gold", "Black", "Red", "Grey", 
    "Amber", "Crimson", "Hollow", "Broken", "Lost", "Fallen", 
    "Silent", "Frozen", "Shatter", "Cobalt", "Basalt", "Quartz", 
    "Xan", "Zel", "Pyr", "Mal", "Tor", "Bal", "Cal", "Thal", 
    "Ren", "Lor", "Mir", "Ven", "Sul", "Gar", "Kel", "Mor", 
    "Wyr", "Nex", "Lux", "Arc", "Dra", "Eld", "Fen", "Pyre", 
]

const SUFFIXES = [
    "fall", "reach", "hold", "haven", "gate", "veil", "heart", 
    "maw", "bane", "fire", "light", "forge", "watch", "ward", 
    "peak", "crest", "vale", "well", "spire", "burn", "cairn", 
    "port", "helm", "keep", "mark", "dale", "mere", "holm", 
    "stead", "wick", "ridge", "stone", "blade", "shade", "deep", 
    "moor", "cross", "bridge", "thane", "brook", "fen", 
]

const SYSTEM_TAGS = [
    "Reach", "Drift", "Expanse", "Nebula", "Sector", "Cluster", 
    "Void", "Rift", "Passage", "Run", "Frontier", "Verge", 
    "Edge", "Rim", "Hollow", "Wastes", "Barrens", "Stretch", 
    "Sweep", "Channel", "March", "Domain", "Terminus", "Gap", 
    "Deeps", "Crossing", "Junction", "Belt", 
]

const DARK_NOUNS = [
    "Sorrow", "Crucible", "Maw", "Harrowing", "Silence", "Abyss", 
    "Reckoning", "Desolation", "Oblivion", "Perdition", "Torment", 
    "Maelstrom", "Cataclysm", "Requiem", "Dirge", "Lament", 
    "Wrath", "Fury", "Judgment", "Eclipse", "Entropy", "Purgatory", 
    "Terminus", "Descent", "Sundering", "Scourge", "Blight", 
    "Dread", "Malice", "Vendetta", "Omen", "Withering", 
]

const OF_TARGETS = [
    "Devils", "Kings", "Serpents", "Gods", "Bones", "Ashes", 
    "Stars", "Shadows", "Thorns", "Teeth", "Souls", "Flames", 
    "Nightmares", "Whispers", "Echoes", "Ghosts", "Blades", 
    "Crowns", "Tyrants", "Saints", "Sinners", "Martyrs", 
    "Worms", "Wolves", "Ravens", "Vultures", "Heralds", 
    "Prophets", "Fools", "Exiles", "Titans", "Cowards", 
]

const HOME_SUFFIXES = ["Haven", "Harbor", "Hearth", "Cradle", "Refuge", "Bastion"]

const PLANET_SUFFIXES = [
    "Prime", "Minor", "Major", "Alpha", "Beta", "Nova", 
    "Umbra", "Vera", "Kaida", "Nexus", "Voss", "Mira", 
]

const STATION_ADJECTIVES = [
    "Central", "Orbital", "Deep", "Free", "High", "Far", 
    "Old", "Grand", "Iron", "Black", "Red", "Blue", 
]



const ALIEN_ONSETS = [
    "Zh", "Th", "Kr", "Xr", "Vr", "Gh", "Tz", "Sk", "Kh", 
    "Dr", "Tr", "Ph", "Zr", "Gl", "Br", "Sh", "Ch", "Gr", 
    "K", "T", "V", "Z", "X", "N", "R", "M", "L", "S", "J", 
]

const ALIEN_VOWELS = [
    "a", "e", "i", "o", "u", "ai", "ei", "ou", "aa", "uu", "ia", 
]

const ALIEN_CODAS = [
    "th", "x", "n", "r", "k", "l", "s", "z", "sh", "rr", "nn", 
    "kh", "zh", "t", "m", "v", "d", "g", "ss", "", 
]

const ALIEN_ORG_TYPES = [
    "Dominion", "Collective", "Swarm", "Hierarchy", "Conclave", 
    "Nexus", "Communion", "Assembly", "Imperium", "Hegemony", 
    "Sovereignty", "Compact", "Accord", "Horde", "Syndicate", 
]

const ALIEN_TRAITS = [
    "aggressive", "diplomatic", "isolationist", "mercantile", 
    "expansionist", "xenophobic", "curious", "ancient", 
    "nomadic", "hive_mind", "predatory", "symbiotic", 
]

const ALIEN_BODY_TYPES = [
    {"id": "insectoid", "desc": "chitinous exoskeleton, compound eyes, mandibles", "size": "human-sized"}, 
    {"id": "reptilian", "desc": "scaled hide, slit-pupil eyes, clawed digits", "size": "tall"}, 
    {"id": "avian", "desc": "feathered crest, hollow bones, taloned feet", "size": "slight"}, 
    {"id": "crystalline", "desc": "translucent mineral body, faceted eyes, resonant voice", "size": "stocky"}, 
    {"id": "amorphous", "desc": "shifting gelatinous mass, pseudopods, bioluminescent", "size": "variable"}, 
    {"id": "aquatic", "desc": "gill slits, webbed digits, iridescent skin", "size": "human-sized"}, 
    {"id": "fungoid", "desc": "mycelial tendrils, spore sacs, spongy tissue", "size": "short"}, 
    {"id": "silicon", "desc": "metallic carapace, photoreceptor arrays, angular joints", "size": "heavy"}, 
    {"id": "ethereal", "desc": "semi-transparent form, luminous veins, floating gait", "size": "tall"}, 
    {"id": "mammalian", "desc": "furred pelt, wide-set eyes, heavy build", "size": "large"}, 
]

const ALIEN_SHIP_STYLES = ["organic", "angular", "crystalline", "hive", "fluid"]

const ALIEN_GREETINGS = {
    "aggressive": ["State your purpose, outsider.", "You enter our space uninvited.", "Weapons are trained on you."], 
    "diplomatic": ["Greetings, traveler. We welcome dialogue.", "Peace between our peoples.", "Well met, star-walker."], 
    "isolationist": ["You are not welcome here. Leave.", "Our borders are closed.", "Turn back."], 
    "mercantile": ["Ah, a potential customer!", "Credits speak all languages.", "What goods do you carry?"], 
    "curious": ["Fascinating vessel. Tell us of your world.", "We have many questions for you.", "Your biology intrigues us."], 
    "xenophobic": ["Outsider filth. State your business.", "Your kind disgusts us.", "Leave our territory."], 
    "ancient": ["We have watched your species for millennia.", "Time moves slowly for us.", "Young one, you tread old ground."], 
    "nomadic": ["Our fleet is our home. Where is yours?", "Fellow wanderers of the void.", "The stars belong to no one."], 
    "hive_mind": ["We are many. You are one. Curious.", "The collective acknowledges you.", "Speak, individual."], 
    "predatory": ["Prey enters our hunting ground.", "We scent weakness.", "Run or fight. Choose."], 
    "symbiotic": ["We sense potential for mutual benefit.", "Together we are stronger.", "Let us join purposes."], 
    "expansionist": ["This sector falls under our domain.", "Expansion is inevitable.", "You may serve us willingly."], 
}

const ALIEN_FIRST_SYLLABLES = [
    "Zk", "Xr", "Th", "Kr", "Vr", "Zh", "Gl", "Dr", "Sk", "Ch", 
    "N", "R", "K", "T", "V", "Z", "M", "L", "S", "J", "X", 
]

const ALIEN_LAST_SYLLABLES = [
    "ax", "ix", "oth", "arn", "ux", "eln", "ik", "ash", "eth", "ozz", 
    "ann", "urr", "iss", "ekk", "ull", "izz", "ath", "okk", "unn", "err", 
]



const STAR_DATA = [
    {"class": "M", "color": [1.0, 0.4, 0.3], "size": [25, 40], "weight": 40}, 
    {"class": "K", "color": [1.0, 0.7, 0.3], "size": [35, 50], "weight": 25}, 
    {"class": "G", "color": [1.0, 0.95, 0.6], "size": [45, 60], "weight": 18}, 
    {"class": "F", "color": [1.0, 1.0, 0.85], "size": [50, 65], "weight": 8}, 
    {"class": "A", "color": [0.8, 0.85, 1.0], "size": [55, 75], "weight": 5}, 
    {"class": "B", "color": [0.6, 0.7, 1.0], "size": [65, 85], "weight": 3}, 
    {"class": "O", "color": [0.5, 0.6, 1.0], "size": [75, 95], "weight": 1}, 
]



const PLANET_BIOMES = [
    {"name": "Barren", "sky": [0.3, 0.25, 0.2], "horizon": [0.5, 0.4, 0.3], 
     "terrain": [[0.3, 0.25, 0.2], [0.25, 0.2, 0.15], [0.2, 0.15, 0.1]], "roughness": 0.7}, 
    {"name": "Jungle", "sky": [0.35, 0.5, 0.8], "horizon": [0.65, 0.45, 0.3], 
     "terrain": [[0.18, 0.35, 0.22], [0.12, 0.25, 0.14], [0.08, 0.2, 0.08]], "roughness": 0.65}, 
    {"name": "Volcanic", "sky": [0.35, 0.15, 0.1], "horizon": [0.8, 0.3, 0.1], 
     "terrain": [[0.25, 0.12, 0.08], [0.2, 0.08, 0.05], [0.15, 0.06, 0.03]], "roughness": 0.85}, 
    {"name": "Oceanic", "sky": [0.25, 0.4, 0.7], "horizon": [0.4, 0.55, 0.7], 
     "terrain": [[0.15, 0.25, 0.35], [0.1, 0.2, 0.3], [0.08, 0.15, 0.25]], "roughness": 0.4}, 
    {"name": "Frozen", "sky": [0.6, 0.65, 0.75], "horizon": [0.8, 0.8, 0.85], 
     "terrain": [[0.7, 0.75, 0.82], [0.55, 0.6, 0.7], [0.4, 0.45, 0.55]], "roughness": 0.45}, 
    {"name": "Desert", "sky": [0.55, 0.45, 0.3], "horizon": [0.75, 0.6, 0.4], 
     "terrain": [[0.45, 0.38, 0.25], [0.38, 0.3, 0.2], [0.3, 0.25, 0.18]], "roughness": 0.55}, 
    {"name": "Toxic", "sky": [0.3, 0.35, 0.2], "horizon": [0.45, 0.5, 0.25], 
     "terrain": [[0.2, 0.25, 0.15], [0.18, 0.22, 0.12], [0.15, 0.18, 0.1]], "roughness": 0.6}, 
    {"name": "Crystalline", "sky": [0.4, 0.35, 0.6], "horizon": [0.6, 0.5, 0.8], 
     "terrain": [[0.35, 0.3, 0.5], [0.28, 0.24, 0.42], [0.2, 0.18, 0.35]], "roughness": 0.75}, 
    {"name": "Swamp", "sky": [0.3, 0.35, 0.25], "horizon": [0.4, 0.45, 0.3], 
     "terrain": [[0.2, 0.28, 0.15], [0.15, 0.22, 0.12], [0.12, 0.18, 0.1]], "roughness": 0.5}, 
    {"name": "Irradiated", "sky": [0.45, 0.35, 0.2], "horizon": [0.6, 0.5, 0.25], 
     "terrain": [[0.35, 0.3, 0.15], [0.3, 0.25, 0.12], [0.25, 0.2, 0.1]], "roughness": 0.8}, 
    {"name": "Temperate", "sky": [0.3, 0.45, 0.7], "horizon": [0.5, 0.55, 0.65], 
     "terrain": [[0.2, 0.35, 0.18], [0.18, 0.3, 0.15], [0.15, 0.25, 0.12]], "roughness": 0.35}, 
    {"name": "Tidally Locked", "sky": [0.2, 0.15, 0.25], "horizon": [0.4, 0.25, 0.35], 
     "terrain": [[0.15, 0.12, 0.2], [0.12, 0.1, 0.18], [0.1, 0.08, 0.15]], "roughness": 0.9}, 
]



const HUMAN_FACTIONS = {
    "cotac": {"name": "COTAC", "color": [0.9, 0.75, 0.3], "disposition": "friendly", "desc": "Church of Technological Advancement and Continuity"}, 
    "castellan": {"name": "Castellan", "color": [0.3, 0.5, 0.85], "disposition": "neutral", "desc": "Local governance authority"}, 
    "isd": {"name": "ISD", "color": [0.7, 0.2, 0.2], "disposition": "friendly", "desc": "Interstellar Security Directorate"}, 
    "union_militia": {"name": "Union Militia", "color": [0.4, 0.65, 0.35], "disposition": "friendly", "desc": "Blue collar defense force"}, 
    "bulwark": {"name": "Bulwark", "color": [0.6, 0.6, 0.65], "disposition": "neutral", "desc": "Elite exterminator corps"}, 
    "xenoculture": {"name": "Xenoculture Emissariat", "color": [0.5, 0.8, 0.7], "disposition": "friendly", "desc": "Alien research and diplomacy"}, 
    "fringe": {"name": "The Fringe", "color": [0.75, 0.55, 0.3], "disposition": "hostile", "desc": "Lawless frontier operators"}, 
    "independent": {"name": "Independent", "color": [0.5, 0.5, 0.55], "disposition": "neutral", "desc": "No faction affiliation"}, 
}

const SAFE_FACTIONS = ["cotac", "castellan", "union_militia", "independent", "isd"]
const HOSTILE_FACTIONS = ["fringe"]



const POI_NAME_POOLS = {
    "station": ["Station", "Outpost", "Platform", "Hub", "Waypoint", "Depot", "Dock", "Port"], 
    "salvage": ["Wreckage", "Derelict", "Debris Field", "Hulk", "Graveyard", "Remains"], 
    "anomaly": ["Signal Source", "Energy Spike", "Distortion", "Rift Echo", "Pulse", "Beacon"], 
    "ruin": ["Ancient Site", "Monument", "Relic", "Artifact", "Monolith", "Temple"], 
    "resource": ["Asteroid Belt", "Mineral Field", "Gas Cloud", "Crystal Formation", "Ore Vein"], 
    "debris_field": ["Debris Field", "Wreck Scatter", "Shrapnel Cloud", "Hull Fragment Zone", "Impact Zone"], 
    "derelict": ["Derelict Hulk", "Ghost Ship", "Abandoned Vessel", "Dead Ship", "Silent Wreck"], 
    "distress_signal": ["Distress Beacon", "SOS Signal", "Emergency Transponder", "Mayday Source", "Rescue Beacon"], 
}



const SPAWN_POOLS = {
    1: [{"class": "scout", "count": [1, 2]}], 
    2: [{"class": "scout", "count": [1, 3]}, {"class": "fighter", "count": [1, 2]}], 
    3: [{"class": "fighter", "count": [2, 3]}, {"class": "interceptor", "count": [1, 2]}], 
    4: [{"class": "interceptor", "count": [2, 3]}, {"class": "gunship", "count": [1, 2]}, {"class": "bomber", "count": [0, 1]}], 
    5: [{"class": "gunship", "count": [2, 3]}, {"class": "bomber", "count": [1, 2]}, {"class": "elite", "count": [1, 2]}], 
}





static func generate(seed_val: int, system_count: int) -> Dictionary:

    var rng = RandomNumberGenerator.new()
    rng.seed = seed_val
    var used_names: Dictionary = {}


    var alien_count = clampi(int(system_count / 30.0) + 1, 1, 6)
    var aliens: Array = []
    for i in alien_count:
        aliens.append(_generate_alien_race(rng))


    var factions: Dictionary = HUMAN_FACTIONS.duplicate(true)
    for alien in aliens:
        factions[alien["id"]] = {
            "name": alien["name"], 
            "color": alien["color"], 
            "disposition": alien["disposition"], 
            "desc": alien["org_name"], 
            "is_alien": true, 
            "traits": alien.get("traits", []), 
            "body_type": alien.get("body_type", {}), 
            "ship_style": alien.get("ship_style", ""), 
            "greeting": alien.get("greeting", ""), 
            "org_name": alien.get("org_name", ""), 
        }


    var positions = _generate_spiral_positions(rng, system_count)


    var _center = Vector2.ZERO
    var home_idx = 0
    var min_dist = INF
    for i in positions.size():
        var d = positions[i].length()
        if d < min_dist:
            min_dist = d
            home_idx = i


    var max_galaxy_dist: float = 1.0
    for p in positions:
        max_galaxy_dist = maxf(max_galaxy_dist, p.length())


    var systems: Dictionary = {}
    var sys_ids: Array = []
    var home_sys_id: String = ""

    for i in positions.size():
        var pos = positions[i]
        var is_home = (i == home_idx)
        var sys_id = "sys_%04d" % i


        var dist_from_home = pos.distance_to(positions[home_idx])
        var threat_raw = dist_from_home / max_galaxy_dist * 5.5
        var threat = clampi(int(threat_raw) + rng.randi_range(-1, 0), 0, 5)
        if is_home:
            threat = 0


        var name = _generate_system_name(rng, threat, is_home, used_names)
        used_names[name] = true


        var star = _pick_star(rng)


        var faction_id = _pick_faction(rng, threat, is_home, aliens)


        var world_pos = [pos.x, pos.y]

        var sys_data: Dictionary = {
            "name": name, 
            "position": world_pos, 
            "star_class": star["class"], 
            "star_color": star["color"], 
            "star_size": star["size"], 
            "description": _generate_description(rng, name, threat, faction_id, factions), 
            "threat_level": threat, 
            "faction": faction_id, 
            "connections": [], 
            "pois": [], 
            "spawn_triggers": [], 
            "procedural": true, 
        }

        systems[sys_id] = sys_data
        sys_ids.append(sys_id)
        if is_home:
            home_sys_id = sys_id


    _generate_connections(systems, sys_ids, positions)


    for sys_id in sys_ids:
        var sys = systems[sys_id]
        var is_home = (sys_id == home_sys_id)
        sys["pois"] = _generate_pois(rng, sys, is_home, used_names)
        if not is_home and sys.get("threat_level", 0) > 0:
            sys["spawn_triggers"] = _generate_spawn_triggers(rng, sys)
        else:
            sys["spawn_triggers"] = []

    return {
        "systems": systems, 
        "factions": factions, 
        "aliens": aliens, 
        "start_system": home_sys_id, 
    }





static func _generate_spiral_positions(rng: RandomNumberGenerator, count: int) -> Array:
    var positions: Array = []
    var num_arms = rng.randi_range(2, 4)
    var total_twist = PI * (2.5 + rng.randf() * 2.0)
    var max_radius = 900.0 + float(count) * 26.0
    var min_separation = 207.0


    var arm_count = int(count * 0.7)
    var _field_count = count - arm_count


    for i in arm_count:
        var arm = i % num_arms
        var arm_offset = TAU * float(arm) / float(num_arms)
        @warning_ignore("integer_division")
        var t = float(i / num_arms) / maxf(float(arm_count / num_arms), 1.0)
        var theta = arm_offset + t * total_twist
        var r = 40.0 + t * max_radius

        var scatter = 20.0 + r * 0.15
        var sx = rng.randf_range( - scatter, scatter)
        var sy = rng.randf_range( - scatter, scatter)
        var pos = Vector2(cos(theta) * r + sx, sin(theta) * r + sy)
        if _check_min_dist(pos, positions, min_separation):
            positions.append(pos)


    var attempts = 0
    while positions.size() < count and attempts < count * 10:
        attempts += 1
        var angle = rng.randf() * TAU
        var r = rng.randf() * max_radius * 0.9
        var pos = Vector2(cos(angle) * r, sin(angle) * r)
        if _check_min_dist(pos, positions, min_separation):
            positions.append(pos)


    while positions.size() < count:
        var angle = rng.randf() * TAU
        var r = rng.randf() * max_radius
        positions.append(Vector2(cos(angle) * r, sin(angle) * r))

    return positions

static func _check_min_dist(pos: Vector2, existing: Array, min_d: float) -> bool:
    for p in existing:
        if pos.distance_to(p) < min_d:
            return false
    return true





static func _generate_connections(systems: Dictionary, sys_ids: Array, positions: Array):

    var id_to_idx: Dictionary = {}
    for i in sys_ids.size():
        id_to_idx[sys_ids[i]] = i


    for i in sys_ids.size():
        var my_id = sys_ids[i]
        var my_pos = positions[i]
        var dists: Array = []
        for j in sys_ids.size():
            if i == j:
                continue
            dists.append({"idx": j, "dist": my_pos.distance_to(positions[j])})
        dists.sort_custom( func(a, b): return a["dist"] < b["dist"])


        var conns: Array = systems[my_id].get("connections", [])
        var target_count = 2 if dists.size() < 5 else 3
        for k in mini(target_count, dists.size()):
            var other_id = sys_ids[dists[k]["idx"]]
            if other_id not in conns:
                conns.append(other_id)
            var other_conns: Array = systems[other_id].get("connections", [])
            if my_id not in other_conns:
                other_conns.append(my_id)
                systems[other_id]["connections"] = other_conns
        systems[my_id]["connections"] = conns


    var visited: Dictionary = {}
    var queue: Array = [sys_ids[0]]
    visited[sys_ids[0]] = true
    while not queue.is_empty():
        var current = queue.pop_front()
        for conn in systems[current].get("connections", []):
            if not visited.has(conn):
                visited[conn] = true
                queue.append(conn)


    if visited.size() < sys_ids.size():
        for sid in sys_ids:
            if visited.has(sid):
                continue

            var my_pos = positions[id_to_idx[sid]]
            var best_id = sys_ids[0]
            var best_dist = INF
            for vid in visited:
                var vpos = positions[id_to_idx[vid]]
                var d = my_pos.distance_to(vpos)
                if d < best_dist:
                    best_dist = d
                    best_id = vid

            systems[sid]["connections"].append(best_id)
            systems[best_id]["connections"].append(sid)

            visited[sid] = true
            var q2: Array = [sid]
            while not q2.is_empty():
                var c = q2.pop_front()
                for cn in systems[c].get("connections", []):
                    if not visited.has(cn):
                        visited[cn] = true
                        q2.append(cn)





static func _generate_system_name(rng: RandomNumberGenerator, threat: int, is_home: bool, used: Dictionary) -> String:
    for _attempt in 20:
        var name = _try_generate_name(rng, threat, is_home)
        if not used.has(name):
            return name

    return "System %d" % rng.randi_range(100, 9999)

static func _try_generate_name(rng: RandomNumberGenerator, threat: int, is_home: bool) -> String:
    if is_home:
        var prefix = PREFIXES[rng.randi_range(0, PREFIXES.size() - 1)]
        var suffix = HOME_SUFFIXES[rng.randi_range(0, HOME_SUFFIXES.size() - 1)]
        return prefix + " " + suffix

    var roll = rng.randf()

    if threat >= 4:

        if roll < 0.5:
            return "The " + DARK_NOUNS[rng.randi_range(0, DARK_NOUNS.size() - 1)]
        else:
            var noun = DARK_NOUNS[rng.randi_range(0, DARK_NOUNS.size() - 1)]
            var target = OF_TARGETS[rng.randi_range(0, OF_TARGETS.size() - 1)]
            return "The " + noun + " of " + target

    if threat >= 3:

        if roll < 0.4:
            return "The " + _compound_name(rng)
        else:
            return _compound_name(rng) + " " + SYSTEM_TAGS[rng.randi_range(0, SYSTEM_TAGS.size() - 1)]


    if roll < 0.6:
        return _compound_name(rng) + " " + SYSTEM_TAGS[rng.randi_range(0, SYSTEM_TAGS.size() - 1)]
    else:
        return _compound_name(rng)

static func _compound_name(rng: RandomNumberGenerator) -> String:
    var prefix = PREFIXES[rng.randi_range(0, PREFIXES.size() - 1)]
    var suffix = SUFFIXES[rng.randi_range(0, SUFFIXES.size() - 1)]
    return prefix + suffix.to_lower()





static func _pick_star(rng: RandomNumberGenerator) -> Dictionary:
    var total_w = 0
    for s in STAR_DATA:
        total_w += s["weight"]
    var roll = rng.randi_range(0, total_w - 1)
    var acc = 0
    for s in STAR_DATA:
        acc += s["weight"]
        if roll < acc:
            return {
                "class": s["class"], 
                "color": s["color"].duplicate(), 
                "size": rng.randi_range(s["size"][0], s["size"][1]), 
            }
    return {"class": "M", "color": [1.0, 0.4, 0.3], "size": 30}





static func _pick_faction(rng: RandomNumberGenerator, threat: int, is_home: bool, aliens: Array) -> String:
    if is_home:
        return "union_militia"
    if threat <= 1:
        return SAFE_FACTIONS[rng.randi_range(0, SAFE_FACTIONS.size() - 1)]
    if threat >= 4 and not aliens.is_empty():

        if rng.randf() < 0.6:
            return aliens[rng.randi_range(0, aliens.size() - 1)]["id"]
    if threat >= 3:
        if rng.randf() < 0.3 and not aliens.is_empty():
            return aliens[rng.randi_range(0, aliens.size() - 1)]["id"]
        var all_human = SAFE_FACTIONS + HOSTILE_FACTIONS
        return all_human[rng.randi_range(0, all_human.size() - 1)]

    var pool = SAFE_FACTIONS.duplicate()
    pool.append_array(HOSTILE_FACTIONS)
    return pool[rng.randi_range(0, pool.size() - 1)]





const DESCRIPTIONS_LOW = [
    "A quiet system on well-traveled lanes. Traders pass through regularly.", 
    "Settled space. The local garrison keeps things orderly.", 
    "A prosperous system with active mining operations.", 
    "Relatively safe, though the occasional pirate raid keeps folks on edge.", 
    "A waypoint system. Not much here but fuel and friendly faces.", 
    "A supply depot system. Fuel prices are fair and the dock crews are fast.", 
    "Mining freighters rumble through on regular schedules. Steady work for steady folk.", 
    "Garden worlds orbit lazy stars here. Colonists and traders keep things running.", 
    "Comm relays link this system to a dozen others. News travels fast.", 
    "Patrol corvettes make regular sweeps. Pirates know better than to linger.", 
]

const DESCRIPTIONS_MID = [
    "Contested territory. Multiple factions stake claims here.", 
    "Frontier space. Law is thin and the bold prosper.", 
    "A system rich in resources but plagued by raiders.", 
    "Disputed borders. Ships go missing without explanation.", 
    "The frontier pushes outward here. Opportunity and danger in equal measure.", 
    "Scavengers and prospectors stake claims among the asteroid belts. No law but leverage.", 
    "Trade routes cross through hostile territory. Convoys run heavy with escort.", 
    "Old mining infrastructure, half-abandoned. Squatters and scrappers move in where corps moved out.", 
    "Nebula interference scrambles long-range comms. Ships here are on their own.", 
    "Competing factions maintain separate stations. Tensions run high at every dock.", 
]

const DESCRIPTIONS_HIGH = [
    "Hostile territory. Ships enter at their own peril.", 
    "Something ancient and terrible lingers in this system.", 
    "Sensors malfunction. Navigation is unreliable. Turn back.", 
    "The void stares back here. Few return from this system.", 
    "A graveyard of ships. Whatever lives here is not friendly.", 
    "Automated weapons platforms orbit dead worlds. Whoever put them here is long gone.", 
    "Radiation storms sweep the system at irregular intervals. Shield integrity is life.", 
    "Wreckage from an ancient war drifts in wide belts. Some of it is still armed.", 
    "Navigation beacons have been destroyed. Finding your way in is hard. Finding your way out is harder.", 
    "Something hunts in this system. Ships vanish without distress calls.", 
]

static func _generate_description(rng: RandomNumberGenerator, _name: String, threat: int, faction_id: String, factions: Dictionary) -> String:
    var pool: Array
    if threat <= 1:
        pool = DESCRIPTIONS_LOW
    elif threat <= 3:
        pool = DESCRIPTIONS_MID
    else:
        pool = DESCRIPTIONS_HIGH
    var desc = pool[rng.randi_range(0, pool.size() - 1)]
    var faction_data = factions.get(faction_id, {})
    var fname = faction_data.get("name", "")
    if fname != "" and fname != "Independent" and rng.randf() < 0.4:
        desc += " %s presence detected." % fname
    return desc





static func _generate_pois(rng: RandomNumberGenerator, sys_data: Dictionary, is_home: bool, used_names: Dictionary) -> Array:
    var pois: Array = []
    var threat = int(sys_data.get("threat_level", 1))
    var faction = sys_data.get("faction", "independent")
    var sys_name = sys_data.get("name", "Unknown")


    if is_home or faction != "independent" or rng.randf() < 0.6:
        var station_name = _station_name(rng, sys_name, used_names)
        used_names[station_name] = true
        var station_type = "station"
        if faction in HOSTILE_FACTIONS:
            station_type = "hostile_station" if rng.randf() < 0.4 else "station"

        var station_event_id = "home_station" if is_home else "proc_station_%s" % sys_data.get("name", "").to_lower().replace(" ", "_")
        pois.append({
            "name": station_name, 
            "type": station_type, 
            "description": "Orbital facility. Docking available.", 
            "event_id": station_event_id, 
            "orbit_dist": rng.randi_range(4000, 7000), 
            "orbit_angle": rng.randi_range(0, 359), 
        })


    if not is_home and rng.randf() < 0.4:
        var station_name2 = _station_name(rng, sys_name, used_names)
        used_names[station_name2] = true
        pois.append({
            "name": station_name2, 
            "type": "station", 
            "description": "Orbital facility. Docking available.", 
            "event_id": "proc_station_%s_2" % sys_name.to_lower().replace(" ", "_"), 
            "orbit_dist": rng.randi_range(6000, 9000), 
            "orbit_angle": rng.randi_range(0, 359), 
        })


    var planet_count = rng.randi_range(2, 6)
    var planet_nodes: Array = []
    for pi in planet_count:
        var biome = PLANET_BIOMES[rng.randi_range(0, PLANET_BIOMES.size() - 1)]
        var planet_name = _planet_name(rng, sys_name, pi, used_names)
        used_names[planet_name] = true
        var orbit_dist = rng.randi_range(8000 + pi * 2500, 11000 + pi * 3000)
        var turrets = [0, 0] if is_home else [maxi(threat - 1, 0), threat + 1]
        var patrols = [0, 0] if is_home else [maxi(threat - 1, 0), threat]
        var planet_poi: Dictionary = {
            "name": planet_name, 
            "type": "planet", 
            "description": biome["name"] + " world.", 
            "orbit_dist": orbit_dist, 
            "orbit_angle": rng.randi_range(0, 359), 
            "planet_data": {
                "name": planet_name, 
                "sky_color": biome["sky"], 
                "horizon_color": biome["horizon"], 
                "terrain_colors": biome["terrain"], 
                "roughness": biome["roughness"], 
                "turret_count": turrets, 
                "patrol_count": patrols, 
                "surface_pois": _generate_surface_pois(rng, planet_name, threat, is_home), 
            }
        }
        pois.append(planet_poi)
        planet_nodes.append({"name": planet_name, "idx": pois.size() - 1})


    if is_home and not planet_nodes.is_empty():

        var first_planet = planet_nodes[0]["name"]
        if pois.size() > 0 and pois[0].get("type", "") in ["station", "hostile_station"]:
            pois[0]["orbit_dist"] = 800
            pois[0]["orbit_angle"] = rng.randi_range(0, 359)
            pois[0]["orbit_parent"] = first_planet


    var extra_count = rng.randi_range(3, 6 + threat)
    var extra_types = ["salvage", "anomaly", "ruin", "resource", "debris_field", "derelict", "distress_signal"]
    for ei in extra_count:
        var etype = extra_types[rng.randi_range(0, extra_types.size() - 1)]
        var name_pool = POI_NAME_POOLS.get(etype, ["Unknown"])
        var ename = name_pool[rng.randi_range(0, name_pool.size() - 1)]
        pois.append({
            "name": ename, 
            "type": etype, 
            "description": "Uncharted point of interest.", 
            "event_id": "proc_%s_%d" % [etype, rng.randi_range(1000, 9999)], 
            "orbit_dist": rng.randi_range(5000, 15000), 
            "orbit_angle": rng.randi_range(0, 359), 
        })

    return pois

static func _generate_surface_pois(rng: RandomNumberGenerator, _pname: String, _threat: int, is_home: bool) -> Array:
    var surface_pois: Array = []
    var count = rng.randi_range(2, 4)
    var types = ["salvage", "anomaly", "ruin", "station"]
    if is_home:
        types = ["station", "salvage"]
    for i in count:
        var stype = types[rng.randi_range(0, types.size() - 1)]
        var name_pool = POI_NAME_POOLS.get(stype, ["Site"])
        var sname = name_pool[rng.randi_range(0, name_pool.size() - 1)]
        surface_pois.append({
            "name": sname, 
            "type": stype, 
            "description": "Surface point of interest.", 
            "x_pos": rng.randi_range(-6000, 6000), 
            "event_id": "proc_%s_%d" % [stype, rng.randi_range(10000, 99999)], 
        })
    return surface_pois

static func _station_name(rng: RandomNumberGenerator, sys_name: String, _used: Dictionary) -> String:
    var adj = STATION_ADJECTIVES[rng.randi_range(0, STATION_ADJECTIVES.size() - 1)]
    var base = POI_NAME_POOLS["station"][rng.randi_range(0, POI_NAME_POOLS["station"].size() - 1)]
    if rng.randf() < 0.5:

        var short = sys_name.split(" ")[0]
        return short + " " + base
    return adj + " " + base

static func _planet_name(rng: RandomNumberGenerator, sys_name: String, index: int, _used: Dictionary) -> String:
    var short = sys_name.split(" ")[0]
    if rng.randf() < 0.6:
        return short + " " + PLANET_SUFFIXES[rng.randi_range(0, PLANET_SUFFIXES.size() - 1)]

    var numerals = ["I", "II", "III", "IV", "V", "VI"]
    return short + " " + numerals[mini(index, numerals.size() - 1)]






static func _generate_spawn_triggers(rng: RandomNumberGenerator, sys_data: Dictionary) -> Array:
    var threat = int(sys_data.get("threat_level", 1))
    threat = clampi(threat, 1, 5)
    var pool = SPAWN_POOLS.get(threat, SPAWN_POOLS[1])
    var spawns: Array = []
    for entry in pool:
        var c = rng.randi_range(entry["count"][0], entry["count"][1])
        if c > 0:
            spawns.append({"class": entry["class"], "count": c})
    if spawns.is_empty():
        return []
    return [{
        "id": "spawn_%s" % sys_data.get("name", "").to_lower().replace(" ", "_"), 
        "on": "enter", 
        "conditions": {}, 
        "spawns": spawns, 
        "dist": [300 + threat * 50, 500 + threat * 100], 
        "once": false, 
    }]





static func _generate_alien_race(rng: RandomNumberGenerator) -> Dictionary:
    var name = _generate_alien_name(rng)
    var org = ALIEN_ORG_TYPES[rng.randi_range(0, ALIEN_ORG_TYPES.size() - 1)]
    var trait1 = ALIEN_TRAITS[rng.randi_range(0, ALIEN_TRAITS.size() - 1)]
    var trait2 = ALIEN_TRAITS[rng.randi_range(0, ALIEN_TRAITS.size() - 1)]
    while trait2 == trait1:
        trait2 = ALIEN_TRAITS[rng.randi_range(0, ALIEN_TRAITS.size() - 1)]
    var disp = "hostile" if trait1 in ["aggressive", "xenophobic", "predatory"] else "neutral"
    if trait1 in ["diplomatic", "mercantile", "curious", "symbiotic"]:
        disp = "friendly"

    var hue = rng.randf()
    var col = Color.from_hsv(hue, 0.6 + rng.randf() * 0.3, 0.7 + rng.randf() * 0.2)

    var body = ALIEN_BODY_TYPES[rng.randi_range(0, ALIEN_BODY_TYPES.size() - 1)]
    var ship_style = ALIEN_SHIP_STYLES[rng.randi_range(0, ALIEN_SHIP_STYLES.size() - 1)]

    var greet_pool = ALIEN_GREETINGS.get(trait1, ["..."])
    var greeting = greet_pool[rng.randi_range(0, greet_pool.size() - 1)]
    return {
        "id": "alien_" + name.to_lower().replace("'", ""), 
        "name": name, 
        "org_name": "The " + name + " " + org, 
        "color": [col.r, col.g, col.b], 
        "disposition": disp, 
        "traits": [trait1, trait2], 
        "body_type": body, 
        "ship_style": ship_style, 
        "greeting": greeting, 
    }

static func generate_alien_personal_name(rng: RandomNumberGenerator) -> String:

    var syllables = rng.randi_range(1, 2)
    var aname = ""
    for i in syllables:
        aname += ALIEN_FIRST_SYLLABLES[rng.randi_range(0, ALIEN_FIRST_SYLLABLES.size() - 1)]
        aname += ALIEN_VOWELS[rng.randi_range(0, ALIEN_VOWELS.size() - 1)]
    if rng.randf() < 0.5:
        aname += ALIEN_LAST_SYLLABLES[rng.randi_range(0, ALIEN_LAST_SYLLABLES.size() - 1)]
    else:
        aname += ALIEN_CODAS[rng.randi_range(0, ALIEN_CODAS.size() - 1)]
    return aname.substr(0, 1).to_upper() + aname.substr(1)

static func _generate_alien_name(rng: RandomNumberGenerator) -> String:
    var syllables = rng.randi_range(2, 3)
    var name = ""
    for i in syllables:
        name += ALIEN_ONSETS[rng.randi_range(0, ALIEN_ONSETS.size() - 1)]
        name += ALIEN_VOWELS[rng.randi_range(0, ALIEN_VOWELS.size() - 1)]
        if i < syllables - 1 and rng.randf() < 0.4:
            name += ALIEN_CODAS[rng.randi_range(0, ALIEN_CODAS.size() - 1)]
        elif i == syllables - 1:
            name += ALIEN_CODAS[rng.randi_range(0, ALIEN_CODAS.size() - 1)]

    if name.length() > 4 and rng.randf() < 0.3:
        var mid = rng.randi_range(2, name.length() - 2)
        name = name.substr(0, mid) + "'" + name.substr(mid)
    return name.substr(0, 1).to_upper() + name.substr(1)
