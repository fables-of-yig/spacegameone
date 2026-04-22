class_name MvPackRef
extends RefCounted

# Content-pack reference. Dual-path: pack lives in both
#   res://Content/{id}/       (shipped read-only baseline)
#   user://Packs/{id}/        (user override layer)
# resolve_read() prefers the user layer so customised files shadow shipped
# baselines; resolve_write() always points at the user layer.

var pack_id: String = ""
var path: String = ""           # res://Content/{id}/
var user_path: String = ""      # user://Packs/{id}/
var manifest: Dictionary = {}
var physics: MvPhysicsProfile


func resolve_read(rel: String) -> String:
	var user := user_path + rel
	return user if FileAccess.file_exists(user) else path + rel


func resolve_write(rel: String) -> String:
	var full := user_path + rel
	var slash := full.rfind("/")
	if slash > 0:
		DirAccess.make_dir_recursive_absolute(full.substr(0, slash))
	return full


func rooms_path() -> String:
	return resolve_read("Rooms/rooms.json")

func slope_shapes_path() -> String:
	return resolve_read("SlopeShapes.json")

func flow_path() -> String:
	return resolve_read("Flow.json")

func items_path() -> String:
	return resolve_read("Items/items.json")

func abilities_path() -> String:
	return resolve_read("Abilities/abilities.json")

func audio_manifest_path() -> String:
	return resolve_read("Audio/audio.json")

func player_sheet_path() -> String:
	return resolve_read("Sprites/player_sheet.png")

func player_frames_path() -> String:
	return resolve_read("Sprites/player_frames.json")

func player_poses_path() -> String:
	return resolve_read("Sprites/player_poses.json")

func spike_profiles_path() -> String:
	return resolve_read("Hazards/spike_profiles.json")

func tileset_dir() -> String:
	return path + "Tilesets"

func tileset_user_dir() -> String:
	return user_path + "Tilesets"
