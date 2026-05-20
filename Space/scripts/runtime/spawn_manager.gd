extends Node

# Space-side spawn coordinator. Instantiates player/enemies/POIs/asteroid
# fields/station entities/NPC ships when a system loads and exposes the
# warp-in wormhole spawn used by trigger + creative-mode paths. Signal
# wiring still routes through main via owner_main.<handler>; node scripts
# and cached spawn arrays are read off the host so the refactor doesn't
# fan out into every other system.

var owner_main: Node = null

func _host() -> Node:
    return owner_main

func spawn_player() -> Node:
    var host = _host()
    var player = host.player_scene.instantiate()
    player.position = Vector2.ZERO
    host.add_child(player)
    player.health_changed.connect(host._on_player_health_changed)
    player.destroyed.connect(host._on_player_destroyed)
    player.scan_pulse_hit.connect(host._on_scan_hit)
    host.player = player
    return player

func spawn_trigger_enemies(spawns: Array, min_dist: float, max_dist: float):
    var host = _host()
    min_dist = maxf(min_dist, 600.0)
    max_dist = maxf(max_dist, min_dist + 200.0)
    var idx: int = 0
    for entry in spawns:
        var class_id: String = entry.get("class", "fighter")
        var count: int = int(entry.get("count", 1))
        for i in count:
            var angle = randf() * TAU
            var dist = randf_range(min_dist, max_dist)
            var spawn_pos = host.player.position + Vector2.from_angle(angle) * dist
            var delay = float(idx) * randf_range(0.6, 1.2)
            spawn_enemy_ship(spawn_pos, class_id, true, delay)
            idx += 1

func spawn_enemies(count: int, min_dist: float, max_dist: float):
    var host = _host()
    min_dist = maxf(min_dist, 600.0)
    max_dist = maxf(max_dist, min_dist + 200.0)
    var sys = DataManager.systems.get(GameManager.current_system, {})
    var threat = sys.get("threat_level", 1)
    for i in count:
        var angle = randf() * TAU
        var dist = randf_range(min_dist, max_dist)
        var spawn_pos = host.player.position + Vector2.from_angle(angle) * dist
        var class_id = pick_enemy_class(threat)
        var delay = float(i) * randf_range(0.6, 1.2)
        spawn_enemy_ship(spawn_pos, class_id, true, delay)

func spawn_enemy_ship(pos: Vector2, class_id: String, use_wormhole: bool = true, delay: float = 0.0):
    if delay > 0.0:
        var timer := get_tree().create_timer(delay, false, false, false)
        timer.timeout.connect(Callable(self, "_spawn_enemy_ship_after_delay").bind(pos, class_id, use_wormhole), CONNECT_ONE_SHOT)
        return
    if use_wormhole:
        _do_wormhole_spawn(pos, class_id)
    else:
        _do_direct_spawn(pos, class_id)

func _spawn_enemy_ship_after_delay(pos: Vector2, class_id: String, use_wormhole: bool) -> void:
    spawn_enemy_ship(pos, class_id, use_wormhole, 0.0)

func spawn_enemy_with_wormhole(pos: Vector2, class_id: String, delay: float):
    spawn_enemy_ship(pos, class_id, true, delay)

func _do_wormhole_spawn(pos: Vector2, class_id: String):
    var host = _host()
    if not is_instance_valid(host.player):
        return

    var enemy = host.enemy_scene.instantiate()
    enemy.position = pos
    host.add_child(enemy)
    enemy.setup_class(class_id)
    enemy.died.connect(host._on_enemy_died)

    host._spawn_warp_portal(pos, enemy)

func _do_direct_spawn(pos: Vector2, class_id: String):
    var host = _host()
    if not is_instance_valid(host.player):
        return
    var enemy = host.enemy_scene.instantiate()
    enemy.position = pos
    host.add_child(enemy)
    enemy.setup_class(class_id)
    enemy.died.connect(host._on_enemy_died)

func pick_enemy_class(threat: int) -> String:
    var eligible: Array = []
    var total_weight: float = 0.0
    for cid in DataManager.enemy_classes:
        var data = DataManager.enemy_classes[cid]
        if data.get("min_threat", 1) <= threat:
            var w = data.get("weight", 1)

            if data.get("min_threat", 1) >= threat - 1:
                w += threat - data.get("min_threat", 1)
            eligible.append({"id": cid, "weight": w})
            total_weight += w

    if eligible.is_empty():
        return "fighter"

    var roll = randf() * total_weight
    var acc: float = 0.0
    for entry in eligible:
        acc += entry.weight
        if roll <= acc:
            return entry.id
    return eligible[-1].id

func spawn_system_pois(sys_id: String):
    var host = _host()
    var sys = DataManager.systems.get(sys_id, {})
    var pois: Array = sys.get("pois", [])
    var sys_pos = host.system_world_positions.get(sys_id, Vector2.ZERO)

    var spawned_markers: Array = []
    for i in pois.size():
        var poi_data = pois[i]
        if typeof(poi_data) != TYPE_DICTIONARY:
            continue
        poi_data = (poi_data as Dictionary).duplicate(true)
        if str(poi_data.get("type", "")).strip_edges() == "planet":
            _enrich_planet_destination(poi_data, sys_id, i)
        var eid: String = poi_data.get("event_id", "")


        if eid != "" and eid in GameManager.consumed_pois:
            continue

        # Hidden POIs are skipped until an unlock_poi action records the
        # POI's id in GameManager.unlocked_pois. The check happens here
        # (rather than after marker construction) so no marker is drawn,
        # no station entity is spawned, and the planet enrichment above
        # is wasted at worst on a single duplicated dict.
        if bool(poi_data.get("hidden", false)):
            var poi_id_check: String = str(poi_data.get("id", "")).strip_edges()
            if poi_id_check.is_empty() or not GameManager.is_poi_unlocked(sys_id, poi_id_check):
                continue

        var marker = Area2D.new()
        marker.set_script(host.poi_script)

        var odist: float = poi_data.get("orbit_dist", 4000.0 + float(i) * 800.0)

        var _poi_sys = DataManager.systems.get(sys_id, {})
        var _min_orbit = _poi_sys.get("star_size", 60) * 20.0 + 800.0
        if odist < _min_orbit:
            odist = _min_orbit + float(i) * 400.0
        var oangle_deg: float = poi_data.get("orbit_angle", float(i) * (360.0 / maxf(pois.size(), 1)))
        var oangle_rad = deg_to_rad(oangle_deg)

        var ospeed: float = 0.03 / maxf(odist / 600.0, 0.5)
        marker.orbit_center = sys_pos
        marker.orbit_dist = odist
        marker.orbit_angle = oangle_rad
        marker.orbit_speed = ospeed
        marker.position = sys_pos + Vector2.from_angle(oangle_rad) * odist
        host.add_child(marker)
        marker.setup(poi_data, eid)

        var known = GameManager.discovered_pois.get(sys_id, [])
        if poi_data.get("name", "") in known:
            marker.discovered = true
        marker.interacted.connect(host._on_poi_interacted)
        marker.planet_entered.connect(host._on_planet_entered)

        if poi_data.get("type", "") in ["station", "hostile_station"]:
            _spawn_station_entity(poi_data, marker, sys_id)
        spawned_markers.append({"marker": marker, "data": poi_data})

    for entry in spawned_markers:
        var oparent: String = entry["data"].get("orbit_parent", "")
        if oparent != "":
            for other in spawned_markers:
                if other["data"].get("name", "") == oparent:
                    entry["marker"].orbit_parent = other["marker"]
                    break


func _enrich_planet_destination(poi_data: Dictionary, sys_id: String, poi_index: int) -> void:
    var planet_v: Variant = poi_data.get("planet_data", {})
    var planet_data: Dictionary = {}
    if typeof(planet_v) == TYPE_DICTIONARY:
        planet_data = (planet_v as Dictionary).duplicate(true)
    var poi_name: String = str(poi_data.get("name", "planet_%d" % poi_index)).strip_edges()
    if poi_name.is_empty():
        poi_name = "planet_%d" % poi_index
    planet_data["source_system"] = sys_id
    planet_data["poi_index"] = poi_index
    planet_data["poi_name"] = poi_name
    if str(planet_data.get("planet_key", "")).strip_edges().is_empty():
        var event_id: String = str(poi_data.get("event_id", "")).strip_edges()
        var key_src := event_id if not event_id.is_empty() else poi_name
        planet_data["planet_key"] = "%s/%s" % [sys_id, _snapshot_key_part(key_src)]
    poi_data["planet_data"] = planet_data


func _snapshot_key_part(value: String) -> String:
    var out := value.strip_edges().to_lower()
    out = out.replace("\\", "/")
    out = out.replace("/", "_")
    out = out.replace(" ", "_")
    out = out.replace(":", "_")
    if out.is_empty():
        return "planet"
    return out

func spawn_asteroid_fields(sys_id: String):
    var host = _host()
    var sys = DataManager.systems.get(sys_id, {})
    var sys_pos = host.system_world_positions.get(sys_id, Vector2.ZERO)
    var threat = int(sys.get("threat_level", 1))
    if threat <= 0:
        return

    var seed_base: int = sys_id.hash()
    var gen = RandomNumberGenerator.new()
    gen.seed = seed_base


    var field_count = gen.randi_range(4, 8 + threat)

    var resource_keys = GameManager.RESOURCE_TYPES.keys()

    for i in field_count:
        var field = Area2D.new()
        field.set_script(host.asteroid_script)


        var angle = gen.randf() * TAU
        var dist = gen.randf_range(5000, 15000)
        field.position = sys_pos + Vector2.from_angle(angle) * dist


        var res_idx = gen.randi_range(0, resource_keys.size() - 1)
        var res_type = resource_keys[res_idx]

        if threat >= 3 and gen.randf() < 0.4:
            res_type = resource_keys[gen.randi_range(3, resource_keys.size() - 1)]

        var richness = gen.randf_range(0.5, 1.5 + float(threat) * 0.3)
        var amount = gen.randf_range(50, 150) * richness

        host.add_child(field)
        field.setup(seed_base + i, res_type, richness, amount)

func clear_pois():
    var host = _host()
    for poi in host._cached_pois:
        poi.queue_free()
    for se in host._cached_station_entities:
        if is_instance_valid(se):
            se.queue_free()

func _spawn_station_entity(poi_data: Dictionary, poi_marker_node: Area2D, sys_id: String):
    var host = _host()
    var stype = poi_data.get("station_type", "trade")

    var eid = poi_data.get("event_id", "")
    if "station:" in eid:
        var layout_part = eid.split("|")[0].replace("station:", "")
        if layout_part in ["trade", "military", "pirate", "science", "gateway"]:
            stype = layout_part
    var sname = poi_data.get("name", "Station")
    var station_key = "%s_%s" % [sys_id, sname.to_lower().replace(" ", "_")]
    var seed_val = station_key.hash()

    var sdata = GameManager.get_or_create_station(station_key, stype, seed_val)
    if GameManager.is_station_destroyed(station_key):
        return

    sdata["name"] = sname
    var entity = Area2D.new()
    entity.set_script(host.station_entity_script)
    host.add_child(entity)
    entity.global_position = poi_marker_node.global_position
    entity.setup(sdata)

    entity.poi_marker = poi_marker_node
    if host.has_method("_on_station_destroyed"):
        entity.died.connect(Callable(host, "_on_station_destroyed"))

func spawn_npc_ships(sys_id: String):
    var host = _host()
    var sys_pos = host.system_world_positions.get(sys_id, Vector2.ZERO)
    var ships = GameManager.generate_npc_ships_for_system(sys_id)
    for ship_data in ships:
        if not ship_data.get("alive", true):
            continue
        var entity = Area2D.new()
        entity.set_script(host.npc_ship_script)
        host.add_child(entity)
        entity.system_center = sys_pos

        var adjusted = ship_data.duplicate(true)
        var wp = adjusted.get("world_pos", [0, 0])
        adjusted["world_pos"] = [wp[0] + sys_pos.x, wp[1] + sys_pos.y]
        var route = adjusted.get("route", [])
        var adj_route: Array = []
        for rp in route:
            adj_route.append([rp[0] + sys_pos.x, rp[1] + sys_pos.y])
        adjusted["route"] = adj_route
        entity.setup(adjusted)
        entity.died.connect(host._on_npc_ship_died)

func spawn_placed_npcs(sys_id: String):
    var host = _host()
    var sys_data = DataManager.systems.get(sys_id, {})
    var placed_npcs: Array = sys_data.get("placed_npcs", [])
    if placed_npcs.is_empty():
        return
    var sys_pos = host.system_world_positions.get(sys_id, Vector2.ZERO)
    for npc_def in placed_npcs:
        var npc_id: String = npc_def.get("id", "")
        if npc_id == "":
            continue
        var beh: Dictionary = npc_def.get("behavior", {})
        var respawn: bool = beh.get("respawn", false)
        var respawn_hrs: float = beh.get("respawn_hours", 0)
        if GameManager.killed_placed_npcs.has(npc_id):
            if not respawn:
                continue
            var kill_time: float = GameManager.killed_placed_npcs[npc_id]
            if GameManager.total_game_hours - kill_time < respawn_hrs:
                continue
            GameManager.killed_placed_npcs.erase(npc_id)

        var template_name: String = npc_def.get("template", "")
        var template_data: Dictionary = {}
        if template_name != "":
            template_data = GameManager.get_template_by_name(template_name)

        var faction_id: String = npc_def.get("faction", "independent")
        var colors = GameManager.get_faction_ship_colors(faction_id)

        var orbit_dist: float = npc_def.get("orbit_dist", 2000)
        var orbit_angle: float = deg_to_rad(npc_def.get("orbit_angle", 0))
        var spawn_pos = sys_pos + Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_dist

        var modules: Array = template_data.get("modules", [])
        var core_id: String = template_data.get("core_id", "core_pod")

        var route: Array = []
        var patrol_route: Array = npc_def.get("patrol_route", [])
        for wp in patrol_route:
            var wd: float = wp.get("dist", 2000)
            var wa: float = deg_to_rad(wp.get("angle", 0))
            var wp_pos = sys_pos + Vector2(cos(wa), sin(wa)) * wd
            route.append([wp_pos.x, wp_pos.y])

        var ship_data: Dictionary = {
            "id": npc_id,
            "name": npc_def.get("name", "NPC"),
            "faction": faction_id,
            "npc_type": npc_def.get("npc_type", "patrol"),
            "hostile": npc_def.get("hostile", false),
            "combat_style": npc_def.get("combat_style", "standard"),
            "color": colors.get("primary", [0.5, 0.5, 0.55]),
            "colors": colors,
            "world_pos": [spawn_pos.x, spawn_pos.y],
            "modules": modules,
            "core_id": core_id,
            "static_hull_path": str(npc_def.get("static_hull_path", template_data.get("static_hull_path", ""))),
            "route": route,
            "placed_npc_id": npc_id,
            "hail_event_id": npc_def.get("hail_event_id", ""),
        }
        var entity = Area2D.new()
        entity.set_script(host.npc_ship_script)
        host.add_child(entity)
        entity.system_center = sys_pos
        entity.setup(ship_data)
        entity.died.connect(host._on_npc_ship_died)
